# SQLite metadata persistence

State: resolved
Type: task

## Goal

Make the active storage root's `.tagtag/tagtag.sqlite` the durable owner of TAGTAG tag-domain metadata. The existing `AppState` JSON graph and user preferences are stored as SQLite metadata documents so the migration preserves behavior while unifying persistence with managed resources and operation history.

## Confirmed scope

- Managed resources, operation logs, tag spaces, tag entities, tag placements, assignments, memberships, usage events, and user preferences remain metadata only.
- Resource files and folders remain original, unencrypted Windows filesystem content under the storage root. No resource bytes enter SQLite.
- A library with no SQLite metadata documents imports the validated legacy app-data JSON once, then treats the library copy as authoritative.
- A library that already has stored metadata documents never falls back to stale app-data JSON.
- Global backup and restore continue to carry tag-domain state and preferences, and restored metadata is persisted into the restored library.

## Acceptance

- A new or migrated library reopens with the same spaces, labels, placements, assignments, memberships, usage history, active space, and import preference.
- Migration writes neither partial tag-domain state nor a migration marker when legacy JSON is invalid.
- Later edits update the SQLite metadata document, and a stale legacy JSON file cannot overwrite those edits on restart.
- The legacy app-data JSON remains a non-destructive compatibility source during this release; it is not used after successful SQLite migration.
- Existing resource import, consistency, undo, backup, and restore tests remain green.

## Comments

- 2026-08-10: Chosen as the final phase 9 data-boundary task before milestone 2 system integrations.
- 2026-08-10: Implemented as schema v6 metadata documents with one-time validated legacy migration and library-authoritative restarts.
