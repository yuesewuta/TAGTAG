# Saved queries, frequent-tag management, history cleanup (P1-4)

Implements the remaining P1-4 roadmap item from `docs/TAGTAG-requirements-audit-draft.md`: 保存查询、固定/隐藏常用标签、历史清理.

## Semantics

### Saved query (保存查询)

- A saved query captures the controller's complete current search condition: `searchTerm`, `searchKind`, size/date ranges, `searchAndTagIds` / `searchOrTagIds` / `searchNotTagIds`, and `includeDescendants`.
- Saved queries belong to the active tag space (tag conditions reference tag entities of that space). They are listed only in their own space.
- `SavedQuery { id, spaceId, name, term, kind, minimumSizeBytes, maximumSizeBytes, createdFrom, createdTo, modifiedFrom, modifiedTo, andTagIds, orTagIds, notTagIds, includeDescendants, createdAt }`.
- Applying a saved query replaces the current search condition wholesale and switches to the search view.
- Save requires a non-empty condition and a non-empty name; duplicate names are allowed (stable id distinguishes them). Delete is a single explicit action, no undo (no files touched).
- Persisted in `AppState` (tag-domain JSON inside the managed library SQLite, same boundary as tag state; included in backups like other tag state). Older state JSON without the new keys must load with empty defaults.

### Pin / hide frequent tags (固定/隐藏常用标签)

- `commonPlacements` today = top 5 placements of the active space by usage-event count.
- New rule: pinned placements always appear first (ordered by usage count among pinned), then unpinned by count; hidden placements never appear. The list still caps at 5.
- Pin state: `pinnedPlacementIds`; hidden state: `hiddenPlacementIds`; both persisted in `AppState`. Hiding a pinned placement keeps the pin (unhiding restores it).
- UI: the hierarchy result panel's 标签操作 menu gains 固定到常用 / 取消固定 and 从常用隐藏 / 取消隐藏 (labels reflect current state). The Quick Tag dialog's 最近使用 section becomes 常用 and shows `commonPlacements` (so pin/hide has a visible effect there).

### History cleanup (历史清理)

- `clearUsageHistory()` removes all usage events of the active space (recent/common lists become empty for that space).
- UI: the status drawer's history tab gets a 清空历史记录 button with a confirm step. No undo (usage history is not operational log; operation log is untouched).

## Acceptance

- Domain tests cover: save/apply/delete saved query round-trip incl. persistence reload; pin/hide ordering and exclusion in `commonPlacements`; clear history scoped to the active space; old-state JSON migration.
- Widget tests cover: search page save/apply/delete flow; hierarchy menu pin/hide labels; Quick Tag 常用 section; history tab clear with confirm.
- `flutter analyze` 0 issues; full test suite green; Windows Release build succeeds.
