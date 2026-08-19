# 02-wizard

State: resolved
Type: task

## Comments

- 2026-08-19 完成。main.dart 的初始化页扩展为两步向导 _LibrarySetupWizard（仅未初始化安装出现；已有安装走 _restoreLibrary 不受影响）。
- 第 1 步存储根：保留原有文案与行为（选择 → ManagedLibrary.initialize → locator.saveRoot），完成后挂起为 _pendingLibrary 进入第 2 步；上一步关闭挂起库并返回。
- 第 2 步关键设置：外观（浅色/深色分段，实时预览主题）、默认导入方式（复制/移动分段）、Quick Tag 快捷键（仅展示 Ctrl + Shift + T）、悬浮接收目标 PillSwitch、开机自动启动 PillSwitch；液态玻璃风格（GlassCanvas + GlassPanel + GlassPrimaryButton）。
- 完成：经 TagTagController.updatePreferences 持久化四项选择（写入库 metadata），并通过新抽取的 lib/services/windows_integration_sync.dart applyWindowsIntegrationPreferences 立即应用自启动注册与悬浮目标（home_screen 启动同步已重构复用同一助手，激活后还会再应用一次，幂等）。
- 测试：test/backup_wizard_ui_test.dart 向导流程 widget 测试（存储根 → 关键设置 → 完成，断言工作区出现、控制器与库 metadata 中的偏好均为所选）。既有「存储根选择器报错」测试保持通过。证据：analyze 0；全量 194/194；Release 构建成功。
