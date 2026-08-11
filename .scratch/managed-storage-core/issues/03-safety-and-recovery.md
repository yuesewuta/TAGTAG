# 03 - Safety and recovery

State: resolved
Type: task
Blocked by: 01, 02

Implement consistency scanning, durable operation entries, safe undo for imports and moves, and a restorable basic backup.

## Acceptance

- Added, missing, and externally moved resources produce explicit findings.
- Undo never overwrites a conflicting path.
- Backup uses a consistent SQLite snapshot and copies managed resources.

## Comments

- 2026-08-09: Copy-import operation logging and staged undo are green.
- 2026-08-09: Move-undo conflict protection is green and leaves both filesystem and metadata unchanged.
- 2026-08-09: Successful move undo is green with staged restoration and compensation.
- 2026-08-09: Consistency scan is green for untracked additions, missing resources, and normal edits.
- 2026-08-09: Basic backup is green with a SQLite online snapshot, manifest, and unwrapped resource hierarchy.
- 2026-08-09: Restore-to-original exit management is green for files and folders, rejects conflicts without side effects, logs durable metadata, and supports full filesystem and tag-domain undo after restart.
- 2026-08-09: Specified-path exit management is green for files and folders, rejects same-name and in-root destinations, migrates schema v2 operation history, and supports full filesystem and tag-domain undo.
- 2026-08-09: Windows Recycle Bin exit is green with a persisted Shell PIDL token, schema v3-to-v4 migration, managed-path conflict protection, and full filesystem/tag-domain undo for files and folders.
- 2026-08-11: Resolved after acceptance audit. Current regression coverage verifies untracked and missing findings, explicit external-move pairing, conflict-safe undo, a consistent SQLite online snapshot, SHA-256 resource validation, and restore into a new empty root.
