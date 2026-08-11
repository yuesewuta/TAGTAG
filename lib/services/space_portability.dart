import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../models/tag_models.dart';
import '../storage/managed_library.dart';

enum SpaceArchiveKind { package, template }

class SpaceArchiveSummary {
  const SpaceArchiveSummary({
    required this.kind,
    required this.spaceName,
    required this.createdAt,
    required this.tagCount,
    required this.resourceCount,
  });

  final SpaceArchiveKind kind;
  final String spaceName;
  final DateTime createdAt;
  final int tagCount;
  final int resourceCount;
}

class SpaceImportMutation {
  const SpaceImportMutation({
    required this.state,
    required this.importedResourceIds,
    required this.summary,
  });

  final AppState state;
  final Set<String> importedResourceIds;
  final SpaceArchiveSummary summary;
}

class SpacePortability {
  static const _formatVersion = 1;
  static const _manifestName = 'manifest.json';
  static const _metadataPath = 'metadata/space.json';

  static Future<File> exportPackage({
    required AppState state,
    required String spaceId,
    required ManagedLibrary library,
    required File destination,
  }) => _export(
    kind: SpaceArchiveKind.package,
    state: state,
    spaceId: spaceId,
    library: library,
    destination: destination,
  );

  static Future<File> exportTemplate({
    required AppState state,
    required String spaceId,
    required File destination,
  }) => _export(
    kind: SpaceArchiveKind.template,
    state: state,
    spaceId: spaceId,
    library: null,
    destination: destination,
  );

  static Future<SpaceArchiveSummary> inspect(File archiveFile) async {
    final archive = await _ValidatedSpaceArchive.open(archiveFile);
    try {
      return archive.summary;
    } finally {
      await archive.dispose();
    }
  }

  static Future<SpaceImportMutation> importArchive({
    required File archiveFile,
    required AppState currentState,
    required ManagedLibrary library,
    required String targetDirectory,
  }) async {
    final archive = await _ValidatedSpaceArchive.open(archiveFile);
    try {
      final metadata = archive.metadata;
      final importedSpace = TagSpace.fromJson(
        Map<String, dynamic>.from(metadata['space'] as Map),
      );
      final tags = _jsonList(
        metadata,
        'tags',
      ).map((item) => TagDefinition.fromJson(item)).toList();
      final placements = _jsonList(
        metadata,
        'placements',
      ).map((item) => TagPlacement.fromJson(item)).toList();
      if (archive.summary.kind == SpaceArchiveKind.template) {
        final now = DateTime.now().toUtc();
        final instantiatedSpace = TagSpace(
          id: newId('space'),
          name: importedSpace.name,
          createdAt: now,
        );
        final tagIds = {for (final tag in tags) tag.id: newId('tag')};
        final placementIds = {
          for (final placement in placements) placement.id: newId('placement'),
        };
        final instantiatedTags = tags
            .map(
              (tag) => TagDefinition(
                id: tagIds[tag.id]!,
                spaceId: instantiatedSpace.id,
                name: tag.name,
                colorValue: tag.colorValue,
                createdAt: now,
              ),
            )
            .toList();
        final instantiatedPlacements = placements
            .map(
              (placement) => TagPlacement(
                id: placementIds[placement.id]!,
                spaceId: instantiatedSpace.id,
                tagId: tagIds[placement.tagId]!,
                parentId: placement.parentId == null
                    ? null
                    : placementIds[placement.parentId]!,
                sortOrder: placement.sortOrder,
              ),
            )
            .toList();
        return SpaceImportMutation(
          state: currentState.copyWith(
            spaces: [...currentState.spaces, instantiatedSpace],
            tags: [...currentState.tags, ...instantiatedTags],
            placements: [...currentState.placements, ...instantiatedPlacements],
            activeSpaceId: instantiatedSpace.id,
          ),
          importedResourceIds: const {},
          summary: archive.summary,
        );
      }

      _ensureDomainIdsAvailable(currentState, metadata, importedSpace.id);

      final memberships = _jsonList(
        metadata,
        'memberships',
      ).map((item) => SpaceMembership.fromJson(item)).toList();
      final assignments = _jsonList(
        metadata,
        'assignments',
      ).map((item) => TagAssignment.fromJson(item)).toList();
      final inheritances = _jsonList(
        metadata,
        'folderTagInheritances',
      ).map((item) => FolderTagInheritance.fromJson(item)).toList();
      final events = _jsonList(
        metadata,
        'usageEvents',
      ).map((item) => UsageEvent.fromJson(item)).toList();
      final tagOperations = _jsonList(
        metadata,
        'tagOperations',
      ).map((item) => TagDomainOperation.fromJson(item)).toList();
      final managedById = {
        for (final resource in await library.listResources())
          resource.id: resource,
      };
      final tagResourcesById = {
        for (final resource in currentState.resources) resource.id: resource,
      };
      final imports = <PackagedResourceImport>[];
      final importedTagResources = <TagResource>[];
      final importedResourceIds = <String>{};
      final normalizedTargetDirectory = _normalizeRelativeDirectory(
        targetDirectory,
      );
      for (final resourceJson in _jsonList(metadata, 'resources')) {
        final packaged = _PackagedResource.fromJson(resourceJson);
        final contentPath = _absoluteArchivePath(
          archive.root,
          packaged.archivePath,
        );
        final content = packaged.kind == ResourceKind.file
            ? File(contentPath)
            : Directory(contentPath);
        final existing = managedById[packaged.id];
        if (existing != null) {
          if (!_sameKind(existing.kind, packaged.kind) ||
              existing.status != ManagedResourceStatus.managed ||
              !await _contentEquals(
                _absoluteManagedPath(library, existing.relativePath),
                contentPath,
                packaged.kind,
              )) {
            throw StateError('稳定资源 ID 已存在但内容不一致：${packaged.id}');
          }
          if (tagResourcesById[packaged.id] == null) {
            importedTagResources.add(_toTagResource(library, existing));
          }
          continue;
        }
        final targetRelativePath = path.posix.join(
          normalizedTargetDirectory,
          packaged.relativePath,
        );
        imports.add(
          PackagedResourceImport(
            id: packaged.id,
            source: content,
            targetRelativePath: targetRelativePath,
            kind: packaged.kind == ResourceKind.file
                ? ManagedResourceKind.file
                : ManagedResourceKind.folder,
            createdAt: packaged.createdAt,
          ),
        );
        importedResourceIds.add(packaged.id);
      }
      final importedManaged = await library.importPackagedResources(imports);
      importedTagResources.addAll(
        importedManaged.map((resource) => _toTagResource(library, resource)),
      );
      return SpaceImportMutation(
        state: currentState.copyWith(
          spaces: [...currentState.spaces, importedSpace],
          tags: [...currentState.tags, ...tags],
          placements: [...currentState.placements, ...placements],
          resources: [...currentState.resources, ...importedTagResources],
          memberships: [...currentState.memberships, ...memberships],
          assignments: [...currentState.assignments, ...assignments],
          folderTagInheritances: [
            ...currentState.folderTagInheritances,
            ...inheritances,
          ],
          usageEvents: [...currentState.usageEvents, ...events],
          tagOperations: [...currentState.tagOperations, ...tagOperations],
          activeSpaceId: importedSpace.id,
        ),
        importedResourceIds: importedResourceIds,
        summary: archive.summary,
      );
    } finally {
      await archive.dispose();
    }
  }

  static Future<File> _export({
    required SpaceArchiveKind kind,
    required AppState state,
    required String spaceId,
    required ManagedLibrary? library,
    required File destination,
  }) async {
    final spaces = state.spaces.where((space) => space.id == spaceId);
    if (spaces.isEmpty) {
      throw ArgumentError.value(spaceId, 'spaceId', '找不到标签空间');
    }
    if (kind == SpaceArchiveKind.package && library == null) {
      throw StateError('空间导出包需要已初始化的受管存储');
    }
    final finalFile = File(path.normalize(destination.absolute.path));
    if (await finalFile.exists()) {
      throw FileSystemException('导出目标已存在，TAGTAG 不会覆盖', finalFile.path);
    }
    await finalFile.parent.create(recursive: true);
    final staging = await Directory.systemTemp.createTemp(
      'tagtag-space-export-',
    );
    final temporaryZip = File('${finalFile.path}.tmp');
    final createdAt = DateTime.now().toUtc();
    try {
      final tags = state.tags.where((tag) => tag.spaceId == spaceId).toList();
      final tagIds = tags.map((tag) => tag.id).toSet();
      final placements = state.placements
          .where((placement) => placement.spaceId == spaceId)
          .toList();
      final placementIds = placements.map((placement) => placement.id).toSet();
      final memberIds = state.resourceIdsForSpace(spaceId);
      final metadataResources = <Map<String, dynamic>>[];
      if (kind == SpaceArchiveKind.package) {
        final managedById = {
          for (final resource in await library!.listResources())
            resource.id: resource,
        };
        final sortedIds = memberIds.toList()..sort();
        for (var index = 0; index < sortedIds.length; index++) {
          final resourceId = sortedIds[index];
          final managed = managedById[resourceId];
          if (managed == null ||
              managed.status != ManagedResourceStatus.managed) {
            throw StateError('空间引用的受管资源不可用于导出：$resourceId');
          }
          final archivePath =
              'resources/${index.toString().padLeft(6, '0')}/content';
          final sourcePath = _absoluteManagedPath(
            library,
            managed.relativePath,
          );
          final destinationPath = _absoluteArchivePath(staging, archivePath);
          await _copyEntity(
            sourcePath,
            destinationPath,
            managed.kind == ManagedResourceKind.file
                ? FileSystemEntityType.file
                : FileSystemEntityType.directory,
          );
          metadataResources.add({
            'id': managed.id,
            'name': managed.name,
            'relativePath': managed.relativePath,
            'kind': managed.kind == ManagedResourceKind.file
                ? 'file'
                : 'folder',
            'sizeBytes': managed.sizeBytes,
            'modifiedAt': managed.modifiedAt.toIso8601String(),
            'createdAt': managed.createdAt.toIso8601String(),
            'archivePath': archivePath,
          });
        }
      }
      final metadata = {
        'formatVersion': _formatVersion,
        'kind': kind.name,
        'space': spaces.single.toJson(),
        'tags': tags.map((tag) => tag.toJson()).toList(),
        'placements': placements
            .map((placement) => placement.toJson())
            .toList(),
        'resources': metadataResources,
        'memberships': kind == SpaceArchiveKind.package
            ? state.memberships
                  .where((membership) => membership.spaceId == spaceId)
                  .map((membership) => membership.toJson())
                  .toList()
            : const [],
        'assignments': kind == SpaceArchiveKind.package
            ? state.assignments
                  .where(
                    (assignment) =>
                        memberIds.contains(assignment.resourceId) &&
                        placementIds.contains(assignment.placementId),
                  )
                  .map((assignment) => assignment.toJson())
                  .toList()
            : const [],
        'folderTagInheritances': kind == SpaceArchiveKind.package
            ? state.folderTagInheritances
                  .where(
                    (rule) =>
                        memberIds.contains(rule.folderResourceId) &&
                        tagIds.contains(rule.tagId),
                  )
                  .map((rule) => rule.toJson())
                  .toList()
            : const [],
        'usageEvents': kind == SpaceArchiveKind.package
            ? state.usageEvents
                  .where((event) => event.spaceId == spaceId)
                  .map((event) => event.toJson())
                  .toList()
            : const [],
        'tagOperations': kind == SpaceArchiveKind.package
            ? state.tagOperations
                  .where((operation) => operation.spaceId == spaceId)
                  .map((operation) => operation.toJson())
                  .toList()
            : const [],
      };
      final metadataFile = File(_absoluteArchivePath(staging, _metadataPath));
      await metadataFile.parent.create(recursive: true);
      await metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );
      final entries = await _collectEntries(staging);
      await File(_absoluteArchivePath(staging, _manifestName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'formatVersion': _formatVersion,
          'kind': kind.name,
          'createdAt': createdAt.toIso8601String(),
          'spaceId': spaceId,
          'metadataPath': _metadataPath,
          'entries': entries.map((entry) => entry.toJson()).toList(),
        }),
        flush: true,
      );
      final encoder = ZipFileEncoder();
      await encoder.zipDirectoryAsync(staging, filename: temporaryZip.path);
      return await temporaryZip.rename(finalFile.path);
    } catch (_) {
      if (await temporaryZip.exists()) {
        await temporaryZip.delete();
      }
      rethrow;
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  static void _ensureDomainIdsAvailable(
    AppState state,
    Map<String, dynamic> metadata,
    String spaceId,
  ) {
    if (state.spaces.any((space) => space.id == spaceId)) {
      throw StateError('目标资料库已存在同 ID 标签空间：$spaceId');
    }
    final collisions = <String>{};
    void addCollisions(Iterable<String> incoming, Iterable<String> existing) {
      collisions.addAll(incoming.toSet().intersection(existing.toSet()));
    }

    addCollisions(
      _jsonList(metadata, 'tags').map((item) => item['id'] as String),
      state.tags.map((item) => item.id),
    );
    addCollisions(
      _jsonList(metadata, 'placements').map((item) => item['id'] as String),
      state.placements.map((item) => item.id),
    );
    addCollisions(
      _jsonList(metadata, 'assignments').map((item) => item['id'] as String),
      state.assignments.map((item) => item.id),
    );
    addCollisions(
      _jsonList(
        metadata,
        'folderTagInheritances',
      ).map((item) => item['id'] as String),
      state.folderTagInheritances.map((item) => item.id),
    );
    addCollisions(
      _jsonList(metadata, 'usageEvents').map((item) => item['id'] as String),
      state.usageEvents.map((item) => item.id),
    );
    addCollisions(
      _jsonList(metadata, 'tagOperations').map((item) => item['id'] as String),
      state.tagOperations.map((item) => item.id),
    );
    if (collisions.isNotEmpty) {
      throw StateError('空间元数据稳定 ID 冲突：${collisions.first}');
    }
  }

  static List<Map<String, dynamic>> _jsonList(
    Map<String, dynamic> source,
    String key,
  ) => (source[key] as List<dynamic>? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  static bool _sameKind(ManagedResourceKind managed, ResourceKind packaged) =>
      (managed == ManagedResourceKind.file && packaged == ResourceKind.file) ||
      (managed == ManagedResourceKind.folder &&
          packaged == ResourceKind.folder);

  static String _absoluteManagedPath(
    ManagedLibrary library,
    String relativePath,
  ) => path.joinAll([library.root.path, ...relativePath.split('/')]);

  static String _absoluteArchivePath(Directory root, String relativePath) =>
      path.joinAll([root.path, ...relativePath.split('/')]);

  static TagResource _toTagResource(
    ManagedLibrary library,
    ManagedResource resource,
  ) => TagResource(
    id: resource.id,
    name: resource.name,
    path: _absoluteManagedPath(library, resource.relativePath),
    kind: resource.kind == ManagedResourceKind.file
        ? ResourceKind.file
        : ResourceKind.folder,
    modifiedAt: resource.modifiedAt,
    sizeBytes: resource.sizeBytes,
    createdAt: resource.createdAt,
  );

  static Future<bool> _contentEquals(
    String firstPath,
    String secondPath,
    ResourceKind kind,
  ) async {
    if (kind == ResourceKind.file) {
      if (await FileSystemEntity.type(firstPath) != FileSystemEntityType.file ||
          await FileSystemEntity.type(secondPath) !=
              FileSystemEntityType.file) {
        return false;
      }
      return await _fileDigest(File(firstPath)) ==
          await _fileDigest(File(secondPath));
    }
    if (await FileSystemEntity.type(firstPath) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(secondPath) !=
            FileSystemEntityType.directory) {
      return false;
    }
    final first = {
      for (final entry in await _collectEntries(Directory(firstPath)))
        entry.relativePath: entry,
    };
    final second = {
      for (final entry in await _collectEntries(Directory(secondPath)))
        entry.relativePath: entry,
    };
    if (!first.keys.toSet().containsAll(second.keys) ||
        !second.keys.toSet().containsAll(first.keys)) {
      return false;
    }
    return first.keys.every((key) => first[key] == second[key]);
  }

  static Future<List<_ArchiveEntryRecord>> _collectEntries(
    Directory root,
  ) async {
    final result = <_ArchiveEntryRecord>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException('空间归档不支持链接或特殊文件', entity.path);
      }
      final relativePath = path
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (relativePath == _manifestName) {
        continue;
      }
      result.add(
        _ArchiveEntryRecord(
          relativePath: relativePath,
          kind: type == FileSystemEntityType.file ? 'file' : 'directory',
          sizeBytes: type == FileSystemEntityType.file
              ? await File(entity.path).length()
              : null,
          sha256Digest: type == FileSystemEntityType.file
              ? await _fileDigest(File(entity.path))
              : null,
        ),
      );
    }
    result.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return result;
  }

  static Future<String> _fileDigest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<void> _copyEntity(
    String sourcePath,
    String destinationPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.file) {
      await File(destinationPath).parent.create(recursive: true);
      await File(sourcePath).copy(destinationPath);
      return;
    }
    final destination = Directory(destinationPath);
    await destination.create(recursive: true);
    await for (final entity in Directory(sourcePath).list(followLinks: false)) {
      final childType = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (childType != FileSystemEntityType.file &&
          childType != FileSystemEntityType.directory) {
        throw FileSystemException('空间归档不支持链接或特殊文件', entity.path);
      }
      await _copyEntity(
        entity.path,
        path.join(destinationPath, path.basename(entity.path)),
        childType,
      );
    }
  }

  static String _normalizeRelativeDirectory(String value) {
    final normalized = path.posix.normalize(value.trim().replaceAll('\\', '/'));
    if (normalized == '.' || normalized.isEmpty) {
      return '';
    }
    _validateRelativePath(normalized);
    return normalized;
  }

  static void _validateRelativePath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.contains(':') ||
        value.split('/').any((segment) => segment.isEmpty || segment == '..') ||
        value == '.tagtag' ||
        value.startsWith('.tagtag/')) {
      throw FormatException('空间归档包含不安全路径：$value');
    }
  }
}

class _ValidatedSpaceArchive {
  const _ValidatedSpaceArchive({
    required this.root,
    required this.metadata,
    required this.summary,
  });

  final Directory root;
  final Map<String, dynamic> metadata;
  final SpaceArchiveSummary summary;

  static Future<_ValidatedSpaceArchive> open(File archiveFile) async {
    final source = File(path.normalize(archiveFile.absolute.path));
    if (!await source.exists()) {
      throw FileSystemException('找不到空间归档文件', source.path);
    }
    final root = await Directory.systemTemp.createTemp('tagtag-space-import-');
    InputFileStream? input;
    Archive? archive;
    try {
      input = InputFileStream(source.path);
      archive = ZipDecoder().decodeBuffer(input, verify: true);
      final paths = <String>{};
      for (final entry in archive) {
        if (entry.isSymbolicLink || entry.name.contains('\\')) {
          throw const FormatException('空间归档不允许链接或反斜杠路径');
        }
        final rawName = entry.name.endsWith('/')
            ? entry.name.substring(0, entry.name.length - 1)
            : entry.name;
        final normalized = path.posix.normalize(rawName);
        SpacePortability._validateRelativePath(normalized);
        if (normalized != rawName || !paths.add(normalized)) {
          throw FormatException('空间归档包含重复或非规范路径：${entry.name}');
        }
        final destination = SpacePortability._absoluteArchivePath(
          root,
          normalized,
        );
        if (entry.isFile) {
          await File(destination).parent.create(recursive: true);
          final output = OutputFileStream(destination);
          try {
            entry.writeContent(output);
          } finally {
            output.closeSync();
          }
        } else {
          await Directory(destination).create(recursive: true);
        }
      }
      final manifestFile = File(
        SpacePortability._absoluteArchivePath(
          root,
          SpacePortability._manifestName,
        ),
      );
      final metadataFile = File(
        SpacePortability._absoluteArchivePath(
          root,
          SpacePortability._metadataPath,
        ),
      );
      if (!await manifestFile.exists() || !await metadataFile.exists()) {
        throw const FormatException('空间归档缺少 manifest.json 或空间元数据');
      }
      final manifest = _decodeObject(await manifestFile.readAsString(), '空间清单');
      final metadata = _decodeObject(
        await metadataFile.readAsString(),
        '空间元数据',
      );
      final formatVersion = manifest['formatVersion'];
      final kindValue = manifest['kind'];
      final createdAtValue = manifest['createdAt'];
      if (formatVersion != SpacePortability._formatVersion ||
          kindValue is! String ||
          createdAtValue is! String ||
          manifest['metadataPath'] != SpacePortability._metadataPath ||
          metadata['formatVersion'] != SpacePortability._formatVersion ||
          metadata['kind'] != kindValue) {
        throw const FormatException('空间归档版本或类型无效');
      }
      final kind = SpaceArchiveKind.values.byName(kindValue);
      final createdAt = DateTime.tryParse(createdAtValue);
      if (createdAt == null) {
        throw const FormatException('空间归档创建时间无效');
      }
      final expectedEntries = <String, _ArchiveEntryRecord>{};
      final entryValues = manifest['entries'];
      if (entryValues is! List<dynamic>) {
        throw const FormatException('空间归档清单条目无效');
      }
      for (final value in entryValues) {
        final entry = _ArchiveEntryRecord.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        SpacePortability._validateRelativePath(entry.relativePath);
        if (expectedEntries[entry.relativePath] != null) {
          throw FormatException('空间归档清单包含重复路径：${entry.relativePath}');
        }
        expectedEntries[entry.relativePath] = entry;
      }
      final actualEntries = {
        for (final entry in await SpacePortability._collectEntries(root))
          entry.relativePath: entry,
      };
      if (!expectedEntries.keys.toSet().containsAll(actualEntries.keys) ||
          !actualEntries.keys.toSet().containsAll(expectedEntries.keys)) {
        throw const FormatException('空间归档内容与清单不一致');
      }
      for (final entry in expectedEntries.entries) {
        if (actualEntries[entry.key] != entry.value) {
          throw FormatException('空间归档完整性校验失败：${entry.key}');
        }
      }
      final space = _validateMetadata(metadata, kind);
      if (manifest['spaceId'] != space.id) {
        throw const FormatException('空间归档清单与元数据的空间 ID 不一致');
      }
      if (kind == SpaceArchiveKind.template &&
          actualEntries.keys.any(
            (entryPath) =>
                entryPath == 'resources' ||
                path.posix.isWithin('resources', entryPath),
          )) {
        throw const FormatException('空间模板不能包含资源内容');
      }
      if (kind == SpaceArchiveKind.package) {
        for (final resourceJson in SpacePortability._jsonList(
          metadata,
          'resources',
        )) {
          final resource = _PackagedResource.fromJson(resourceJson);
          final entityType = await FileSystemEntity.type(
            SpacePortability._absoluteArchivePath(root, resource.archivePath),
            followLinks: false,
          );
          final expectedType = resource.kind == ResourceKind.file
              ? FileSystemEntityType.file
              : FileSystemEntityType.directory;
          if (entityType != expectedType) {
            throw FormatException('空间导出包资源内容缺失或类型不一致：${resource.id}');
          }
        }
      }
      return _ValidatedSpaceArchive(
        root: root,
        metadata: metadata,
        summary: SpaceArchiveSummary(
          kind: kind,
          spaceName: space.name,
          createdAt: createdAt.toUtc(),
          tagCount: SpacePortability._jsonList(metadata, 'tags').length,
          resourceCount: SpacePortability._jsonList(
            metadata,
            'resources',
          ).length,
        ),
      );
    } catch (_) {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      rethrow;
    } finally {
      input?.closeSync();
    }
  }

  static Map<String, dynamic> _decodeObject(String source, String label) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw FormatException('$label必须是 JSON 对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static TagSpace _validateMetadata(
    Map<String, dynamic> metadata,
    SpaceArchiveKind kind,
  ) {
    final space = TagSpace.fromJson(
      Map<String, dynamic>.from(metadata['space'] as Map),
    );
    final tags = SpacePortability._jsonList(
      metadata,
      'tags',
    ).map(TagDefinition.fromJson).toList();
    final placements = SpacePortability._jsonList(
      metadata,
      'placements',
    ).map(TagPlacement.fromJson).toList();
    if (tags.any((tag) => tag.spaceId != space.id) ||
        placements.any((placement) => placement.spaceId != space.id)) {
      throw const FormatException('空间归档包含跨空间标签关系');
    }
    _requireUnique(tags.map((tag) => tag.id), '标签 ID');
    _requireUnique(placements.map((placement) => placement.id), '标签位置 ID');
    final tagIds = tags.map((tag) => tag.id).toSet();
    final placementIds = placements.map((placement) => placement.id).toSet();
    if (placements.any(
      (placement) =>
          !tagIds.contains(placement.tagId) ||
          (placement.parentId != null &&
              !placementIds.contains(placement.parentId)),
    )) {
      throw const FormatException('空间归档标签位置引用无效');
    }
    if (kind == SpaceArchiveKind.template) {
      for (final key in [
        'resources',
        'memberships',
        'assignments',
        'folderTagInheritances',
        'usageEvents',
        'tagOperations',
      ]) {
        if (SpacePortability._jsonList(metadata, key).isNotEmpty) {
          throw const FormatException('空间模板不能包含资源、关系或历史');
        }
      }
      return space;
    }
    final resources = SpacePortability._jsonList(
      metadata,
      'resources',
    ).map(_PackagedResource.fromJson).toList();
    _requireUnique(resources.map((resource) => resource.id), '资源 ID');
    _requireUnique(resources.map((resource) => resource.archivePath), '资源归档路径');
    final resourceIds = resources.map((resource) => resource.id).toSet();
    final memberships = SpacePortability._jsonList(
      metadata,
      'memberships',
    ).map(SpaceMembership.fromJson).toList();
    final assignments = SpacePortability._jsonList(
      metadata,
      'assignments',
    ).map(TagAssignment.fromJson).toList();
    final rules = SpacePortability._jsonList(
      metadata,
      'folderTagInheritances',
    ).map(FolderTagInheritance.fromJson).toList();
    final events = SpacePortability._jsonList(
      metadata,
      'usageEvents',
    ).map(UsageEvent.fromJson).toList();
    final tagOperations = SpacePortability._jsonList(
      metadata,
      'tagOperations',
    ).map(TagDomainOperation.fromJson).toList();
    final resourcesById = {
      for (final resource in resources) resource.id: resource,
    };
    _requireUnique(
      memberships.map((membership) => membership.resourceId),
      '空间成员资源 ID',
    );
    if (memberships.length != resourceIds.length ||
        memberships.any(
          (membership) =>
              membership.spaceId != space.id ||
              !resourceIds.contains(membership.resourceId),
        ) ||
        assignments.any(
          (assignment) =>
              !resourceIds.contains(assignment.resourceId) ||
              !placementIds.contains(assignment.placementId),
        ) ||
        rules.any(
          (rule) =>
              !resourceIds.contains(rule.folderResourceId) ||
              resourcesById[rule.folderResourceId]?.kind !=
                  ResourceKind.folder ||
              !tagIds.contains(rule.tagId),
        ) ||
        events.any(
          (event) =>
              event.spaceId != space.id ||
              (event.resourceId != null &&
                  !resourceIds.contains(event.resourceId)) ||
              (event.placementId != null &&
                  !placementIds.contains(event.placementId)),
        ) ||
        tagOperations.any((operation) => operation.spaceId != space.id)) {
      throw const FormatException('空间导出包资源关系引用无效');
    }
    _requireUnique(assignments.map((item) => item.id), '标注 ID');
    _requireUnique(rules.map((item) => item.id), '继承规则 ID');
    _requireUnique(events.map((item) => item.id), '使用历史 ID');
    _requireUnique(tagOperations.map((item) => item.id), '标签操作历史 ID');
    for (final resource in resources) {
      SpacePortability._validateRelativePath(resource.relativePath);
      SpacePortability._validateRelativePath(resource.archivePath);
      if (!path.posix.isWithin('resources', resource.archivePath)) {
        throw FormatException('资源归档路径必须位于 resources/：${resource.archivePath}');
      }
    }
    return space;
  }

  static void _requireUnique(Iterable<String> values, String label) {
    final list = values.toList();
    if (list.toSet().length != list.length) {
      throw FormatException('空间归档包含重复$label');
    }
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _PackagedResource {
  const _PackagedResource({
    required this.id,
    required this.relativePath,
    required this.kind,
    required this.createdAt,
    required this.archivePath,
  });

  final String id;
  final String relativePath;
  final ResourceKind kind;
  final DateTime createdAt;
  final String archivePath;

  factory _PackagedResource.fromJson(Map<String, dynamic> json) =>
      _PackagedResource(
        id: json['id'] as String,
        relativePath: json['relativePath'] as String,
        kind: ResourceKind.values.byName(json['kind'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        archivePath: json['archivePath'] as String,
      );
}

class _ArchiveEntryRecord {
  const _ArchiveEntryRecord({
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.sha256Digest,
  });

  final String relativePath;
  final String kind;
  final int? sizeBytes;
  final String? sha256Digest;

  Map<String, dynamic> toJson() => {
    'path': relativePath,
    'kind': kind,
    'sizeBytes': sizeBytes,
    'sha256': sha256Digest,
  };

  factory _ArchiveEntryRecord.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (json['path'] is! String ||
        (kind != 'file' && kind != 'directory') ||
        (kind == 'file' &&
            (json['sizeBytes'] is! int || json['sha256'] is! String))) {
      throw const FormatException('空间归档清单条目无效');
    }
    return _ArchiveEntryRecord(
      relativePath: json['path'] as String,
      kind: kind as String,
      sizeBytes: json['sizeBytes'] as int?,
      sha256Digest: json['sha256'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ArchiveEntryRecord &&
      other.relativePath == relativePath &&
      other.kind == kind &&
      other.sizeBytes == sizeBytes &&
      other.sha256Digest == sha256Digest;

  @override
  int get hashCode => Object.hash(relativePath, kind, sizeBytes, sha256Digest);
}
