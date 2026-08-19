import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  test('undo create removes the placement and the new tag entity', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    final placementId = await controller.createPlacement(
      name: 'New Tag',
      colorValue: 0xff000000,
    );
    final placement = controller.state.placementById(placementId);
    final tagId = placement.tagId;
    expect(controller.state.tagById(tagId).name, 'New Tag');
    expect(controller.activePlacementId, placementId);

    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.create);
    expect(operation.context['createdNewTag'], isTrue);

    await controller.undoTagOperation(operation.id);
    expect(
      controller.state.placements.map((item) => item.id),
      isNot(contains(placementId)),
    );
    expect(
      controller.state.tags.map((item) => item.id),
      isNot(contains(tagId)),
    );
    expect(controller.activePlacementId, isNull);
    expect(controller.tagOperations.first.undoneAt, isNotNull);

    await expectLater(
      controller.undoTagOperation(operation.id),
      throwsA(isA<StateError>()),
    );
  });

  test('undo create with a reused tag entity keeps the entity', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    final placementId = await controller.createPlacement(
      name: 'Shared',
      colorValue: 0,
      parentId: 'place-child',
      reuseTagId: 'tag-shared',
    );
    final operation = controller.tagOperations.first;
    expect(operation.context['createdNewTag'], isFalse);

    await controller.undoTagOperation(operation.id);
    expect(
      controller.state.placements.map((item) => item.id),
      isNot(contains(placementId)),
    );
    expect(controller.state.tagById('tag-shared').name, 'Shared');
    expect(controller.state.placementById('place-shared-a').tagId, 'tag-shared');
  });

  test('undo edit restores the previous name and color', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.updateTag(
      tagId: 'tag-root',
      name: 'Renamed',
      colorValue: 0xff222222,
    );
    expect(controller.state.tagById('tag-root').name, 'Renamed');
    expect(controller.state.tagById('tag-root').colorValue, 0xff222222);

    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.edit);
    await controller.undoTagOperation(operation.id);
    expect(controller.state.tagById('tag-root').name, 'Root');
    expect(controller.state.tagById('tag-root').colorValue, 0xff111111);
  });

  test('undo policy restores the previous name policy', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.setTagNamePolicy('tag-root', TagNamePolicy.unique);
    expect(controller.tagNamePolicyOf('tag-root'), TagNamePolicy.unique);

    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.policy);
    expect(operation.context['previousPolicy'], TagNamePolicy.inherit.name);

    await controller.undoTagOperation(operation.id);
    expect(controller.tagNamePolicyOf('tag-root'), TagNamePolicy.inherit);
  });

  test('undo reparent restores the previous parent and sort order', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.reparentPlacement('place-shared-a', 'place-child');
    final moved = controller.state.placementById('place-shared-a');
    expect(moved.parentId, 'place-child');
    expect(moved.sortOrder, 0);

    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.reparent);
    await controller.undoTagOperation(operation.id);
    final restored = controller.state.placementById('place-shared-a');
    expect(restored.parentId, isNull);
    expect(restored.sortOrder, 1);
  });

  test(
    'undo delete placement restores children and reassigned assignments',
    () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final assignmentsBefore = _assignmentsById(controller);

      await controller.deletePlacement('place-shared-a');
      expect(
        controller.state.placements.map((item) => item.id),
        isNot(contains('place-shared-a')),
      );
      // The child placement is promoted to the deleted placement's parent.
      expect(controller.state.placementById('place-leaf').parentId, isNull);
      // resource-file already carried place-shared-b, so its reassigned
      // assignment is dropped by the dedup; resource-file2 is moved over.
      expect(
        controller.state.assignments.map((item) => item.id),
        containsAll(const ['assignment-a', 'assignment-c']),
      );
      expect(
        controller.state.assignments.map((item) => item.id),
        isNot(contains('assignment-b')),
      );

      final operation = controller.tagOperations.first;
      expect(operation.type, TagDomainOperationType.deletePlacement);
      await controller.undoTagOperation(operation.id);

      final restored = controller.state.placementById('place-shared-a');
      expect(restored.parentId, isNull);
      expect(restored.sortOrder, 1);
      expect(
        controller.state.placementById('place-leaf').parentId,
        'place-shared-a',
      );
      expect(_assignmentsById(controller), assignmentsBefore);
      expect(controller.activePlacementId, 'place-shared-a');
    },
  );

  test('undo delete entity restores the full entity snapshot', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    final assignmentsBefore = _assignmentsById(controller);

    await controller.deleteTagEntity('tag-shared');
    expect(
      controller.state.tags.map((item) => item.id),
      isNot(contains('tag-shared')),
    );
    expect(
      controller.state.placements.map((item) => item.id),
      isNot(contains('place-shared-a')),
    );
    expect(
      controller.state.placements.map((item) => item.id),
      isNot(contains('place-shared-b')),
    );
    expect(controller.state.placementById('place-leaf').parentId, isNull);
    expect(controller.state.assignments, isEmpty);
    expect(controller.state.folderTagInheritances, isEmpty);

    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.deleteEntity);
    await controller.undoTagOperation(operation.id);

    final tag = controller.state.tagById('tag-shared');
    expect(tag.name, 'Shared');
    expect(tag.colorValue, 0xff333333);
    expect(controller.state.placementById('place-shared-a').parentId, isNull);
    expect(
      controller.state.placementById('place-shared-b').parentId,
      'place-root',
    );
    expect(
      controller.state.placementById('place-leaf').parentId,
      'place-shared-a',
    );
    expect(_assignmentsById(controller), assignmentsBefore);
    expect(
      controller.state.folderTagInheritances.single.tagId,
      'tag-shared',
    );
    expect(controller.activePlacementId, 'place-shared-a');
  });

  test('undo pin and hide restore set membership in both directions', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.togglePlacementPinned('place-root');
    expect(controller.isPlacementPinned('place-root'), isTrue);
    final pin = controller.tagOperations.first;
    expect(pin.type, TagDomainOperationType.pin);
    await controller.undoTagOperation(pin.id);
    expect(controller.isPlacementPinned('place-root'), isFalse);

    await controller.togglePlacementHidden('place-root');
    expect(controller.isPlacementHidden('place-root'), isTrue);
    await controller.togglePlacementHidden('place-root');
    expect(controller.isPlacementHidden('place-root'), isFalse);
    final hide = controller.tagOperations.first;
    expect(hide.type, TagDomainOperationType.hide);
    await controller.undoTagOperation(hide.id);
    expect(controller.isPlacementHidden('place-root'), isTrue);
  });

  test('persistence reload keeps the undo context usable', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    final placementId = await controller.createPlacement(
      name: 'Persisted',
      colorValue: 0xff444444,
    );
    final tagId = controller.state.placementById(placementId).tagId;
    await controller.updateTag(
      tagId: tagId,
      name: 'Persisted renamed',
      colorValue: 0xff555555,
    );
    await controller.reparentPlacement(placementId, 'place-root');

    final reloaded = TagTagController(store: fixture.store);
    await reloaded.load();
    final operationIds = reloaded.tagOperations
        .map((operation) => operation.id)
        .toList();
    expect(operationIds, hasLength(3));

    // Undo newest first: reparent, edit, create.
    await reloaded.undoTagOperation(operationIds[0]);
    expect(reloaded.state.placementById(placementId).parentId, isNull);
    await reloaded.undoTagOperation(operationIds[1]);
    expect(reloaded.state.tagById(tagId).name, 'Persisted');
    expect(reloaded.state.tagById(tagId).colorValue, 0xff444444);
    await reloaded.undoTagOperation(operationIds[2]);
    expect(
      reloaded.state.placements.map((item) => item.id),
      isNot(contains(placementId)),
    );
    expect(
      reloaded.state.tags.map((item) => item.id),
      isNot(contains(tagId)),
    );
  });

  test('undo of a legacy context-free edit fails with a clear error', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    // Assignment add/remove entries are recorded as edit operations without
    // undo context; they must refuse to undo instead of corrupting state.
    controller.selectResource('resource-folder');
    await controller.assignPlacementToSelection('place-root');
    final operation = controller.tagOperations.first;
    expect(operation.type, TagDomainOperationType.edit);
    expect(operation.context, isEmpty);

    await expectLater(
      controller.undoTagOperation(operation.id),
      throwsA(isA<StateError>()),
    );
  });

  test('operation JSON stays backwards compatible for legacy entries', () {
    final now = DateTime.utc(2026, 1, 1);
    for (final type in TagDomainOperationType.values) {
      final operation = TagDomainOperation(
        id: 'op-$type',
        spaceId: 'space',
        type: type,
        summary: 'summary',
        context: const {},
        createdAt: now,
        undoneAt: null,
      );
      final decoded = TagDomainOperation.fromJson(operation.toJson());
      expect(decoded.type, type);
      expect(decoded.context, isEmpty);
      expect(decoded.undoneAt, isNull);
    }
  });
}

List<Map<String, dynamic>> _assignmentsById(TagTagController controller) {
  final assignments = controller.state.assignments
      .map((assignment) => assignment.toJson())
      .toList();
  assignments.sort(
    (first, second) =>
        (first['id'] as String).compareTo(second['id'] as String),
  );
  return assignments;
}

class _Fixture {
  const _Fixture({
    required this.controller,
    required this.store,
    required this.directory,
  });

  final TagTagController controller;
  final LocalStore store;
  final Directory directory;

  Future<void> dispose() => directory.delete(recursive: true);
}

Future<_Fixture> _createFixture() async {
  final directory = await Directory.systemTemp.createTemp('tagtag-undo-');
  final store = LocalStore(baseDirectory: directory);
  final now = DateTime.utc(2026, 1, 1);
  final state = AppState(
    spaces: [TagSpace(id: 'space', name: 'Space', createdAt: now)],
    tags: [
      _tag('tag-root', 'Root', 0xff111111, now),
      _tag('tag-child', 'Child', 0xff222222, now),
      _tag('tag-shared', 'Shared', 0xff333333, now),
      _tag('tag-leaf', 'Leaf', 0xff444444, now),
    ],
    placements: const [
      TagPlacement(
        id: 'place-root',
        spaceId: 'space',
        tagId: 'tag-root',
        parentId: null,
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-child',
        spaceId: 'space',
        tagId: 'tag-child',
        parentId: 'place-root',
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-shared-a',
        spaceId: 'space',
        tagId: 'tag-shared',
        parentId: null,
        sortOrder: 1,
      ),
      TagPlacement(
        id: 'place-shared-b',
        spaceId: 'space',
        tagId: 'tag-shared',
        parentId: 'place-root',
        sortOrder: 1,
      ),
      TagPlacement(
        id: 'place-leaf',
        spaceId: 'space',
        tagId: 'tag-leaf',
        parentId: 'place-shared-a',
        sortOrder: 0,
      ),
    ],
    resources: [
      TagResource(
        id: 'resource-file',
        name: 'file.txt',
        path: r'D:\Library\file.txt',
        kind: ResourceKind.file,
        modifiedAt: now,
      ),
      TagResource(
        id: 'resource-file2',
        name: 'file2.txt',
        path: r'D:\Library\file2.txt',
        kind: ResourceKind.file,
        modifiedAt: now,
      ),
      TagResource(
        id: 'resource-folder',
        name: 'folder',
        path: r'D:\Library\folder',
        kind: ResourceKind.folder,
        modifiedAt: now,
      ),
    ],
    memberships: [
      for (final resourceId in [
        'resource-file',
        'resource-file2',
        'resource-folder',
      ])
        SpaceMembership(
          resourceId: resourceId,
          spaceId: 'space',
          createdAt: now,
        ),
    ],
    assignments: [
      _assignment('assignment-a', 'resource-file', 'place-shared-a', now),
      _assignment('assignment-b', 'resource-file', 'place-shared-b', now),
      _assignment('assignment-c', 'resource-file2', 'place-shared-a', now),
    ],
    folderTagInheritances: [
      FolderTagInheritance(
        id: 'inherit-shared',
        folderResourceId: 'resource-folder',
        tagId: 'tag-shared',
        createdAt: now,
      ),
    ],
    usageEvents: const [],
    activeSpaceId: 'space',
  );
  await store.save(state);
  final controller = TagTagController(store: store);
  await controller.load();
  return _Fixture(controller: controller, store: store, directory: directory);
}

TagDefinition _tag(
  String id,
  String name,
  int colorValue,
  DateTime createdAt,
) => TagDefinition(
  id: id,
  spaceId: 'space',
  name: name,
  colorValue: colorValue,
  createdAt: createdAt,
);

TagAssignment _assignment(
  String id,
  String resourceId,
  String placementId,
  DateTime createdAt,
) => TagAssignment(
  id: id,
  resourceId: resourceId,
  placementId: placementId,
  createdAt: createdAt,
);
