# 02 - Wiring + verification

State: resolved
Type: task
Blocked by: 01

- Resolved 2026-08-19: `showPrototypeToast` 增加 `actionLabel`/`onAction` 透传（lib/ui/prototype_workspace.dart）；workspace 新增 `_captureTagOperationIds` + `_showTagOperationUndoToast` 助手（按操作 ID 差集捕获、逆序撤销、失败弹错误 Toast），接入：拖拽 `_dropOn`（保持同步弹 Toast 的时序，校验失败仍走 catchError）、结果面板 `_reparent`、树节点 `_TagTreeNode._reparentTag`、`_togglePin`/`_toggleHide`/`_setPolicy`。home_screen 的 `_runAction` 撤销过滤器放开到全部标签操作类型，`_showCreateTag`/`_editActiveTag`/`_deleteActiveTag`（位置与实体两个分支）开启 `undoable: true`。
- 证据：`analyze --no-pub` 0 问题；全量 `test --no-pub` 173/173 通过（基线 162 + 新增 11，含 ui_refresh 拖拽改层级用例回归）；`build windows --no-pub` 成功产出 build\windows\x64\runner\Release\tagtag.exe。未做 git 提交。
