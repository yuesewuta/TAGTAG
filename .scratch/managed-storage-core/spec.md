# Managed storage core

State: claimed
Type: task

## Goal

Deliver milestone 1 of TAGTAG: a Windows Flutter application whose managed resources live under one initialized storage root and whose metadata is persisted transactionally.

## Confirmed scope

- Initialization is mandatory before the application can be used.
- Files and folders are imported by copy by default or move when explicitly selected.
- Every managed entity maps to one concrete file or folder under the storage root.
- Tags and spaces reference the managed entity without copying its file.
- Untagged managed resources remain valid and appear in the relevant inbox.
- Storage changes, operation logging, undo, monitoring, and basic backup are part of milestone 1.
- Main-window drag-in is included. Global hotkeys, Explorer context menus, the floating target, and tray integration are milestone 2.
- Global content addressing, transparent deduplication, virtual filesystems, previews, and full-text indexing are out of scope.
- SQLite is limited to metadata and indexes. Resource bytes remain original, unencrypted files under the storage root and are never stored as database BLOBs or application containers.

## Acceptance

- A new install cannot enter the workspace until a writable storage root is initialized.
- Importing a file or folder produces the requested copy or move under the root and one durable resource record.
- Failed imports do not leave committed metadata claiming a missing resource.
- Managed paths cannot escape the configured root.
- Untagged resources remain manageable and queryable in the inbox.
- External additions, missing resources, and external moves are represented as actionable consistency findings.
- Supported managed operations produce durable log entries and can be undone without automatic overwrite.
- Metadata and backup operations survive restart.
- `flutter analyze`, tests, and a Windows build pass.

## Test seam proposal

Tests and callers use one `ManagedLibrary` interface for initialization, import, queries, consistency scanning, backup, and undo. Tests use a temporary real filesystem and the production SQLite adapter; UI and platform launch behavior are tested separately at their public adapters.

## Comments

- 2026-08-09: Requirements approved; development authorized.
- 2026-08-09: User confirmed the proposed public test seams.
