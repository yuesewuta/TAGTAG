import 'package:path/path.dart' as path;

/// Pure helpers for the scheduled-backup feature, kept free of IO so the
/// directory rules and the due-interval math are directly unit-testable.

/// Validates [directory] against the storage root. Returns a user-facing
/// error message, or null when the directory is acceptable. A backup
/// directory must not be the storage root, sit inside it, or be an ancestor
/// of it; the comparison is done on normalized absolute paths.
String? validateBackupDirectory({
  required String directory,
  required String storageRoot,
}) {
  final trimmed = directory.trim();
  if (trimmed.isEmpty) {
    return '请选择备份目录';
  }
  final normalized = path.normalize(trimmed);
  final normalizedRoot = path.normalize(storageRoot);
  if (path.equals(normalized, normalizedRoot)) {
    return '备份目录不能与存储根目录相同';
  }
  if (path.isWithin(normalizedRoot, normalized)) {
    return '备份目录不能位于存储根目录内';
  }
  if (path.isWithin(normalized, normalizedRoot)) {
    return '备份目录不能是存储根目录的上级目录';
  }
  return null;
}

/// Whether a scheduled backup is due at [now]. An empty or unparsable
/// [lastBackupAt] counts as "never", so the first check runs immediately.
bool isBackupDue({
  required DateTime now,
  required String lastBackupAt,
  required int intervalHours,
}) {
  if (intervalHours < 1) {
    return false;
  }
  if (lastBackupAt.isEmpty) {
    return true;
  }
  final last = DateTime.tryParse(lastBackupAt);
  if (last == null) {
    return true;
  }
  return !now.difference(last).isNegative &&
      now.difference(last) >= Duration(hours: intervalHours);
}
