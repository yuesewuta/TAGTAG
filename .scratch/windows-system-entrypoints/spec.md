# Windows system entrypoints

State: resolved
Type: task

## Goal

Add Windows-native entrypoints without duplicating TAGTAG domain operations. Every entrypoint activates the existing Flutter application and routes into the established selection, import, and tag-assignment workflows.

## Sequencing

1. Global Quick Tag hotkey.
2. Tray lifecycle, so the process can remain available after its main window closes.
3. Explorer context-menu bridge for selected external paths.
4. Optional floating drop target.

## Global Quick Tag acceptance

- The runner registers `Ctrl+Shift+T` using the Windows global-hotkey API and unregisters it at window teardown.
- When invoked, the runner restores and foregrounds TAGTAG, then sends a typed channel event to Flutter.
- Flutter reuses the existing Quick Tag dialog for selected managed resources.
- When no managed resource is selected, Flutter opens the normal file chooser; chosen external resources continue through the existing single import-and-tag dialog.
- A conflicting Windows shortcut does not crash the application; Flutter can read the registration state and presents an actionable error.
- No tag, import, filesystem, or SQLite business rule is implemented in C++.

## Comments

- 2026-08-10: Explorer-selected paths, tray persistence and floating-target drag handling were implemented as separate tickets to preserve a small native boundary.
