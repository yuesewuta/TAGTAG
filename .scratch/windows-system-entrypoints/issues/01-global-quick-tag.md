# 01 - Windows global Quick Tag

State: resolved
Type: task

Implement the native `RegisterHotKey` bridge, Flutter channel adapter, status query, activation routing, and regression coverage.

## Acceptance

- `Ctrl+Shift+T` works while TAGTAG is not the foreground window.
- Native activation restores the TAGTAG window and enters the existing selected-resource or file-import workflow.
- Native code transports only activation/status; Flutter retains all domain behavior.

## Comments

- 2026-08-10: Implemented with `RegisterHotKey` / `UnregisterHotKey` in the Windows runner and the `tagtag/windows_quick_tag` channel. The registration state is queryable from Flutter; registration conflicts show an actionable in-app message.
- 2026-08-10: Verified with the complete Flutter test suite, `flutter analyze --no-pub`, Windows Release build, and packaged-plugin smoke check.
