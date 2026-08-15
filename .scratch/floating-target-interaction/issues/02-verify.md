# 02 - Verification

State: claimed
Type: task
Blocked by: 01

## Comments

- 2026-08-15：静态检查与测试已完成——`analyze --no-pub` 0 问题，全量 `test --no-pub` 129/129 通过（新增：setPosition/savePosition 通道 round-trip、偏好位置字段容错解析与回写、位置变更不产生设置日志）。Release 构建在链接阶段失败（LNK1104 无法打开 tagtag.exe）：本机存在会话开始前（11:27）启动、窗口可见的既有 tagtag.exe（PID 18648，父进程已退出），按约定不得结束非本任务启动的进程；该实例同时持有单实例 Mutex，隔离验证实例也无法启动。真机验证脚本已就绪：`.scratch/floating-target-interaction/verify_floating_target.py`（启动前拒绝在已有实例下运行，仅结束自己拉起的 PID；覆盖拖动/吸附停靠/悬停滑出/双状态接近辉光/点击 Quick Tag/WM_DROPFILES 导入/重启位置恢复，截图输出到 build/parity-shots/floating-target/）。待既有实例退出后：重跑 `build windows --no-pub` + 该脚本即可补齐证据并关闭两卡。
