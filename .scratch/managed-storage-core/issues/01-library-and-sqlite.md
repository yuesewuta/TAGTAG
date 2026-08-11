# 01 - ManagedLibrary and SQLite

State: resolved
Type: task

Define the public managed-library interface and persist configuration, managed resources, space membership, tags, placements, assignments, operation log, and consistency findings in versioned SQLite schema.

SQLite stores metadata only. Resource bytes remain original, unencrypted files under the configured storage root and must never be stored as BLOBs or application containers.

## Acceptance

- Initialization and restart are verified through the public interface.
- Writes are transactional and foreign keys are enforced.
- The schema has no resource-content BLOB column; database deletion cannot alter resource file bytes.
- The application no longer creates demo data for a new library.

## Comments

- 2026-08-09: Public `ManagedLibrary` seam confirmed. First slice is initialize, close, and reopen against a real temporary root.
- 2026-08-09: Initialization/reopen slice is green with an empty metadata-only schema.
- 2026-08-11: Resolved after acceptance audit. Schema v6 enables `PRAGMA foreign_keys`, runs schema preparation and migrations inside `BEGIN IMMEDIATE`, persists tag-domain documents in SQLite metadata, and keeps the resource table limited to identity, path, status, timestamps, and size. Initialization/reopen tests verify an empty library without demo records; resource bytes remain ordinary files outside SQLite.
