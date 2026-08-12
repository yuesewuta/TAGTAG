# Production UI refresh

Refactor the production Flutter workspace to follow the approved `prototypes/ui-refresh/` visual language while preserving TAGTAG's confirmed workflows and domain semantics.

## Acceptance

- The wide Windows workspace uses a modern, expanded navigation pane, a compact context bar, and a scan-friendly resource surface.
- Narrow desktop widths collapse navigation to an icon rail without changing the active page or making the hierarchy page control navigation state.
- Persistent navigation remains `全部资源 / 标签层级 / 待整理 / 最近 / 搜索 / 设置`.
- Space switching, file import, folder import, and new-space commands remain in the upper-right workspace command area.
- Search input appears only on the Search page; the workspace has no duplicate global search field.
- Resource actions remain directly visible and keyboard-labelled; no folded three-dot action menu or right-side resource inspector is introduced.
- The tag hierarchy page uses a tree-and-results layout with recursive expansion, resource counts, and existing merge/split operations.
- Settings uses a categorized desktop dialog and exposes only implemented preferences or existing operational entry points.
- Colors, typography, spacing, focus, disabled states, and hit targets follow the persisted TAGTAG workspace design system.
- The requested logo is copied from `C:\Users\zcc\Desktop\LOGO.png` into a Flutter asset directory and rendered without changing its proportions once the source file exists.
- Existing behavior labels used by widget tests remain stable unless tests are deliberately updated with the new public UI contract.
- Static analysis, targeted widget tests, the full test suite, and a Windows Release build pass.

## Non-goals

- No resource preview or inspector.
- No global search field outside the Search page.
- No database or managed-file behavior changes.
- No virtual filesystem, content deduplication, or file-byte migration.
