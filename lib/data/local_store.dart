import 'dart:convert';
import 'dart:io';

import '../models/tag_models.dart';

class UserPreferences {
  const UserPreferences({
    this.moveImportsByDefault = false,
    this.floatingDropTargetEnabled = false,
    this.closeToTray = true,
    this.autoStartEnabled = false,
    this.startupView = 'last',
    this.appearanceTheme = 'light',
    this.interfaceDensity = 'compact',
    this.quickTagShortcut = 'Ctrl+Shift+T',
    this.uniqueTagNames = false,
    this.namingTemplate = '',
    this.floatingTargetX,
    this.floatingTargetY,
    this.backupEnabled = false,
    this.backupDirectory = '',
    this.backupIntervalHours = 24,
    this.backupIncremental = false,
    this.lastBackupAt = '',
  });

  final bool moveImportsByDefault;
  final bool floatingDropTargetEnabled;
  final bool closeToTray;

  /// Launch TAGTAG automatically when the user logs into Windows.
  final bool autoStartEnabled;
  final String startupView;
  final String appearanceTheme;
  final String interfaceDensity;
  final String quickTagShortcut;

  /// Global import naming template; empty keeps the original file names.
  /// Placeholders: {原名} {日期} {时间} {标签} {序号}.
  final String namingTemplate;

  /// When true, tag names are unique within a space unless the tag is
  /// explicitly exempted (TagNamePolicy.free).
  final bool uniqueTagNames;

  /// Last persisted floating drop target center (fully visible), in screen
  /// coordinates. Null until the ball is first dragged.
  final double? floatingTargetX;
  final double? floatingTargetY;

  /// Scheduled backups. [backupDirectory] is an absolute path outside the
  /// storage root; empty disables scheduling even when [backupEnabled] is
  /// true. [backupIntervalHours] is the minimum spacing between runs.
  /// [backupIncremental] selects the incremental strategy (fixed
  /// `TAGTAG-incremental` directory) over timestamped full backups.
  /// [lastBackupAt] is an ISO-8601 timestamp; empty means never attempted.
  final bool backupEnabled;
  final String backupDirectory;
  final int backupIntervalHours;
  final bool backupIncremental;
  final String lastBackupAt;

  UserPreferences copyWith({
    bool? moveImportsByDefault,
    bool? floatingDropTargetEnabled,
    bool? closeToTray,
    bool? autoStartEnabled,
    String? startupView,
    String? appearanceTheme,
    String? interfaceDensity,
    String? quickTagShortcut,
    bool? uniqueTagNames,
    String? namingTemplate,
    double? floatingTargetX,
    double? floatingTargetY,
    bool? backupEnabled,
    String? backupDirectory,
    int? backupIntervalHours,
    bool? backupIncremental,
    String? lastBackupAt,
  }) => UserPreferences(
    moveImportsByDefault: moveImportsByDefault ?? this.moveImportsByDefault,
    floatingDropTargetEnabled:
        floatingDropTargetEnabled ?? this.floatingDropTargetEnabled,
    closeToTray: closeToTray ?? this.closeToTray,
    autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
    startupView: startupView ?? this.startupView,
    appearanceTheme: appearanceTheme ?? this.appearanceTheme,
    interfaceDensity: interfaceDensity ?? this.interfaceDensity,
    quickTagShortcut: quickTagShortcut ?? this.quickTagShortcut,
    uniqueTagNames: uniqueTagNames ?? this.uniqueTagNames,
    namingTemplate: namingTemplate ?? this.namingTemplate,
    floatingTargetX: floatingTargetX ?? this.floatingTargetX,
    floatingTargetY: floatingTargetY ?? this.floatingTargetY,
    backupEnabled: backupEnabled ?? this.backupEnabled,
    backupDirectory: backupDirectory ?? this.backupDirectory,
    backupIntervalHours: backupIntervalHours ?? this.backupIntervalHours,
    backupIncremental: backupIncremental ?? this.backupIncremental,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'moveImportsByDefault': moveImportsByDefault,
    'floatingDropTargetEnabled': floatingDropTargetEnabled,
    'closeToTray': closeToTray,
    'autoStartEnabled': autoStartEnabled,
    'startupView': startupView,
    'appearanceTheme': appearanceTheme,
    'interfaceDensity': interfaceDensity,
    'quickTagShortcut': quickTagShortcut,
    'uniqueTagNames': uniqueTagNames,
    'namingTemplate': namingTemplate,
    'floatingTargetX': floatingTargetX,
    'floatingTargetY': floatingTargetY,
    'backupEnabled': backupEnabled,
    'backupDirectory': backupDirectory,
    'backupIntervalHours': backupIntervalHours,
    'backupIncremental': backupIncremental,
    'lastBackupAt': lastBackupAt,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final floatingDropTargetEnabled = json['floatingDropTargetEnabled'];
    final closeToTray = json['closeToTray'];
    final autoStartEnabled = json['autoStartEnabled'];
    final startupView = json['startupView'];
    final appearanceTheme = json['appearanceTheme'];
    final interfaceDensity = json['interfaceDensity'];
    final quickTagShortcut = json['quickTagShortcut'];
    final floatingTargetX = json['floatingTargetX'];
    final floatingTargetY = json['floatingTargetY'];
    final backupEnabled = json['backupEnabled'];
    final backupDirectory = json['backupDirectory'];
    final backupIntervalHours = json['backupIntervalHours'];
    final backupIncremental = json['backupIncremental'];
    final lastBackupAt = json['lastBackupAt'];
    if (json['version'] != 1 ||
        json['moveImportsByDefault'] is! bool ||
        (floatingDropTargetEnabled != null &&
            floatingDropTargetEnabled is! bool) ||
        (closeToTray != null && closeToTray is! bool) ||
        (autoStartEnabled != null && autoStartEnabled is! bool) ||
        (startupView != null || startupView is String) &&
            !const {'last', 'all', 'inbox'}.contains(startupView) ||
        (appearanceTheme != null || appearanceTheme is String) &&
            !const {'light', 'dark'}.contains(appearanceTheme) ||
        (interfaceDensity != null || interfaceDensity is String) &&
            !const {'compact', 'comfortable'}.contains(interfaceDensity) ||
        (quickTagShortcut != null && quickTagShortcut is! String) ||
        (json['uniqueTagNames'] != null && json['uniqueTagNames'] is! bool) ||
        (json['namingTemplate'] != null && json['namingTemplate'] is! String) ||
        (floatingTargetX != null && floatingTargetX is! num) ||
        (floatingTargetY != null && floatingTargetY is! num) ||
        (backupEnabled != null && backupEnabled is! bool) ||
        (backupDirectory != null && backupDirectory is! String) ||
        (backupIntervalHours != null &&
            (backupIntervalHours is! int || backupIntervalHours < 1)) ||
        (backupIncremental != null && backupIncremental is! bool) ||
        (lastBackupAt != null &&
            (lastBackupAt is! String ||
                lastBackupAt.isNotEmpty &&
                    DateTime.tryParse(lastBackupAt) == null))) {
      throw const FormatException('TAGTAG 设置文件无效');
    }
    return UserPreferences(
      moveImportsByDefault: json['moveImportsByDefault'] as bool,
      floatingDropTargetEnabled: floatingDropTargetEnabled as bool? ?? false,
      closeToTray: closeToTray as bool? ?? true,
      autoStartEnabled: autoStartEnabled as bool? ?? false,
      startupView: startupView as String? ?? 'last',
      appearanceTheme: appearanceTheme as String? ?? 'light',
      interfaceDensity: interfaceDensity as String? ?? 'compact',
      quickTagShortcut: quickTagShortcut as String? ?? 'Ctrl+Shift+T',
      uniqueTagNames: json['uniqueTagNames'] as bool? ?? false,
      namingTemplate: json['namingTemplate'] as String? ?? '',
      floatingTargetX: (floatingTargetX as num?)?.toDouble(),
      floatingTargetY: (floatingTargetY as num?)?.toDouble(),
      backupEnabled: backupEnabled as bool? ?? false,
      backupDirectory: backupDirectory as String? ?? '',
      backupIntervalHours: backupIntervalHours as int? ?? 24,
      backupIncremental: backupIncremental as bool? ?? false,
      lastBackupAt: lastBackupAt as String? ?? '',
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
