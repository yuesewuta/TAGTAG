# Floating drop target manual verification (real machine).
#
# Launches an isolated TAGTAG instance with APPDATA pointed at the UI test
# seed, then drives the floating ball with synthesized input:
#   1. free-state screenshot
#   2. drag to mid screen, release -> edge snap (half-off-screen docking)
#   3. hover a snapped ball -> slides fully out
#   4. left button held near the ball -> proximity glow (both states)
#   5. click (no drag) -> Quick Tag activation (main window + file picker)
#   6. posted WM_DROPFILES -> import-and-tag flow
#   7. restart -> docked position restored from preferences
#
# Safety: refuses to run while any tagtag.exe is already alive (single-
# instance mutex would redirect the launch) and only ever kills the PID it
# launched itself.
#
# Usage: python .scratch/floating-target-interaction/verify_floating_target.py

import ctypes
import ctypes.wintypes as wintypes
import os
import struct
import subprocess
import sys
import time

ROOT = r"D:\Documents\codeSpace\TAGTAG"
EXE = os.path.join(ROOT, r"build\windows\x64\runner\Release\tagtag.exe")
SEED_APPDATA = os.path.join(ROOT, r"build\ui-test-appdata")
SHOT_DIR = os.path.join(ROOT, r"build\parity-shots\floating-target")
BALL_CLASS = "TAGTAG_FLOATING_DROP_TARGET"
MAIN_CLASS = "FLUTTER_RUNNER_WIN32_WINDOW"
MAIN_TITLE = "tagtag"
BALL = 64
WM_DROPFILES = 0x233

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
kernel32 = ctypes.windll.kernel32

SRCCOPY = 0x00CC0020
CAPTUREBLT = 0x40000000
SPI_GETWORKAREA = 0x30
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004


def fail(message):
    print("FAIL:", message)
    sys.exit(1)


def running_tagtag_pids():
    ps = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            "(Get-CimInstance Win32_Process -Filter \"Name='tagtag.exe'\" |"
            " Where-Object { $_.CommandLine -like '*TAGTAG*' }).ProcessId",
        ],
        capture_output=True,
        text=True,
    )
    return [int(token) for token in ps.stdout.split() if token.isdigit()]


def find_window(class_name, title=None, attempts=100, interval=0.1):
    for _ in range(attempts):
        hwnd = user32.FindWindowW(class_name, title)
        if hwnd:
            return hwnd
        time.sleep(interval)
    return 0


def window_rect(hwnd):
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def work_area():
    rect = wintypes.RECT()
    user32.SystemParametersInfoW(SPI_GETWORKAREA, 0, ctypes.byref(rect), 0)
    return rect.left, rect.top, rect.right, rect.bottom


def screenshot(rect, name):
    left, top, right, bottom = rect
    width, height = right - left, bottom - top
    screen_dc = user32.GetDC(None)
    memory_dc = gdi32.CreateCompatibleDC(screen_dc)
    bitmap = gdi32.CreateCompatibleBitmap(screen_dc, width, height)
    gdi32.SelectObject(memory_dc, bitmap)
    gdi32.BitBlt(memory_dc, 0, 0, width, height, screen_dc, left, top,
                 SRCCOPY | CAPTUREBLT)
    stride = width * 4
    buffer = (ctypes.c_byte * (stride * height))()
    gdi32.GetBitmapBits(bitmap, len(buffer), buffer)
    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(memory_dc)
    user32.ReleaseDC(None, screen_dc)
    header = struct.pack("<2sIHHI", b"BM", 54 + len(buffer), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, width, -height, 1, 32, 0,
                       len(buffer), 2835, 2835, 0, 0)
    path = os.path.join(SHOT_DIR, name)
    with open(path, "wb") as handle:
        handle.write(header + info + bytes(buffer))
    print("screenshot:", path)


def shot_ball(hwnd, name, pad=80):
    left, top, right, bottom = window_rect(hwnd)
    screenshot((left - pad, top - pad, right + pad, bottom + pad), name)


def move_to(x, y, steps=1):
    if steps <= 1:
        user32.SetCursorPos(x, y)
        time.sleep(0.05)
        return
    start = wintypes.POINT()
    user32.GetCursorPos(ctypes.byref(start))
    for index in range(1, steps + 1):
        user32.SetCursorPos(
            int(start.x + (x - start.x) * index / steps),
            int(start.y + (y - start.y) * index / steps),
        )
        time.sleep(0.02)


def left_down():
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(0.05)


def left_up():
    user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(0.05)


def launch_instance():
    env = dict(os.environ)
    env["APPDATA"] = SEED_APPDATA
    process = subprocess.Popen([EXE], env=env, cwd=ROOT)
    time.sleep(1)
    hwnd = find_window(BALL_CLASS)
    if not hwnd:
        process.kill()
        fail("floating drop target window never appeared")
    return process, hwnd


def kill_own_instance(process):
    subprocess.run(
        ["taskkill", "/PID", str(process.pid), "/F"],
        capture_output=True,
    )
    process.wait(timeout=15)
    time.sleep(1)


def post_drop_files(hwnd, paths):
    payload = "".join(path + "\0" for path in paths).encode("utf-16-le")
    payload += b"\x00\x00"
    dropfiles = struct.pack("<Iiiii", 20, 0, 0, 0, 1)
    total = len(dropfiles) + len(payload)
    handle = kernel32.GlobalAlloc(0x0042, total)  # GHND
    locked = kernel32.GlobalLock(handle)
    ctypes.memmove(locked, dropfiles, len(dropfiles))
    ctypes.memmove(locked + len(dropfiles), payload, len(payload))
    kernel32.GlobalUnlock(handle)
    if not user32.PostMessageW(hwnd, WM_DROPFILES, handle, 0):
        kernel32.GlobalFree(handle)
        fail("PostMessage WM_DROPFILES failed")


def main():
    os.makedirs(SHOT_DIR, exist_ok=True)
    preexisting = running_tagtag_pids()
    if preexisting:
        fail(f"tagtag.exe already running (PIDs {preexisting}); refusing to "
             "launch an isolated instance while the single-instance mutex "
             "is held")

    work_left, work_top, work_right, work_bottom = work_area()
    print(f"work area: ({work_left},{work_top})-({work_right},{work_bottom})")

    # --- session 1: free state, drag, snap, hover, glow, click, drop ---
    process, ball = launch_instance()
    try:
        rect = window_rect(ball)
        print("free-state rect:", rect)
        shot_ball(ball, "01-free-state.bmp")

        # Proximity glow in the free (non-snapped) state: hold the left
        # button near the ball and the glow ring must start pulsing.
        free_cx = (rect[0] + rect[2]) // 2
        free_cy = (rect[1] + rect[3]) // 2
        move_to(rect[0] - 40, free_cy)
        left_down()
        move_to(rect[0] - 37, free_cy + 3)
        time.sleep(0.5)
        shot_ball(ball, "02-free-proximity-glow.bmp")
        left_up()
        time.sleep(0.4)

        # Drag the ball to the middle-left of the screen, then release.
        move_to(free_cx, free_cy)
        left_down()
        move_to((work_left + work_right) // 3, (work_top + work_bottom) // 2,
                steps=15)
        left_up()
        time.sleep(0.8)
        rect = window_rect(ball)
        snapped_left = rect[0] < work_left
        snapped_right = rect[2] > work_right
        print("after snap:", rect, "snapped:", snapped_left or snapped_right)
        if not (snapped_left or snapped_right):
            fail("ball did not dock half off-screen after release")
        shot_ball(ball, "03-snapped-docked.bmp")

        # Hover the docked ball: it must slide fully out.
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        move_to(cx, cy)
        time.sleep(0.6)
        expanded = window_rect(ball)
        is_expanded = expanded[0] >= work_left and expanded[2] <= work_right
        print("hover expanded rect:", expanded)
        if not is_expanded:
            fail("hover did not slide the snapped ball fully out")
        shot_ball(ball, "04-hover-expanded.bmp")

        # Leaving slides it back into the dock.
        move_to((work_left + work_right) // 2, (work_top + work_bottom) // 2)
        time.sleep(0.6)
        docked = window_rect(ball)
        print("after leave:", docked)
        if not (docked[0] < work_left or docked[2] > work_right):
            fail("ball did not slide back after hover leave")

        # Proximity glow in the snapped state: hold the button nearby.
        cx = (docked[0] + docked[2]) // 2
        cy = (docked[1] + docked[3]) // 2
        move_to(cx, cy)
        move_to((work_left + work_right) // 2, (work_top + work_bottom) // 2)
        near_x = max(work_left, docked[0]) + BALL + 20 if docked[0] < work_left \
            else min(work_right, docked[2]) - BALL - 20
        move_to(near_x, cy)
        left_down()
        move_to(near_x + 3, cy + 3)
        time.sleep(0.5)
        glow_rect = window_rect(ball)
        print("glow rect (should slide out):", glow_rect)
        if not (glow_rect[0] >= work_left and glow_rect[2] <= work_right):
            fail("proximity glow did not slide the snapped ball fully out")
        shot_ball(ball, "05-snapped-proximity-glow.bmp")
        left_up()
        time.sleep(0.5)

        # Click (no drag) activates Quick Tag; with no selection the app
        # opens its file picker. Close that dialog with IDCANCEL.
        docked = window_rect(ball)
        cx = (docked[0] + docked[2]) // 2
        cy = (docked[1] + docked[3]) // 2
        move_to(cx, cy)
        left_down()
        left_up()
        dialog = find_window("#32770", None, attempts=40)
        main = find_window(MAIN_CLASS, MAIN_TITLE, attempts=10)
        print("quick tag main window:", main, "picker dialog:", dialog)
        if not main:
            fail("click did not surface the main window")
        shot = window_rect(dialog) if dialog else window_rect(main)
        screenshot(shot, "06-click-quick-tag.bmp")
        if dialog:
            user32.PostMessageW(dialog, 0x0111, 2, 0)  # WM_COMMAND IDCANCEL
            time.sleep(0.5)

        # WM_DROPFILES import still routes to the external quick-tag flow.
        sample = os.path.join(ROOT, r"build\ui-test-library\Notes\读书笔记.txt")
        post_drop_files(ball, [sample])
        time.sleep(1.5)
        main = find_window(MAIN_CLASS, MAIN_TITLE, attempts=10)
        if not main:
            fail("main window not found after WM_DROPFILES")
        main_rect = window_rect(main)
        print("main window after drop:", main_rect)
        screenshot(main_rect, "07-drop-import.bmp")
    finally:
        kill_own_instance(process)

    # --- session 2: the docked position survives a restart ---
    process, ball = launch_instance()
    try:
        restored = window_rect(ball)
        print("restored rect:", restored)
        if not (restored[0] < work_left or restored[2] > work_right):
            fail("docked position was not restored after restart")
        shot_ball(ball, "08-restart-restored.bmp")
    finally:
        kill_own_instance(process)

    print("OK: all floating drop target checks passed")


if __name__ == "__main__":
    main()
