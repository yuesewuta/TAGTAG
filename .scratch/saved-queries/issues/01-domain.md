# 01 - Domain: saved queries, pin/hide, clear history

State: resolved
Type: task

## Comments

- `SavedQuery` model with the full search condition + `spaceId` + `createdAt`; `AppState` gained `savedQueries` / `pinnedPlacementIds` / `hiddenPlacementIds` with backwards-compatible `fromJson` defaults; state JSON version bumped 4 → 5 (read path ignores version, matching the `tagOperations` precedent).
- Controller APIs: `savedQueriesInActiveSpace`, `hasActiveSearchCondition`, `saveCurrentSearch` (rejects empty name/condition), `applySavedQuery` (wholesale replace + `showSearchResources()`), `deleteSavedQuery`, `isPlacementPinned/Hidden`, `togglePlacementPinned/Hidden` (reject foreign-space placements), `clearUsageHistory` (scoped to active space). `commonPlacements` = pinned first by usage count, then unpinned by count, hidden excluded, cap 5.
- 10 domain tests in `test/saved_queries_test.dart` all pass, covering save/apply/delete round-trip with reload, space scoping, duplicate names, old-JSON migration, pin/hide ordering and persistence, and space-scoped history cleanup.
