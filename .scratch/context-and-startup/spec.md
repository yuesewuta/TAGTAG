# Context menus, same-name imports, launch at login

## 1. Resource context menus

All resource rows (全部资源/最近/搜索/待整理 table rows AND the tag-hierarchy result rows) support right-click with a prototype-styled menu:

- 打开 / 在资源管理器中定位
- 添加标签 / 清除标签（标签修改）
- 恢复原路径并退出管理 / 移动到指定位置并退出 / 移入回收站（三项退出管理操作）

Reuse the existing row-action callbacks; menu follows the current popup styling. Right-click selects the row first, then shows the menu.

## 2. Same-name import support

Current behavior rejects importing a file whose name is taken in the target directory. New behavior: auto-rename on conflict with a numeric suffix — `name (2).txt`, `name (3).txt`, … (folder `name (2)`), both files stay independent managed entities, never overwrite. Applies to copy/move import, naming-template imports (after template rendering), and takeovers where applicable. The import dialog shows the final names (with suffixes) in its source list so the user sees what will happen. Exit/restore operations keep the existing never-overwrite semantics.

## 3. Launch at login

- Settings → Windows 集成: new row 开机自动启动 (PillSwitch). Persisted in preferences (`launchAtLogin`, default false) and logged via the existing settings-diff log.
- Native: extend the windows runner with a `tagtag/startup` method channel (setLaunchAtLogin/isLaunchAtLogin) writing/deleting `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\TAGTAG` pointing at the current exe. Per-user, no admin. On startup, sync the registry with the preference.
- C++ constraints: ASCII-only comments, warnings-as-errors, fopen_s if needed.

## Acceptance

- Widget tests: right-click opens the menu with all items; each item routes to the same callbacks as the row icons.
- Domain tests: same-name copy/move import auto-suffixes and keeps both files byte-identical; suffix increments; template + suffix interaction; existing conflict-protection tests for exit/restore unchanged.
- Channel test for the startup toggle (pattern: windows_quick_tag_hotkey_test).
- analyze 0; full suite green; Release build GREEN.
