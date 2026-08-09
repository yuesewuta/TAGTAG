#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "TAGTAG-windows-x64-setup"
#endif

[Setup]
AppId={{82F13D35-24D8-4B89-B8A8-E44EF4C40A8E}
AppName=TAGTAG
AppVersion={#AppVersion}
AppPublisher=TAGTAG
AppPublisherURL=https://github.com/yuesewuta/TAGTAG
AppSupportURL=https://github.com/yuesewuta/TAGTAG/issues
AppUpdatesURL=https://github.com/yuesewuta/TAGTAG/releases
DefaultDirName={localappdata}\Programs\TAGTAG
DefaultGroupName=TAGTAG
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\tagtag.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=tagtag.exe
RestartApplications=no
AppMutex=Local\TAGTAG-82F13D35-24D8-4B89-B8A8-E44EF4C40A8E
VersionInfoVersion={#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\TAGTAG"; Filename: "{app}\tagtag.exe"
Name: "{autodesktop}\TAGTAG"; Filename: "{app}\tagtag.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\tagtag.exe"; Description: "{cm:LaunchProgram,TAGTAG}"; Flags: nowait postinstall skipifsilent
