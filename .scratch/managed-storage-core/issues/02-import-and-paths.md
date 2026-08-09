# 02 - Import and managed paths

State: resolved
Type: task
Blocked by: 01

Implement copy and move import for files and folders, target-directory validation, collision rejection, source-path history, and zero-tag imports.

## Acceptance

- Real temporary files and directories verify copy and move behavior.
- The destination cannot escape the initialized storage root.
- Failure leaves neither a false resource record nor an overwritten destination.

## Comments

- 2026-08-09: Copy-import slice is green against real files and production SQLite metadata.
- 2026-08-09: Move-import slice is green with normalized original-path metadata and filesystem compensation on failure.
- 2026-08-09: Folder copy-import slice is green and preserves complete hierarchy; symbolic links are rejected.
