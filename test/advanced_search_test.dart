import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  test('legacy resources load without optional search metadata', () {
    final resource = TagResource.fromJson({
      'id': 'resource-legacy',
      'name': 'legacy.txt',
      'path': r'D:\Library\legacy.txt',
      'kind': 'file',
      'modifiedAt': '2026-01-10T12:00:00.000Z',
    });

    expect(resource.sizeBytes, isNull);
    expect(resource.createdAt, isNull);
  });

  test(
    'advanced search composes metadata and stable tag entity filters',
    () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;

      controller.showSearchResources();
      controller.setSearchTerm('shared');
      expect(
        controller.visibleResources.map((resource) => resource.id),
        containsAll(<String>['resource-one', 'resource-two']),
      );

      controller.setSearchTerm('projects');
      controller.setSearchKind(SearchKindFilter.file);
      controller.setSearchSizeRange(minimumBytes: 90, maximumBytes: 110);
      controller.setSearchCreatedRange(
        from: DateTime.utc(2026, 1, 1),
        to: DateTime.utc(2026, 1, 6),
      );
      controller.setSearchModifiedRange(
        from: DateTime.utc(2026, 1, 9),
        to: DateTime.utc(2026, 1, 11),
      );
      controller.setSearchTagCondition('tag-shared-a', SearchTagCondition.and);

      expect(controller.visibleResources.map((resource) => resource.id), [
        'resource-one',
      ]);

      controller.setSearchTerm('');
      controller.setSearchKind(SearchKindFilter.all);
      controller.setSearchSizeRange();
      controller.setSearchCreatedRange();
      controller.setSearchModifiedRange();
      controller.setSearchTagCondition('tag-shared-a', SearchTagCondition.none);
      controller.setSearchTagCondition('tag-shared-b', SearchTagCondition.and);

      expect(
        controller.visibleResources.map((resource) => resource.id),
        ['resource-two'],
        reason: 'independent same-name tags must be filtered by stable tag ID',
      );

      controller.setSearchTagCondition('tag-shared-b', SearchTagCondition.none);
      controller.setSearchTagCondition('tag-shared-a', SearchTagCondition.or);
      controller.setSearchTagCondition('tag-other', SearchTagCondition.or);
      controller.setSearchTagCondition('tag-blocked', SearchTagCondition.not);

      expect(controller.visibleResources.map((resource) => resource.id), [
        'resource-one',
      ]);
    },
  );

  test('global inbox excludes a resource tagged in any space', () async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    controller.showInboxResources();
    expect(controller.visibleResources.map((resource) => resource.id).toSet(), {
      'resource-three',
      'resource-five',
    });

    controller.setInboxScope(InboxScope.global);
    expect(controller.visibleResources.map((resource) => resource.id).toSet(), {
      'resource-three',
      'resource-four',
    });
    expect(
      controller.effectiveTagsForResourceInSpace('resource-five', 'space-b'),
      isNotEmpty,
    );
  });
}

class _Fixture {
  const _Fixture({required this.controller, required this.directory});

  final TagTagController controller;
  final Directory directory;

  Future<void> dispose() => directory.delete(recursive: true);
}

Future<_Fixture> _createFixture() async {
  final directory = await Directory.systemTemp.createTemp('tagtag-search-');
  final now = DateTime.utc(2026, 1, 1);
  final state = AppState(
    spaces: [
      TagSpace(id: 'space-a', name: 'A', createdAt: now),
      TagSpace(id: 'space-b', name: 'B', createdAt: now),
    ],
    tags: [
      TagDefinition(
        id: 'tag-shared-a',
        spaceId: 'space-a',
        name: 'Shared',
        colorValue: 0xff2563eb,
        createdAt: now,
      ),
      TagDefinition(
        id: 'tag-shared-b',
        spaceId: 'space-a',
        name: 'Shared',
        colorValue: 0xffdc2626,
        createdAt: now,
      ),
      TagDefinition(
        id: 'tag-other',
        spaceId: 'space-a',
        name: 'Other',
        colorValue: 0xff0f766e,
        createdAt: now,
      ),
      TagDefinition(
        id: 'tag-blocked',
        spaceId: 'space-a',
        name: 'Blocked',
        colorValue: 0xff7c3aed,
        createdAt: now,
      ),
      TagDefinition(
        id: 'tag-space-b',
        spaceId: 'space-b',
        name: 'Elsewhere',
        colorValue: 0xff0369a1,
        createdAt: now,
      ),
    ],
    placements: const [
      TagPlacement(
        id: 'place-shared-a',
        spaceId: 'space-a',
        tagId: 'tag-shared-a',
        parentId: null,
        sortOrder: 0,
      ),
      TagPlacement(
        id: 'place-shared-b',
        spaceId: 'space-a',
        tagId: 'tag-shared-b',
        parentId: null,
        sortOrder: 1,
      ),
      TagPlacement(
        id: 'place-other',
        spaceId: 'space-a',
        tagId: 'tag-other',
        parentId: null,
        sortOrder: 2,
      ),
      TagPlacement(
        id: 'place-blocked',
        spaceId: 'space-a',
        tagId: 'tag-blocked',
        parentId: null,
        sortOrder: 3,
      ),
      TagPlacement(
        id: 'place-space-b',
        spaceId: 'space-b',
        tagId: 'tag-space-b',
        parentId: null,
        sortOrder: 0,
      ),
    ],
    resources: [
      TagResource(
        id: 'resource-one',
        name: 'plan.txt',
        path: r'D:\Library\projects\plan.txt',
        kind: ResourceKind.file,
        sizeBytes: 100,
        createdAt: DateTime.utc(2026, 1, 5),
        modifiedAt: DateTime.utc(2026, 1, 10),
      ),
      TagResource(
        id: 'resource-two',
        name: 'Shared folder',
        path: r'D:\Library\shared',
        kind: ResourceKind.folder,
        createdAt: DateTime.utc(2026, 1, 7),
        modifiedAt: DateTime.utc(2026, 1, 12),
      ),
      TagResource(
        id: 'resource-three',
        name: 'inbox.txt',
        path: r'D:\Library\inbox.txt',
        kind: ResourceKind.file,
        sizeBytes: 20,
        createdAt: DateTime.utc(2026, 1, 8),
        modifiedAt: DateTime.utc(2026, 1, 13),
      ),
      TagResource(
        id: 'resource-four',
        name: 'global.txt',
        path: r'D:\Library\global.txt',
        kind: ResourceKind.file,
        sizeBytes: 30,
        createdAt: DateTime.utc(2026, 1, 9),
        modifiedAt: DateTime.utc(2026, 1, 14),
      ),
      TagResource(
        id: 'resource-five',
        name: 'current-space-inbox.txt',
        path: r'D:\Library\current-space-inbox.txt',
        kind: ResourceKind.file,
        sizeBytes: 40,
        createdAt: DateTime.utc(2026, 1, 10),
        modifiedAt: DateTime.utc(2026, 1, 15),
      ),
    ],
    memberships: [
      for (final resourceId in [
        'resource-one',
        'resource-two',
        'resource-three',
      ])
        SpaceMembership(
          resourceId: resourceId,
          spaceId: 'space-a',
          createdAt: now,
        ),
      SpaceMembership(
        resourceId: 'resource-five',
        spaceId: 'space-a',
        createdAt: now,
      ),
      for (final resourceId in ['resource-four', 'resource-five'])
        SpaceMembership(
          resourceId: resourceId,
          spaceId: 'space-b',
          createdAt: now,
        ),
    ],
    assignments: [
      TagAssignment(
        id: 'assignment-one',
        resourceId: 'resource-one',
        placementId: 'place-shared-a',
        createdAt: now,
      ),
      TagAssignment(
        id: 'assignment-two',
        resourceId: 'resource-two',
        placementId: 'place-shared-b',
        createdAt: now,
      ),
      TagAssignment(
        id: 'assignment-space-b',
        resourceId: 'resource-five',
        placementId: 'place-space-b',
        createdAt: now,
      ),
    ],
    folderTagInheritances: const [],
    usageEvents: const [],
    activeSpaceId: 'space-a',
  );
  final store = LocalStore(baseDirectory: directory);
  await store.save(state);
  final controller = TagTagController(store: store);
  await controller.load();
  return _Fixture(controller: controller, directory: directory);
}
