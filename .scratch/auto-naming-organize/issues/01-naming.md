# 01-naming

State: resolved
Type: task

## Comments

- 2026-08-16: 已完成。`UserPreferences.namingTemplate`（默认 ''，fromJson 缺 key 容错、类型错误抛 FormatException，与 quickTagShortcut 同模式）；`TagTagController.applyNamingTemplate` 静态纯函数渲染 {原名}/{日期}/{时间}/{标签}/{序号}，保留原扩展名，`\/:*?"<>|` 清洗为 `-`，空标签回退 `未标注`；`updatePreferences` 新增该字段并记录设置日志“命名模板 已更新/已清除”（不回显模板内容）。设置→导入与标注新增模板输入框 + 占位符帮助 + 实时示例；导入对话框在模板非空时显示“按模板重命名”开关（默认开）+ 第一个来源的预览行，确认结果 `PrototypeImportResult.renamedSources` 携带重命名计划（来源路径 → 新名称）；home_screen 导入循环经 `importManagedResource(targetName:)` → `importResource(targetName:)` 应用新名，名称冲突仍不覆盖。证据：analyze 0 问题；全量测试 148/148（新增渲染/偏好持久化/导入重命名/设置与导入对话框 widget 测试，见 test/auto_naming_organize_test.dart）。
