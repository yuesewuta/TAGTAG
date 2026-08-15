# 01 - Native interaction

State: resolved
Type: task

## Comments

- 2026-08-15：实现完成（原生 + Dart seam）。原生侧 `windows/runner/flutter_window.cpp/.h`：WM_LBUTTONDOWN 捕获 + 4px 拖动阈值，WM_MOUSEMOVE 拖动实时 SetWindowPos；释放后按 MonitorFromWindow 工作区计算最近左右边缘，16ms 定时器 ease-out cubic（180ms）滑入约 1/3 可见（2/3 屏外）的停靠态（左 workLeft-42 / 右 workRight-21；spec 结构节公式与需求文字不一致，按需求文字"roughly one third visible"实现）；TrackMouseEvent + WM_MOUSELEAVE 驱动悬停滑出/滑回；WH_MOUSE_LL 钩子只做 GetCursorPos 级命中（+64px 膨胀矩形 + VK_LBUTTON 检查）并 PostMessage 状态变化，辉光为 55ms 定时器按 900ms 周期以 alpha 0.35-0.75 重绘分层像素（logo + 预乘 src-over 软光环）；禁用时卸载钩子、清理定时器并恢复纯 logo 像素。位置持久化：通道新增 `setPosition{x,y}`（Dart 启动/设置保存时传入，就近显示器工作区夹取，落点贴边 6px 内恢复停靠态），拖动吸附完成后原生回调 `savePosition{x,y}`（逻辑完全可见中心点）。Dart 侧：`UserPreferences` 新增可空 `floatingTargetX/Y`（容错解析，version 仍为 1），`updatePreferences` 透传且 `_describePreferenceChanges` 不描述位置字段（纯位置变更不写设置日志），`WindowsFloatingDropTarget` 新增 `setPosition`/`start`/`dispose`，home_screen 启动与设置保存两条路径统一走 `_applyFloatingDropTarget`。点击（未拖动）仍走 ActivateQuickTag，WM_DROPFILES 路径未动。门禁：`analyze --no-pub` 0 问题；全量测试 129/129 通过（新增 4 项）；flutter_window.cpp 在 /W4 /WX 下编译通过，`build windows --no-pub` 于 12:39 重试成功。真机人工捕获因非本任务启动的常驻实例持有单实例 Mutex 未执行，见 02 卡。

- Resolved 2026-08-15: drag/snap/hover/glow/persistence all implemented; snap gated to a 48px edge threshold per user feedback; hook tracks button state itself (injected-input reliable).
