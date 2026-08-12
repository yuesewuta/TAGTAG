import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../data/local_store.dart';
import '../models/tag_models.dart';
import '../services/space_portability.dart';
import '../storage/managed_library.dart';

enum ResourceView { all, hierarchy, inbox, recent, search }

enum SearchKindFilter { all, file, folder }

enum SearchTagCondition { none, and, or, not }

enum InboxScope { currentSpace, global }

class EffectiveTagView {
  const EffectiveTagView({
    required this.tag,
    required this.directPlacements,
    required this.inheritedSources,
  });

  final TagDefinition tag;
  final List<TagPlacement> directPlacements;
  final List<TagResource> inheritedSources;

  bool get isDirect => directPlacements.isNotEmpty;
  bool get isInherited => inheritedSources.isNotEmpty;
}

class TagIdentityImpact {
  const TagIdentityImpact({
    required this.type,
    required this.sourceTags,
    required this.targetTag,
    required this.placementCount,
    required this.assignmentCount,
    required this.resourceCount,
    required this.inheritanceRuleCount,
  });

  final TagDomainOperationType type;
  final List<TagDefinition> sourceTags;
  final TagDefinition? targetTag;
  final int placementCount;
  final int assignmentCount;
  final int resourceCount;
  final int inheritanceRuleCount;
}

class TagTagController extends ChangeNotifier {
  TagTagController({required this.store, this.library, this.recycleBin});

  final LocalStore store;
  final ManagedLibrary? library;
  final RecycleBinGateway? recycleBin;
  AppState _state = AppState.empty();
  UserPreferences _preferences = const UserPreferences();
  final Set<String> selectedResourceIds = <String>{};

  String? activePlacementId;
  String searchTerm = '';
  SearchKindFilter searchKind = SearchKindFilter.all;
  int? searchMinimumSizeBytes;
  int? searchMaximumSizeBytes;
  DateTime? searchCreatedFrom;
  DateTime? searchCreatedTo;
  DateTime? searchModifiedFrom;
  DateTime? searchModifiedTo;
  final Set<String> searchAndTagIds = <String>{};
  final Set<String> searchOrTagIds = <String>{};
  final Set<String> searchNotTagIds = <String>{};
  InboxScope inboxScope = InboxScope.currentSpace;
  bool includeDescendants = true;
  ResourceView activeView = ResourceView.all;

  AppState get state => _state;
  UserPreferences get preferences => _preferences;
  bool get showRecent => activeView == ResourceView.recent;
  bool get showInbox => activeView == ResourceView.inbox;
  bool get hasAdvancedSearchFilters =>
      searchKind != SearchKindFilter.all ||
      searchMinimumSizeBytes != null ||
      searchMaximumSizeBytes != null ||
      searchCreatedFrom != null ||
      searchCreatedTo != null ||
      searchModifiedFrom != null ||
      searchModifiedTo != null ||
      searchAndTagIds.isNotEmpty ||
      searchOrTagIds.isNotEmpty ||
      searchNotTagIds.isNotEmpty;
  Directory? get storageRoot => library?.root;
  String? get activeSpaceId => _state.activeSpaceId;
  TagSpace? get activeSpace {
    final id = activeSpaceId;
    if (id == null) {
      return null;
    }
    final matches = _state.spaces.where((space) => space.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  int visibleResourceCountForSpace(String? spaceId) {
    if (spaceId == null) return 0;
    return _state.resourceIdsForSpace(spaceId).length;
  }

  int inboxCountForSpace(String? spaceId) {
    if (spaceId == null) return 0;
    return _state
        .resourceIdsForSpace(spaceId)
        .where(
          (resourceId) =>
              effectiveTagsForResourceInSpace(resourceId, spaceId).isEmpty,
        )
        .length;
  }

  List<TagDomainOperation> get tagOperations {
    final operations = _state.tagOperations.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return operations;
  }

  Future<void> load() async {
    final managedLibrary = library;
    final storedMetadata = await managedLibrary?.readTagDomainMetadata();
    if (storedMetadata == null) {
      _preferences = await store.loadPreferences();
      _state = await store.load();
      if (managedLibrary != null) {
        await _persistTagDomainMetadata();
      }
    } else {
      _preferences = _preferencesFromJson(storedMetadata.preferencesJson);
      _state = _stateFromJson(storedMetadata.tagStateJson);
    }
    if (_state.activeSpaceId == null && _state.spaces.isNotEmpty) {
      _state = _state.copyWith(activeSpaceId: _state.spaces.first.id);
    }
    activeView = switch (_preferences.startupView) {
      'inbox' => ResourceView.inbox,
      _ => ResourceView.all,
    };
    await _syncManagedResources();
    notifyListeners();
  }

  Future<void> updatePreferences({
    bool? moveImportsByDefault,
    bool? floatingDropTargetEnabled,
    bool? closeToTray,
    String? startupView,
    String? appearanceTheme,
    String? interfaceDensity,
    String? quickTagShortcut,
  }) async {
    _preferences = _preferences.copyWith(
      moveImportsByDefault: moveImportsByDefault,
      floatingDropTargetEnabled: floatingDropTargetEnabled,
      closeToTray: closeToTray,
      startupView: startupView,
      appearanceTheme: appearanceTheme,
      interfaceDensity: interfaceDensity,
      quickTagShortcut: quickTagShortcut,
    );
    notifyListeners();
    await _persistTagDomainMetadata();
  }

  List<TagPlacement> get rootPlacements {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    return _state.childrenOf(null, spaceId);
  }

  List<TagPlacement> childrenOf(String placementId) {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    return _state.childrenOf(placementId, spaceId);
  }

  TagDefinition tagForPlacement(TagPlacement placement) =>
      _state.tagById(placement.tagId);

  String pathOf(String placementId) => _state.pathOf(placementId);

  List<TagPlacement> get placementsInActiveSpace {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    return _state.placementsForSpace(spaceId);
  }

  List<TagSpace> spacesForResource(String resourceId) {
    final spaceIds = _state.memberships
        .where((membership) => membership.resourceId == resourceId)
        .map((membership) => membership.spaceId)
        .toSet();
    return _state.spaces
        .where((space) => spaceIds.contains(space.id))
        .toList();
  }

  List<TagResource> get visibleResources {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    final query = activeView == ResourceView.search
        ? searchTerm.trim().toLowerCase()
        : '';
    final matchingIds = _matchingResourceIds();
    final memberResourceIds = _state.resourceIdsForSpace(spaceId);
    final resourceScopeIds =
        activeView == ResourceView.inbox && inboxScope == InboxScope.global
        ? _state.resources.map((resource) => resource.id).toSet()
        : memberResourceIds;
    final resources = _state.resources
        .where((resource) => resourceScopeIds.contains(resource.id))
        .where(
          (resource) =>
              matchingIds == null || matchingIds.contains(resource.id),
        )
        .where(
          (resource) =>
              query.isEmpty ||
              resource.name.toLowerCase().contains(query) ||
              resource.path.toLowerCase().contains(query) ||
              effectiveTagsForResourceInSpace(resource.id, spaceId).any(
                (effective) => effective.tag.name.toLowerCase().contains(query),
              ),
        )
        .where(
          (resource) =>
              activeView != ResourceView.search ||
              _matchesAdvancedSearch(resource, spaceId),
        )
        .toList();
    resources.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return resources;
  }

  List<TagResource> get recentResources {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    final resourceById = {
      for (final resource in _state.resources) resource.id: resource,
    };
    final seen = <String>{};
    final result = <TagResource>[];
    final events =
        _state.usageEvents
            .where(
              (event) => event.spaceId == spaceId && event.resourceId != null,
            )
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    for (final event in events) {
      final id = event.resourceId!;
      if (seen.add(id) && resourceById[id] != null) {
        result.add(resourceById[id]!);
      }
    }
    return result;
  }

  List<TagPlacement> get commonPlacements {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    final counts = <String, int>{};
    for (final event in _state.usageEvents) {
      if (event.spaceId == spaceId && event.placementId != null) {
        counts.update(
          event.placementId!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final placements =
        placementsInActiveSpace
            .where((placement) => counts.containsKey(placement.id))
            .toList()
          ..sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    return placements.take(5).toList();
  }

  List<TagPlacement> assignmentsForResource(String resourceId) {
    final ids = _state.assignments
        .where((assignment) => assignment.resourceId == resourceId)
        .map((assignment) => assignment.placementId)
        .toSet();
    return placementsInActiveSpace
        .where((placement) => ids.contains(placement.id))
        .toList();
  }

  List<EffectiveTagView> effectiveTagsForResource(String resourceId) {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    return effectiveTagsForResourceInSpace(resourceId, spaceId);
  }

  List<EffectiveTagView> effectiveTagsForResourceInSpace(
    String resourceId,
    String spaceId,
  ) {
    final resourceMatches = _state.resources.where(
      (resource) => resource.id == resourceId,
    );
    if (resourceMatches.isEmpty) {
      return const [];
    }
    final resource = resourceMatches.single;
    final memberResourceIds = _state.resourceIdsForSpace(spaceId);
    if (!memberResourceIds.contains(resourceId)) {
      return const [];
    }
    final placementsById = {
      for (final placement in _state.placementsForSpace(spaceId))
        placement.id: placement,
    };
    final tagsById = {
      for (final tag in _state.tags)
        if (tag.spaceId == spaceId) tag.id: tag,
    };
    final directByTagId = <String, List<TagPlacement>>{};
    for (final assignment in _state.assignments) {
      if (assignment.resourceId != resourceId) {
        continue;
      }
      final placement = placementsById[assignment.placementId];
      if (placement != null) {
        directByTagId.putIfAbsent(placement.tagId, () => []).add(placement);
      }
    }
    final directTagKeys = <String>{
      for (final assignment in _state.assignments)
        if (placementsById[assignment.placementId] case final placement?)
          '${assignment.resourceId}|${placement.tagId}',
    };
    final resourcesById = {for (final item in _state.resources) item.id: item};
    final inheritedByTagId = <String, List<TagResource>>{};
    for (final rule in _state.folderTagInheritances) {
      if (!tagsById.containsKey(rule.tagId) ||
          !memberResourceIds.contains(rule.folderResourceId) ||
          !directTagKeys.contains('${rule.folderResourceId}|${rule.tagId}')) {
        continue;
      }
      final source = resourcesById[rule.folderResourceId];
      if (source == null ||
          source.kind != ResourceKind.folder ||
          path.equals(source.path, resource.path) ||
          !path.isWithin(source.path, resource.path)) {
        continue;
      }
      inheritedByTagId.putIfAbsent(rule.tagId, () => []).add(source);
    }
    final tagIds = {...directByTagId.keys, ...inheritedByTagId.keys};
    final result = [
      for (final tagId in tagIds)
        if (tagsById[tagId] case final tag?)
          EffectiveTagView(
            tag: tag,
            directPlacements: directByTagId[tagId] ?? const [],
            inheritedSources: inheritedByTagId[tagId] ?? const [],
          ),
    ];
    result.sort(
      (first, second) =>
          first.tag.name.toLowerCase().compareTo(second.tag.name.toLowerCase()),
    );
    return result;
  }

  TagResource? get selectedFolderForInheritance {
    if (selectedResourceIds.length != 1) {
      return null;
    }
    final resourceId = selectedResourceIds.single;
    final matches = _state.resources.where(
      (resource) =>
          resource.id == resourceId && resource.kind == ResourceKind.folder,
    );
    return matches.isEmpty ? null : matches.single;
  }

  bool folderInheritsTag(String folderResourceId, String tagId) =>
      _state.folderTagInheritances.any(
        (rule) =>
            rule.folderResourceId == folderResourceId && rule.tagId == tagId,
      );

  List<TagResource> resourcesForPlacement(TagPlacement placement) {
    final spaceId = activeSpaceId;
    if (spaceId == null || placement.spaceId != spaceId) {
      return const [];
    }
    final memberResourceIds = _state.resourceIdsForSpace(spaceId);
    final resources = _state.resources
        .where((resource) => memberResourceIds.contains(resource.id))
        .where(
          (resource) => effectiveTagsForResource(
            resource.id,
          ).any((effective) => effective.tag.id == placement.tagId),
        )
        .toList();
    resources.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return resources;
  }

  Future<void> selectSpace(String spaceId) async {
    activePlacementId = null;
    selectedResourceIds.clear();
    activeView = ResourceView.all;
    await _update(_state.copyWith(activeSpaceId: spaceId));
  }

  void selectPlacement(String? placementId) {
    activePlacementId = placementId;
    activeView = placementId == null
        ? ResourceView.all
        : ResourceView.hierarchy;
    notifyListeners();
  }

  void showAllResources() {
    activePlacementId = null;
    activeView = ResourceView.all;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void showTagHierarchy() {
    activeView = ResourceView.hierarchy;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void showRecentResources() {
    activePlacementId = null;
    activeView = ResourceView.recent;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void showInboxResources() {
    activePlacementId = null;
    activeView = ResourceView.inbox;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void showSearchResources() {
    activePlacementId = null;
    activeView = ResourceView.search;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void setSearchTerm(String value) {
    searchTerm = value;
    notifyListeners();
  }

  void setSearchKind(SearchKindFilter value) {
    searchKind = value;
    notifyListeners();
  }

  void setSearchSizeRange({int? minimumBytes, int? maximumBytes}) {
    searchMinimumSizeBytes = minimumBytes;
    searchMaximumSizeBytes = maximumBytes;
    notifyListeners();
  }

  void setSearchCreatedRange({DateTime? from, DateTime? to}) {
    searchCreatedFrom = from;
    searchCreatedTo = to;
    notifyListeners();
  }

  void setSearchModifiedRange({DateTime? from, DateTime? to}) {
    searchModifiedFrom = from;
    searchModifiedTo = to;
    notifyListeners();
  }

  SearchTagCondition searchConditionForTag(String tagId) {
    if (searchAndTagIds.contains(tagId)) {
      return SearchTagCondition.and;
    }
    if (searchOrTagIds.contains(tagId)) {
      return SearchTagCondition.or;
    }
    if (searchNotTagIds.contains(tagId)) {
      return SearchTagCondition.not;
    }
    return SearchTagCondition.none;
  }

  void setSearchTagCondition(String tagId, SearchTagCondition condition) {
    searchAndTagIds.remove(tagId);
    searchOrTagIds.remove(tagId);
    searchNotTagIds.remove(tagId);
    switch (condition) {
      case SearchTagCondition.and:
        searchAndTagIds.add(tagId);
      case SearchTagCondition.or:
        searchOrTagIds.add(tagId);
      case SearchTagCondition.not:
        searchNotTagIds.add(tagId);
      case SearchTagCondition.none:
        break;
    }
    notifyListeners();
  }

  void clearSearchFilters() {
    searchTerm = '';
    searchKind = SearchKindFilter.all;
    searchMinimumSizeBytes = null;
    searchMaximumSizeBytes = null;
    searchCreatedFrom = null;
    searchCreatedTo = null;
    searchModifiedFrom = null;
    searchModifiedTo = null;
    searchAndTagIds.clear();
    searchOrTagIds.clear();
    searchNotTagIds.clear();
    notifyListeners();
  }

  void setInboxScope(InboxScope value) {
    inboxScope = value;
    selectedResourceIds.clear();
    notifyListeners();
  }

  void setIncludeDescendants(bool value) {
    includeDescendants = value;
    notifyListeners();
  }

  void toggleResourceSelection(String resourceId, bool selected) {
    if (selected) {
      selectedResourceIds.add(resourceId);
    } else {
      selectedResourceIds.remove(resourceId);
    }
    notifyListeners();
  }

  void selectResource(String resourceId) {
    selectedResourceIds
      ..clear()
      ..add(resourceId);
    notifyListeners();
  }

  void clearSelection() {
    selectedResourceIds.clear();
    notifyListeners();
  }

  Future<void> createSpace(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('标签空间名称不能为空');
    }
    final space = TagSpace(
      id: newId('space'),
      name: cleanName,
      createdAt: DateTime.now(),
    );
    activePlacementId = null;
    selectedResourceIds.clear();
    activeView = ResourceView.all;
    await _update(
      _state.copyWith(
        spaces: [..._state.spaces, space],
        activeSpaceId: space.id,
      ),
    );
  }

  Future<String> createPlacement({
    required String name,
    required int colorValue,
    String? parentId,
    String? reuseTagId,
  }) async {
    final spaceId = activeSpaceId;
    final cleanName = name.trim();
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    if (reuseTagId == null && cleanName.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    if (parentId != null && reuseTagId != null) {
      final ancestors = _state.ancestorTagIds(parentId);
      if (ancestors.contains(reuseTagId)) {
        throw StateError('不能把同一个标签实体放进自己的祖先路径');
      }
    }
    final tag = reuseTagId == null
        ? TagDefinition(
            id: newId('tag'),
            spaceId: spaceId,
            name: cleanName,
            colorValue: colorValue,
            createdAt: DateTime.now(),
          )
        : _state.tagById(reuseTagId);
    if (tag.spaceId != spaceId) {
      throw StateError('只能复用当前空间的标签');
    }
    final siblings = _state.childrenOf(parentId, spaceId);
    if (siblings.any((placement) => placement.tagId == tag.id)) {
      throw StateError('该父级下已经有此标签实体');
    }
    final placement = TagPlacement(
      id: newId('placement'),
      spaceId: spaceId,
      tagId: tag.id,
      parentId: parentId,
      sortOrder: siblings.length,
    );
    await _update(
      _state.copyWith(
        tags: reuseTagId == null ? [..._state.tags, tag] : _state.tags,
        placements: [..._state.placements, placement],
      ),
    );
    activePlacementId = placement.id;
    notifyListeners();
    return placement.id;
  }

  Future<void> updateTag({
    required String tagId,
    required String name,
    required int colorValue,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    await _update(
      _state.copyWith(
        tags: _state.tags
            .map(
              (tag) => tag.id == tagId
                  ? tag.copyWith(name: cleanName, colorValue: colorValue)
                  : tag,
            )
            .toList(),
      ),
    );
  }

  Future<void> reparentPlacement(
    String placementId,
    String? nextParentId,
  ) async {
    final spaceId = _requireActiveSpace();
    final placement = placementsInActiveSpace.singleWhere(
      (item) => item.id == placementId,
    );
    if (placement.parentId == nextParentId) {
      return;
    }
    if (nextParentId == placementId) {
      throw StateError('标签位置不能作为自己的上级');
    }
    if (nextParentId != null) {
      final parent = placementsInActiveSpace.singleWhere(
        (item) => item.id == nextParentId,
      );
      if (parent.spaceId != spaceId) {
        throw StateError('只能选择当前标签空间内的上级标签');
      }
      var cursor = parent.parentId;
      while (cursor != null) {
        if (cursor == placementId) {
          throw StateError('不能把标签移动到自己的子级下');
        }
        final matches = placementsInActiveSpace.where(
          (item) => item.id == cursor,
        );
        cursor = matches.isEmpty ? null : matches.single.parentId;
      }
    }
    final siblings = _state.childrenOf(nextParentId, spaceId);
    await _update(
      _state.copyWith(
        placements: _state.placements
            .map(
              (item) => item.id == placementId
                  ? TagPlacement(
                      id: item.id,
                      spaceId: item.spaceId,
                      tagId: item.tagId,
                      parentId: nextParentId,
                      sortOrder: siblings.length,
                    )
                  : item,
            )
            .toList(),
      ),
    );
    activePlacementId = placementId;
    notifyListeners();
  }

  TagIdentityImpact previewTagMerge({
    required String targetTagId,
    required Set<String> sourceTagIds,
  }) {
    final spaceId = _requireActiveSpace();
    final normalizedSources = sourceTagIds.difference({targetTagId});
    if (normalizedSources.isEmpty) {
      throw ArgumentError('请至少选择一个不同的来源标签实体');
    }
    final target = _tagInSpace(targetTagId, spaceId);
    final sources = normalizedSources
        .map((tagId) => _tagInSpace(tagId, spaceId))
        .toList();
    final placementIds = _state.placements
        .where(
          (placement) =>
              placement.spaceId == spaceId &&
              normalizedSources.contains(placement.tagId),
        )
        .map((placement) => placement.id)
        .toSet();
    return _tagIdentityImpact(
      type: TagDomainOperationType.merge,
      sourceTags: sources,
      targetTag: target,
      placementIds: placementIds,
      inheritanceTagIds: normalizedSources,
    );
  }

  Future<TagDomainOperation> mergeTags({
    required String targetTagId,
    required Set<String> sourceTagIds,
  }) async {
    final impact = previewTagMerge(
      targetTagId: targetTagId,
      sourceTagIds: sourceTagIds,
    );
    final sourceIds = impact.sourceTags.map((tag) => tag.id).toSet();
    final affectedTagIds = {targetTagId, ...sourceIds};
    final changedPlacements = _state.placements
        .where((placement) => sourceIds.contains(placement.tagId))
        .toList();
    final rulesBefore = _state.folderTagInheritances
        .where((rule) => affectedTagIds.contains(rule.tagId))
        .toList();
    final nextRules = _state.folderTagInheritances
        .where((rule) => !sourceIds.contains(rule.tagId))
        .toList();
    final ruleKeys = {
      for (final rule in nextRules) '${rule.folderResourceId}|${rule.tagId}',
    };
    for (final rule in _state.folderTagInheritances.where(
      (item) => sourceIds.contains(item.tagId),
    )) {
      final key = '${rule.folderResourceId}|$targetTagId';
      if (ruleKeys.add(key)) {
        nextRules.add(
          FolderTagInheritance(
            id: rule.id,
            folderResourceId: rule.folderResourceId,
            tagId: targetTagId,
            createdAt: rule.createdAt,
          ),
        );
      }
    }
    final operation = TagDomainOperation(
      id: newId('tag-operation'),
      spaceId: _requireActiveSpace(),
      type: TagDomainOperationType.merge,
      summary:
          '合并“${impact.sourceTags.map((tag) => tag.name).join('、')}”到“${impact.targetTag!.name}”',
      context: _tagOperationContext(
        affectedTagIds: affectedTagIds,
        tagsBefore: _state.tags
            .where((tag) => affectedTagIds.contains(tag.id))
            .toList(),
        placementsBefore: changedPlacements,
        rulesBefore: rulesBefore,
      ),
      createdAt: DateTime.now(),
      undoneAt: null,
    );
    searchAndTagIds.removeAll(sourceIds);
    searchOrTagIds.removeAll(sourceIds);
    searchNotTagIds.removeAll(sourceIds);
    await _update(
      _state.copyWith(
        tags: _state.tags.where((tag) => !sourceIds.contains(tag.id)).toList(),
        placements: _state.placements
            .map(
              (placement) => sourceIds.contains(placement.tagId)
                  ? TagPlacement(
                      id: placement.id,
                      spaceId: placement.spaceId,
                      tagId: targetTagId,
                      parentId: placement.parentId,
                      sortOrder: placement.sortOrder,
                    )
                  : placement,
            )
            .toList(),
        folderTagInheritances: nextRules,
        tagOperations: [..._state.tagOperations, operation],
      ),
    );
    return operation;
  }

  TagIdentityImpact previewTagSplit(Set<String> placementIds) {
    final split = _validatedSplitPlacements(placementIds);
    final sourceTag = _state.tagById(split.first.tagId);
    return _tagIdentityImpact(
      type: TagDomainOperationType.split,
      sourceTags: [sourceTag],
      targetTag: null,
      placementIds: placementIds,
      inheritanceTagIds: {sourceTag.id},
    );
  }

  Future<TagDomainOperation> splitTagPlacements({
    required Set<String> placementIds,
    String? newName,
    int? newColorValue,
  }) async {
    final impact = previewTagSplit(placementIds);
    final placements = _validatedSplitPlacements(placementIds);
    final originalTag = impact.sourceTags.single;
    final cleanName = newName?.trim();
    final newTag = TagDefinition(
      id: newId('tag'),
      spaceId: originalTag.spaceId,
      name: cleanName == null || cleanName.isEmpty
          ? originalTag.name
          : cleanName,
      colorValue: newColorValue ?? originalTag.colorValue,
      createdAt: DateTime.now(),
    );
    final selectedIds = placements.map((placement) => placement.id).toSet();
    final oldTagPlacementIds = _state.placements
        .where((placement) => placement.tagId == originalTag.id)
        .map((placement) => placement.id)
        .toSet();
    final retainedIds = oldTagPlacementIds.difference(selectedIds);
    final rulesBefore = _state.folderTagInheritances
        .where((rule) => rule.tagId == originalTag.id)
        .toList();
    final nextRules = _state.folderTagInheritances
        .where((rule) => rule.tagId != originalTag.id)
        .toList();
    for (final rule in rulesBefore) {
      final assignedPlacementIds = _state.assignments
          .where((assignment) => assignment.resourceId == rule.folderResourceId)
          .map((assignment) => assignment.placementId)
          .toSet();
      final hasSelected = assignedPlacementIds.any(selectedIds.contains);
      final hasRetained = assignedPlacementIds.any(retainedIds.contains);
      if (hasSelected && !hasRetained) {
        nextRules.add(
          FolderTagInheritance(
            id: rule.id,
            folderResourceId: rule.folderResourceId,
            tagId: newTag.id,
            createdAt: rule.createdAt,
          ),
        );
      } else {
        nextRules.add(rule);
        if (hasSelected && hasRetained) {
          nextRules.add(
            FolderTagInheritance(
              id: newId('inheritance'),
              folderResourceId: rule.folderResourceId,
              tagId: newTag.id,
              createdAt: DateTime.now(),
            ),
          );
        }
      }
    }
    final operation = TagDomainOperation(
      id: newId('tag-operation'),
      spaceId: _requireActiveSpace(),
      type: TagDomainOperationType.split,
      summary: '从“${originalTag.name}”拆分 ${placements.length} 个位置',
      context: _tagOperationContext(
        affectedTagIds: {originalTag.id, newTag.id},
        tagsBefore: [originalTag],
        placementsBefore: placements,
        rulesBefore: rulesBefore,
      ),
      createdAt: DateTime.now(),
      undoneAt: null,
    );
    await _update(
      _state.copyWith(
        tags: [..._state.tags, newTag],
        placements: _state.placements
            .map(
              (placement) => selectedIds.contains(placement.id)
                  ? TagPlacement(
                      id: placement.id,
                      spaceId: placement.spaceId,
                      tagId: newTag.id,
                      parentId: placement.parentId,
                      sortOrder: placement.sortOrder,
                    )
                  : placement,
            )
            .toList(),
        folderTagInheritances: nextRules,
        tagOperations: [..._state.tagOperations, operation],
      ),
    );
    return operation;
  }

  Future<void> undoTagOperation(String operationId) async {
    final matches = _state.tagOperations.where(
      (operation) => operation.id == operationId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId', '找不到标签操作记录');
    }
    final operation = matches.single;
    if (operation.undoneAt != null) {
      throw StateError('该标签操作已经撤销');
    }
    final active =
        _state.tagOperations.where((item) => item.undoneAt == null).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (active.last.id != operationId) {
      throw StateError('标签操作必须按从新到旧的顺序撤销');
    }
    final context = operation.context;
    final affectedTagIds = (context['affectedTagIds'] as List<dynamic>)
        .cast<String>()
        .toSet();
    final tagsBefore = (context['tagsBefore'] as List<dynamic>)
        .map(
          (item) =>
              TagDefinition.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final placementsBefore = (context['placementsBefore'] as List<dynamic>)
        .map(
          (item) =>
              TagPlacement.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final placementBeforeById = {
      for (final placement in placementsBefore) placement.id: placement,
    };
    final rulesBefore = (context['rulesBefore'] as List<dynamic>)
        .map(
          (item) => FolderTagInheritance.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final ruleFolderIds = (context['ruleFolderIds'] as List<dynamic>)
        .cast<String>()
        .toSet();
    await _update(
      _state.copyWith(
        tags: [
          ..._state.tags.where((tag) => !affectedTagIds.contains(tag.id)),
          ...tagsBefore,
        ],
        placements: _state.placements
            .map((placement) => placementBeforeById[placement.id] ?? placement)
            .toList(),
        folderTagInheritances: [
          ..._state.folderTagInheritances.where(
            (rule) =>
                !affectedTagIds.contains(rule.tagId) ||
                !ruleFolderIds.contains(rule.folderResourceId),
          ),
          ...rulesBefore,
        ],
        tagOperations: _state.tagOperations
            .map(
              (item) => item.id == operationId
                  ? item.copyWith(undoneAt: DateTime.now())
                  : item,
            )
            .toList(),
      ),
    );
  }

  Future<void> deletePlacement(String placementId) async {
    final placement = _state.placementById(placementId);
    final alternativePlacements = _state.placements
        .where(
          (item) => item.tagId == placement.tagId && item.id != placementId,
        )
        .toList();
    if (alternativePlacements.isEmpty) {
      throw StateError('这是该标签实体的最后一个位置，请改用“删除标签实体”');
    }
    final remainingPlacements = _state.placements
        .where((item) => item.id != placementId)
        .map(
          (item) => item.parentId == placementId
              ? TagPlacement(
                  id: item.id,
                  spaceId: item.spaceId,
                  tagId: item.tagId,
                  parentId: placement.parentId,
                  sortOrder: item.sortOrder,
                )
              : item,
        )
        .toList();
    final replacementPlacementId = alternativePlacements.first.id;
    final assignmentKeys = <String>{};
    final remainingAssignments = <TagAssignment>[];
    for (final assignment in _state.assignments) {
      final next = assignment.placementId == placementId
          ? TagAssignment(
              id: assignment.id,
              resourceId: assignment.resourceId,
              placementId: replacementPlacementId,
              createdAt: assignment.createdAt,
            )
          : assignment;
      if (assignmentKeys.add('${next.resourceId}|${next.placementId}')) {
        remainingAssignments.add(next);
      }
    }
    activePlacementId = null;
    await _update(
      _state.copyWith(
        placements: remainingPlacements,
        assignments: remainingAssignments,
      ),
    );
  }

  Future<void> deleteTagEntity(String tagId) async {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    final tag = _state.tagById(tagId);
    if (tag.spaceId != spaceId) {
      throw StateError('只能删除当前空间中的标签实体');
    }
    final removedPlacements = _state.placements
        .where(
          (placement) =>
              placement.spaceId == spaceId && placement.tagId == tagId,
        )
        .toList();
    if (removedPlacements.isEmpty) {
      throw ArgumentError.value(tagId, 'tagId', '找不到标签位置');
    }
    final parentByRemovedId = {
      for (final placement in removedPlacements)
        placement.id: placement.parentId,
    };
    String? promotedParent(String? parentId) {
      final seen = <String>{};
      var current = parentId;
      while (current != null &&
          parentByRemovedId.containsKey(current) &&
          seen.add(current)) {
        current = parentByRemovedId[current];
      }
      return current;
    }

    final removedPlacementIds = parentByRemovedId.keys.toSet();
    final placements = _state.placements
        .where((placement) => !removedPlacementIds.contains(placement.id))
        .map(
          (placement) => removedPlacementIds.contains(placement.parentId)
              ? TagPlacement(
                  id: placement.id,
                  spaceId: placement.spaceId,
                  tagId: placement.tagId,
                  parentId: promotedParent(placement.parentId),
                  sortOrder: placement.sortOrder,
                )
              : placement,
        )
        .toList();
    activePlacementId = null;
    await _update(
      _state.copyWith(
        tags: _state.tags.where((item) => item.id != tagId).toList(),
        placements: placements,
        assignments: _state.assignments
            .where(
              (assignment) =>
                  !removedPlacementIds.contains(assignment.placementId),
            )
            .toList(),
        folderTagInheritances: _state.folderTagInheritances
            .where((rule) => rule.tagId != tagId)
            .toList(),
      ),
    );
  }

  Future<void> addResource({
    required String name,
    required String path,
    required ResourceKind kind,
  }) async {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    final cleanName = name.trim();
    final cleanPath = path.trim();
    if (cleanName.isEmpty || cleanPath.isEmpty) {
      throw ArgumentError('名称和路径不能为空');
    }
    final resource = TagResource(
      id: newId('resource'),
      name: cleanName,
      path: cleanPath,
      kind: kind,
      modifiedAt: DateTime.now(),
    );
    await _update(
      _state.copyWith(
        resources: [..._state.resources, resource],
        memberships: [
          ..._state.memberships,
          SpaceMembership(
            resourceId: resource.id,
            spaceId: spaceId,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  Future<TagResource> importManagedResource({
    required FileSystemEntity source,
    required String targetDirectory,
    ImportMode mode = ImportMode.copy,
    Set<String> placementIds = const {},
  }) async {
    final managedLibrary = library;
    final spaceId = activeSpaceId;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    final placementByTagId = <String, String>{};
    for (final placementId in placementIds) {
      final placement = _state.placementById(placementId);
      if (placement.spaceId != spaceId) {
        throw StateError('只能使用当前标签空间中的标签');
      }
      placementByTagId.putIfAbsent(placement.tagId, () => placementId);
    }
    final normalizedPlacementIds = placementByTagId.values;
    final managed = await managedLibrary.importResource(
      source: source,
      targetDirectory: targetDirectory,
      mode: mode,
    );
    final resource = _tagResourceFromManaged(managed);
    final now = DateTime.now();
    final assignments = [
      ..._state.assignments,
      for (final placementId in normalizedPlacementIds)
        TagAssignment(
          id: newId('assignment'),
          resourceId: resource.id,
          placementId: placementId,
          createdAt: now,
        ),
    ];
    final usageEvents = [
      ..._state.usageEvents,
      for (final placementId in normalizedPlacementIds)
        UsageEvent(
          id: newId('usage'),
          spaceId: spaceId,
          resourceId: resource.id,
          placementId: placementId,
          type: UsageEventType.tagged,
          occurredAt: now,
        ),
    ];
    await _update(
      _state.copyWith(
        resources: [
          ..._state.resources.where((item) => item.id != resource.id),
          resource,
        ],
        memberships: [
          ..._state.memberships,
          SpaceMembership(
            resourceId: resource.id,
            spaceId: spaceId,
            createdAt: now,
          ),
        ],
        assignments: assignments,
        usageEvents: usageEvents,
      ),
    );
    return resource;
  }

  Future<void> addResourceToActiveSpace(String resourceId) async {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    if (!_state.resources.any((resource) => resource.id == resourceId)) {
      throw ArgumentError.value(resourceId, 'resourceId', '找不到受管资源');
    }
    if (_state.memberships.any(
      (membership) =>
          membership.resourceId == resourceId && membership.spaceId == spaceId,
    )) {
      return;
    }
    await _update(
      _state.copyWith(
        memberships: [
          ..._state.memberships,
          SpaceMembership(
            resourceId: resourceId,
            spaceId: spaceId,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  Future<List<ManagedOperation>> listOperations() async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      return const [];
    }
    return managedLibrary.listOperations();
  }

  Future<ManagedOperation> restoreResourceToOriginalPath(
    String resourceId,
  ) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final contextJson = _exitContextJson(resourceId);
    final operation = await managedLibrary.restoreToOriginalPath(
      resourceId,
      contextJson: contextJson,
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
  }

  Future<ManagedOperation> moveResourceToSpecifiedPath(
    String resourceId,
    String destinationPath,
  ) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final operation = await managedLibrary.moveToSpecifiedPath(
      resourceId,
      destinationPath,
      contextJson: _exitContextJson(resourceId),
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
  }

  Future<ManagedOperation> recycleResource(String resourceId) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final recycleBinGateway = recycleBin;
    if (recycleBinGateway == null) {
      throw UnsupportedError('当前平台没有可用的回收站适配器');
    }
    final operation = await managedLibrary.moveToRecycleBin(
      resourceId,
      recycleBin: recycleBinGateway,
      contextJson: _exitContextJson(resourceId),
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
  }

  String _exitContextJson(String resourceId) {
    return jsonEncode({
      'memberships': [
        for (final membership in _state.memberships)
          if (membership.resourceId == resourceId) membership.toJson(),
      ],
      'assignments': [
        for (final assignment in _state.assignments)
          if (assignment.resourceId == resourceId) assignment.toJson(),
      ],
      'folderTagInheritances': [
        for (final rule in _state.folderTagInheritances)
          if (rule.folderResourceId == resourceId) rule.toJson(),
      ],
      'usageEvents': [
        for (final event in _state.usageEvents)
          if (event.resourceId == resourceId) event.toJson(),
      ],
    });
  }

  Future<void> undoOperation(String operationId) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final operations = await managedLibrary.listOperations();
    final matches = operations.where(
      (operation) => operation.id == operationId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId', '找不到操作记录');
    }
    final operation = matches.single;
    await managedLibrary.undo(operationId, recycleBin: recycleBin);
    await _syncManagedResources();
    if ((operation.type == ManagedOperationType.exitRestore ||
            operation.type == ManagedOperationType.exitMove ||
            operation.type == ManagedOperationType.exitRecycle) &&
        operation.contextJson != null) {
      await _restoreExitContext(operation);
    }
    notifyListeners();
  }

  Future<void> _restoreExitContext(ManagedOperation operation) async {
    final snapshot = Map<String, dynamic>.from(
      jsonDecode(operation.contextJson!) as Map,
    );
    final validSpaceIds = _state.spaces.map((space) => space.id).toSet();
    final validPlacementIds = _state.placements
        .map((placement) => placement.id)
        .toSet();
    final validTagIds = _state.tags.map((tag) => tag.id).toSet();
    final memberships = (snapshot['memberships'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              SpaceMembership.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where((membership) => validSpaceIds.contains(membership.spaceId));
    final assignments = (snapshot['assignments'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              TagAssignment.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where(
          (assignment) => validPlacementIds.contains(assignment.placementId),
        );
    final usageEvents = (snapshot['usageEvents'] as List<dynamic>? ?? const [])
        .map(
          (item) => UsageEvent.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where(
          (event) =>
              validSpaceIds.contains(event.spaceId) &&
              (event.placementId == null ||
                  validPlacementIds.contains(event.placementId)),
        );
    final folderTagInheritances =
        (snapshot['folderTagInheritances'] as List<dynamic>? ?? const [])
            .map(
              (item) => FolderTagInheritance.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .where(
              (rule) =>
                  rule.folderResourceId == operation.resourceId &&
                  validTagIds.contains(rule.tagId),
            );
    await _update(
      _state.copyWith(
        memberships: [
          ..._state.memberships.where(
            (membership) => membership.resourceId != operation.resourceId,
          ),
          ...memberships,
        ],
        assignments: [
          ..._state.assignments.where(
            (assignment) => assignment.resourceId != operation.resourceId,
          ),
          ...assignments,
        ],
        folderTagInheritances: [
          ..._state.folderTagInheritances.where(
            (rule) => rule.folderResourceId != operation.resourceId,
          ),
          ...folderTagInheritances,
        ],
        usageEvents: [
          ..._state.usageEvents.where(
            (event) => event.resourceId != operation.resourceId,
          ),
          ...usageEvents,
        ],
      ),
    );
  }

  Future<List<ConsistencyFinding>> scanConsistency() async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      return const [];
    }
    return managedLibrary.scanConsistency();
  }

  Future<ManagedResource> takeOverUntracked(String relativePath) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final resource = await managedLibrary.takeOverUntracked(relativePath);
    await _syncManagedResources();
    notifyListeners();
    return resource;
  }

  Future<ManagedOperation> moveUntrackedOutside(
    String relativePath,
    String destinationPath,
  ) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    return managedLibrary.moveUntrackedOutside(relativePath, destinationPath);
  }

  Future<ManagedOperation> acceptExternalMove(
    String missingResourceId,
    String untrackedRelativePath,
  ) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final operation = await managedLibrary.acceptExternalMove(
      missingResourceId,
      untrackedRelativePath,
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
  }

  Future<ManagedOperation> restoreExternalMove(
    String missingResourceId,
    String untrackedRelativePath,
  ) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final operation = await managedLibrary.restoreExternalMove(
      missingResourceId,
      untrackedRelativePath,
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
  }

  Future<void> assignPlacementToSelection(
    String placementId, {
    bool? inheritChildren,
  }) async {
    final spaceId = activeSpaceId;
    if (spaceId == null || selectedResourceIds.isEmpty) {
      return;
    }
    final placement = _state.placementById(placementId);
    if (placement.spaceId != spaceId) {
      throw StateError('只能使用当前标签空间中的标签');
    }
    final existing = {
      for (final assignment in _state.assignments)
        '${assignment.resourceId}|${assignment.placementId}',
    };
    final assignments = [..._state.assignments];
    var folderTagInheritances = [..._state.folderTagInheritances];
    final events = [..._state.usageEvents];
    for (final resourceId in selectedResourceIds) {
      if (existing.add('$resourceId|$placementId')) {
        assignments.add(
          TagAssignment(
            id: newId('assignment'),
            resourceId: resourceId,
            placementId: placementId,
            createdAt: DateTime.now(),
          ),
        );
      }
      events.add(
        UsageEvent(
          id: newId('usage'),
          spaceId: spaceId,
          resourceId: resourceId,
          placementId: placementId,
          type: UsageEventType.tagged,
          occurredAt: DateTime.now(),
        ),
      );
    }
    if (inheritChildren != null) {
      final folder = selectedFolderForInheritance;
      if (folder == null) {
        throw StateError('子项继承一次只能设置一个文件夹');
      }
      folderTagInheritances = folderTagInheritances
          .where(
            (rule) =>
                rule.folderResourceId != folder.id ||
                rule.tagId != placement.tagId,
          )
          .toList();
      if (inheritChildren) {
        folderTagInheritances.add(
          FolderTagInheritance(
            id: newId('inheritance'),
            folderResourceId: folder.id,
            tagId: placement.tagId,
            createdAt: DateTime.now(),
          ),
        );
      }
    }
    await _update(
      _state.copyWith(
        assignments: assignments,
        folderTagInheritances: folderTagInheritances,
        usageEvents: events,
      ),
    );
  }

  Future<void> clearSelectedTags() async {
    if (selectedResourceIds.isEmpty) {
      return;
    }
    await _update(
      _state.copyWith(
        assignments: _state.assignments
            .where(
              (assignment) =>
                  !selectedResourceIds.contains(assignment.resourceId),
            )
            .toList(),
        folderTagInheritances: _state.folderTagInheritances
            .where(
              (rule) => !selectedResourceIds.contains(rule.folderResourceId),
            )
            .toList(),
      ),
    );
  }

  Future<void> recordOpen(String resourceId) async {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return;
    }
    await _update(
      _state.copyWith(
        usageEvents: [
          ..._state.usageEvents,
          UsageEvent(
            id: newId('usage'),
            spaceId: spaceId,
            resourceId: resourceId,
            placementId: null,
            type: UsageEventType.opened,
            occurredAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  Future<Directory> createBackup(Directory destinationDirectory) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    return managedLibrary.createBackup(
      destinationDirectory,
      metadataDocuments: {
        'tag-state.json': const JsonEncoder.withIndent(
          '  ',
        ).convert(_state.toJson()),
        'preferences.json': const JsonEncoder.withIndent(
          '  ',
        ).convert(_preferences.toJson()),
      },
    );
  }

  Future<File> exportActiveSpacePackage(File destination) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    return SpacePortability.exportPackage(
      state: _state,
      spaceId: _requireActiveSpace(),
      library: managedLibrary,
      destination: destination,
    );
  }

  Future<File> exportActiveSpaceTemplate(File destination) {
    return SpacePortability.exportTemplate(
      state: _state,
      spaceId: _requireActiveSpace(),
      destination: destination,
    );
  }

  Future<SpaceArchiveSummary> inspectSpaceArchive(File archiveFile) =>
      SpacePortability.inspect(archiveFile);

  Future<SpaceArchiveSummary> importSpaceArchive({
    required File archiveFile,
    required SpaceArchiveKind expectedKind,
    String targetDirectory = '',
  }) async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final inspected = await SpacePortability.inspect(archiveFile);
    if (inspected.kind != expectedKind) {
      throw FormatException(
        expectedKind == SpaceArchiveKind.package ? '所选文件不是空间导出包' : '所选文件不是空间模板',
      );
    }
    SpaceImportMutation? mutation;
    try {
      mutation = await SpacePortability.importArchive(
        archiveFile: archiveFile,
        currentState: _state,
        library: managedLibrary,
        targetDirectory: targetDirectory,
      );
      await _persistTagDomainMetadata(state: mutation.state);
      _state = mutation.state;
      activePlacementId = null;
      selectedResourceIds.clear();
      activeView = ResourceView.all;
      notifyListeners();
      return mutation.summary;
    } catch (_) {
      if (mutation != null) {
        await managedLibrary.rollbackPackagedResources(
          mutation.importedResourceIds,
        );
      }
      rethrow;
    }
  }

  Future<BackupValidationResult> validateGlobalBackup(
    Directory backupDirectory,
  ) => ManagedLibrary.validateBackup(backupDirectory);

  Future<void> persistRestoredBackupMetadata(
    BackupRestoreResult restored,
  ) async {
    final stateValue = jsonDecode(restored.tagStateJson);
    if (stateValue is! Map<String, dynamic>) {
      throw const FormatException('全局备份标签状态必须是 JSON 对象');
    }
    final restoredState = AppState.fromJson(stateValue);
    final preferencesJson = restored.preferencesJson;
    final restoredPreferences = preferencesJson == null
        ? const UserPreferences()
        : UserPreferences.fromJson(
            Map<String, dynamic>.from(jsonDecode(preferencesJson) as Map),
          );
    await _persistTagDomainMetadata(
      state: restoredState,
      preferences: restoredPreferences,
    );
  }

  Future<void> restoreTagStateBackup(String path) async {
    final restored = await store.readBackup(path);
    if (restored.spaces.isEmpty) {
      throw const FormatException('备份内没有标签空间');
    }
    activePlacementId = null;
    selectedResourceIds.clear();
    activeView = ResourceView.all;
    await _update(restored);
  }

  String _requireActiveSpace() {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      throw StateError('请先创建标签空间');
    }
    return spaceId;
  }

  TagDefinition _tagInSpace(String tagId, String spaceId) {
    final matches = _state.tags.where(
      (tag) => tag.id == tagId && tag.spaceId == spaceId,
    );
    if (matches.isEmpty) {
      throw ArgumentError.value(tagId, 'tagId', '找不到当前空间中的标签实体');
    }
    return matches.single;
  }

  List<TagPlacement> _validatedSplitPlacements(Set<String> placementIds) {
    final spaceId = _requireActiveSpace();
    if (placementIds.isEmpty) {
      throw ArgumentError('请至少选择一个待拆分标签位置');
    }
    final placements = placementIds.map((placementId) {
      final matches = _state.placements.where(
        (placement) =>
            placement.id == placementId && placement.spaceId == spaceId,
      );
      if (matches.isEmpty) {
        throw ArgumentError.value(placementId, 'placementIds', '找不到当前空间中的标签位置');
      }
      return matches.single;
    }).toList();
    final tagIds = placements.map((placement) => placement.tagId).toSet();
    if (tagIds.length != 1) {
      throw StateError('只能一次拆分同一个标签实体的位置');
    }
    final allPlacements = _state.placements
        .where(
          (placement) =>
              placement.spaceId == spaceId && placement.tagId == tagIds.single,
        )
        .toList();
    if (allPlacements.length < 2) {
      throw StateError('该标签实体只有一个位置，无需拆分');
    }
    if (placements.length == allPlacements.length) {
      throw StateError('必须至少保留一个原标签位置');
    }
    return placements;
  }

  TagIdentityImpact _tagIdentityImpact({
    required TagDomainOperationType type,
    required List<TagDefinition> sourceTags,
    required TagDefinition? targetTag,
    required Set<String> placementIds,
    required Set<String> inheritanceTagIds,
  }) {
    if (type == TagDomainOperationType.merge) {
      _validateMergedPlacementStructure(
        targetTag!.id,
        sourceTags.map((tag) => tag.id).toSet(),
      );
    }
    final assignments = _state.assignments
        .where((assignment) => placementIds.contains(assignment.placementId))
        .toList();
    return TagIdentityImpact(
      type: type,
      sourceTags: sourceTags,
      targetTag: targetTag,
      placementCount: placementIds.length,
      assignmentCount: assignments.length,
      resourceCount: assignments
          .map((assignment) => assignment.resourceId)
          .toSet()
          .length,
      inheritanceRuleCount: _state.folderTagInheritances
          .where((rule) => inheritanceTagIds.contains(rule.tagId))
          .length,
    );
  }

  void _validateMergedPlacementStructure(
    String targetTagId,
    Set<String> sourceTagIds,
  ) {
    final spaceId = _requireActiveSpace();
    final placements = _state.placementsForSpace(spaceId);
    final nextTagByPlacementId = {
      for (final placement in placements)
        placement.id: sourceTagIds.contains(placement.tagId)
            ? targetTagId
            : placement.tagId,
    };
    final siblingKeys = <String>{};
    for (final placement in placements) {
      final tagId = nextTagByPlacementId[placement.id]!;
      final key = '${placement.parentId ?? '<root>'}|$tagId';
      if (!siblingKeys.add(key)) {
        throw StateError('合并会在同一父级产生重复标签位置，请先移动或删除其中一个位置');
      }
      final seen = <String>{};
      var parentId = placement.parentId;
      while (parentId != null && seen.add(parentId)) {
        if (nextTagByPlacementId[parentId] == tagId) {
          throw StateError('合并会让标签实体进入自己的层级路径，无法执行');
        }
        final parents = placements.where((item) => item.id == parentId);
        parentId = parents.isEmpty ? null : parents.single.parentId;
      }
    }
  }

  Map<String, dynamic> _tagOperationContext({
    required Set<String> affectedTagIds,
    required List<TagDefinition> tagsBefore,
    required List<TagPlacement> placementsBefore,
    required List<FolderTagInheritance> rulesBefore,
  }) => {
    'affectedTagIds': affectedTagIds.toList(),
    'tagsBefore': tagsBefore.map((tag) => tag.toJson()).toList(),
    'placementsBefore': placementsBefore
        .map((placement) => placement.toJson())
        .toList(),
    'rulesBefore': rulesBefore.map((rule) => rule.toJson()).toList(),
    'ruleFolderIds': rulesBefore
        .map((rule) => rule.folderResourceId)
        .toSet()
        .toList(),
  };

  Set<String>? _matchingResourceIds() {
    if (activeView == ResourceView.recent) {
      return recentResources.map((resource) => resource.id).toSet();
    }
    if (activeView == ResourceView.inbox) {
      final spaceId = activeSpaceId;
      if (spaceId == null) {
        return <String>{};
      }
      if (inboxScope == InboxScope.global) {
        return _state.resources
            .where(
              (resource) => !_state.spaces.any(
                (space) => effectiveTagsForResourceInSpace(
                  resource.id,
                  space.id,
                ).isNotEmpty,
              ),
            )
            .map((resource) => resource.id)
            .toSet();
      }
      final memberResourceIds = _state.resourceIdsForSpace(spaceId);
      return _state.resources
          .where((resource) => memberResourceIds.contains(resource.id))
          .where(
            (resource) =>
                effectiveTagsForResourceInSpace(resource.id, spaceId).isEmpty,
          )
          .map((resource) => resource.id)
          .toSet();
    }
    final selectedPlacement = activePlacementId;
    if (selectedPlacement == null) {
      return null;
    }
    final placementIds = includeDescendants
        ? _state.descendantsOf(selectedPlacement).map((item) => item.id).toSet()
        : {selectedPlacement};
    final tagIds = placementIds
        .map((placementId) => _state.placementById(placementId).tagId)
        .toSet();
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return <String>{};
    }
    final memberResourceIds = _state.resourceIdsForSpace(spaceId);
    return _state.resources
        .where((resource) => memberResourceIds.contains(resource.id))
        .where(
          (resource) => effectiveTagsForResource(
            resource.id,
          ).any((effective) => tagIds.contains(effective.tag.id)),
        )
        .map((resource) => resource.id)
        .toSet();
  }

  Future<void> _update(AppState next) async {
    _state = next;
    notifyListeners();
    await _persistTagDomainMetadata();
  }

  bool _matchesAdvancedSearch(TagResource resource, String spaceId) {
    if (searchKind == SearchKindFilter.file &&
        resource.kind != ResourceKind.file) {
      return false;
    }
    if (searchKind == SearchKindFilter.folder &&
        resource.kind != ResourceKind.folder) {
      return false;
    }
    final size = resource.sizeBytes;
    if (searchMinimumSizeBytes case final minimum?) {
      if (size == null || size < minimum) {
        return false;
      }
    }
    if (searchMaximumSizeBytes case final maximum?) {
      if (size == null || size > maximum) {
        return false;
      }
    }
    final createdAt = resource.createdAt;
    if (searchCreatedFrom case final from?) {
      if (createdAt == null || createdAt.isBefore(from)) {
        return false;
      }
    }
    if (searchCreatedTo case final to?) {
      if (createdAt == null || createdAt.isAfter(to)) {
        return false;
      }
    }
    if (searchModifiedFrom case final from?) {
      if (resource.modifiedAt.isBefore(from)) {
        return false;
      }
    }
    if (searchModifiedTo case final to?) {
      if (resource.modifiedAt.isAfter(to)) {
        return false;
      }
    }
    final tagIds = effectiveTagsForResourceInSpace(
      resource.id,
      spaceId,
    ).map((effective) => effective.tag.id).toSet();
    if (!tagIds.containsAll(searchAndTagIds)) {
      return false;
    }
    if (searchOrTagIds.isNotEmpty && !searchOrTagIds.any(tagIds.contains)) {
      return false;
    }
    if (searchNotTagIds.any(tagIds.contains)) {
      return false;
    }
    return true;
  }

  Future<void> _syncManagedResources() async {
    final managedLibrary = library;
    if (managedLibrary == null) {
      return;
    }
    final fallbackSpaceId = activeSpaceId;
    final managedResources = await managedLibrary.listResources();
    final resources = managedResources.map(_tagResourceFromManaged).toList();
    final resourceIds = resources.map((resource) => resource.id).toSet();
    final resourcesById = {
      for (final resource in resources) resource.id: resource,
    };
    final memberships = _state.memberships
        .where((membership) => resourceIds.contains(membership.resourceId))
        .toList();
    final membershipResourceIds = memberships
        .map((membership) => membership.resourceId)
        .toSet();
    if (fallbackSpaceId != null) {
      for (final resource in resources) {
        if (membershipResourceIds.add(resource.id)) {
          memberships.add(
            SpaceMembership(
              resourceId: resource.id,
              spaceId: fallbackSpaceId,
              createdAt: DateTime.now(),
            ),
          );
        }
      }
    }
    selectedResourceIds.retainAll(resourceIds);
    _state = _state.copyWith(
      resources: resources,
      memberships: memberships,
      assignments: _state.assignments
          .where((assignment) => resourceIds.contains(assignment.resourceId))
          .toList(),
      folderTagInheritances: _state.folderTagInheritances
          .where(
            (rule) =>
                resourcesById[rule.folderResourceId]?.kind ==
                    ResourceKind.folder &&
                _state.tags.any((tag) => tag.id == rule.tagId),
          )
          .toList(),
      usageEvents: _state.usageEvents
          .where(
            (event) =>
                event.resourceId == null ||
                resourceIds.contains(event.resourceId),
          )
          .toList(),
    );
    await _persistTagDomainMetadata();
  }

  AppState _stateFromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('TAGTAG 标签状态必须是 JSON 对象');
    }
    return AppState.fromJson(Map<String, dynamic>.from(decoded));
  }

  UserPreferences _preferencesFromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('TAGTAG 设置必须是 JSON 对象');
    }
    return UserPreferences.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> _persistTagDomainMetadata({
    AppState? state,
    UserPreferences? preferences,
  }) async {
    final nextState = state ?? _state;
    final nextPreferences = preferences ?? _preferences;
    final managedLibrary = library;
    if (managedLibrary == null) {
      await store.save(nextState);
      await store.savePreferences(nextPreferences);
      return;
    }
    await managedLibrary.writeTagDomainMetadata(
      tagStateJson: jsonEncode(nextState.toJson()),
      preferencesJson: jsonEncode(nextPreferences.toJson()),
    );
  }

  TagResource _tagResourceFromManaged(ManagedResource managed) => TagResource(
    id: managed.id,
    name: managed.name,
    path: path.joinAll([
      library!.root.path,
      ...managed.relativePath.split('/'),
    ]),
    kind: managed.kind == ManagedResourceKind.file
        ? ResourceKind.file
        : ResourceKind.folder,
    modifiedAt: managed.modifiedAt,
    sizeBytes: managed.sizeBytes,
    createdAt: managed.createdAt,
  );
}
