import 'dart:convert';
import 'dart:io';

import '../models/tag_models.dart';

class UserPreferences {
  const UserPreferences({this.moveImportsByDefault = false});

  final bool moveImportsByDefault;

  UserPreferences copyWith({bool? moveImportsByDefault}) => UserPreferences(
    moveImportsByDefault: moveImportsByDefault ?? this.moveImportsByDefault,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'moveImportsByDefault': moveImportsByDefault,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['moveImportsByDefault'] is! bool) {
      throw const FormatException('TAGTAG 设置文件无效');
    }
    return UserPreferences(
      moveImportsByDefault: json['moveImportsByDefault'] as bool,
    );
  }
}

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

  Future<UserPreferences> loadPreferences() async {
    final file = await _preferencesFile();
    if (!await file.exists()) {
      return const UserPreferences();
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return UserPreferences.fromJson(decoded);
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final file = await _preferencesFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
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

  Future<File> _preferencesFile() async {
    final root = await directory;
    return File('${root.path}${Platform.pathSeparator}preferences.json');
  }

  Future<Directory> _ensureDirectory(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
