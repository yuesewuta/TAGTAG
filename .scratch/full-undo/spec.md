# Full undo coverage for tag operations

## Background

Toast undo currently covers resource operations (import/rename/organize) and tag merge/split. The user wants undo for ALL tag modifications: create, edit (rename/color), reparent, delete placement, delete entity, pin/hide, uniqueness-policy changes.

## Domain work (tagtag_controller.dart)

Every recorded `TagDomainOperation` needs enough `context` to reverse it, and `undoTagOperation` needs a handler per type:

- `create` (createPlacement): context {placementId, tagId, createdNewTag}. Undo: remove the placement; also remove the tag entity when it was created by this operation.
- `edit` (updateTag): context {tagId, previousName, previousColorValue}. Undo: restore both.
- `reparent`: context {placementId, previousParentId, previousSortOrder}. Undo: restore.
- `deletePlacement`: currently reassigns assignments to a replacement placement and promotes children. Context must snapshot: {placementId, tagId, parentId, sortOrder, promotedChildIds, reassignedAssignmentIds}. Undo: recreate the placement, move children back, reassign assignments back.
- `deleteEntity`: snapshot the full entity: {tag fields, placements[], assignments[], inheritanceRules[]}. Undo: restore all of them.
- `pin` / `hide`: context {placementId, previous: bool}. Undo: restore set membership.
- uniqueness policy changes are recorded as `edit` today — give them their own context shape {tagId, previousPolicy} (a `policy` value in TagDomainOperationType is cleaner; migrating old entries: unknown/old values must still parse).
- Undo marks `undoneAt` like merge/split; undoing an already-undone op errors; undo of an op whose target has since changed structurally should fail with a clear StateError rather than corrupting state.

## Toast wiring

Extend the undo affordance to the toasts of: edit tag (home_screen `_editActiveTag`), create tag, delete tag flows, reparent (result panel + tree node + drag), pin/hide/policy (workspace `_togglePin`/`_toggleHide`/`_setPolicy`). Follow the existing before/after capture pattern used by `_runAction(undoable: true)`; the workspace has controller access — extend `showPrototypeToast` with `actionLabel`/`onAction` passthrough and use AppToast directly where needed. The `newTagOps` filter in `_runAction` should accept all supported types (not just merge/split).

## Acceptance

- Domain tests: undo round-trips for create/edit/reparent/deletePlacement/deleteEntity/pin/hide/policy; persistence reload keeps undo context; double-undo errors.
- Existing 161+ tests stay green; analyze 0; Release build GREEN.
