# 02-organize

State: resolved
Type: task

## Comments

- 2026-08-16: 已完成。`ManagedLibrary.organizeMove`（schema v6→v7 迁移，operations CHECK 新增 `organize_move`）：同一事务内完成文件复制、resources 行路径更新（含文件夹内嵌套受管资源前缀改写）、源删除与操作日志写入，失败按既有模式回滚并补偿；`_undoOrganizeMove` 依 context 中的 previousRelativePath 恢复原路径并支持嵌套前缀回写；移动后修剪遗留空目录，一致性扫描保持干净。控制器新增 `previewOrganizeForPlacement`（有效标签 = 直接 + 继承，产出可移动数/目标目录/冲突清单，已在目标目录的跳过、冲突永不覆盖）与 `organizeForPlacement`（逐项受管移动 + 同步 + 通知）。层级结果面板“标签操作”菜单新增“整理此标签的资源到目录…”，打开 PrototypeDialogFrame 预览对话框（计数/目标目录/冲突列表，取消/整理），执行后 toast 汇总；统一日志显示“整理资源到标签目录”。证据：analyze 0 问题；全量测试 148/148（新增预览计数与冲突、字节级往返 + 扫描干净 + 撤销恢复、继承标签嵌套移动、v6 迁移、标签菜单 widget 端到端测试）。
