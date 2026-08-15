# 03-verify

State: resolved
Type: task

## Comments

- 2026-08-16: 验证通过。`analyze --no-pub` 0 问题；`test --no-pub` 全量 148/148 通过（基线 130 + 本特性新增 18：模板渲染 6、偏好持久化与兼容 2、模板导入 3、整理域层 5、widget 流程 3，含一个聚合用例内多断言）；`build windows --no-pub` 成功（build\windows\x64\runner\Release\tagtag.exe，32.0s）。测试覆盖规格验收项：占位符渲染/扩展名保留/非法字符清洗/序号/空标签回退；预览计数与冲突；整理移动字节一致、DB 路径同事务更新、扫描干净、撤销恢复；模板偏好持久化与 fromJson 向后兼容；设置保存模板、导入对话框预览与开关、标签菜单打开预览并执行的 widget 测试。
