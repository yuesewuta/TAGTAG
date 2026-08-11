# Tag merge and split

Merging turns selected independent tags into one chosen tag entity. Splitting turns selected placements of a reused unique tag into a new independent tag entity. Both operations are explicit, previewed, logged, and undoable.

## Acceptance

- Merge keeps the chosen target tag ID and repoints source placements to it.
- Placement IDs remain stable, so direct assignments remain attached to their placements.
- Split creates one new tag ID and repoints only the selected placements.
- Independent same-name tags are never merged implicitly.
- Folder inheritance rules continue to produce effective tags for the intended placement groups after merge or split.
- Preview reports affected entities, placements, assignments, resources, and inheritance rules before mutation.
- Undo restores only the changed tag-domain entities and does not snapshot or replace the whole application state.
