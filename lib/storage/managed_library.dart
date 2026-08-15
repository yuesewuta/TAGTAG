import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../models/tag_models.dart' show AppState, newId;

enum ImportMode { copy, move }

enum ManagedResourceKind { file, folder }

enum ManagedResourceStatus { managed, missing }

enum ManagedOperationType {
  importCopy,
  importMove,
  exitRestore,
  exitMove,
  exitRecycle,
  takeover,
  untrackedMoveOut,
  externalMoveAccept,
  externalMoveRestore,
  organizeMove,
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

class PackagedResourceImport {
  const PackagedResourceImport({
    required this.id,
    required this.source,
    required this.targetRelativePath,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final FileSystemEntity source;
  final String targetRelativePath;
  final ManagedResourceKind kind;
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

class BackupValidationResult {
  const BackupValidationResult({
    required this.backupDirectory,
    required this.formatVersion,
    required this.createdAt,
    required this.resourceCount,
    required this.tagStateJson,
    required this.preferencesJson,
  });

  final Directory backupDirectory;
  final int formatVersion;
  final DateTime createdAt;
  final int resourceCount;
  final String tagStateJson;
  final String? preferencesJson;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.root,
    required this.tagStateJson,
    required this.preferencesJson,
  });

  final Directory root;
  final String tagStateJson;
  final String? preferencesJson;
}

class TagDomainMetadata {
  const TagDomainMetadata({
    required this.tagStateJson,
    required this.preferencesJson,
  });

  final String tagStateJson;
  final String preferencesJson;
}

class ManagedLibrary {
  ManagedLibrary._({required this.root, required this._database});

  static const _metadataDirectoryName = '.tagtag';
  static const _databaseFileName = 'tagtag.sqlite';
  static const _schemaVersion = 7;
  static const _tagStateMetadataKey = 'tag_state_json';
  static const _preferencesMetadataKey = 'preferences_json';

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

  Future<TagDomainMetadata?> readTagDomainMetadata() async {
    final rows = _database.select(
      'SELECT key, value FROM metadata WHERE key IN (?, ?)',
      [_tagStateMetadataKey, _preferencesMetadataKey],
    );
    if (rows.isEmpty) {
      return null;
    }
    final values = <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final tagStateJson = values[_tagStateMetadataKey];
    final preferencesJson = values[_preferencesMetadataKey];
    if (tagStateJson == null || preferencesJson == null) {
      throw const FormatException('TAGTAG 标签元数据不完整');
    }
    return TagDomainMetadata(
      tagStateJson: tagStateJson,
      preferencesJson: preferencesJson,
    );
  }

  Future<void> writeTagDomainMetadata({
    required String tagStateJson,
    required String preferencesJson,
  }) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)',
        [_tagStateMetadataKey, tagStateJson],
      );
      _database.execute(
        'INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)',
        [_preferencesMetadataKey, preferencesJson],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
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
    String? targetName,
  }) async {
    final sourceType = await FileSystemEntity.type(source.absolute.path);
    if (sourceType == FileSystemEntityType.notFound) {
      throw FileSystemException('找不到导入源', source.path);
    }
    if (sourceType != FileSystemEntityType.file &&
        sourceType != FileSystemEntityType.directory) {
      throw UnsupportedError('只支持导入普通文件或文件夹');
    }
    final importName = targetName ?? path.basename(source.path);
    if (importName.trim().isEmpty ||
        importName == '.' ||
        importName == '..' ||
        path.basename(importName) != importName) {
      throw ArgumentError.value(
        targetName,
        'targetName',
        '导入名称必须是不含路径分隔符的普通名称',
      );
    }
    final relativeDirectory = _normalizeRelativeDirectory(targetDirectory);
    final relativePath = path.posix.join(relativeDirectory, importName);
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
        name: importName,
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

  Future<List<ManagedResource>> importPackagedResources(
    List<PackagedResourceImport> imports,
  ) async {
    if (imports.isEmpty) {
      return const [];
    }
    final existing = await listResources();
    final existingIds = existing.map((resource) => resource.id).toSet();
    final importIds = <String>{};
    final normalizedImports = <PackagedResourceImport>[];
    for (final item in imports) {
      if (item.id.trim().isEmpty ||
          existingIds.contains(item.id) ||
          !importIds.add(item.id)) {
        throw StateError('空间包包含重复或已存在的资源 ID：${item.id}');
      }
      final relativePath = _normalizeRelativePath(item.targetRelativePath);
      final expectedType = item.kind == ManagedResourceKind.file
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (await FileSystemEntity.type(item.source.absolute.path) !=
          expectedType) {
        throw FileSystemException('空间包资源内容类型不一致', item.source.path);
      }
      normalizedImports.add(
        PackagedResourceImport(
          id: item.id,
          source: item.source,
          targetRelativePath: relativePath,
          kind: item.kind,
          createdAt: item.createdAt,
        ),
      );
    }
    final candidatePaths = normalizedImports
        .map((item) => item.targetRelativePath)
        .toList();
    for (var index = 0; index < candidatePaths.length; index++) {
      final candidate = candidatePaths[index];
      if (existing.any(
            (resource) =>
                resource.relativePath == candidate ||
                (resource.kind == ManagedResourceKind.folder &&
                    path.posix.isWithin(resource.relativePath, candidate)) ||
                (normalizedImports[index].kind == ManagedResourceKind.folder &&
                    path.posix.isWithin(candidate, resource.relativePath)),
          ) ||
          candidatePaths.indexed.any(
            (other) =>
                other.$1 != index &&
                (other.$2 == candidate ||
                    (normalizedImports[other.$1].kind ==
                            ManagedResourceKind.folder &&
                        path.posix.isWithin(other.$2, candidate)) ||
                    (normalizedImports[index].kind ==
                            ManagedResourceKind.folder &&
                        path.posix.isWithin(candidate, other.$2))),
          )) {
        throw FileSystemException('空间包导入目标与已有受管范围冲突', candidate);
      }
      final destination = _absolutePath(candidate);
      if (await FileSystemEntity.type(destination) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('空间包导入目标已存在，TAGTAG 不会覆盖', destination);
      }
    }

    final copied = <({String path, FileSystemEntityType type})>[];
    final resources = <ManagedResource>[];
    var transactionActive = false;
    try {
      for (final item in normalizedImports) {
        final destination = _absolutePath(item.targetRelativePath);
        final type = item.kind == ManagedResourceKind.file
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        await Directory(path.dirname(destination)).create(recursive: true);
        await _copyEntity(item.source.absolute.path, destination, type);
        copied.add((path: destination, type: type));
        final stat = await FileStat.stat(destination);
        resources.add(
          ManagedResource(
            id: item.id,
            name: path.posix.basename(item.targetRelativePath),
            relativePath: item.targetRelativePath,
            kind: item.kind,
            status: ManagedResourceStatus.managed,
            originalPath: null,
            sizeBytes: item.kind == ManagedResourceKind.file ? stat.size : null,
            modifiedAt: stat.modified.toUtc(),
            createdAt: item.createdAt.toUtc(),
          ),
        );
      }
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      for (final resource in resources) {
        _database.execute(
          '''
            INSERT INTO resources(
              id, name, relative_path, kind, status, original_path,
              size_bytes, modified_at, created_at
            ) VALUES (?, ?, ?, ?, 'managed', NULL, ?, ?, ?)
          ''',
          [
            resource.id,
            resource.name,
            resource.relativePath,
            resource.kind.name,
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
            ) VALUES (?, 'import_copy', ?, ?, ?, ?, NULL)
          ''',
          [
            newId('operation'),
            resource.id,
            'space-package',
            resource.relativePath,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
      _database.execute('COMMIT');
      transactionActive = false;
      return resources;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      for (final item in copied.reversed) {
        if (await FileSystemEntity.type(item.path) !=
            FileSystemEntityType.notFound) {
          await _deleteEntity(item.path, item.type);
        }
      }
      rethrow;
    }
  }

  Future<void> rollbackPackagedResources(Set<String> resourceIds) async {
    if (resourceIds.isEmpty) {
      return;
    }
    final resources = (await listResources())
        .where((resource) => resourceIds.contains(resource.id))
        .toList();
    final removed = <({ManagedResource resource, String stagingPath})>[];
    final staging = await Directory.systemTemp.createTemp('tagtag-rollback-');
    var transactionActive = false;
    try {
      for (final resource in resources) {
        final sourcePath = _absolutePath(resource.relativePath);
        final type = resource.kind == ManagedResourceKind.file
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        final stagingPath = path.join(staging.path, resource.id);
        await _copyEntity(sourcePath, stagingPath, type);
        await _deleteEntity(sourcePath, type);
        removed.add((resource: resource, stagingPath: stagingPath));
      }
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      for (final resource in resources) {
        _database.execute('DELETE FROM operations WHERE resource_id = ?', [
          resource.id,
        ]);
        _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      }
      _database.execute('COMMIT');
      transactionActive = false;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      for (final item in removed) {
        final destination = _absolutePath(item.resource.relativePath);
        final type = item.resource.kind == ManagedResourceKind.file
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        if (await FileSystemEntity.type(destination) ==
            FileSystemEntityType.notFound) {
          await Directory(path.dirname(destination)).create(recursive: true);
          await _copyEntity(item.stagingPath, destination, type);
        }
      }
      rethrow;
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
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
              'takeover' => ManagedOperationType.takeover,
              'untracked_move_out' => ManagedOperationType.untrackedMoveOut,
              'external_move_accept' => ManagedOperationType.externalMoveAccept,
              'external_move_restore' =>
                ManagedOperationType.externalMoveRestore,
              'organize_move' => ManagedOperationType.organizeMove,
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
    final resourceUpdates =
        <
          ({
            String id,
            ManagedResourceStatus status,
            int? size,
            DateTime? modified,
          })
        >[];
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
        resourceUpdates.add((
          id: resource.id,
          status: ManagedResourceStatus.missing,
          size: null,
          modified: null,
        ));
        continue;
      }
      try {
        final stat = await FileStat.stat(_absolutePath(resource.relativePath));
        resourceUpdates.add((
          id: resource.id,
          status: ManagedResourceStatus.managed,
          size: resource.kind == ManagedResourceKind.file ? stat.size : null,
          modified: stat.modified.toUtc(),
        ));
      } on FileSystemException {
        findings.add(
          ConsistencyFinding(
            id: newId('finding'),
            type: ConsistencyFindingType.missing,
            relativePath: resource.relativePath,
            resourceId: resource.id,
            detectedAt: now,
          ),
        );
        resourceUpdates.add((
          id: resource.id,
          status: ManagedResourceStatus.missing,
          size: null,
          modified: null,
        ));
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
      for (final update in resourceUpdates) {
        if (update.status == ManagedResourceStatus.missing) {
          _database.execute(
            "UPDATE resources SET status = 'missing' WHERE id = ?",
            [update.id],
          );
        } else {
          _database.execute(
            '''
              UPDATE resources
              SET status = 'managed', size_bytes = ?, modified_at = ?
              WHERE id = ?
            ''',
            [update.size, update.modified!.toIso8601String(), update.id],
          );
        }
      }
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

  Future<ManagedResource> takeOverUntracked(String relativePath) async {
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    final resources = await listResources();
    if (resources.any(
      (resource) =>
          resource.relativePath == normalizedRelativePath ||
          (resource.kind == ManagedResourceKind.folder &&
              path.posix.isWithin(
                resource.relativePath,
                normalizedRelativePath,
              )) ||
          path.posix.isWithin(normalizedRelativePath, resource.relativePath),
    )) {
      throw StateError('该路径已属于现有受管资源范围');
    }
    final absolutePath = _absolutePath(normalizedRelativePath);
    final type = await FileSystemEntity.type(absolutePath, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('孤立内容不存在或类型不受支持', absolutePath);
    }
    final stat = await FileStat.stat(absolutePath);
    final now = DateTime.now().toUtc();
    final resource = ManagedResource(
      id: newId('resource'),
      name: path.posix.basename(normalizedRelativePath),
      relativePath: normalizedRelativePath,
      kind: type == FileSystemEntityType.file
          ? ManagedResourceKind.file
          : ManagedResourceKind.folder,
      status: ManagedResourceStatus.managed,
      originalPath: null,
      sizeBytes: type == FileSystemEntityType.file ? stat.size : null,
      modifiedAt: stat.modified.toUtc(),
      createdAt: now,
    );
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''
          INSERT INTO resources(
            id, name, relative_path, kind, status, original_path,
            size_bytes, modified_at, created_at
          ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?)
        ''',
        [
          resource.id,
          resource.name,
          resource.relativePath,
          resource.kind.name,
          resource.status.name,
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
          ) VALUES (?, 'takeover', ?, ?, ?, ?, NULL)
        ''',
        [
          newId('operation'),
          resource.id,
          absolutePath,
          resource.relativePath,
          now.toIso8601String(),
        ],
      );
      _database.execute('COMMIT');
      return resource;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<ManagedOperation> moveUntrackedOutside(
    String relativePath,
    String destinationPath,
  ) async {
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    final resources = await listResources();
    if (resources.any(
      (resource) =>
          resource.relativePath == normalizedRelativePath ||
          (resource.kind == ManagedResourceKind.folder &&
              path.posix.isWithin(
                resource.relativePath,
                normalizedRelativePath,
              )) ||
          path.posix.isWithin(normalizedRelativePath, resource.relativePath),
    )) {
      throw StateError('该路径已属于现有受管资源范围');
    }
    final sourcePath = _absolutePath(normalizedRelativePath);
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('孤立内容不存在或类型不受支持', sourcePath);
    }
    final normalizedDestination = path.normalize(
      path.absolute(destinationPath),
    );
    if (path.equals(normalizedDestination, root.path) ||
        path.isWithin(root.path, normalizedDestination)) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        '移出目标必须位于 TAGTAG 存储根之外',
      );
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
      type: ManagedOperationType.untrackedMoveOut,
      resourceId: newId('untracked'),
      sourcePath: normalizedDestination,
      destinationRelativePath: normalizedRelativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
    );
    await Directory(
      path.dirname(normalizedDestination),
    ).create(recursive: true);
    await _copyEntity(sourcePath, normalizedDestination, type);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at
          ) VALUES (?, 'untracked_move_out', ?, ?, ?, ?, NULL)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
        ],
      );
      await _deleteEntity(sourcePath, type);
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(sourcePath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(normalizedDestination) == type) {
        await Directory(path.dirname(sourcePath)).create(recursive: true);
        await _copyEntity(normalizedDestination, sourcePath, type);
      }
      if (await FileSystemEntity.type(normalizedDestination) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(normalizedDestination, type);
      }
      rethrow;
    }
  }

  Future<ManagedOperation> acceptExternalMove(
    String missingResourceId,
    String untrackedRelativePath,
  ) async {
    final resources = await listResources();
    final matches = resources.where(
      (resource) => resource.id == missingResourceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(
        missingResourceId,
        'missingResourceId',
        '找不到缺失资源记录',
      );
    }
    final resource = matches.single;
    final recordedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(recordedPath) !=
        FileSystemEntityType.notFound) {
      throw StateError('资源记录路径并未缺失，不能接受外部移动');
    }
    final normalizedCandidate = _normalizeRelativePath(untrackedRelativePath);
    if (resources.any(
      (other) =>
          other.id != resource.id &&
          (other.relativePath == normalizedCandidate ||
              (other.kind == ManagedResourceKind.folder &&
                  path.posix.isWithin(
                    other.relativePath,
                    normalizedCandidate,
                  )) ||
              path.posix.isWithin(normalizedCandidate, other.relativePath)),
    )) {
      throw StateError('候选路径已属于其他受管资源范围');
    }
    final candidatePath = _absolutePath(normalizedCandidate);
    final candidateType = await FileSystemEntity.type(
      candidatePath,
      followLinks: false,
    );
    final expectedType = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (candidateType != expectedType) {
      throw FileSystemException('候选路径不存在或资源类型与缺失记录不一致', candidatePath);
    }
    final stat = await FileStat.stat(candidatePath);
    final operation = ManagedOperation(
      id: newId('operation'),
      type: ManagedOperationType.externalMoveAccept,
      resourceId: resource.id,
      sourcePath: candidatePath,
      destinationRelativePath: resource.relativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
    );

    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at
          ) VALUES (?, 'external_move_accept', ?, ?, ?, ?, NULL)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
        ],
      );
      _database.execute(
        '''
          UPDATE resources
          SET name = ?, relative_path = ?, status = 'managed',
              size_bytes = ?, modified_at = ?
          WHERE id = ?
        ''',
        [
          path.posix.basename(normalizedCandidate),
          normalizedCandidate,
          candidateType == FileSystemEntityType.file ? stat.size : null,
          stat.modified.toUtc().toIso8601String(),
          resource.id,
        ],
      );
      _database.execute('COMMIT');
      return operation;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<ManagedOperation> restoreExternalMove(
    String missingResourceId,
    String untrackedRelativePath,
  ) async {
    final resources = await listResources();
    final matches = resources.where(
      (resource) => resource.id == missingResourceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(
        missingResourceId,
        'missingResourceId',
        '找不到缺失资源记录',
      );
    }
    final resource = matches.single;
    final recordedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(recordedPath) !=
        FileSystemEntityType.notFound) {
      throw StateError('资源记录路径并未缺失，不能恢复外部移动');
    }
    final normalizedCandidate = _normalizeRelativePath(untrackedRelativePath);
    if (resources.any(
      (other) =>
          other.id != resource.id &&
          (other.relativePath == normalizedCandidate ||
              (other.kind == ManagedResourceKind.folder &&
                  path.posix.isWithin(
                    other.relativePath,
                    normalizedCandidate,
                  )) ||
              path.posix.isWithin(normalizedCandidate, other.relativePath)),
    )) {
      throw StateError('候选路径已属于其他受管资源范围');
    }
    final candidatePath = _absolutePath(normalizedCandidate);
    final candidateType = await FileSystemEntity.type(
      candidatePath,
      followLinks: false,
    );
    final expectedType = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (candidateType != expectedType) {
      throw FileSystemException('候选路径不存在或资源类型与缺失记录不一致', candidatePath);
    }
    final operation = ManagedOperation(
      id: newId('operation'),
      type: ManagedOperationType.externalMoveRestore,
      resourceId: resource.id,
      sourcePath: candidatePath,
      destinationRelativePath: resource.relativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
    );

    await Directory(path.dirname(recordedPath)).create(recursive: true);
    await _copyEntity(candidatePath, recordedPath, candidateType);
    var transactionActive = false;
    try {
      final stat = await FileStat.stat(recordedPath);
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at
          ) VALUES (?, 'external_move_restore', ?, ?, ?, ?, NULL)
        ''',
        [
          operation.id,
          operation.resourceId,
          operation.sourcePath,
          operation.destinationRelativePath,
          operation.createdAt.toIso8601String(),
        ],
      );
      _database.execute(
        '''
          UPDATE resources
          SET status = 'managed', size_bytes = ?, modified_at = ?
          WHERE id = ?
        ''',
        [
          candidateType == FileSystemEntityType.file ? stat.size : null,
          stat.modified.toUtc().toIso8601String(),
          resource.id,
        ],
      );
      await _deleteEntity(candidatePath, candidateType);
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(candidatePath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(recordedPath) == candidateType) {
        await Directory(path.dirname(candidatePath)).create(recursive: true);
        await _copyEntity(recordedPath, candidatePath, candidateType);
      }
      if (await FileSystemEntity.type(recordedPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(recordedPath, candidateType);
      }
      rethrow;
    }
  }

  /// Moves a managed resource into another directory inside the storage
  /// root, keeping its name and bytes. Managed resources nested inside a
  /// moved folder have their recorded paths rewritten in the same
  /// transaction, so a consistency scan stays clean. The destination must
  /// not exist: TAGTAG never overwrites.
  Future<ManagedOperation> organizeMove(
    String resourceId,
    String targetRelativeDirectory,
  ) async {
    final resources = await listResources();
    final matches = resources.where((resource) => resource.id == resourceId);
    if (matches.isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId', '找不到受管资源');
    }
    final resource = matches.single;
    if (resource.status == ManagedResourceStatus.missing) {
      throw StateError('受管资源已缺失，无法整理移动');
    }
    final relativeDirectory = _normalizeRelativeDirectory(
      targetRelativeDirectory,
    );
    final nextRelativePath = relativeDirectory.isEmpty
        ? resource.name
        : path.posix.join(relativeDirectory, resource.name);
    if (nextRelativePath == resource.relativePath) {
      throw StateError('资源已位于目标目录');
    }
    if (resource.kind == ManagedResourceKind.folder &&
        path.posix.isWithin(resource.relativePath, nextRelativePath)) {
      throw ArgumentError.value(
        targetRelativeDirectory,
        'targetRelativeDirectory',
        '不能把文件夹整理到自身内部',
      );
    }
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final managedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(managedPath) != type) {
      throw FileSystemException('受管资源已缺失，无法整理移动', managedPath);
    }
    if (resources.any(
      (other) =>
          other.id != resource.id && other.relativePath == nextRelativePath,
    )) {
      throw StateError('目标路径已被其他受管资源占用');
    }
    final destinationPath = _absolutePath(nextRelativePath);
    if (await FileSystemEntity.type(destinationPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标位置已存在同名资源，TAGTAG 不会覆盖', destinationPath);
    }
    final nested = resources
        .where(
          (other) =>
              other.id != resource.id &&
              path.posix.isWithin(resource.relativePath, other.relativePath),
        )
        .toList();
    final managedRelativePaths = {
      for (final item in resources) item.relativePath,
    };

    final operation = ManagedOperation(
      id: newId('operation'),
      type: ManagedOperationType.organizeMove,
      resourceId: resource.id,
      sourcePath: managedPath,
      destinationRelativePath: nextRelativePath,
      createdAt: DateTime.now().toUtc(),
      undoneAt: null,
      contextJson: jsonEncode({'previousRelativePath': resource.relativePath}),
    );
    await Directory(path.dirname(destinationPath)).create(recursive: true);
    await _copyEntity(managedPath, destinationPath, type);
    var transactionActive = false;
    try {
      final stat = await FileStat.stat(destinationPath);
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        '''
          INSERT INTO operations(
            id, type, resource_id, source_path,
            destination_relative_path, created_at, undone_at, context_json
          ) VALUES (?, 'organize_move', ?, ?, ?, ?, NULL, ?)
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
      _database.execute(
        '''
          UPDATE resources
          SET relative_path = ?, status = 'managed',
              size_bytes = ?, modified_at = ?
          WHERE id = ?
        ''',
        [
          nextRelativePath,
          type == FileSystemEntityType.file ? stat.size : null,
          stat.modified.toUtc().toIso8601String(),
          resource.id,
        ],
      );
      for (final item in nested) {
        _database
            .execute('UPDATE resources SET relative_path = ? WHERE id = ?', [
              nextRelativePath +
                  item.relativePath.substring(resource.relativePath.length),
              item.id,
            ]);
      }
      await _deleteEntity(managedPath, type);
      // Directories left empty by the move must not surface as untracked
      // content in the next consistency scan.
      await _pruneEmptyDirectories(
        path.dirname(managedPath),
        managedRelativePaths,
      );
      _database.execute('COMMIT');
      transactionActive = false;
      return operation;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(managedPath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(destinationPath) == type) {
        await Directory(path.dirname(managedPath)).create(recursive: true);
        await _copyEntity(destinationPath, managedPath, type);
      }
      if (await FileSystemEntity.type(destinationPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(destinationPath, type);
      }
      rethrow;
    }
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
    if (operation.type == ManagedOperationType.takeover) {
      await _undoTakeover(operation);
      return;
    }
    if (operation.type == ManagedOperationType.untrackedMoveOut) {
      await _undoUntrackedMoveOut(operation);
      return;
    }
    if (operation.type == ManagedOperationType.externalMoveAccept) {
      await _undoExternalMoveAccept(operation);
      return;
    }
    if (operation.type == ManagedOperationType.externalMoveRestore) {
      await _undoExternalMoveRestore(operation);
      return;
    }
    if (operation.type == ManagedOperationType.organizeMove) {
      await _undoOrganizeMove(operation);
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

  Future<void> _undoTakeover(ManagedOperation operation) async {
    final resources = (await listResources()).where(
      (resource) => resource.id == operation.resourceId,
    );
    if (resources.isEmpty) {
      throw StateError('接管操作对应的受管资源记录已不存在');
    }
    final resource = resources.single;
    final expectedType = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (await FileSystemEntity.type(_absolutePath(resource.relativePath)) !=
        expectedType) {
      throw FileSystemException(
        '受管资源已缺失，无法撤销接管',
        _absolutePath(resource.relativePath),
      );
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('DELETE FROM resources WHERE id = ?', [resource.id]);
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> _undoUntrackedMoveOut(ManagedOperation operation) async {
    final type = await FileSystemEntity.type(
      operation.sourcePath,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('移出位置的孤立内容已缺失，无法撤销', operation.sourcePath);
    }
    final originalPath = _absolutePath(operation.destinationRelativePath);
    if (await FileSystemEntity.type(originalPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原存储路径已存在同名资源，TAGTAG 不会覆盖', originalPath);
    }

    await Directory(path.dirname(originalPath)).create(recursive: true);
    await _copyEntity(operation.sourcePath, originalPath, type);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
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
          await FileSystemEntity.type(originalPath) == type) {
        await Directory(
          path.dirname(operation.sourcePath),
        ).create(recursive: true);
        await _copyEntity(originalPath, operation.sourcePath, type);
      }
      if (await FileSystemEntity.type(originalPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(originalPath, type);
      }
      rethrow;
    }
  }

  Future<void> _undoExternalMoveAccept(ManagedOperation operation) async {
    final resources = (await listResources()).where(
      (resource) => resource.id == operation.resourceId,
    );
    if (resources.isEmpty) {
      throw StateError('接受外部移动对应的资源记录已不存在');
    }
    final resource = resources.single;
    final acceptedPath = path.normalize(operation.sourcePath);
    if (!path.equals(acceptedPath, root.path) &&
        !path.isWithin(root.path, acceptedPath)) {
      throw StateError('接受外部移动的操作记录包含无效路径');
    }
    if (path.normalize(_absolutePath(resource.relativePath)) != acceptedPath) {
      throw StateError('资源记录已再次变更，无法撤销接受新路径');
    }
    final expectedType = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (await FileSystemEntity.type(acceptedPath, followLinks: false) !=
        expectedType) {
      throw FileSystemException('已接受的新路径内容缺失，无法撤销', acceptedPath);
    }
    final recordedPath = _absolutePath(operation.destinationRelativePath);
    if (await FileSystemEntity.type(recordedPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原记录路径已被占用，无法撤销接受新路径', recordedPath);
    }

    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''
          UPDATE resources
          SET name = ?, relative_path = ?, status = 'missing'
          WHERE id = ?
        ''',
        [
          path.posix.basename(operation.destinationRelativePath),
          operation.destinationRelativePath,
          operation.resourceId,
        ],
      );
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> _undoExternalMoveRestore(ManagedOperation operation) async {
    final resources = await listResources();
    final matches = resources.where(
      (resource) => resource.id == operation.resourceId,
    );
    if (matches.isEmpty) {
      throw StateError('恢复外部移动对应的资源记录已不存在');
    }
    final resource = matches.single;
    if (resource.relativePath != operation.destinationRelativePath) {
      throw StateError('资源记录已再次变更，无法撤销恢复记录路径');
    }
    final recordedPath = _absolutePath(operation.destinationRelativePath);
    final expectedType = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (await FileSystemEntity.type(recordedPath, followLinks: false) !=
        expectedType) {
      throw FileSystemException('记录路径内容已缺失，无法撤销恢复', recordedPath);
    }
    final candidatePath = path.normalize(operation.sourcePath);
    if (!path.equals(candidatePath, root.path) &&
        !path.isWithin(root.path, candidatePath)) {
      throw StateError('恢复外部移动的操作记录包含无效路径');
    }
    if (await FileSystemEntity.type(candidatePath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原候选路径已被占用，TAGTAG 不会覆盖', candidatePath);
    }
    final candidateRelativePath = path
        .relative(candidatePath, from: root.path)
        .replaceAll('\\', '/');
    if (resources.any(
      (other) =>
          other.id != resource.id &&
          (other.relativePath == candidateRelativePath ||
              (other.kind == ManagedResourceKind.folder &&
                  path.posix.isWithin(
                    other.relativePath,
                    candidateRelativePath,
                  )) ||
              path.posix.isWithin(candidateRelativePath, other.relativePath)),
    )) {
      throw StateError('原候选路径已属于其他受管资源范围');
    }

    await Directory(path.dirname(candidatePath)).create(recursive: true);
    await _copyEntity(recordedPath, candidatePath, expectedType);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute(
        "UPDATE resources SET status = 'missing' WHERE id = ?",
        [resource.id],
      );
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      await _deleteEntity(recordedPath, expectedType);
      _database.execute('COMMIT');
      transactionActive = false;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(recordedPath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(candidatePath) == expectedType) {
        await Directory(path.dirname(recordedPath)).create(recursive: true);
        await _copyEntity(candidatePath, recordedPath, expectedType);
      }
      if (await FileSystemEntity.type(candidatePath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(candidatePath, expectedType);
      }
      rethrow;
    }
  }

  Future<void> _undoOrganizeMove(ManagedOperation operation) async {
    final context = operation.contextJson == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(operation.contextJson!) as Map);
    final previousRelativePath = context['previousRelativePath'] as String?;
    if (previousRelativePath == null || previousRelativePath.isEmpty) {
      throw const FormatException('整理移动操作缺少原路径上下文');
    }
    final resources = await listResources();
    final matches = resources.where(
      (resource) => resource.id == operation.resourceId,
    );
    if (matches.isEmpty) {
      throw StateError('整理移动对应的资源记录已不存在');
    }
    final resource = matches.single;
    if (resource.relativePath != operation.destinationRelativePath) {
      throw StateError('资源记录已再次变更，无法撤销整理移动');
    }
    final type = resource.kind == ManagedResourceKind.file
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    final organizedPath = _absolutePath(resource.relativePath);
    if (await FileSystemEntity.type(organizedPath) != type) {
      throw FileSystemException('整理后的资源已缺失，无法撤销', organizedPath);
    }
    final previousPath = _absolutePath(previousRelativePath);
    if (await FileSystemEntity.type(previousPath) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('原位置已存在同名资源，TAGTAG 不会覆盖', previousPath);
    }
    final nested = resources
        .where(
          (other) =>
              other.id != resource.id &&
              path.posix.isWithin(resource.relativePath, other.relativePath),
        )
        .toList();
    final managedRelativePaths = {
      for (final item in resources) item.relativePath,
    };

    await Directory(path.dirname(previousPath)).create(recursive: true);
    await _copyEntity(organizedPath, previousPath, type);
    var transactionActive = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      transactionActive = true;
      _database.execute('UPDATE resources SET relative_path = ? WHERE id = ?', [
        previousRelativePath,
        resource.id,
      ]);
      for (final item in nested) {
        _database
            .execute('UPDATE resources SET relative_path = ? WHERE id = ?', [
              previousRelativePath +
                  item.relativePath.substring(resource.relativePath.length),
              item.id,
            ]);
      }
      _database.execute('UPDATE operations SET undone_at = ? WHERE id = ?', [
        DateTime.now().toUtc().toIso8601String(),
        operation.id,
      ]);
      await _deleteEntity(organizedPath, type);
      await _pruneEmptyDirectories(
        path.dirname(organizedPath),
        managedRelativePaths,
      );
      _database.execute('COMMIT');
      transactionActive = false;
    } catch (_) {
      if (transactionActive) {
        _database.execute('ROLLBACK');
      }
      if (await FileSystemEntity.type(organizedPath) ==
              FileSystemEntityType.notFound &&
          await FileSystemEntity.type(previousPath) == type) {
        await Directory(path.dirname(organizedPath)).create(recursive: true);
        await _copyEntity(previousPath, organizedPath, type);
      }
      if (await FileSystemEntity.type(previousPath) !=
          FileSystemEntityType.notFound) {
        await _deleteEntity(previousPath, type);
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
      final entries = await _collectBackupEntries(temporaryDirectory);
      await manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': 2,
          'createdAt': createdAt.toIso8601String(),
          'resourceCount': resources.length,
          'entries': [for (final entry in entries) entry.toJson()],
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

  static Future<BackupValidationResult> validateBackup(
    Directory backupDirectory,
  ) async {
    final backup = Directory(path.normalize(backupDirectory.absolute.path));
    if (!await backup.exists()) {
      throw FileSystemException('找不到全局备份目录', backup.path);
    }
    final manifestFile = File(path.join(backup.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      throw const FormatException('全局备份缺少 manifest.json');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(await manifestFile.readAsString());
    } on FormatException catch (error) {
      throw FormatException('全局备份清单不是有效 JSON：${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('全局备份清单必须是 JSON 对象');
    }
    if (decoded['formatVersion'] != 2) {
      throw FormatException('不支持的全局备份格式版本：${decoded['formatVersion']}');
    }
    final createdAtValue = decoded['createdAt'];
    final resourceCount = decoded['resourceCount'];
    final entryValues = decoded['entries'];
    final resourceValues = decoded['resources'];
    if (createdAtValue is! String ||
        resourceCount is! int ||
        resourceCount < 0 ||
        entryValues is! List<dynamic> ||
        resourceValues is! List<dynamic> ||
        resourceValues.length != resourceCount) {
      throw const FormatException('全局备份清单字段无效');
    }
    final createdAt = DateTime.tryParse(createdAtValue);
    if (createdAt == null) {
      throw const FormatException('全局备份创建时间无效');
    }

    final entries = <String, _BackupEntry>{};
    for (final value in entryValues) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('全局备份条目必须是 JSON 对象');
      }
      final entry = _BackupEntry.fromJson(value);
      if (entries[entry.relativePath] != null) {
        throw FormatException('全局备份清单包含重复路径：${entry.relativePath}');
      }
      entries[entry.relativePath] = entry;
    }
    if (entries['metadata/$_databaseFileName']?.kind !=
            FileSystemEntityType.file ||
        entries['metadata/tag-state.json']?.kind != FileSystemEntityType.file) {
      throw const FormatException('全局备份缺少 SQLite 或标签状态');
    }

    final actualEntries = {
      for (final entry in await _collectBackupEntries(backup))
        entry.relativePath: entry,
    };
    if (entries.keys
            .toSet()
            .difference(actualEntries.keys.toSet())
            .isNotEmpty ||
        actualEntries.keys
            .toSet()
            .difference(entries.keys.toSet())
            .isNotEmpty) {
      throw const FormatException('全局备份内容与清单条目不一致');
    }
    for (final entry in entries.values) {
      final actual = actualEntries[entry.relativePath]!;
      if (actual.kind != entry.kind) {
        throw FormatException('全局备份条目类型不一致：${entry.relativePath}');
      }
      if (entry.kind == FileSystemEntityType.file &&
          (actual.sizeBytes != entry.sizeBytes ||
              actual.sha256Digest != entry.sha256Digest)) {
        throw FormatException('全局备份文件校验失败：${entry.relativePath}');
      }
    }

    final databasePath = path.join(backup.path, 'metadata', _databaseFileName);
    final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
    try {
      final integrity = database.select('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('全局备份 SQLite 完整性校验失败');
      }
      final rows = database.select(
        'SELECT id, relative_path, kind FROM resources',
      );
      if (rows.length != resourceCount) {
        throw const FormatException('全局备份资源数量与 SQLite 不一致');
      }
      final manifestResources = <String, ({String path, String kind})>{};
      for (final value in resourceValues) {
        if (value is! Map<String, dynamic> ||
            value['id'] is! String ||
            value['relativePath'] is! String ||
            value['kind'] is! String) {
          throw const FormatException('全局备份资源清单无效');
        }
        final resourcePath = _normalizeRelativePath(
          value['relativePath'] as String,
        );
        final kind = value['kind'] as String;
        if (kind != 'file' && kind != 'folder') {
          throw const FormatException('全局备份资源类型无效');
        }
        final id = value['id'] as String;
        if (manifestResources[id] != null) {
          throw const FormatException('全局备份资源清单包含重复 ID');
        }
        manifestResources[id] = (path: resourcePath, kind: kind);
      }
      for (final row in rows) {
        final id = row['id'] as String;
        final relativePath = row['relative_path'] as String;
        final kind = row['kind'] as String;
        final manifestResource = manifestResources[id];
        if (manifestResource == null ||
            manifestResource.path != relativePath ||
            manifestResource.kind != kind) {
          throw const FormatException('全局备份资源清单与 SQLite 不一致');
        }
        final entry = entries['resources/$relativePath'];
        final expectedType = kind == 'file'
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        if (entry?.kind != expectedType) {
          throw FormatException('全局备份缺少资源内容：$relativePath');
        }
      }
    } finally {
      database.close();
    }

    final tagStateFile = File(
      path.join(backup.path, 'metadata', 'tag-state.json'),
    );
    final tagStateJson = await tagStateFile.readAsString();
    try {
      final tagState = jsonDecode(tagStateJson);
      if (tagState is! Map<String, dynamic>) {
        throw const FormatException('标签状态必须是 JSON 对象');
      }
      AppState.fromJson(tagState);
    } on Object catch (error) {
      throw FormatException('全局备份标签状态无效：$error');
    }
    final preferencesFile = File(
      path.join(backup.path, 'metadata', 'preferences.json'),
    );
    final preferencesJson = await preferencesFile.exists()
        ? await preferencesFile.readAsString()
        : null;
    return BackupValidationResult(
      backupDirectory: backup,
      formatVersion: 2,
      createdAt: createdAt.toUtc(),
      resourceCount: resourceCount,
      tagStateJson: tagStateJson,
      preferencesJson: preferencesJson,
    );
  }

  static Future<BackupRestoreResult> restoreBackup(
    Directory backupDirectory,
    Directory targetRoot,
  ) async {
    final validation = await validateBackup(backupDirectory);
    final target = Directory(path.normalize(targetRoot.absolute.path));
    final backup = validation.backupDirectory;
    if (path.equals(target.path, backup.path) ||
        path.isWithin(backup.path, target.path)) {
      throw ArgumentError.value(targetRoot.path, 'targetRoot', '恢复目标不能位于备份目录内');
    }
    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound &&
        targetType != FileSystemEntityType.directory) {
      throw FileSystemException('恢复目标必须是目录', target.path);
    }
    final targetExisted = targetType == FileSystemEntityType.directory;
    if (targetExisted && !(await target.list(followLinks: false).isEmpty)) {
      throw FileSystemException('恢复目标必须是新的空目录', target.path);
    }
    final parent = Directory(path.dirname(target.path));
    await parent.create(recursive: true);
    final staging = Directory(
      path.join(
        parent.path,
        '.${path.basename(target.path)}-${newId('restore')}.tmp',
      ),
    );
    if (await staging.exists()) {
      throw FileSystemException('恢复临时目录已存在', staging.path);
    }

    try {
      await Directory(
        path.join(staging.path, _metadataDirectoryName),
      ).create(recursive: true);
      await File(path.join(backup.path, 'metadata', _databaseFileName)).copy(
        path.join(staging.path, _metadataDirectoryName, _databaseFileName),
      );
      final resourcesDirectory = Directory(path.join(backup.path, 'resources'));
      await for (final child in resourcesDirectory.list(followLinks: false)) {
        final type = await FileSystemEntity.type(
          child.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          throw FileSystemException('备份资源包含不支持的链接或条目', child.path);
        }
        await _copyEntity(
          child.path,
          path.join(staging.path, path.basename(child.path)),
          type,
        );
      }

      final restoredLibrary = await ManagedLibrary.open(staging);
      try {
        final findings = await restoredLibrary.scanConsistency();
        if (findings.isNotEmpty) {
          throw const FormatException('恢复后的资料库未通过资源一致性校验');
        }
      } finally {
        await restoredLibrary.close();
      }

      if (targetExisted) {
        await target.delete();
      }
      try {
        await staging.rename(target.path);
      } catch (_) {
        if (targetExisted && !await target.exists()) {
          await target.create();
        }
        rethrow;
      }
      return BackupRestoreResult(
        root: Directory(target.path),
        tagStateJson: validation.tagStateJson,
        preferencesJson: validation.preferencesJson,
      );
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
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

  static String _normalizeRelativePath(String value) {
    final normalized = _normalizeRelativeDirectory(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'relativePath', '必须指定存储根内的资源路径');
    }
    return normalized;
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

  static Future<List<_BackupEntry>> _collectBackupEntries(
    Directory backupRoot,
  ) async {
    final entries = <_BackupEntry>[];
    for (final directoryName in const ['metadata', 'resources']) {
      final directory = Directory(path.join(backupRoot.path, directoryName));
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.directory) {
          throw FormatException('全局备份包含不支持的链接或条目：${entity.path}');
        }
        final relativePath = path
            .relative(entity.path, from: backupRoot.path)
            .replaceAll('\\', '/');
        if (type == FileSystemEntityType.directory) {
          entries.add(
            _BackupEntry(
              relativePath: relativePath,
              kind: type,
              sizeBytes: null,
              sha256Digest: null,
            ),
          );
        } else {
          final file = File(entity.path);
          entries.add(
            _BackupEntry(
              relativePath: relativePath,
              kind: type,
              sizeBytes: await file.length(),
              sha256Digest: await _sha256File(file),
            ),
          );
        }
      }
    }
    entries.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return entries;
  }

  static Future<String> _sha256File(File file) async {
    final digests = sha256.bind(file.openRead());
    return (await digests.first).toString();
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

  /// Deletes [directoryPath] and its ancestors while they are empty, never
  /// crossing the storage root or a directory that is itself a managed
  /// resource. Used after managed moves so leftover empty directories do
  /// not show up as untracked content.
  Future<void> _pruneEmptyDirectories(
    String directoryPath,
    Set<String> managedRelativePaths,
  ) async {
    var current = path.normalize(directoryPath);
    while (path.isWithin(root.path, current)) {
      final relative = path
          .relative(current, from: root.path)
          .replaceAll('\\', '/');
      if (managedRelativePaths.contains(relative)) {
        return;
      }
      final directory = Directory(current);
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
        current = path.dirname(current);
      } else {
        return;
      }
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
        case 4:
          _migrateV4ToV5(database);
        case 5:
          _migrateV5ToV6(database);
        case 6:
          _migrateV6ToV7(database);
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

  static void _migrateV4ToV5(Database database) {
    database.execute('ALTER TABLE operations RENAME TO operations_v4');
    _createOperationsTable(database);
    database.execute('''
      INSERT INTO operations(
        id, type, resource_id, source_path,
        destination_relative_path, created_at, undone_at, context_json
      )
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at, context_json
      FROM operations_v4
    ''');
    database.execute('DROP TABLE operations_v4');
  }

  static void _migrateV5ToV6(Database database) {
    _createSchema(database);
  }

  static void _migrateV6ToV7(Database database) {
    database.execute('ALTER TABLE operations RENAME TO operations_v6');
    _createOperationsTable(database);
    database.execute('''
      INSERT INTO operations(
        id, type, resource_id, source_path,
        destination_relative_path, created_at, undone_at, context_json
      )
      SELECT id, type, resource_id, source_path,
             destination_relative_path, created_at, undone_at, context_json
      FROM operations_v6
    ''');
    database.execute('DROP TABLE operations_v6');
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
            'exit_move', 'exit_recycle', 'takeover',
            'untracked_move_out', 'external_move_accept',
            'external_move_restore', 'organize_move'
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

class _BackupEntry {
  const _BackupEntry({
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.sha256Digest,
  });

  final String relativePath;
  final FileSystemEntityType kind;
  final int? sizeBytes;
  final String? sha256Digest;

  Map<String, dynamic> toJson() => {
    'path': relativePath,
    'kind': kind == FileSystemEntityType.file ? 'file' : 'folder',
    if (kind == FileSystemEntityType.file) ...{
      'sizeBytes': sizeBytes,
      'sha256': sha256Digest,
    },
  };

  factory _BackupEntry.fromJson(Map<String, dynamic> json) {
    final relativePath = json['path'];
    final kindValue = json['kind'];
    if (relativePath is! String || kindValue is! String) {
      throw const FormatException('全局备份条目字段无效');
    }
    final normalized = path.posix.normalize(relativePath);
    if (relativePath.contains('\\') ||
        normalized != relativePath ||
        path.posix.isAbsolute(normalized) ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        (!normalized.startsWith('metadata/') &&
            !normalized.startsWith('resources/'))) {
      throw FormatException('全局备份条目路径无效：$relativePath');
    }
    final kind = switch (kindValue) {
      'file' => FileSystemEntityType.file,
      'folder' => FileSystemEntityType.directory,
      _ => throw FormatException('全局备份条目类型无效：$kindValue'),
    };
    final sizeBytes = json['sizeBytes'];
    final digest = json['sha256'];
    if (kind == FileSystemEntityType.file &&
        (sizeBytes is! int ||
            sizeBytes < 0 ||
            digest is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest))) {
      throw FormatException('全局备份文件摘要无效：$relativePath');
    }
    return _BackupEntry(
      relativePath: normalized,
      kind: kind,
      sizeBytes: kind == FileSystemEntityType.file ? sizeBytes as int : null,
      sha256Digest: kind == FileSystemEntityType.file ? digest as String : null,
    );
  }
}
