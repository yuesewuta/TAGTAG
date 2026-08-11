# 01 - Tag identity operations

State: resolved
Type: task

Implement merge, split, persisted operation context, and undo at the tag-domain boundary.

## Comments

- 2026-08-11: Resolved. Merge preserves the target entity and placement-bound assignments. Split creates a new entity for selected placements, transforms inheritance rules from actual folder assignments, persists minimal affected-entity context, and enforces reverse-order undo.
