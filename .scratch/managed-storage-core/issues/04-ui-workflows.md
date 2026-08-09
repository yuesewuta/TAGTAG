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
- 2026-08-09: Replaced the resource overflow menu with direct open/reveal icons, added the six-entry collapsible navigation and persistent settings dialog, and moved clear-direct-tags to a secondary inspector icon.
- 2026-08-09: Real row double-clicks opened all three managed TXT files, including two Chinese filenames; 1280x720 and 960x720 expanded/collapsed layouts passed `PrintWindow` inspection.
- 2026-08-09: Corrected navigation semantics: collapse is local view state, space switching and direct file/folder imports moved to the app bar, and search/tag hierarchy are independent content pages.
- 2026-08-09: Removed the inspector, exposed five direct actions per resource, added explicit multi-select mode, and verified normal clicks retain only the latest selection.
- 2026-08-09: The hierarchy page now recursively expands tag paths, shows tag-entity resource counts, and renders each tag's directly assigned resources inline.
- 2026-08-09: Resource rows now expose specified-location exit directly; target conflicts offer rename, choose another location, or cancel, and `exit_move` appears in the undoable operation log.
- 2026-08-09: Resource rows now expose Windows Recycle Bin exit directly with destructive confirmation; `exit_recycle` is visible and undoable in operation history.
