import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/services/space_portability.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  test(
    'space package round trip preserves resource ids, bytes, and empty folders',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-space-round-trip-',
      );
      final sourceLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'source-library')),
      );
      final targetLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'target-library')),
      );
      try {
        final sourceFile = File(path.join(sandbox.path, 'outside', 'note.txt'));
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsBytes([0, 1, 2, 3, 255]);
        final sourceFolder = Directory(
          path.join(sandbox.path, 'outside', 'reference'),
        );
        await Directory(
          path.join(sourceFolder.path, 'empty'),
        ).create(recursive: true);
        await File(
          path.join(sourceFolder.path, 'nested.txt'),
        ).writeAsString('folder bytes');
        final managedFile = await sourceLibrary.importResource(
          source: sourceFile,
          targetDirectory: 'documents',
        );
        final managedFolder = await sourceLibrary.importResource(
          source: sourceFolder,
          targetDirectory: 'collections',
        );
        final state = _portableState(sourceLibrary, [
          managedFile,
          managedFolder,
        ]);
        final archive = File(
          path.join(sandbox.path, 'portable.tagtag-space.zip'),
        );

        await SpacePortability.exportPackage(
          state: state,
          spaceId: 'space-portable',
          library: sourceLibrary,
          destination: archive,
        );
        final mutation = await SpacePortability.importArchive(
          archiveFile: archive,
          currentState: AppState.empty(),
          library: targetLibrary,
          targetDirectory: 'imported',
        );

        expect(
          mutation.state.resources.map((resource) => resource.id).toSet(),
          {managedFile.id, managedFolder.id},
        );
        expect(
          await File(
            path.join(
              targetLibrary.root.path,
              'imported',
              managedFile.relativePath,
            ),
          ).readAsBytes(),
          [0, 1, 2, 3, 255],
        );
        expect(
          await File(
            path.join(
              targetLibrary.root.path,
              'imported',
              managedFolder.relativePath,
              'nested.txt',
            ),
          ).readAsString(),
          'folder bytes',
        );
        expect(
          await Directory(
            path.join(
              targetLibrary.root.path,
              'imported',
              managedFolder.relativePath,
              'empty',
            ),
          ).exists(),
          isTrue,
        );
      } finally {
        await sourceLibrary.close();
        await targetLibrary.close();
        await sandbox.delete(recursive: true);
      }
    },
  );

  test(
    'space package uses resource identity instead of assignment or content deduplication',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-space-identity-',
      );
      final library = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'library')),
      );
      try {
        final firstSource = File(path.join(sandbox.path, 'first.txt'));
        final secondSource = File(path.join(sandbox.path, 'second.txt'));
        await firstSource.writeAsString('identical bytes');
        await secondSource.writeAsString('identical bytes');
        final first = await library.importResource(
          source: firstSource,
          targetDirectory: 'one',
        );
        final second = await library.importResource(
          source: secondSource,
          targetDirectory: 'two',
        );
        final baseState = _portableState(library, [first, second]);
        final state = baseState.copyWith(
          placements: [
            ...baseState.placements,
            const TagPlacement(
              id: 'placement-portable-second',
              spaceId: 'space-portable',
              tagId: 'tag-portable',
              parentId: null,
              sortOrder: 1,
            ),
          ],
          assignments: [
            ...baseState.assignments,
            TagAssignment(
              id: 'assignment-first-second-placement',
              resourceId: first.id,
              placementId: 'placement-portable-second',
              createdAt: DateTime.utc(2026, 8, 11, 8),
            ),
          ],
        );
        final archive = File(path.join(sandbox.path, 'identity.zip'));

        await SpacePortability.exportPackage(
          state: state,
          spaceId: 'space-portable',
          library: library,
          destination: archive,
        );
        final summary = await SpacePortability.inspect(archive);

        expect(summary.resourceCount, 2);
      } finally {
        await library.close();
        await sandbox.delete(recursive: true);
      }
    },
  );

  test('space package import reuses a matching stable resource id', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-space-id-reuse-',
    );
    final sourceLibrary = await ManagedLibrary.initialize(
      Directory(path.join(sandbox.path, 'source-library')),
    );
    final targetLibrary = await ManagedLibrary.initialize(
      Directory(path.join(sandbox.path, 'target-library')),
    );
    try {
      final source = File(path.join(sandbox.path, 'source.txt'));
      await source.writeAsString('stable bytes');
      final managed = await sourceLibrary.importResource(
        source: source,
        targetDirectory: 'documents',
      );
      final archive = File(path.join(sandbox.path, 'stable-id.zip'));
      await SpacePortability.exportPackage(
        state: _portableState(sourceLibrary, [managed]),
        spaceId: 'space-portable',
        library: sourceLibrary,
        destination: archive,
      );
      final existingSource = File(path.join(sandbox.path, 'existing.txt'));
      await existingSource.writeAsString('stable bytes');
      await targetLibrary.importPackagedResources([
        PackagedResourceImport(
          id: managed.id,
          source: existingSource,
          targetRelativePath: 'existing/source.txt',
          kind: ManagedResourceKind.file,
          createdAt: managed.createdAt,
        ),
      ]);

      final mutation = await SpacePortability.importArchive(
        archiveFile: archive,
        currentState: AppState.empty(),
        library: targetLibrary,
        targetDirectory: 'incoming',
      );

      expect(mutation.importedResourceIds, isEmpty);
      expect((await targetLibrary.listResources()).single.id, managed.id);
      expect(mutation.state.resources.single.id, managed.id);
    } finally {
      await sourceLibrary.close();
      await targetLibrary.close();
      await sandbox.delete(recursive: true);
    }
  });

  test(
    'space package import rejects a conflicting stable resource id',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-space-id-conflict-',
      );
      final sourceLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'source-library')),
      );
      final targetLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'target-library')),
      );
      try {
        final source = File(path.join(sandbox.path, 'source.txt'));
        await source.writeAsString('packaged bytes');
        final managed = await sourceLibrary.importResource(
          source: source,
          targetDirectory: 'documents',
        );
        final archive = File(path.join(sandbox.path, 'conflicting-id.zip'));
        await SpacePortability.exportPackage(
          state: _portableState(sourceLibrary, [managed]),
          spaceId: 'space-portable',
          library: sourceLibrary,
          destination: archive,
        );
        final existingSource = File(path.join(sandbox.path, 'existing.txt'));
        await existingSource.writeAsString('different bytes');
        await targetLibrary.importPackagedResources([
          PackagedResourceImport(
            id: managed.id,
            source: existingSource,
            targetRelativePath: 'existing/source.txt',
            kind: ManagedResourceKind.file,
            createdAt: managed.createdAt,
          ),
        ]);

        await expectLater(
          SpacePortability.importArchive(
            archiveFile: archive,
            currentState: AppState.empty(),
            library: targetLibrary,
            targetDirectory: 'incoming',
          ),
          throwsA(isA<StateError>()),
        );
        expect((await targetLibrary.listResources()).single.id, managed.id);
        expect(
          await Directory(
            path.join(targetLibrary.root.path, 'incoming'),
          ).exists(),
          isFalse,
        );
      } finally {
        await sourceLibrary.close();
        await targetLibrary.close();
        await sandbox.delete(recursive: true);
      }
    },
  );

  test('space package inspection rejects tampered resource bytes', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-space-tamper-',
    );
    final library = await ManagedLibrary.initialize(
      Directory(path.join(sandbox.path, 'library')),
    );
    try {
      final source = File(path.join(sandbox.path, 'source.txt'));
      await source.writeAsString('original bytes');
      final managed = await library.importResource(
        source: source,
        targetDirectory: 'documents',
      );
      final archive = File(path.join(sandbox.path, 'tampered.zip'));
      await SpacePortability.exportPackage(
        state: _portableState(library, [managed]),
        spaceId: 'space-portable',
        library: library,
        destination: archive,
      );
      await _replaceFirstResourceContent(archive, 'tampered bytes'.codeUnits);

      await expectLater(
        SpacePortability.inspect(archive),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await library.close();
      await sandbox.delete(recursive: true);
    }
  });

  test('space package inspection rejects zip traversal entries', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-space-traversal-',
    );
    try {
      final malicious = Archive()
        ..addFile(ArchiveFile('../outside.txt', 3, [1, 2, 3]));
      final archiveFile = File(path.join(sandbox.path, 'traversal.zip'));
      await archiveFile.writeAsBytes(ZipEncoder().encode(malicious)!);

      await expectLater(
        SpacePortability.inspect(archiveFile),
        throwsA(isA<FormatException>()),
      );
      expect(
        await File(path.join(sandbox.parent.path, 'outside.txt')).exists(),
        isFalse,
      );
    } finally {
      await sandbox.delete(recursive: true);
    }
  });

  test(
    'space template round trip imports structure without resource data',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-space-template-',
      );
      final sourceLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'source-library')),
      );
      final targetLibrary = await ManagedLibrary.initialize(
        Directory(path.join(sandbox.path, 'target-library')),
      );
      try {
        final source = File(path.join(sandbox.path, 'source.txt'));
        await source.writeAsString('must not enter template');
        final managed = await sourceLibrary.importResource(
          source: source,
          targetDirectory: 'documents',
        );
        final archive = File(path.join(sandbox.path, 'template.zip'));

        await SpacePortability.exportTemplate(
          state: _portableState(sourceLibrary, [managed]),
          spaceId: 'space-portable',
          destination: archive,
        );
        final summary = await SpacePortability.inspect(archive);
        final occupiedState = _portableState(sourceLibrary, [managed]).copyWith(
          resources: const [],
          memberships: const [],
          assignments: const [],
          folderTagInheritances: const [],
          usageEvents: const [],
          tagOperations: const [],
        );
        final mutation = await SpacePortability.importArchive(
          archiveFile: archive,
          currentState: occupiedState,
          library: targetLibrary,
          targetDirectory: '',
        );

        expect(summary.kind, SpaceArchiveKind.template);
        expect(summary.resourceCount, 0);
        expect(mutation.state.spaces, hasLength(2));
        expect(mutation.state.activeSpaceId, isNot('space-portable'));
        final instantiatedTag = mutation.state.tags.last;
        final instantiatedPlacement = mutation.state.placements.last;
        expect(instantiatedTag.id, isNot('tag-portable'));
        expect(instantiatedTag.spaceId, mutation.state.activeSpaceId);
        expect(instantiatedPlacement.id, isNot('placement-portable'));
        expect(instantiatedPlacement.spaceId, mutation.state.activeSpaceId);
        expect(instantiatedPlacement.tagId, instantiatedTag.id);
        expect(mutation.state.resources, isEmpty);
        expect(mutation.state.memberships, isEmpty);
        expect(mutation.state.assignments, isEmpty);
        expect(mutation.state.folderTagInheritances, isEmpty);
        expect(mutation.state.usageEvents, isEmpty);
        expect(mutation.state.tagOperations, isEmpty);
        expect(await targetLibrary.listResources(), isEmpty);
      } finally {
        await sourceLibrary.close();
        await targetLibrary.close();
        await sandbox.delete(recursive: true);
      }
    },
  );

  test('controller persists an imported space package across reopen', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-space-controller-',
    );
    final sourceLibrary = await ManagedLibrary.initialize(
      Directory(path.join(sandbox.path, 'source-library')),
    );
    var targetLibrary = await ManagedLibrary.initialize(
      Directory(path.join(sandbox.path, 'target-library')),
    );
    try {
      final source = File(path.join(sandbox.path, 'source.txt'));
      await source.writeAsString('controller bytes');
      final managed = await sourceLibrary.importResource(
        source: source,
        targetDirectory: 'documents',
      );
      final archive = File(path.join(sandbox.path, 'controller.zip'));
      await SpacePortability.exportPackage(
        state: _portableState(sourceLibrary, [managed]),
        spaceId: 'space-portable',
        library: sourceLibrary,
        destination: archive,
      );
      final store = LocalStore(
        baseDirectory: Directory(path.join(sandbox.path, 'app')),
      );
      final controller = TagTagController(store: store, library: targetLibrary);
      await controller.load();

      await controller.importSpaceArchive(
        archiveFile: archive,
        expectedKind: SpaceArchiveKind.package,
        targetDirectory: 'incoming',
      );
      await targetLibrary.close();
      targetLibrary = await ManagedLibrary.open(
        Directory(path.join(sandbox.path, 'target-library')),
      );
      final reopened = TagTagController(store: store, library: targetLibrary);
      await reopened.load();

      expect(reopened.activeSpaceId, 'space-portable');
      expect(reopened.state.resources.single.id, managed.id);
      expect(reopened.state.memberships.single.resourceId, managed.id);
      expect(reopened.state.assignments.single.resourceId, managed.id);
    } finally {
      await sourceLibrary.close();
      await targetLibrary.close();
      await sandbox.delete(recursive: true);
    }
  });
}

Future<void> _replaceFirstResourceContent(
  File archiveFile,
  List<int> replacement,
) async {
  final decoded = ZipDecoder().decodeBytes(
    await archiveFile.readAsBytes(),
    verify: true,
  );
  final rebuilt = Archive();
  var replaced = false;
  for (final entry in decoded) {
    if (entry.isFile && entry.name.startsWith('resources/') && !replaced) {
      rebuilt.addFile(ArchiveFile(entry.name, replacement.length, replacement));
      replaced = true;
      continue;
    }
    if (entry.isFile) {
      final content = List<int>.from(entry.content as List<int>);
      rebuilt.addFile(ArchiveFile(entry.name, content.length, content));
    } else {
      rebuilt.addFile(ArchiveFile(entry.name, 0, null)..isFile = false);
    }
  }
  expect(replaced, isTrue);
  await archiveFile.writeAsBytes(ZipEncoder().encode(rebuilt)!, flush: true);
}

AppState _portableState(
  ManagedLibrary library,
  List<ManagedResource> resources,
) {
  final now = DateTime.utc(2026, 8, 11, 8);
  const spaceId = 'space-portable';
  const tagId = 'tag-portable';
  const placementId = 'placement-portable';
  return AppState(
    spaces: [TagSpace(id: spaceId, name: '便携空间', createdAt: now)],
    tags: [
      TagDefinition(
        id: tagId,
        spaceId: spaceId,
        name: '资料',
        colorValue: 0xff0f766e,
        createdAt: now,
      ),
    ],
    placements: const [
      TagPlacement(
        id: placementId,
        spaceId: spaceId,
        tagId: tagId,
        parentId: null,
        sortOrder: 0,
      ),
    ],
    resources: resources
        .map(
          (resource) => TagResource(
            id: resource.id,
            name: resource.name,
            path: path.joinAll([
              library.root.path,
              ...resource.relativePath.split('/'),
            ]),
            kind: resource.kind == ManagedResourceKind.file
                ? ResourceKind.file
                : ResourceKind.folder,
            modifiedAt: resource.modifiedAt,
            sizeBytes: resource.sizeBytes,
            createdAt: resource.createdAt,
          ),
        )
        .toList(),
    memberships: resources
        .map(
          (resource) => SpaceMembership(
            resourceId: resource.id,
            spaceId: spaceId,
            createdAt: now,
          ),
        )
        .toList(),
    assignments: resources.indexed
        .map(
          (entry) => TagAssignment(
            id: 'assignment-${entry.$1}',
            resourceId: entry.$2.id,
            placementId: placementId,
            createdAt: now,
          ),
        )
        .toList(),
    folderTagInheritances: [
      for (final resource in resources)
        if (resource.kind == ManagedResourceKind.folder)
          FolderTagInheritance(
            id: 'inheritance-${resource.id}',
            folderResourceId: resource.id,
            tagId: tagId,
            createdAt: now,
          ),
    ],
    usageEvents: [
      UsageEvent(
        id: 'usage-portable',
        spaceId: spaceId,
        resourceId: resources.first.id,
        placementId: placementId,
        type: UsageEventType.opened,
        occurredAt: now,
      ),
    ],
    tagOperations: [
      TagDomainOperation(
        id: 'operation-portable',
        spaceId: spaceId,
        type: TagDomainOperationType.merge,
        summary: '历史记录',
        context: const {},
        createdAt: now,
        undoneAt: null,
      ),
    ],
    activeSpaceId: spaceId,
  );
}
