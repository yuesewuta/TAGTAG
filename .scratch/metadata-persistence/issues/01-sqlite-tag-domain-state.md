# 01 - Persist tag-domain state in SQLite

State: resolved
Type: task

Implement schema v6 metadata-document storage, legacy JSON migration, controller persistence routing, and backup/restore integration.

## Acceptance

- `ManagedLibrary` exposes metadata-document read/write operations for tag state and preferences.
- Controller startup migrates legacy state once when the library document is absent, then reads and writes the library copy.
- Tests cover migration, restart authority, preferences, and restored backup persistence.

## Comments

- 2026-08-10: Resolved with atomic `tag_state_json` and `preferences_json` SQLite metadata documents. Legacy files are only read before those documents first exist.
