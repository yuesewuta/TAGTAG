# 02 - Verification

State: resolved
Type: task
Blocked by: 01

## Comments

- 2026-08-15：静态检查与测试已完成——`analyze --no-pub` 0 问题，全量 `test --no-pub` 129/129 通过（新增：setPosition/savePosition 通道 round-trip、偏好位置字段容错解析与回写、位置变更不产生设置日志）。Release 构建首次因既有 tagtag.exe（PID 18648，会话前 11:27 启动）占用输出文件而 LNK1104；该实例于 12:38 左右自行退出后重试，`build windows --no-pub` 成功（√ Built build\windows\x64\runner\Release\tagtag.exe）。
- 2026-08-15：构建成功后复核 spec 发现结构节吸附公式与需求文字不一致（"roughly one third visible" vs workLeft-size/3），已按需求文字修正为约 1/3 可见（左 workLeft-42/右 workRight-21，共 3 处）；修正后 analyze 0 问题、测试 129/129 通过、flutter_window.obj 在 /W4 /WX 下重新编译通过（13:36）。
- 2026-08-15：最终链接与真机人工捕获未执行：12:40 起新的 tagtag.exe 实例（PID 11716，父进程已退出、主窗口可见，非本任务启动）持续 55 分钟以上持有单实例 Mutex 并锁定 Release 输出（LNK1104）；按约定不得结束非本任务启动的进程，三次守候（10+19+5 分钟轮询）期间该实例始终存活。真机验证脚本已就绪：`.scratch/floating-target-interaction/verify_floating_target.py`（启动前拒绝在已有实例下运行并先清空种子库中的悬浮球位置保证可重复运行；仅结束自己拉起的 PID；覆盖拖动/吸附停靠/悬停滑出/双状态接近辉光/点击 Quick Tag/WM_DROPFILES 导入/重启位置恢复，截图输出到 build/parity-shots/floating-target/）。待本机无 tagtag.exe 运行时：先 `build windows --no-pub` 再执行该脚本即可补齐证据并关闭两卡。

- Resolved 2026-08-15: verify_floating_target.py prints OK — free/glow/mid-drag-stays/edge-snap/hover-expand/glow-expand/click/drop/restart-restore all pass; 8 screenshots in build/parity-shots/floating-target/. analyze 0, tests 129/129, Release build GREEN.
