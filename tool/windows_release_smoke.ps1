param(
    [ValidateSet('Packaging', 'FolderDialog', 'SingleInstance', 'All')]
    [string]$Check = 'All',
    [string]$ExePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\tagtag.exe'
}
$ExePath = [System.IO.Path]::GetFullPath($ExePath)
$releaseDirectory = Split-Path -Parent $ExePath

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class TagTagSmokeNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, UIntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);

  public static IntPtr MainWindowForProcess(uint target) {
    var result = IntPtr.Zero;
    EnumWindows((window, unused) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId == target) {
        var className = new StringBuilder(256);
        GetClassName(window, className, className.Capacity);
        if (className.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") {
          result = window;
          return false;
        }
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static IntPtr FlutterViewForWindow(IntPtr parent) {
    var result = IntPtr.Zero;
    EnumChildWindows(parent, (window, unused) => {
      var className = new StringBuilder(256);
      GetClassName(window, className, className.Capacity);
      if (className.ToString() == "FLUTTERVIEW") {
        result = window;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static void Click(IntPtr window, int x, int y) {
    var position = new IntPtr((y << 16) | (x & 0xffff));
    SendMessage(window, 0x0201, new UIntPtr(1), position);
    SendMessage(window, 0x0202, UIntPtr.Zero, position);
  }

  public static string[] WindowClassesForProcess(uint target) {
    var values = new List<string>();
    EnumWindows((window, unused) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId == target && IsWindowVisible(window)) {
        var className = new StringBuilder(256);
        GetClassName(window, className, className.Capacity);
        values.Add(className.ToString());
      }
      return true;
    }, IntPtr.Zero);
    return values.ToArray();
  }
}
'@

function Wait-MainWindow([System.Diagnostics.Process]$Process) {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $window = [TagTagSmokeNative]::MainWindowForProcess([uint32]$Process.Id)
        if ($window -ne [IntPtr]::Zero) {
            return $window
        }
        Start-Sleep -Milliseconds 125
    }
    throw "TAGTAG did not create a main window: $($Process.Id)"
}

function Invoke-PackagingCheck {
    $requiredFiles = @(
        'tagtag.exe',
        'tagtag_explorer_bridge.exe',
        'flutter_windows.dll',
        'file_selector_windows_plugin.dll',
        'desktop_drop_plugin.dll'
    )
    $missing = @($requiredFiles | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $releaseDirectory $_) -PathType Leaf)
    })
    if ($missing.Count -gt 0) {
        throw "Release package is missing native files: $($missing -join ', ')"
    }
    Write-Output 'GREEN: required Windows plugin DLLs are packaged'
}

function Invoke-FolderDialogCheck {
    $isolatedAppData = Join-Path $env:TEMP "tagtag-folder-dialog-$([Guid]::NewGuid().ToString('N'))"
    $originalAppData = $env:APPDATA
    $process = $null
    try {
        New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
        $env:APPDATA = $isolatedAppData
        $process = Start-Process -FilePath $ExePath -PassThru
        $window = Wait-MainWindow $process
        $rect = New-Object TagTagSmokeNative+RECT
        [TagTagSmokeNative]::GetWindowRect($window, [ref]$rect) | Out-Null
        [TagTagSmokeNative]::ShowWindow($window, 9) | Out-Null
        [TagTagSmokeNative]::SetForegroundWindow($window) | Out-Null
        Start-Sleep -Milliseconds 1500
        $flutterView = [TagTagSmokeNative]::FlutterViewForWindow($window)
        if ($flutterView -eq [IntPtr]::Zero) {
            throw 'TAGTAG main window does not contain a FLUTTERVIEW child window'
        }
        [TagTagSmokeNative]::Click($flutterView, 480, 450)

        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $classes = @([TagTagSmokeNative]::WindowClassesForProcess([uint32]$process.Id))
            if ($classes -contains '#32770') {
                Write-Output 'GREEN: storage root folder dialog opened'
                return
            }
            Start-Sleep -Milliseconds 125
        }
        $windowWidth = $rect.Right - $rect.Left
        $windowHeight = $rect.Bottom - $rect.Top
        throw "Storage root button did not open a Windows folder dialog. Window: $windowWidth x $windowHeight. Visible window classes: $($classes -join ', ')"
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        $env:APPDATA = $originalAppData
        if (Test-Path -LiteralPath $isolatedAppData) {
            Remove-Item -LiteralPath $isolatedAppData -Recurse -Force
        }
    }
}

function Invoke-SingleInstanceCheck {
    $isolatedAppData = Join-Path $env:TEMP "tagtag-single-instance-$([Guid]::NewGuid().ToString('N'))"
    $originalAppData = $env:APPDATA
    $launched = @()
    try {
        New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
        $env:APPDATA = $isolatedAppData
        $first = Start-Process -FilePath $ExePath -PassThru
        $launched += $first
        $firstWindow = Wait-MainWindow $first
        [TagTagSmokeNative]::ShowWindow($firstWindow, 6) | Out-Null
        Start-Sleep -Milliseconds 250

        $second = Start-Process -FilePath $ExePath -PassThru
        $launched += $second
        if (-not $second.WaitForExit(3000)) {
            throw 'Second launch remained alive instead of handing off to the first instance'
        }

        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            if (-not [TagTagSmokeNative]::IsIconic($firstWindow)) {
                Write-Output 'GREEN: second launch restored the existing window and exited'
                return
            }
            Start-Sleep -Milliseconds 125
        }
        throw 'Second launch exited but did not restore the existing window'
    }
    finally {
        foreach ($process in $launched) {
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
        $env:APPDATA = $originalAppData
        if (Test-Path -LiteralPath $isolatedAppData) {
            Remove-Item -LiteralPath $isolatedAppData -Recurse -Force
        }
    }
}

if ($Check -in @('Packaging', 'All')) { Invoke-PackagingCheck }
if ($Check -in @('FolderDialog', 'All')) { Invoke-FolderDialogCheck }
if ($Check -in @('SingleInstance', 'All')) { Invoke-SingleInstanceCheck }
