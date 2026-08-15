import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  group('saved queries', () {
    test('saveCurrentSearch rejects empty name and empty condition', () async {
      final fixture = await _storeWith(AppState.demo());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      controller.clearSearchFilters();
      controller.setSearchTerm('');
      expect(() => controller.saveCurrentSearch('  名称  '), throwsStateError);

      controller.setSearchTerm('架构');
      expect(() => controller.saveCurrentSearch('   '), throwsArgumentError);
    });

    test('save captures the full condition and survives a reload', () async {
      final fixture = await _storeWith(AppState.demo());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      controller.setSearchTerm('架构');
      controller.setSearchKind(SearchKindFilter.file);
      controller.setSearchSizeRange(minimumBytes: 10, maximumBytes: 2048);
      controller.setSearchCreatedRange(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 2, 1),
      );
      controller.setSearchModifiedRange(from: DateTime(2026, 3, 1));
      controller.setSearchTagCondition('tag-design', SearchTagCondition.and);
      controller.setSearchTagCondition('tag-project', SearchTagCondition.or);
      controller.setSearchTagCondition('tag-personal', SearchTagCondition.not);
      controller.setIncludeDescendants(false);

      final saved = await controller.saveCurrentSearch('  我的查询  ');
      expect(saved.name, '我的查询');
      expect(saved.spaceId, controller.activeSpaceId);
      expect(saved.term, '架构');
      expect(saved.kind, SearchKindFilter.file);
      expect(saved.minimumSizeBytes, 10);
      expect(saved.maximumSizeBytes, 2048);
      expect(saved.createdFrom, DateTime(2026, 1, 1));
      expect(saved.createdTo, DateTime(2026, 2, 1));
      expect(saved.modifiedFrom, DateTime(2026, 3, 1));
      expect(saved.modifiedTo, isNull);
      expect(saved.andTagIds, {'tag-design'});
      expect(saved.orTagIds, {'tag-project'});
      expect(saved.notTagIds, {'tag-personal'});
      expect(saved.includeDescendants, isFalse);
      expect(controller.savedQueriesInActiveSpace, hasLength(1));

      final reloaded = await _loadController(fixture);
      expect(reloaded.savedQueriesInActiveSpace, hasLength(1));
      expect(reloaded.savedQueriesInActiveSpace.single.id, saved.id);
      expect(reloaded.savedQueriesInActiveSpace.single.term, '架构');
    });

    test(
      'applySavedQuery replaces the condition and opens the search view',
      () async {
        final fixture = await _storeWith(AppState.demo());
        addTearDown(() => fixture.delete(recursive: true));
        final controller = await _loadController(fixture);

        controller.setSearchTerm('架构');
        controller.setSearchTagCondition('tag-design', SearchTagCondition.and);
        controller.setSearchSizeRange(minimumBytes: 64);
        final saved = await controller.saveCurrentSearch('组合条件');

        controller.showAllResources();
        controller.clearSearchFilters();
        expect(controller.hasAdvancedSearchFilters, isFalse);
        expect(controller.searchTerm, isEmpty);

        await controller.applySavedQuery(saved.id);
        expect(controller.activeView, ResourceView.search);
        expect(controller.searchTerm, '架构');
        expect(controller.searchMinimumSizeBytes, 64);
        expect(
          controller.searchConditionForTag('tag-design'),
          SearchTagCondition.and,
        );
        expect(
          controller.searchConditionForTag('tag-project'),
          SearchTagCondition.none,
        );

        // Applying twice keeps working after further edits.
        controller.setSearchTerm('其他');
        await controller.applySavedQuery(saved.id);
        expect(controller.searchTerm, '架构');
      },
    );

    test(
      'saved queries are scoped to the active space and allow duplicate names',
      () async {
        final fixture = await _storeWith(AppState.demo());
        addTearDown(() => fixture.delete(recursive: true));
        final controller = await _loadController(fixture);

        controller.setSearchTerm('一');
        final first = await controller.saveCurrentSearch('同名');
        controller.setSearchTerm('二');
        final second = await controller.saveCurrentSearch('同名');
        expect(first.id, isNot(second.id));
        expect(controller.savedQueriesInActiveSpace, hasLength(2));

        await controller.createSpace('团队空间');
        expect(controller.savedQueriesInActiveSpace, isEmpty);
        controller.setSearchTerm('三');
        await controller.saveCurrentSearch('另一空间');
        expect(controller.savedQueriesInActiveSpace.single.term, '三');
      },
    );

    test('deleteSavedQuery removes the entry and persists', () async {
      final fixture = await _storeWith(AppState.demo());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      controller.setSearchTerm('临时');
      final saved = await controller.saveCurrentSearch('临时查询');
      await controller.deleteSavedQuery(saved.id);
      expect(controller.savedQueriesInActiveSpace, isEmpty);

      final reloaded = await _loadController(fixture);
      expect(reloaded.savedQueriesInActiveSpace, isEmpty);
    });

    test('state JSON without the new keys loads with empty defaults', () {
      final json = AppState.demo().toJson()
        ..remove('savedQueries')
        ..remove('pinnedPlacementIds')
        ..remove('hiddenPlacementIds');
      final restored = AppState.fromJson(json);
      expect(restored.savedQueries, isEmpty);
      expect(restored.pinnedPlacementIds, isEmpty);
      expect(restored.hiddenPlacementIds, isEmpty);
    });
  });

  group('pin and hide frequent tags', () {
    test(
      'commonPlacements puts pinned first by count, excludes hidden, caps at five',
      () async {
        final fixture = await _storeWith(_usageState());
        addTearDown(() => fixture.delete(recursive: true));
        final controller = await _loadController(fixture);

        // Raw order by count: p6(6) p5(5) p4(4) p3(3) p2(2), p1(1) cut off.
        expect(controller.commonPlacements.map((p) => p.id).toList(), [
          'p6',
          'p5',
          'p4',
          'p3',
          'p2',
        ]);

        await controller.togglePlacementPinned('p1'); // count 1, pinned
        await controller.togglePlacementPinned('p3'); // count 3, pinned
        await controller.togglePlacementHidden('p6'); // highest count, hidden

        // Pinned first by count (p3 before p1), then unpinned by count,
        // hidden p6 excluded, total capped at five.
        expect(controller.commonPlacements.map((p) => p.id).toList(), [
          'p3',
          'p1',
          'p5',
          'p4',
          'p2',
        ]);

        final reloaded = await _loadController(fixture);
        expect(reloaded.commonPlacements.map((p) => p.id).toList(), [
          'p3',
          'p1',
          'p5',
          'p4',
          'p2',
        ]);
      },
    );

    test('hiding a pinned placement keeps the pin for later unhide', () async {
      final fixture = await _storeWith(_usageState());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      await controller.togglePlacementPinned('p2');
      await controller.togglePlacementHidden('p2');
      expect(controller.isPlacementPinned('p2'), isTrue);
      expect(controller.isPlacementHidden('p2'), isTrue);
      expect(controller.commonPlacements.any((p) => p.id == 'p2'), isFalse);

      await controller.togglePlacementHidden('p2');
      expect(controller.isPlacementHidden('p2'), isFalse);
      expect(controller.commonPlacements.first.id, 'p2');

      await controller.togglePlacementPinned('p2');
      expect(controller.isPlacementPinned('p2'), isFalse);
    });

    test('toggles reject placements outside the active space', () async {
      final fixture = await _storeWith(_usageState());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      expect(
        () => controller.togglePlacementPinned('other-space-placement'),
        throwsStateError,
      );
    });
  });

  group('usage history cleanup', () {
    test('clearUsageHistory removes only the active space events', () async {
      final fixture = await _storeWith(_usageState());
      addTearDown(() => fixture.delete(recursive: true));
      final controller = await _loadController(fixture);

      expect(controller.state.usageEvents, hasLength(22));
      await controller.clearUsageHistory();
      expect(controller.commonPlacements, isEmpty);
      expect(
        controller.state.usageEvents.where((e) => e.spaceId == 'space-a'),
        isEmpty,
      );
      expect(
        controller.state.usageEvents.where((e) => e.spaceId == 'space-b'),
        hasLength(1),
      );

      final reloaded = await _loadController(fixture);
      expect(reloaded.state.usageEvents, hasLength(1));
    });
  });
}

Future<Directory> _storeWith(AppState state) async {
  final directory = await Directory.systemTemp.createTemp('tagtag-savedq-');
  final store = LocalStore(baseDirectory: directory);
  await store.save(state);
  return directory;
}

Future<TagTagController> _loadController(Directory directory) async {
  final controller = TagTagController(
    store: LocalStore(baseDirectory: directory),
  );
  await controller.load();
  return controller;
}

/// Six placements in space-a with usage counts 1..6 (p1..p6), plus one
/// event in another space that must never leak into space-a lists.
AppState _usageState() {
  final now = DateTime(2026, 8, 1);
  TagPlacement placement(String id, int order) => TagPlacement(
    id: id,
    spaceId: 'space-a',
    tagId: 'tag-$id',
    parentId: null,
    sortOrder: order,
  );
  return AppState(
    spaces: [
      TagSpace(id: 'space-a', name: '设计空间', createdAt: now),
      TagSpace(id: 'space-b', name: '团队空间', createdAt: now),
    ],
    tags: [
      for (var i = 1; i <= 6; i++)
        TagDefinition(
          id: 'tag-p$i',
          spaceId: 'space-a',
          name: '标签$i',
          colorValue: 0xff2563eb,
          createdAt: now,
        ),
      TagDefinition(
        id: 'tag-other',
        spaceId: 'space-b',
        name: '外部',
        colorValue: 0xff2563eb,
        createdAt: now,
      ),
    ],
    placements: [
      for (var i = 1; i <= 6; i++) placement('p$i', i),
      const TagPlacement(
        id: 'other-space-placement',
        spaceId: 'space-b',
        tagId: 'tag-other',
        parentId: null,
        sortOrder: 0,
      ),
    ],
    resources: const [],
    memberships: const [],
    assignments: const [],
    folderTagInheritances: const [],
    activeSpaceId: 'space-a',
    usageEvents: [
      for (var i = 1; i <= 6; i++)
        for (var n = 0; n < i; n++)
          UsageEvent(
            id: 'usage-p$i-$n',
            spaceId: 'space-a',
            resourceId: null,
            placementId: 'p$i',
            type: UsageEventType.tagged,
            occurredAt: now,
          ),
      UsageEvent(
        id: 'usage-other',
        spaceId: 'space-b',
        resourceId: null,
        placementId: 'other-space-placement',
        type: UsageEventType.tagged,
        occurredAt: now,
      ),
    ],
  );
}
