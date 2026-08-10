# 03 - Explorer context-menu bridge

State: resolved
Type: task

Add a per-user Explorer command for files and folders that forwards selected paths to the existing TAGTAG process.

## Acceptance

- Explorer exposes a `使用 TAGTAG 添加标签` command for files and folders after installer registration.
- The registered bridge handles one or more selected paths without loading Flutter, SQLite, or TAGTAG domain code into Explorer.
- When TAGTAG is running, the bridge forwards the complete path list to its existing window. When it is not running, it starts TAGTAG with the same path list.
- Flutter routes paths already under management into tag assignment and external paths into the existing import-and-tag dialog. It never creates a duplicate managed resource for an already managed path.
- The installer removes the per-user command registration on uninstall.

## Comments

- 2026-08-10: The initial implementation uses an out-of-process bridge registered as a classic per-user shell verb. This preserves Explorer responsiveness and keeps the bridge independent of the Flutter process.
- 2026-08-10: Implemented the `tagtag_explorer_bridge.exe` protocol, single-instance `WM_COPYDATA` forwarding, Flutter path routing, and per-user installer registration for files and folders. The bridge has no Flutter, SQLite, import, or tag-domain dependency.
- 2026-08-10: Verified with protocol/channel regression tests, the complete Flutter suite, `flutter analyze --no-pub`, Windows Release build, and package smoke check. The local machine does not have Inno Setup; installer compilation and install/upgrade/uninstall remain verified by the existing GitHub Actions job.
