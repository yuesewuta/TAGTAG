import 'dart:convert';
import 'dart:io';

import '../models/tag_models.dart';

class LocalStore {
  LocalStore({this.baseDirectory});

  final Directory? baseDirectory;

  Future<Directory> get directory async {
    final override = baseDirectory;
    if (override != null) {
      return _ensureDirectory(override);
    }
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    return _ensureDirectory(Directory('$base${Platform.pathSeparator}TAGTAG'));
  }

  Future<AppState> load() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return AppState.empty();
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppState.fromJson(decoded);
  }

  Future<void> save(AppState state) async {
    final file = await _stateFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }

  Future<String> createBackup(AppState state) async {
    final root = await directory;
    final backups = await _ensureDirectory(
      Directory('${root.path}${Platform.pathSeparator}backups'),
    );
    final suffix = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(
      '${backups.path}${Platform.pathSeparator}tagtag-$suffix.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
    return file.path;
  }

  Future<AppState> readBackup(String path) async {
    final file = File(path.trim());
    if (!await file.exists()) {
      throw const FileSystemException('找不到备份文件');
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppState.fromJson(decoded);
  }

  Future<File> _stateFile() async {
    final root = await directory;
    return File('${root.path}${Platform.pathSeparator}state.json');
  }

  Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
