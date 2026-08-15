# Tag name uniqueness policy

## Semantics

- `TagDefinition` gains `namePolicy`: `inherit` (default, follows the global setting) | `unique` (no same-name tag allowed in the space) | `free` (allowed even when the global setting is on).
- `UserPreferences` gains `uniqueTagNames` (bool, default false → current duplicate-friendly behavior).
- An existing tag is effectively unique when `policy == unique || (policy == inherit && uniqueTagNames)`.
- Creating a NEW tag with a name that matches an effectively-unique existing tag in the same space is rejected with a clear error pointing at the reuse path (`复用已有标签实体`). Same-name creation against non-unique tags stays allowed. Explicit reuse (`reuseTagId`) is unaffected.
- The setting/policy changes are recorded as tag/settings log entries (existing unified log).

## UI

- Settings → 导入与标注: new row 标签名称全局唯一 (switch, subtitle explains per-tag exceptions).
- Hierarchy result panel 标签操作 menu: state-dependent policy item — inherit: 设为唯一标签 (+允许同名（例外） when global on); unique: 取消唯一标记; free: 移除同名例外.
- Same-name annotation: tags whose name is shared by multiple independent entities in the active space show a small muted 同名×N badge on tree nodes (placement paths already distinguish them in lists).

## Acceptance

- Domain tests: default duplicates allowed; global-on blocks duplicates; per-tag unique blocks with global off; free exception allows with global on; policy round-trips persistence; log entries written.
- Widget tests: settings row toggles; menu item labels follow policy; 同名 badge appears for the demo's duplicated 参考 tags.
- analyze 0; full suite green; Release build.
