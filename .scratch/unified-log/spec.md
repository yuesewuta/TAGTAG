# Unified log page, leveled entries, no undo in UI

## Background

The operation log currently lives in the status drawer's history tab (plus a legacy dialog) and offers per-entry undo. The user wants:

1. **Undo removed from every log surface.** The log becomes a pure, append-only timeline. Domain undo APIs may remain internally but no UI exposes them.
2. **日志 as a first-class left-navigation destination** (new `ResourceView.log` + `nav-日志` entry) showing ALL software-related changes: resource operations (import/exit/consistency actions), tag changes (create/edit/delete/reparent/merge/split/pin/hide — extend coverage to whatever is not yet recorded), settings changes (every `updatePreferences` call logs a human-readable summary of what changed), and consistency events (newly appeared findings, logged once per change, not on every 15s scan).
3. **Levels with distinct colors**: 信息 (blue) for normal operations, 提醒 (amber) for exits/destructive-ish actions and consistency findings, 警告 (red) for failures/errors. Rendered as a colored dot + tinted level chip per row.
4. **Filtering**: the log page has a filter row — keyword field (matches summary), level filter (全部/信息/提醒/警告), category filter (全部/资源/标签/设置/一致性). Filters compose; empty result shows an empty state.

## Semantics

- Unified view model: the controller exposes `logEntries` — a merged, time-descending list of `LogEntry {timestamp, level, category, summary}` built from: managed operations (resource), tag operations (tag), settings events (settings), consistency events (consistency). Settings and consistency events are new lightweight persisted lists in `AppState` (cap each at 500 entries, drop oldest).
- Settings logging: `updatePreferences` compares old vs new and logs one entry summarizing changed fields (e.g. `更新设置：默认导入方式 复制 → 移动`); no entry when nothing changed.
- Tag coverage: create/rename/delete placement/entity, reparent, merge, split, pin/hide — anything already recorded in `tagOperations` is reused; missing actions get recorded the same way. Level 信息, except tag-entity deletion = 提醒.
- Resource operations keep their existing store; level mapping: import/restore = 信息, exit/recycle/move-out = 提醒, consistency actions = 信息.
- Consistency: when a scan produces a changed findings set (new signature), log one 提醒 entry summarizing counts (e.g. `一致性扫描：2 项外部新增，1 项缺失`); unchanged findings log nothing.
- The drawer's history tab stays as a short recent view but loses undo buttons and gains a "查看全部日志" link that navigates to the log page. The legacy `_OperationLogDialog` and its undo flow are removed if no longer referenced.

## Acceptance

- Domain tests: settings change logging (incl. no-op case), consistency signature dedupe, merged `logEntries` ordering/mapping, level/category mapping.
- Widget tests: nav shows 日志 entry and opens the page; entries render with level chips; level/category/keyword filters compose; no undo affordance exists on any log surface (drawer + page); drawer link navigates to the page.
- `flutter analyze` 0 issues; full suite green; Windows Release build succeeds.
