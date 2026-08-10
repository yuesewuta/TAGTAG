# 02 - Windows tray lifecycle

State: resolved
Type: task

Implement a Windows-native notification-area lifecycle for the existing TAGTAG process.

## Acceptance

- Closing the primary window hides it to the notification area instead of terminating the process.
- The tray menu provides commands to show the main window, begin Quick Tag, and exit TAGTAG.
- Tray Quick Tag only restores the window and emits the existing Flutter Quick Tag activation event; it does not implement import, tag, filesystem, or SQLite behavior in C++.
- Removing the process unregisters the notification-area icon and the existing global hotkey.

## Comments

- 2026-08-10: The implementation will use the Win32 notification-area API in the existing runner, avoiding a second Flutter-side lifecycle or tray dependency.
- 2026-08-10: Implemented with `Shell_NotifyIconW`. Normal close now hides TAGTAG, while the native tray menu exposes show, Quick Tag, and explicit exit. Teardown removes the icon and unregisters the hotkey using its retained registration window handle.
- 2026-08-10: Verified with a native-runner regression test, complete Flutter tests, `flutter analyze --no-pub`, Windows Release build, and packaged-plugin smoke check.
