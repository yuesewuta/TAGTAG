# 04 - Optional floating drop target

State: resolved
Type: task

Provide a configurable Windows floating drop target that forwards dragged files and folders into TAGTAG's existing import-and-tag workflow.

## Acceptance

- The target is disabled by default and can be enabled from TAGTAG settings.
- The preference is stored with the active library's tag-domain metadata.
- The target stays visible while the main window is hidden to the tray, accepts one or more files or folders, and routes them to the existing external-path Quick Tag event.
- The native window does not perform imports, tag assignment, filesystem mutations, or SQLite operations.
- Closing TAGTAG removes the target window.

## Comments

- 2026-08-10: Implemented as a small topmost Win32 drop target rather than a second Flutter window, so it remains available during tray residence and retains the existing single-process ownership boundary.
- 2026-08-10: The disabled-by-default setting is persisted in `UserPreferences`; the target receives files and folders through `WM_DROPFILES` and forwards their paths to the existing Quick Tag channel. Complete Flutter tests, static analysis, Windows Release build, and package smoke check pass.
