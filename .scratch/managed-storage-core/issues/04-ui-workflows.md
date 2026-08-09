# 04 - Core UI workflows

State: resolved
Type: task
Blocked by: 01, 02, 03

Connect mandatory initialization, main-window import, storage browsing, untagged inbox, open, reveal, consistency findings, operation history, undo, and backup to the Flutter UI.

## Acceptance

- The application starts in initialization when no root is configured.
- A user can complete a zero-tag import and find the resource in the inbox.
- Platform launch/reveal errors are visible and do not corrupt metadata.

## Comments

- 2026-08-09: Initialization gate, file/folder pickers, main-window drop, copy/move choice, target directory, zero-or-more tags, and inbox are connected.
- 2026-08-09: Windows open/reveal adapter, operation history with undo, consistency alert count, and complete backup creation are connected.
- 2026-08-09: Release-window visual verification passed at 1280x720 without overlap or clipping.
