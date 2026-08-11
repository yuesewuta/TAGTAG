import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  test(
    'merge keeps placement assignments and supports persisted undo',
    () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final assignmentsBefore = controller.state.assignments
          .map((assignment) => assignment.toJson())
          .toList();

      final impact = controller.previewTagMerge(
        targetTagId: 'tag-target',
        sourceTagIds: const {'tag-source'},
      );

      expect(impact.placementCount, 1);
      expect(impact.assignmentCount, 2);
      expect(impact.resourceCount, 2);
      expect(impact.inheritanceRuleCount, 1);

      final operation = await controller.mergeTags(
        targetTagId: 'tag-target',
        sourceTagIds: const {'tag-source'},
      );

      expect(
        controller.state.tags.map((tag) => tag.id),
        isNot(contains('tag-source')),
      );
      expect(
        controller.state.placementById('place-source').tagId,
        'tag-target',
      );
      expect(
        controller.state.assignments.map((assignment) => assignment.toJson()),
        assignmentsBefore,
        reason: 'assignments stay attached to their stable placement IDs',
      );
      expect(
        controller.state.folderTagInheritances
            .where((rule) => rule.folderResourceId == 'resource-folder')
            .map((rule) => rule.tagId),
        contains('tag-target'),
        reason: 'source and target inheritance rules are deduplicated on merge',
      );
      expect(
        controller.state.folderTagInheritances.where(
          (rule) =>
              rule.folderResourceId == 'resource-folder' &&
              rule.tagId == 'tag-target',
        ),
        hasLength(1),
      );
      expect(
        controller.state.folderTagInheritances.map((rule) => rule.tagId),
        isNot(contains('tag-source')),
      );

      final reloaded = TagTagController(store: fixture.store);
      await reloaded.load();
      expect(reloaded.tagOperations.single.id, operation.id);
      await reloaded.undoTagOperation(operation.id);

      expect(reloaded.state.tagById('tag-source').name, 'Source');
      expect(reloaded.state.placementById('place-source').tagId, 'tag-source');
      expect(
        reloaded.state.assignments.map((assignment) => assignment.toJson()),
        assignmentsBefore,
      );
      expect(
        reloaded.state.folderTagInheritances
            .where((rule) => rule.folderResourceId == 'resource-folder')
            .map((rule) => rule.tagId)
            .where((tagId) => tagId == 'tag-source' || tagId == 'tag-target')
            .toSet(),
        {'tag-source', 'tag-target'},
      );
      expect(reloaded.tagOperations.single.undoneAt, isNotNull);
    },
  );

  test(
    'split creates an independent entity and duplicates shared inheritance',
    () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final assignmentsBefore = controller.state.assignments
          .map((assignment) => assignment.toJson())
          .toList();

      final impact = controller.previewTagSplit(const {'place-unique-one'});
      expect(impact.placementCount, 1);
      expect(impact.assignmentCount, 2);
      expect(impact.resourceCount, 2);
      expect(impact.inheritanceRuleCount, 1);

      final operation = await controller.splitTagPlacements(
        placementIds: const {'place-unique-one'},
        newName: 'Split copy',
      );
      final newTagId = controller.state.placementById('place-unique-one').tagId;

      expect(newTagId, isNot('tag-unique'));
      expect(controller.state.tagById(newTagId).name, 'Split copy');
      expect(
        controller.state.placementById('place-unique-two').tagId,
        'tag-unique',
      );
      expect(
        controller.state.assignments.map((assignment) => assignment.toJson()),
        assignmentsBefore,
      );
      expect(
        controller.state.folderTagInheritances
            .where((rule) => rule.folderResourceId == 'resource-folder')
            .map((rule) => rule.tagId)
            .toSet(),
        containsAll({'tag-unique', newTagId}),
      );
      expect(
        controller
            .effectiveTagsForResource('resource-child')
            .map((effective) => effective.tag.id)
            .toSet(),
        containsAll({'tag-unique', newTagId}),
      );

      await controller.undoTagOperation(operation.id);
      expect(
        controller.state.placementById('place-unique-one').tagId,
        'tag-unique',
      );
      expect(
        controller.state.tags.map((tag) => tag.id),
        isNot(contains(newTagId)),
      );
      expect(
        controller.state.folderTagInheritances
            .where((rule) => rule.folderResourceId == 'resource-folder')
            .map((rule) => rule.tagId)
            .where((tagId) => tagId == 'tag-unique'),
        hasLength(1),
      );
    },
  );

  test('tag operations must be undone from newest to oldest', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final merge = await fixture.controller.mergeTags(
      targetTagId: 'tag-target',
      sourceTagIds: const {'tag-source'},
    );
    final split = await fixture.controller.splitTagPlacements(
      placementIds: const {'place-unique-one'},
    );

    await expectLater(
      fixture.controller.undoTagOperation(merge.id),
      throwsA(isA<StateError>()),
    );
    await fixture.controller.undoTagOperation(split.id);
    await fixture.controller.undoTagOperation(merge.id);
  });
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
  final directory = await Directory.systemTemp.createTemp('tagtag-identity-');
  final store = LocalStore(baseDirectory: directory);
  final now = DateTime.utc(2026, 1, 1);
  final state = AppState(
    spaces: [TagSpace(id: 'space', name: 'Space', createdAt: now)],
    tags: [
      _tag('tag-group', 'Group', now),
      _tag('tag-target', 'Target', now),
      _tag('tag-source', 'Source', now),
      _tag('tag-branch-one', 'Branch one', now),
      _tag('tag-branch-two', 'Branch two', now),
      _tag('tag-unique', 'Unique', now),
    ],
    placements: const [
      TagPlacement(
        id: 'place-group',
        spaceId: 'space',
        tagId: 'tag-group',
        parentId: null,
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-target',
        spaceId: 'space',
        tagId: 'tag-target',
        parentId: null,
        sortOrder: 1,
      ),
      TagPlacement(
        id: 'place-source',
        spaceId: 'space',
        tagId: 'tag-source',
        parentId: 'place-group',
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-branch-one',
        spaceId: 'space',
        tagId: 'tag-branch-one',
        parentId: null,
        sortOrder: 2,
      ),
      TagPlacement(
        id: 'place-branch-two',
        spaceId: 'space',
        tagId: 'tag-branch-two',
        parentId: null,
        sortOrder: 3,
      ),
      TagPlacement(
        id: 'place-unique-one',
        spaceId: 'space',
        tagId: 'tag-unique',
        parentId: 'place-branch-one',
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-unique-two',
        spaceId: 'space',
        tagId: 'tag-unique',
        parentId: 'place-branch-two',
        sortOrder: 0,
      ),
    ],
    resources: [
      TagResource(
        id: 'resource-folder',
        name: 'folder',
        path: r'D:\Library\folder',
        kind: ResourceKind.folder,
        modifiedAt: now,
      ),
      TagResource(
        id: 'resource-child',
        name: 'child.txt',
        path: r'D:\Library\folder\child.txt',
        kind: ResourceKind.file,
        modifiedAt: now,
      ),
      TagResource(
        id: 'resource-source',
        name: 'source.txt',
        path: r'D:\Library\source.txt',
        kind: ResourceKind.file,
        modifiedAt: now,
      ),
      TagResource(
        id: 'resource-split',
        name: 'split.txt',
        path: r'D:\Library\split.txt',
        kind: ResourceKind.file,
        modifiedAt: now,
      ),
    ],
    memberships: [
      for (final resourceId in [
        'resource-folder',
        'resource-child',
        'resource-source',
        'resource-split',
      ])
        SpaceMembership(
          resourceId: resourceId,
          spaceId: 'space',
          createdAt: now,
        ),
    ],
    assignments: [
      _assignment(
        'assignment-folder-source',
        'resource-folder',
        'place-source',
        now,
      ),
      _assignment(
        'assignment-folder-target',
        'resource-folder',
        'place-target',
        now,
      ),
      _assignment(
        'assignment-folder-unique-one',
        'resource-folder',
        'place-unique-one',
        now,
      ),
      _assignment(
        'assignment-folder-unique-two',
        'resource-folder',
        'place-unique-two',
        now,
      ),
      _assignment(
        'assignment-resource-source',
        'resource-source',
        'place-source',
        now,
      ),
      _assignment(
        'assignment-resource-split',
        'resource-split',
        'place-unique-one',
        now,
      ),
    ],
    folderTagInheritances: [
      FolderTagInheritance(
        id: 'inherit-source',
        folderResourceId: 'resource-folder',
        tagId: 'tag-source',
        createdAt: now,
      ),
      FolderTagInheritance(
        id: 'inherit-target',
        folderResourceId: 'resource-folder',
        tagId: 'tag-target',
        createdAt: now,
      ),
      FolderTagInheritance(
        id: 'inherit-unique',
        folderResourceId: 'resource-folder',
        tagId: 'tag-unique',
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

TagDefinition _tag(String id, String name, DateTime createdAt) => TagDefinition(
  id: id,
  spaceId: 'space',
  name: name,
  colorValue: 0xff2563eb,
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
