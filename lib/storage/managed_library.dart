import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../models/tag_models.dart' show newId;

enum ImportMode { copy, move }

enum ManagedResourceKind { file, folder }

enum ManagedResourceStatus { managed, missing }

enum ManagedOperationType {
  importCopy,
  importMove,
  exitRestore,
  exitMove,
  exitRecycle,
}

enum ConsistencyFindingType { untracked, missing }

abstract interface class RecycleBinGateway {
  Future<String> recycle(String resourcePath);

  Future<void> restore(String token, String destinationPath);
}

class ManagedResource {
  const ManagedResource({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.status,
    required this.originalPath,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String relativePath;
  final ManagedResourceKind kind;
  final ManagedResourceStatus status;
  final String? originalPath;
  final int? sizeBytes;
  final DateTime modifiedAt;
  final DateTime createdAt;
}

class ManagedOperation {
  const ManagedOperation({
    required this.id,
    required this.type,
    required this.resourceId,
    required this.sourcePath,
    required this.destinationRelativePath,
    required this.createdAt,
    required this.undoneAt,
    this.contextJson,
  });

  final String id;
  final ManagedOperationType type;
  final String resourceId;
  final String sourcePath;
  final String destinationRelativePath;
  final DateTime createdAt;
  final DateTime? undoneAt;
  final String? contextJson;
}

class ConsistencyFinding {
  const ConsistencyFinding({
    required this.id,
    required this.type,
    required this.relativePath,
    required this.resourceId,
    required this.detectedAt,
  });

  final String id;
  final ConsistencyFindingType type;
  final String relativePath;
  final String? resourceId;
  final DateTime detectedAt;
}

class ManagedLibrary {
  ManagedLibrary._({required this.root, required this._database});

  static const _metadataDirectoryName = '.tagtag';
  static const _databaseFileName = 'tagtag.sqlite';
  static const _schemaVersion = 4;

  final Directory root;
  final Database _database;

  static Future<ManagedLibrary> initialize(Directory root) async {
    final normalizedRoot = Directory(path.normalize(root.absolute.path));
    if (!await normalizedRoot.exists()) {
      await normalizedRoot.create(recursive: true);
    }
    final metadataDirectory = Directory(
      path.join(normalizedRoot.path, _metadataDirectoryName),
    );
    await metadataDirectory.create(recursive: true);
    final database = sqlite3.open(
      path.join(metadataDirectory.path, _databaseFileName),
    );
    try {
      _configure(database);
      _prepareSchema(database);
      return ManagedLibrary._(root: normalizedRoot, database: database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  static Future<ManagedLibrary> open(Directory root) async {
    final normalizedRoot = Directory(path.normalize(root.absolute.path));
    final databaseFile = File(
      path.join(normalizedRoot.path, _metadataDirectoryName, _databaseFileName),
    );
    if (!await databaseFile.exists()) {
      throw const FileSystemException('该目录尚未初始化为 TAGTAG 存储根');
    }
    final database = sqlite3.open(databaseFile.path);
    try {
      _configure(database);
      _prepareSchema(database);
      return ManagedLibrary._(root: normalizedRoot, database: database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  Future<List<ManagedResource>> listResources() async {
    final rows = _database.select('''
      SELECT id, name, relative_path, kind, status, original_path,
             size_bytes, modified_at, created_at
      FROM resources
      ORDER BY created_at DESC
    ''');
    return rows
        .map(
          (row) => ManagedResource(
            id: row['id'] as String,
            name: row['name'] as String,
            relativePath: row['relative_path'] as String,
            kind: ManagedResourceKind.values.byName(row['kind'] as String),
            status: ManagedResourceStatus.values.byName(
              row['status'] as String,
            ),
            originalPath: row['original_path'] as String?,
            sizeBytes: row['size_bytes'] as int?,
            modifiedAt: DateTime.parse(row['modified_at'] as String),
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<ManagedResource> importResource({
    required FileSystemEntity source,
    required String targetDirectory,
    ImportMode mode = ImportMode.copy,
  }) async {
    final sourceType = await FileSystemEntity.type(source.absolute.path);
    if (sourceType == FileSystemEntityType.notFound) {
      throw FileSystemException('找不到导入源', source.path);
    }
    if (sourceType != FileSystemEntityType.file &&
        sourceType != FileSystemEntityType.directory) {
      throw UnsupportedError('只支持导入普通文件或文件夹');
    }
    final relativeDirectory = _normalizeRelativeDirectory(targetDirectory);
    final relativePath = path.posix.join(
      relativeDirectory,
      path.basename(source.path),
    );
    final destinationPath = _absolutePath(relativePath);
    if (await FileSystemEntity.type(destinationPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标位置已存在同名资源，TAGTAG 不会覆盖', destinationPath);
    }

    await Directory(path.dirname(destinationPath)).create(recursive: true);
    await _copyEntity(source.path, destinationPath, sourceType);
    var transactionActive = false;
    try {
      final stat = await FileStat.stat(destinationPath);
      final now = DateTime.now().toUtc();
      final resource = ManagedResource(
        id: newId('resource'),
        name: path.basename(source.path),
        relativePath: relativePath,
        kind: sourceType == FileSystemEntityType.file
            ? ManagedResourceKind.file
            : ManagedResourceKind.folder,
        status: ManagedResourceStatus.managed,
        originalPath: path.normalize(source.absolute.path),
        sizeBytes: sourceType == FileSystemEntityType.file ? stat.size : null,
        modifiedAt: stat.modified.toUtc(),
        createdAt: now,
      );
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO resources(
            id, name, relative_path, kind, status, original_path,
            size_bytes, modified_at, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          resource.id,
          resource.name,
          resource.relativePath,
          resource.kind.name,
          resource.status.name,
          resource.originalPath,
          resource.sizeBytes,
          resource.modifiedAt.toIso8601String(),
          resource.createdAt.toIso8601String(),
        ],
      );
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at
          ) VALUES (?, ?, ?, ?, ?, ?, NULL)
        ''',
        [
          newId('operation'),
          mode == ImportMode.copy ? 'import_copy' : 'import_move',
          resource.id,
          resource.originalPath,
          resource.relativePath,
          resource.createdAt.toIso8601String(),
        ],
      );
      if (mode == ImportMode.move) {
        await _deleteEntity(source.path, sourceType);
      }
      _database.execute('COMMIT');
      transactionActive = false;
      return resource;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (mode == ImportMode.move &&
          await FileSystemEntity.type(source.path) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(destinationPath) !=
              FileSystemEntityType.notFound) {
        await Directory(path.dirname(source.path)).create(recursive: true);
        await _copyEntity(destinationPath, source.path, sourceType);
      }
      if (await FileSystemEntity.type(destinationPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(destinationPath, sourceType);
      }
      rethrow;
    }
  }

  Future<List<ManagedOperation>> listOperations() async {
    final rows = _database.select('''
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at, context_json
      FROM operations
      ORDER BY created_at DESC
    ''');
    return rows
        .map(
          (row) => ManagedOperation(
            id: row['id'] as String,
            type: switch (row['type'] as String) {
              'import_copy' => ManagedOperationType.importCopy,
              'import_move' => ManagedOperationType.importMove,
              'exit_restore' => ManagedOperationType.exitRestore,
              'exit_move' => ManagedOperationType.exitMove,
              'exit_recycle' => ManagedOperationType.exitRecycle,
              final value => throw FormatException('未知操作类型: $value'),
            },
            resourceId: row['resource_id'] as String,
            sourcePath: row['source_path'] as String,
            destinationRelativePath: row['destination_relative_path'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            undoneAt: row['undone_at'] == null
                ? null
                : DateTime.parse(row['undone_at'] as String),
            contextJson: row['context_json'] as String?,
          ),
        )
        .toList();
  }

  Future<ManagedOperation> restoreToOriginalPath(
    String resourceId, {
    String? contextJson,
  }) async {
    final matches = (await listResources()).where(
      (resource) => resource.id == resourceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', '找不到受管资源');
    }
    final resource = matches.single;
    final originalPath = resource.originalPath;
    if (originalPath == null || originalPath.isEmpty) {
      throw StateError('该资源没有可恢复的先前路径');
    }
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final managedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(managedPath) != type) {
      throw FileSystemException('受管资源已缺失，无法恢复到先前路径', managedPath);
    }
    if (await FileSystemEntity.type(originalPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('先前路径已存在同名资源，TAGTAG 不会覆盖', originalPath);
    }

    final operation = ManagedOperation(
      id: newId('operation'),
      type: ManagedOperationType.exitRestore,
      resourceId: resource.id,
      sourcePath: originalPath,
      destinationRelativePath: resource.relativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
      contextJson: _exitContextJson(resource, contextJson),
    );
    await Directory(path.dirname(originalPath)).create(recursive: true);
    await _copyEntity(managedPath, originalPath, type);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at, context_json
          ) VALUES (?, 'exit_restore', ?, ?, ?, ?, NULL, ?)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
          operation.contextJson,
        ],
      );
      _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      await _deleteEntity(managedPath, type);
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(managedPath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(originalPath) == type) {
        await Directory(path.dirname(managedPath)).create(recursive: true);
        await _copyEntity(originalPath, managedPath, type);
      }
      if (await FileSystemEntity.type(originalPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(originalPath, type);
      }
      rethrow;
    }
  }

  Future<ManagedOperation> moveToSpecifiedPath(
    String resourceId,
    String destinationPath, {
    String? contextJson,
  }) async {
    final matches = (await listResources()).where(
      (resource) => resource.id == resourceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', '找不到受管资源');
    }
    final resource = matches.single;
    final normalizedDestination = path.normalize(
      path.absolute(destinationPath),
    );
    if (path.equals(normalizedDestination, root.path) ||
        path.isWithin(root.path, normalizedDestination)) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        '退出管理的目标必须位于 TAGTAG 存储根之外',
      );
    }
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final managedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(managedPath) != type) {
      throw FileSystemException('受管资源已缺失，无法移动到指定位置', managedPath);
    }
    if (await FileSystemEntity.type(normalizedDestination) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        '指定位置已存在同名资源，TAGTAG 不会覆盖',
        normalizedDestination,
      );
    }

    final operation = ManagedOperation(
      id: newId('operation'),
      type: ManagedOperationType.exitMove,
      resourceId: resource.id,
      sourcePath: normalizedDestination,
      destinationRelativePath: resource.relativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
      contextJson: _exitContextJson(resource, contextJson),
    );
    await Directory(
      path.dirname(normalizedDestination),
    ).create(recursive: true);
    await _copyEntity(managedPath, normalizedDestination, type);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at, context_json
          ) VALUES (?, 'exit_move', ?, ?, ?, ?, NULL, ?)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
          operation.contextJson,
        ],
      );
      _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      await _deleteEntity(managedPath, type);
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(managedPath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(normalizedDestination) == type) {
        await Directory(path.dirname(managedPath)).create(recursive: true);
        await _copyEntity(normalizedDestination, managedPath, type);
      }
      if (await FileSystemEntity.type(normalizedDestination) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(normalizedDestination, type);
      }
      rethrow;
    }
  }

  Future<ManagedOperation> moveToRecycleBin(
    String resourceId, {
    required RecycleBinGateway recycleBin,
    String? contextJson,
  }) async {
    final matches = (await listResources()).where(
      (resource) => resource.id == resourceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', '找不到受管资源');
    }
    final resource = matches.single;
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final managedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(managedPath) != type) {
      throw FileSystemException('受管资源已缺失，无法移入回收站', managedPath);
    }

    final operationId = newId('operation');
    final token = await recycleBin.recycle(managedPath);
    if (token.isEmpty) {
      throw StateError('Windows 回收站没有返回可撤销标识');
    }
    if (await FileSystemEntity.type(managedPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('资源未成功移入 Windows 回收站', managedPath);
    }
    final operation = ManagedOperation(
      id: operationId,
      type: ManagedOperationType.exitRecycle,
      resourceId: resource.id,
      sourcePath: token,
      destinationRelativePath: resource.relativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
      contextJson: _exitContextJson(resource, contextJson),
    );
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at, context_json
          ) VALUES (?, 'exit_recycle', ?, ?, ?, ?, NULL, ?)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
          operation.contextJson,
        ],
      );
      _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(managedPath) ==
          FileSystemEntityType.notFound) {
        await recycleBin.restore(token, managedPath);
      }
      rethrow;
    }
  }

  Future<List<ConsistencyFinding>> scanConsistency() async {
    final resources = await listResources();
    final findings = <ConsistencyFinding>[];
    final now = DateTime.now().toUtc();
    final managedPaths = {
      for (final resource in resources) resource.relativePath,
    };
    final managedFolders = {
      for (final resource in resources)
        if (resource.kind == ManagedResourceKind.folder) resource.relativePath,
    };
    final managedAncestors = <String>{};
    for (final resourcePath in managedPaths) {
      var parent = path.posix.dirname(resourcePath);
      while (parent != '.') {
        managedAncestors.add(parent);
        parent = path.posix.dirname(parent);
      }
    }

    for (final resource in resources) {
      final actualType = await FileSystemEntity.type(
        _absolutePath(resource.relativePath),
      );
      final expectedType = resource.kind == ManagedResourceKind.file
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (actualType != expectedType) {
        findings.add(
          ConsistencyFinding(
            id: newId('finding'),
            type: ConsistencyFindingType.missing,
            relativePath: resource.relativePath,
            resourceId: resource.id,
            detectedAt: now,
          ),
        );
      }
    }

    Future<void> inspect(FileSystemEntity entity) async {
      final relativePath = path
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (relativePath == _metadataDirectoryName) {
        return;
      }
      if (managedPaths.contains(relativePath)) {
        return;
      }
      if (managedAncestors.contains(relativePath) && entity is Directory) {
        await for (final child in entity.list(followLinks: false)) {
          await inspect(child);
        }
        return;
      }
      if (managedFolders.any((folder) => relativePath.startsWith('$folder/'))) {
        return;
      }
      findings.add(
        ConsistencyFinding(
          id: newId('finding'),
          type: ConsistencyFindingType.untracked,
          relativePath: relativePath,
          resourceId: null,
          detectedAt: now,
        ),
      );
    }

    await for (final child in root.list(followLinks: false)) {
      await inspect(child);
    }

    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('DELETE FROM consistency_findings');
      for (final finding in findings) {
        _database.execute(
          '''
            INSERT INTO consistency_findings(
              id, type, relative_path, resource_id, detected_at
            ) VALUES (?, ?, ?, ?, ?)
          ''',
          [
            finding.id,
            finding.type.name,
            finding.relativePath,
            finding.resourceId,
            finding.detectedAt.toIso8601String(),
          ],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return findings;
  }

  Future<void> undo(String operationId, {RecycleBinGateway? recycleBin}) async {
    final matches = (await listOperations()).where(
      (operation) => operation.id == operationId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId', '找不到操作记录');
    }
    final operation = matches.single;
    if (operation.undoneAt != null) {
      throw StateError('该操作已经撤销');
    }
    if (operation.type == ManagedOperationType.exitRestore ||
        operation.type == ManagedOperationType.exitMove) {
      await _undoExit(operation);
      return;
    }
    if (operation.type == ManagedOperationType.exitRecycle) {
      if (recycleBin == null) {
        throw StateError('撤销回收站操作需要 Windows 回收站适配器');
      }
      await _undoRecycleExit(operation, recycleBin);
      return;
    }
    if (operation.type == ManagedOperationType.importMove &&
        await FileSystemEntity.type(operation.sourcePath) !=
            FileSystemEntityType.notFound) {
      throw FileSystemException('原路径已存在同名资源，TAGTAG 不会覆盖', operation.sourcePath);
    }
    final resources = (await listResources()).where(
      (resource) => resource.id == operation.resourceId,
    );
    if (resources.isEmpty) {
      throw StateError('操作对应的受管资源记录已不存在');
    }
    final resource = resources.single;
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final destinationPath = _absolutePath(operation.destinationRelativePath);
    if (await FileSystemEntity.type(destinationPath) ==
        FileSystemEntityType.notFound) {
      throw FileSystemException('受管资源已缺失，无法撤销导入', destinationPath);
    }
    final stagingDirectory = Directory(
      path.join(root.path, _metadataDirectoryName, 'undo-staging'),
    );
    await stagingDirectory.create(recursive: true);
    final stagingPath = path.join(
      stagingDirectory.path,
      '${operation.id}-${path.basename(destinationPath)}',
    );
    await _renameEntity(destinationPath, stagingPath, type);

    var transactionActive = false;
    var restoredOriginal = false;
    try {
      if (operation.type == ManagedOperationType.importMove) {
        await Directory(
          path.dirname(operation.sourcePath),
        ).create(recursive: true);
        await _copyEntity(stagingPath, operation.sourcePath, type);
        restoredOriginal = true;
      }
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      _database.execute('COMMIT');
      transactionActive = false;
      await _deleteEntity(stagingPath, type);
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (restoredOriginal &&
          await FileSystemEntity.type(operation.sourcePath) !=
              FileSystemEntityType.notFound) {
        await _deleteEntity(operation.sourcePath, type);
      }
      if (await FileSystemEntity.type(stagingPath) !=
          FileSystemEntityType.notFound) {
        await Directory(path.dirname(destinationPath)).create(recursive: true);
        await _renameEntity(stagingPath, destinationPath, type);
      }
      rethrow;
    }
  }

  Future<void> _undoExit(ManagedOperation operation) async {
    final type = await FileSystemEntity.type(
      operation.sourcePath,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('退出位置的资源已缺失，无法撤销退出管理', operation.sourcePath);
    }
    final managedPath = _absolutePath(operation.destinationRelativePath);
    if (await FileSystemEntity.type(managedPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原受管路径已存在同名资源，TAGTAG 不会覆盖', managedPath);
    }

    await Directory(path.dirname(managedPath)).create(recursive: true);
    await _copyEntity(operation.sourcePath, managedPath, type);
    var transactionActive = false;
    try {
      final stat = await FileStat.stat(managedPath);
      final context = operation.contextJson == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(operation.contextJson!) as Map,
            );
      final originalPath = operation.type == ManagedOperationType.exitRestore
          ? operation.sourcePath
          : context['_resourceOriginalPath'] as String?;
      final resourceCreatedAt = DateTime.tryParse(
        context['_resourceCreatedAt'] as String? ?? '',
      );
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO resources(
            id, name, relative_path, kind, status, original_path,
            size_bytes, modified_at, created_at
          ) VALUES (?, ?, ?, ?, 'managed', ?, ?, ?, ?)
        ''',
        [
          operation.resourceId,
          path.posix.basename(operation.destinationRelativePath),
          operation.destinationRelativePath,
          type == FileSystemEntityType.file ? 'file' : 'folder',
          originalPath,
          type == FileSystemEntityType.file ? stat.size : null,
          stat.modified.toUtc().toIso8601String(),
          (resourceCreatedAt ?? operation.createdAt).toIso8601String(),
        ],
      );
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      await _deleteEntity(operation.sourcePath, type);
      _database.execute('COMMIT');
      transactionActive = false;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(operation.sourcePath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(managedPath) == type) {
        await Directory(
          path.dirname(operation.sourcePath),
        ).create(recursive: true);
        await _copyEntity(managedPath, operation.sourcePath, type);
      }
      if (await FileSystemEntity.type(managedPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(managedPath, type);
      }
      rethrow;
    }
  }

  Future<void> _undoRecycleExit(
    ManagedOperation operation,
    RecycleBinGateway recycleBin,
  ) async {
    final managedPath = _absolutePath(operation.destinationRelativePath);
    if (await FileSystemEntity.type(managedPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原受管路径已存在同名资源，TAGTAG 不会覆盖', managedPath);
    }

    await Directory(path.dirname(managedPath)).create(recursive: true);
    await recycleBin.restore(operation.sourcePath, managedPath);
    final type = await FileSystemEntity.type(managedPath, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('回收站资源未恢复到受管路径', managedPath);
    }
    var transactionActive = false;
    try {
      final stat = await FileStat.stat(managedPath);
      final context = operation.contextJson == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(operation.contextJson!) as Map,
            );
      final resourceCreatedAt = DateTime.tryParse(
        context['_resourceCreatedAt'] as String? ?? '',
      );
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO resources(
            id, name, relative_path, kind, status, original_path,
            size_bytes, modified_at, created_at
          ) VALUES (?, ?, ?, ?, 'managed', ?, ?, ?, ?)
        ''',
        [
          operation.resourceId,
          path.posix.basename(operation.destinationRelativePath),
          operation.destinationRelativePath,
          type == FileSystemEntityType.file ? 'file' : 'folder',
          context['_resourceOriginalPath'] as String?,
          type == FileSystemEntityType.file ? stat.size : null,
          stat.modified.toUtc().toIso8601String(),
          (resourceCreatedAt ?? operation.createdAt).toIso8601String(),
        ],
      );
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      _database.execute('COMMIT');
      transactionActive = false;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(managedPath) !=
          FileSystemEntityType.notFound) {
        final replacementToken = await recycleBin.recycle(managedPath);
        _database.execute(
          'UPDATE operations SET source_path = ? WHERE id = ?',
          [replacementToken, operation.id],
        );
      }
      rethrow;
    }
  }

  static String _exitContextJson(
    ManagedResource resource,
    String? contextJson,
  ) {
    final context = <String, dynamic>{};
    if (contextJson != null) {
      final decoded = jsonDecode(contextJson);
      if (decoded is! Map) {
        throw const FormatException('退出管理操作上下文必须是 JSON 对象');
      }
      context.addAll(Map<String, dynamic>.from(decoded));
    }
    context['_resourceOriginalPath'] = resource.originalPath;
    context['_resourceCreatedAt'] = resource.createdAt.toIso8601String();
    return jsonEncode(context);
  }

  Future<Directory> createBackup(
    Directory destinationDirectory, {
    Map<String, String> metadataDocuments = const {},
  }) async {
    final destinationRoot = Directory(
      path.normalize(destinationDirectory.absolute.path),
    );
    if (path.equals(destinationRoot.path, root.path) ||
        path.isWithin(root.path, destinationRoot.path)) {
      throw ArgumentError.value(
        destinationDirectory.path,
        'destinationDirectory',
        '备份目录必须位于存储根之外',
      );
    }
    await destinationRoot.create(recursive: true);
    final createdAt = DateTime.now().toUtc();
    final suffix = createdAt.toIso8601String().replaceAll(':', '-');
    final name = 'tagtag-backup-$suffix';
    final finalDirectory = Directory(path.join(destinationRoot.path, name));
    final temporaryDirectory = Directory(
      path.join(destinationRoot.path, '.$name.tmp'),
    );
    if (await finalDirectory.exists() || await temporaryDirectory.exists()) {
      throw FileSystemException('备份目标已存在', finalDirectory.path);
    }

    try {
      final metadataDirectory = Directory(
        path.join(temporaryDirectory.path, 'metadata'),
      );
      final resourcesDirectory = Directory(
        path.join(temporaryDirectory.path, 'resources'),
      );
      await metadataDirectory.create(recursive: true);
      await resourcesDirectory.create(recursive: true);

      final snapshotDatabase = sqlite3.open(
        path.join(metadataDirectory.path, _databaseFileName),
      );
      try {
        await _database.backup(snapshotDatabase).drain<void>();
      } finally {
        snapshotDatabase.close();
      }
      for (final entry in metadataDocuments.entries) {
        if (entry.key == _databaseFileName ||
            path.basename(entry.key) != entry.key ||
            entry.key == '.' ||
            entry.key == '..') {
          throw ArgumentError.value(
            entry.key,
            'metadataDocuments',
            '备份元数据名称必须是普通文件名且不能覆盖 SQLite 快照',
          );
        }
        await File(
          path.join(metadataDirectory.path, entry.key),
        ).writeAsString(entry.value, flush: true);
      }

      final resources = await listResources();
      for (final resource in resources) {
        final type = resource.kind == ManagedResourceKind.file
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        final sourcePath = _absolutePath(resource.relativePath);
        if (await FileSystemEntity.type(sourcePath) != type) {
          throw FileSystemException('受管资源缺失，无法创建完整备份', sourcePath);
        }
        final backupPath = path.joinAll([
          resourcesDirectory.path,
          ...resource.relativePath.split('/'),
        ]);
        await Directory(path.dirname(backupPath)).create(recursive: true);
        await _copyEntity(sourcePath, backupPath, type);
      }

      final manifest = File(
        path.join(temporaryDirectory.path, 'manifest.json'),
      );
      await manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': 1,
          'createdAt': createdAt.toIso8601String(),
          'resourceCount': resources.length,
          'resources': [
            for (final resource in resources)
              {
                'id': resource.id,
                'relativePath': resource.relativePath,
                'kind': resource.kind.name,
                'sizeBytes': resource.sizeBytes,
              },
          ],
        }),
        flush: true,
      );
      return await temporaryDirectory.rename(finalDirectory.path);
    } catch (_) {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> close() async {
    _database.close();
  }

  String _absolutePath(String relativePath) =>
      path.joinAll([root.path, ...relativePath.split('/')]);

  static String _normalizeRelativeDirectory(String value) {
    final normalized = path.posix.normalize(value.trim().replaceAll('\\', '/'));
    if (path.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized == _metadataDirectoryName ||
        normalized.startsWith('$_metadataDirectoryName/')) {
      throw ArgumentError.value(value, 'targetDirectory', '目标必须位于存储根内');
    }
    return normalized == '.' ? '' : normalized;
  }

  static Future<void> _copyEntity(
    String sourcePath,
    String destinationPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.file) {
      await File(sourcePath).copy(destinationPath);
      return;
    }
    final sourceDirectory = Directory(sourcePath);
    await Directory(destinationPath).create(recursive: true);
    await for (final child in sourceDirectory.list(followLinks: false)) {
      final childType = await FileSystemEntity.type(
        child.path,
        followLinks: false,
      );
      if (childType == FileSystemEntityType.link) {
        throw FileSystemException('文件夹中包含暂不支持的符号链接', child.path);
      }
      await _copyEntity(
        child.path,
        path.join(destinationPath, path.basename(child.path)),
        childType,
      );
    }
  }

  static Future<void> _deleteEntity(
    String entityPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.directory) {
      await Directory(entityPath).delete(recursive: true);
    } else {
      await File(entityPath).delete();
    }
  }

  static Future<void> _renameEntity(
    String sourcePath,
    String destinationPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.directory) {
      await Directory(sourcePath).rename(destinationPath);
    } else {
      await File(sourcePath).rename(destinationPath);
    }
  }

  static void _configure(Database database) {
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA journal_mode = WAL');
  }

  static void _prepareSchema(Database database) {
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute('''
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      final versionRows = database.select(
        "SELECT value FROM metadata WHERE key = 'schema_version'",
      );
      final version = versionRows.isEmpty
          ? null
          : int.tryParse(versionRows.single['value'] as String);
      switch (version) {
        case null:
          _createSchema(database);
        case 1:
          _migrateV1ToV2(database);
        case 2:
          _migrateV2ToV3(database);
        case 3:
          _migrateV3ToV4(database);
        case _schemaVersion:
          _createSchema(database);
        default:
          throw const FormatException('不支持的 TAGTAG 元数据版本');
      }
      database.execute(
        'INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)',
        ['schema_version', '$_schemaVersion'],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static void _migrateV1ToV2(Database database) {
    database.execute('ALTER TABLE operations RENAME TO operations_v1');
    _createOperationsTable(database);
    database.execute('''
      INSERT INTO operations(
        id, type, resource_id, source_path,
        destination_relative_path, created_at, undone_at
      )
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at
      FROM operations_v1
    ''');
    database.execute('DROP TABLE operations_v1');
  }

  static void _migrateV2ToV3(Database database) {
    database.execute('ALTER TABLE operations RENAME TO operations_v2');
    _createOperationsTable(database);
    database.execute('''
      INSERT INTO operations(
        id, type, resource_id, source_path,
        destination_relative_path, created_at, undone_at, context_json
      )
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at, context_json
      FROM operations_v2
    ''');
    database.execute('DROP TABLE operations_v2');
  }

  static void _migrateV3ToV4(Database database) {
    database.execute('ALTER TABLE operations RENAME TO operations_v3');
    _createOperationsTable(database);
    database.execute('''
      INSERT INTO operations(
        id, type, resource_id, source_path,
        destination_relative_path, created_at, undone_at, context_json
      )
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at, context_json
      FROM operations_v3
    ''');
    database.execute('DROP TABLE operations_v3');
  }

  static void _createSchema(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS resources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        relative_path TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL CHECK (kind IN ('file', 'folder')),
        status TEXT NOT NULL CHECK (status IN ('managed', 'missing')),
        original_path TEXT,
        size_bytes INTEGER,
        modified_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _createOperationsTable(database);
    database.execute('''
      CREATE TABLE IF NOT EXISTS consistency_findings (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK (type IN ('untracked', 'missing')),
        relative_path TEXT NOT NULL,
        resource_id TEXT,
        detected_at TEXT NOT NULL
      )
    ''');
  }

  static void _createOperationsTable(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS operations (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL CHECK (
          type IN (
            'import_copy', 'import_move', 'exit_restore',
            'exit_move', 'exit_recycle'
          )
        ),
        resource_id TEXT NOT NULL,
        source_path TEXT NOT NULL,
        destination_relative_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        undone_at TEXT,
        context_json TEXT
      )
    ''');
  }
}
