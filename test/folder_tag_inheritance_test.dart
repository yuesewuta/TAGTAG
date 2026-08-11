import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  test('legacy tag state loads with inheritance disabled', () {
    final legacy = AppState.demo().toJson()
      ..['version'] = 2
      ..remove('folderTagInheritances');

    final restored = AppState.fromJson(legacy);

    expect(restored.folderTagInheritances, isEmpty);
  });

  test(
    'an inheritance rule without its source direct tag has no effect',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-dangling-inheritance-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(baseDirectory: directory);
      await store.save(
        AppState.demo().copyWith(
          folderTagInheritances: [
            FolderTagInheritance(
              id: 'inheritance-dangling',
              folderResourceId: 'resource-folder',
              tagId: 'tag-personal',
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
      final controller = TagTagController(store: store);
      await controller.load();

      expect(
        controller
            .effectiveTagsForResource('resource-architecture')
            .map((effective) => effective.tag.id),
        isNot(contains('tag-personal')),
      );
    },
  );

  test(
    'folder inheritance is persisted and follows the current resource path',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-folder-inheritance-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(baseDirectory: directory);
      await store.save(AppState.demo());
      final controller = TagTagController(store: store);
      await controller.load();

      controller.selectResource('resource-folder');
      await controller.assignPlacementToSelection(
        'place-personal',
        inheritChildren: true,
      );

      final childDirectTagIds = controller
          .assignmentsForResource('resource-architecture')
          .map((placement) => placement.tagId);
      final inherited = controller
          .effectiveTagsForResource('resource-architecture')
          .singleWhere((effective) => effective.tag.id == 'tag-personal');
      expect(childDirectTagIds, isNot(contains('tag-personal')));
      expect(inherited.isDirect, isFalse);
      expect(inherited.inheritedSources.map((source) => source.id), [
        'resource-folder',
      ]);

      final restarted = TagTagController(store: store);
      await restarted.load();
      expect(
        restarted.folderInheritsTag('resource-folder', 'tag-personal'),
        isTrue,
      );

      await store.save(
        restarted.state.copyWith(
          resources: restarted.state.resources
              .map(
                (resource) => resource.id == 'resource-architecture'
                    ? _withPath(resource, r'D:\Outside\architecture.md')
                    : resource,
              )
              .toList(),
        ),
      );
      final movedOutside = TagTagController(store: store);
      await movedOutside.load();
      expect(
        movedOutside
            .effectiveTagsForResource('resource-architecture')
            .map((effective) => effective.tag.id),
        isNot(contains('tag-personal')),
      );

      final sourceFolder = movedOutside.state.resources.singleWhere(
        (resource) => resource.id == 'resource-folder',
      );
      final futureChild = TagResource(
        id: 'resource-future-child',
        name: 'future.txt',
        path: path.join(sourceFolder.path, 'future.txt'),
        kind: ResourceKind.file,
        modifiedAt: DateTime.now(),
      );
      await store.save(
        movedOutside.state.copyWith(
          resources: [...movedOutside.state.resources, futureChild],
          memberships: [
            ...movedOutside.state.memberships,
            SpaceMembership(
              resourceId: futureChild.id,
              spaceId: movedOutside.activeSpaceId!,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
      final movedInside = TagTagController(store: store);
      await movedInside.load();
      expect(
        movedInside
            .effectiveTagsForResource(futureChild.id)
            .map((effective) => effective.tag.id),
        contains('tag-personal'),
      );
    },
  );

  test(
    'inbox uses effective tags and clearing the source removes its rule',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-effective-inbox-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(baseDirectory: directory);
      final initial = AppState.demo();
      final folder = initial.resources.singleWhere(
        (resource) => resource.id == 'resource-folder',
      );
      final child = TagResource(
        id: 'resource-untagged-child',
        name: 'untagged.txt',
        path: path.join(folder.path, 'nested', 'untagged.txt'),
        kind: ResourceKind.file,
        modifiedAt: DateTime.now(),
      );
      await store.save(
        initial.copyWith(
          resources: [...initial.resources, child],
          memberships: [
            ...initial.memberships,
            SpaceMembership(
              resourceId: child.id,
              spaceId: initial.activeSpaceId!,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
      final controller = TagTagController(store: store);
      await controller.load();

      controller.selectResource(folder.id);
      await controller.assignPlacementToSelection(
        'place-project',
        inheritChildren: true,
      );
      controller.showInboxResources();

      expect(controller.assignmentsForResource(child.id), isEmpty);
      expect(
        controller.visibleResources.map((resource) => resource.id),
        isNot(contains(child.id)),
      );
      expect(
        controller
            .resourcesForPlacement(
              controller.state.placementById('place-project'),
            )
            .map((resource) => resource.id),
        contains(child.id),
      );

      controller.selectResource(folder.id);
      await controller.clearSelectedTags();
      expect(controller.state.folderTagInheritances, isEmpty);
      controller.showInboxResources();
      expect(
        controller.visibleResources.map((resource) => resource.id),
        contains(child.id),
      );
    },
  );
}

TagResource _withPath(TagResource resource, String nextPath) => TagResource(
  id: resource.id,
  name: resource.name,
  path: nextPath,
  kind: resource.kind,
  modifiedAt: resource.modifiedAt,
);
