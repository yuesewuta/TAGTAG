# 01-backup

State: resolved
Type: task

## Comments

- 2026-08-19 完成。偏好：UserPreferences 新增 backupEnabled/backupDirectory/backupIntervalHours(24)/backupIncremental/lastBackupAt（fromJson 宽容：缺 key 走默认，类型或取值非法抛 FormatException）；updatePreferences 支持新字段并在 _describePreferenceChanges 记录（lastBackupAt 由调度器盖章，沿用 floatingTargetX/Y 先例不写入设置日志）。
- 校验与到期逻辑：lib/services/scheduled_backup.dart 纯函数 validateBackupDirectory（normalize 后拒绝等于/位于/祖先于存储根，空目录报错）与 isBackupDue（可注入时钟）。
- 增量备份：ManagedLibrary.createIncrementalBackup 写入固定 TAGTAG-incremental 子目录，每次刷新 SQLite 在线快照（先清理旧 WAL sidecar）与 manifest（formatVersion 1, strategy incremental），按 size+mtime 对比仅复制新增/变化文件（文件夹递归逐文件对比），远端多余文件绝不删除；损坏 manifest 自动降级为全量重拷。完整备份复用 createBackup 写入 backupDirectory 下新的时间戳目录。
- 调度：home_screen 15 分钟周期 Timer + 启动检查；执行前盖章 lastBackupAt（避免失败时每 15 分钟刷告警），结果经 controller.recordScheduledBackupOutcome 写入统一日志（LogCategory.resource，成功 info / 失败 warning），全程 unawaited 不阻塞 UI。
- 设置 UI：存储与备份分区新增 定期备份 PillSwitch、备份目录选择（内联校验错误，保存时再校验可创建性，非法则停留在对话框并跳到该分区）、备份间隔下拉（6/12/24/72 小时）、备份策略分段（完整/增量）、上次备份时间行。
- 测试：test/scheduled_backup_test.dart 新增 19 个域测试（目录校验 6、到期逻辑 6、偏好往返/兼容/非法值 3、设置日志 1、增量备份目标守卫 1、增量仅复制变化且绝不删除远端 1、文件夹递归仅重拷变化文件 1）；test/backup_wizard_ui_test.dart 含设置备份行 widget 测试。证据：analyze 0；全量 194/194；Release 构建成功。
