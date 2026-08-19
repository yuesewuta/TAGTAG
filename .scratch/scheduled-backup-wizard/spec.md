# Scheduled backups and first-run setup wizard

## A. Scheduled backups (定期备份)

- Preferences: `backupEnabled` (false), `backupDirectory` (''), `backupIntervalHours` (int, default 24), `backupIncremental` (bool, default false), `lastBackupAt` (ISO string, '' = never).
- Directory validation: must not be the storage root, inside it, or an ancestor of it (normalized path comparison); must be creatable.
- Scheduler: a periodic check (every 15 min while the app runs, plus one check at startup): when enabled and `now - lastBackupAt >= interval`, run a backup and stamp `lastBackupAt`. Failures surface in the unified log as a warning entry; never block the UI.
- Strategies: 完整备份 = existing full backup into a new timestamped directory. 增量备份 = into a fixed `TAGTAG-incremental` directory: fresh SQLite online snapshot + manifest, and only new/changed resource files are copied (size+mtime vs stored manifest); removed files are NOT deleted remotely. 
- Settings → 存储与备份: enable PillSwitch, directory picker with validation error, interval dropdown (6/12/24/72 小时), strategy segmented (完整/增量), 上次备份时间 line.

## B. First-run setup wizard (首次启动向导)

- The current init page only picks the storage root. Extend it into a two-step wizard: step 1 storage root (existing behavior); step 2 key settings: 外观 (浅色/深色), 默认导入方式 (复制/移动), Quick Tag 快捷键 (display only, changeable later in settings is fine — but a recorder already exists in settings, reuse it if cheap), 悬浮接收目标 toggle, 开机自动启动 toggle. 完成 finishes initialization and writes the chosen preferences.
- The wizard appears only when the library is uninitialized; existing installs are untouched.
- Style follows the liquid-glass design system.

## Acceptance

- Domain tests: directory validation rules; scheduler due-logic (injectable clock or interval math helper); incremental copy only-changed behavior.
- Widget tests: settings backup rows; wizard flow from storage root to settings to done.
- analyze 0; full suite green; Release build.
