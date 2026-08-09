import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  test('user preferences persist the default import mode', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tagtag-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(baseDirectory: directory);

    await store.savePreferences(
      const UserPreferences(moveImportsByDefault: true),
    );

    final loaded = await LocalStore(baseDirectory: directory).loadPreferences();
    expect(loaded.moveImportsByDefault, isTrue);
  });

  test(
    'normal selection replaces while explicit multi-selection accumulates',
    () {
      final controller = TagTagController(store: LocalStore());

      controller.selectResource('resource-one');
      controller.selectResource('resource-two');

      expect(controller.selectedResourceIds, {'resource-two'});

      controller.toggleResourceSelection('resource-one', true);

      expect(controller.selectedResourceIds, {'resource-one', 'resource-two'});
    },
  );

  test(
    'one tag entity can appear at two paths while same names stay independent',
    () {
      final state = AppState.demo();
      final references = state.tags.where((tag) => tag.name == '参考').toList();
      final sharedReference = references.singleWhere(
        (tag) => tag.id == 'tag-reference-shared',
      );
      final sharedPlacements = state.placements
          .where((placement) => placement.tagId == sharedReference.id)
          .toList();

      expect(references, hasLength(2));
      expect(sharedPlacements, hasLength(2));
      expect(state.pathOf(sharedPlacements.first.id), contains('参考'));
      expect(state.pathOf(sharedPlacements.last.id), contains('参考'));
      expect(
        state.pathOf(sharedPlacements.first.id),
        isNot(state.pathOf(sharedPlacements.last.id)),
      );
    },
  );

  test(
    'browsing either placement of a unique tag shows the same resources',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-shared-tag-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = TagTagController(
        store: LocalStore(baseDirectory: directory),
      );
      await controller.store.save(AppState.demo());
      await controller.load();

      controller.selectPlacement('place-project-design-reference');
      final firstPathIds = controller.visibleResources
          .map((item) => item.id)
          .toSet();
      controller.selectPlacement('place-personal-reading-reference');
      final secondPathIds = controller.visibleResources
          .map((item) => item.id)
          .toSet();

      expect(firstPathIds, contains('resource-architecture'));
      expect(secondPathIds, firstPathIds);
      expect(secondPathIds, isNot(contains('resource-notes')));
    },
  );

  test('hierarchy nodes share resources by tag entity identity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tagtag-hierarchy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final controller = TagTagController(
      store: LocalStore(baseDirectory: directory),
    );
    await controller.store.save(AppState.demo());
    await controller.load();

    final first = controller.resourcesForPlacement(
      controller.state.placementById('place-project-design-reference'),
    );
    final second = controller.resourcesForPlacement(
      controller.state.placementById('place-personal-reading-reference'),
    );

    expect(first.map((resource) => resource.id).toSet(), {
      'resource-architecture',
      'resource-comparison',
    });
    expect(second.map((resource) => resource.id).toSet(), {
      'resource-architecture',
      'resource-comparison',
    });
  });

  test(
    'deleting one tag placement promotes children and preserves tag resources',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-delete-placement-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = TagTagController(
        store: LocalStore(baseDirectory: directory),
      );
      await controller.store.save(AppState.demo());
      await controller.load();
      final childId = await controller.createPlacement(
        name: '待提升子标签',
        colorValue: 0xff0f766e,
        parentId: 'place-personal-reading-reference',
      );

      await controller.deletePlacement('place-personal-reading-reference');

      expect(
        controller.state.placements.any(
          (item) => item.id == 'place-personal-reading-reference',
        ),
        isFalse,
      );
      expect(
        controller.state.placementById(childId).parentId,
        'place-personal-reading',
      );
      controller.selectPlacement('place-project-design-reference');
      expect(
        controller.visibleResources.map((item) => item.id),
        containsAll(<String>['resource-architecture', 'resource-comparison']),
      );
    },
  );

  test(
    'direct parent and child assignments coexist, exact duplicates do not',
    () async {
      final directory = await Directory.systemTemp.createTemp('tagtag-model-');
      addTearDown(() => directory.delete(recursive: true));
      final controller = TagTagController(
        store: LocalStore(baseDirectory: directory),
      );
      await controller.store.save(AppState.demo());
      await controller.load();
      const resourceId = 'resource-architecture';

      controller.toggleResourceSelection(resourceId, true);
      await controller.assignPlacementToSelection('place-project');
      await controller.assignPlacementToSelection('place-project');

      final assignedIds = controller
          .assignmentsForResource(resourceId)
          .map((placement) => placement.id)
          .toSet();
      expect(assignedIds, contains('place-project'));
      expect(assignedIds, contains('place-project-design-reference'));
      expect(
        controller.state.assignments
            .where(
              (assignment) =>
                  assignment.resourceId == resourceId &&
                  assignment.placementId == 'place-project',
            )
            .length,
        1,
      );
    },
  );

  test('clearing tags never changes a resource path', () async {
    final directory = await Directory.systemTemp.createTemp('tagtag-clear-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = TagTagController(
      store: LocalStore(baseDirectory: directory),
    );
    await controller.store.save(AppState.demo());
    await controller.load();
    const resourceId = 'resource-architecture';
    final originalPath = controller.state.resources
        .singleWhere((resource) => resource.id == resourceId)
        .path;

    controller.toggleResourceSelection(resourceId, true);
    await controller.clearSelectedTags();

    expect(controller.assignmentsForResource(resourceId), isEmpty);
    expect(
      controller.state.resources
          .singleWhere((resource) => resource.id == resourceId)
          .path,
      originalPath,
    );
  });

  test('backup storage round trip preserves spaces and assignments', () async {
    final directory = await Directory.systemTemp.createTemp('tagtag-store-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(baseDirectory: directory);
    final original = AppState.demo();

    await store.save(original);
    final loaded = await store.load();

    expect(loaded.spaces.single.name, original.spaces.single.name);
    expect(loaded.placements.length, original.placements.length);
    expect(loaded.assignments.length, original.assignments.length);
    expect(loaded.pathOf('place-personal-reading-reference'), '个人 / 阅读 / 参考');
  });

  test(
    'a new local store starts empty instead of injecting demo data',
    () async {
      final directory = await Directory.systemTemp.createTemp('tagtag-empty-');
      addTearDown(() => directory.delete(recursive: true));

      final state = await LocalStore(baseDirectory: directory).load();

      expect(state.spaces, isEmpty);
      expect(state.resources, isEmpty);
    },
  );

  test(
    'managed imports are restored through the tag domain after restart',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-domain-import-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/source.txt');
      await source.writeAsString('managed bytes');
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final controller = TagTagController(store: store, library: library);
      await controller.load();
      await controller.createSpace('默认空间');

      final imported = await controller.importManagedResource(
        source: source,
        targetDirectory: 'inbox',
      );

      expect(await source.readAsString(), 'managed bytes');
      expect(imported.id, controller.visibleResources.single.id);
      expect(
        imported.path,
        path.normalize(path.join(root.path, 'inbox', 'source.txt')),
      );

      final restarted = TagTagController(store: store, library: library);
      await restarted.load();
      expect(restarted.visibleResources.single.id, imported.id);
      expect(restarted.visibleResources.single.path, imported.path);
    },
  );

  test('a managed import can apply tags in the same domain action', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-tagged-import-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/tagged.txt');
    await source.writeAsString('tag me');
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();

    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: '',
      placementIds: const {
        'place-project-design-reference',
        'place-personal-reading-reference',
      },
    );

    expect(controller.assignmentsForResource(imported.id), hasLength(1));
    controller.selectPlacement('place-project-design-reference');
    expect(
      controller.visibleResources.map((item) => item.id),
      contains(imported.id),
    );
  });

  test('the inbox contains managed resources without tags', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-inbox-');
    addTearDown(() => sandbox.delete(recursive: true));
    final taggedSource = File('${sandbox.path}/tagged.txt');
    final untaggedSource = File('${sandbox.path}/untagged.txt');
    await taggedSource.writeAsString('tagged');
    await untaggedSource.writeAsString('untagged');
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();
    final tagged = await controller.importManagedResource(
      source: taggedSource,
      targetDirectory: '',
      placementIds: const {'place-project'},
    );
    final untagged = await controller.importManagedResource(
      source: untaggedSource,
      targetDirectory: '',
    );

    controller.showInboxResources();

    final visibleIds = controller.visibleResources.map((item) => item.id);
    expect(visibleIds, contains(untagged.id));
    expect(visibleIds, isNot(contains(tagged.id)));
  });

  test('consistency actions keep the tag domain synchronized', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-domain-consistency-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();
    final untracked = File('${root.path}/takeover.txt');
    await untracked.writeAsString('take over');

    final takenOver = await controller.takeOverUntracked('takeover.txt');

    expect(
      controller.state.resources.map((item) => item.id),
      contains(takenOver.id),
    );
    expect(
      controller.state.memberships.any(
        (membership) =>
            membership.resourceId == takenOver.id &&
            membership.spaceId == controller.activeSpaceId,
      ),
      isTrue,
    );

    final source = File('${sandbox.path}/tagged.txt');
    await source.writeAsString('keep tags');
    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: '',
      placementIds: const {'place-project'},
    );
    await File(imported.path).rename('${root.path}/tagged-renamed.txt');

    await controller.acceptExternalMove(imported.id, 'tagged-renamed.txt');

    expect(
      controller.state.resources
          .singleWhere((item) => item.id == imported.id)
          .path,
      path.normalize('${root.path}/tagged-renamed.txt'),
    );
    expect(
      controller.state.assignments
          .where((assignment) => assignment.resourceId == imported.id)
          .map((assignment) => assignment.placementId),
      {'place-project'},
    );
  });

  test('undoing an import removes the resource from the tag domain', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-domain-undo-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/undo.txt');
    await source.writeAsString('undo me');
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();
    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: '',
      placementIds: const {'place-project'},
    );
    final operation = (await controller.listOperations()).single;

    await controller.undoOperation(operation.id);

    expect(controller.state.resources, isEmpty);
    expect(
      controller.state.assignments.any(
        (assignment) => assignment.resourceId == imported.id,
      ),
      isFalse,
    );
    expect((await controller.listOperations()).single.undoneAt, isNotNull);
  });

  test('restoring a resource exits it from the complete tag domain', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-domain-exit-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/exit-domain.txt');
    await source.writeAsString('exit domain');
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();
    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: '',
      mode: ImportMode.move,
      placementIds: const {'place-project'},
    );
    controller.toggleResourceSelection(imported.id, true);

    await controller.restoreResourceToOriginalPath(imported.id);

    expect(
      controller.state.resources.any((resource) => resource.id == imported.id),
      isFalse,
    );
    expect(
      controller.state.memberships.any(
        (membership) => membership.resourceId == imported.id,
      ),
      isFalse,
    );
    expect(
      controller.state.assignments.any(
        (assignment) => assignment.resourceId == imported.id,
      ),
      isFalse,
    );
    expect(
      controller.state.usageEvents.any(
        (event) => event.resourceId == imported.id,
      ),
      isFalse,
    );
    expect(controller.selectedResourceIds, isNot(contains(imported.id)));
    expect(
      (await controller.listOperations()).first.type,
      ManagedOperationType.exitRestore,
    );
  });

  test(
    'undoing a restore exit restores its tag domain relationships',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-domain-undo-exit-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = File('${sandbox.path}/undo-domain-exit.txt');
      await source.writeAsString('undo domain exit');
      final library = await ManagedLibrary.initialize(
        Directory('${sandbox.path}/library'),
      );
      addTearDown(library.close);
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await store.save(AppState.demo());
      final controller = TagTagController(store: store, library: library);
      await controller.load();
      final imported = await controller.importManagedResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
        placementIds: const {'place-project'},
      );
      final exitOperation = await controller.restoreResourceToOriginalPath(
        imported.id,
      );

      await controller.undoOperation(exitOperation.id);

      expect(
        controller.state.resources
            .singleWhere((resource) => resource.id == imported.id)
            .path,
        imported.path,
      );
      expect(
        controller.state.memberships
            .where((membership) => membership.resourceId == imported.id)
            .map((membership) => membership.spaceId),
        {'space-design'},
      );
      expect(
        controller.state.assignments
            .where((assignment) => assignment.resourceId == imported.id)
            .map((assignment) => assignment.placementId),
        {'place-project'},
      );
      expect(
        controller.state.usageEvents.any(
          (event) =>
              event.resourceId == imported.id &&
              event.placementId == 'place-project',
        ),
        isTrue,
      );
      expect(await source.exists(), isFalse);
    },
  );

  test(
    'specified-path exit cleanup and undo preserve tag relationships',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-domain-exit-move-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final source = File('${sandbox.path}/domain-move.txt');
      final destination = File('${sandbox.path}/exports/domain-renamed.txt');
      await source.writeAsString('domain move');
      final library = await ManagedLibrary.initialize(
        Directory('${sandbox.path}/library'),
      );
      addTearDown(library.close);
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await store.save(AppState.demo());
      final controller = TagTagController(store: store, library: library);
      await controller.load();
      final imported = await controller.importManagedResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
        placementIds: const {'place-project'},
      );

      final operation = await controller.moveResourceToSpecifiedPath(
        imported.id,
        destination.path,
      );

      expect(controller.state.resources, isNot(contains(imported)));
      expect(
        controller.state.memberships.any(
          (membership) => membership.resourceId == imported.id,
        ),
        isFalse,
      );
      expect(
        controller.state.assignments.any(
          (assignment) => assignment.resourceId == imported.id,
        ),
        isFalse,
      );

      await controller.undoOperation(operation.id);

      expect(
        controller.state.resources.any(
          (resource) => resource.id == imported.id,
        ),
        isTrue,
      );
      expect(
        controller.state.memberships
            .where((membership) => membership.resourceId == imported.id)
            .map((membership) => membership.spaceId),
        {'space-design'},
      );
      expect(
        controller.state.assignments
            .where((assignment) => assignment.resourceId == imported.id)
            .map((assignment) => assignment.placementId),
        {'place-project'},
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test('recycle exit cleanup and undo preserve tag relationships', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-domain-exit-recycle-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/domain-recycle.txt');
    await source.writeAsString('domain recycle');
    final recycleBin = _ControllerFakeRecycleBin(
      Directory('${sandbox.path}/recycle'),
    );
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(
      store: store,
      library: library,
      recycleBin: recycleBin,
    );
    await controller.load();
    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
      placementIds: const {'place-project'},
    );

    final operation = await controller.recycleResource(imported.id);

    expect(
      controller.state.resources.any((resource) => resource.id == imported.id),
      isFalse,
    );
    expect(
      controller.state.assignments.any(
        (assignment) => assignment.resourceId == imported.id,
      ),
      isFalse,
    );

    await controller.undoOperation(operation.id);

    expect(
      controller.state.resources.any((resource) => resource.id == imported.id),
      isTrue,
    );
    expect(
      controller.state.assignments
          .where((assignment) => assignment.resourceId == imported.id)
          .map((assignment) => assignment.placementId),
      {'place-project'},
    );
  });

  test('one managed resource can be a member of multiple tag spaces', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tagtag-membership-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final controller = TagTagController(
      store: LocalStore(baseDirectory: directory),
    );
    await controller.store.save(AppState.demo());
    await controller.load();
    await controller.createSpace('第二空间');

    await controller.addResourceToActiveSpace('resource-architecture');

    expect(
      controller.visibleResources.map((item) => item.id),
      contains('resource-architecture'),
    );
    await controller.selectSpace('space-design');
    expect(
      controller.visibleResources.map((item) => item.id),
      contains('resource-architecture'),
    );
    expect(
      controller.state.resources.where(
        (item) => item.id == 'resource-architecture',
      ),
      hasLength(1),
    );
  });

  test(
    'deleting a tag entity preserves resources and space memberships',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-delete-entity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = TagTagController(
        store: LocalStore(baseDirectory: directory),
      );
      await controller.store.save(AppState.demo());
      await controller.load();

      await controller.deleteTagEntity('tag-reference-independent');

      expect(
        controller.state.tags.any(
          (tag) => tag.id == 'tag-reference-independent',
        ),
        isFalse,
      );
      expect(
        controller.state.resources.any(
          (resource) => resource.id == 'resource-notes',
        ),
        isTrue,
      );
      expect(
        controller.state.resourceIdsForSpace('space-design'),
        contains('resource-notes'),
      );
      expect(controller.assignmentsForResource('resource-notes'), isEmpty);
    },
  );
}

class _ControllerFakeRecycleBin implements RecycleBinGateway {
  _ControllerFakeRecycleBin(this.directory);

  final Directory directory;

  @override
  Future<String> recycle(String resourcePath) async {
    await directory.create(recursive: true);
    final token = path.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}-${path.basename(resourcePath)}',
    );
    await _rename(resourcePath, token);
    return token;
  }

  @override
  Future<void> restore(String token, String destinationPath) async {
    await Directory(path.dirname(destinationPath)).create(recursive: true);
    await _rename(token, destinationPath);
  }

  static Future<void> _rename(String source, String destination) async {
    final type = await FileSystemEntity.type(source);
    if (type == FileSystemEntityType.file) {
      await File(source).rename(destination);
      return;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(destination);
      return;
    }
    throw FileSystemException('找不到回收站测试资源', source);
  }
}
