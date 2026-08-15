# 01 - Native interaction

State: claimed
Type: task

## Comments

- 2026-08-15：实现完成（原生 + Dart seam）。原生侧 `windows/runner/flutter_window.cpp/.h`：WM_LBUTTONDOWN 捕获 + 4px 拖动阈值，WM_MOUSEMOVE 拖动实时 SetWindowPos；释放后按 MonitorFromWindow 工作区计算最近左右边缘，16ms 定时器 ease-out cubic（180ms）滑入半隐藏停靠（左 workLeft-21 / 右 workRight-42）；TrackMouseEvent + WM_MOUSELEAVE 驱动悬停滑出/滑回；WH_MOUSE_LL 钩子只做 GetCursorPos 级命中（+64px 膨胀矩形 + VK_LBUTTON 检查）并 PostMessage 状态变化，辉光为 55ms 定时器按 900ms 周期以 alpha 0.35-0.75 重绘分层像素（logo + 预乘 src-over 软光环）；禁用时卸载钩子、清理定时器并恢复纯 logo 像素。位置持久化：通道新增 `setPosition{x,y}`（Dart 启动/设置保存时传入，就近显示器工作区夹取，落点贴边 6px 内恢复停靠态），拖动吸附完成后原生回调 `savePosition{x,y}`（逻辑完全可见中心点）。Dart 侧：`UserPreferences` 新增可空 `floatingTargetX/Y`（容错解析，version 仍为 1），`updatePreferences` 透传且 `_describePreferenceChanges` 不描述位置字段（纯位置变更不写设置日志），`WindowsFloatingDropTarget` 新增 `setPosition`/`start`/`dispose`，home_screen 启动与设置保存两条路径统一走 `_applyFloatingDropTarget`。点击（未拖动）仍走 ActivateQuickTag，WM_DROPFILES 路径未动。门禁：`analyze --no-pub` 0 问题；全量测试 129/129 通过（新增 4 项）；flutter_window.cpp 在 /W4 /WX 下编译通过（flutter_window.obj 12:24 重新生成）。Release 链接被既有 tagtag.exe 实例占用，见 02 卡。
