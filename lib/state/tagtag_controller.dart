import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../data/local_store.dart';
import '../models/tag_models.dart';
import '../storage/managed_library.dart';

class TagTagController extends ChangeNotifier {
  TagTagController({required this.store, this.library});

  final LocalStore store;
  final ManagedLibrary? library;
  AppState _state = AppState.empty();
  UserPreferences _preferences = const UserPreferences();
  final Set<String> selectedResourceIds = <String>{};

  String? activePlacementId;
  String searchTerm = '';
  bool includeDescendants = true;
  bool showRecent = false;
  bool showInbox = false;

  AppState get state => _state;
  UserPreferences get preferences => _preferences;
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

  Future<void> load() async {
    _preferences = await store.loadPreferences();
    _state = await store.load();
    if (_state.activeSpaceId == null && _state.spaces.isNotEmpty) {
      _state = _state.copyWith(activeSpaceId: _state.spaces.first.id);
    }
    await _syncManagedResources();
    notifyListeners();
  }

  Future<void> updatePreferences({
    bool? moveImportsByDefault,
    bool? navigationCollapsed,
  }) async {
    _preferences = _preferences.copyWith(
      moveImportsByDefault: moveImportsByDefault,
      navigationCollapsed: navigationCollapsed,
    );
    notifyListeners();
    await store.savePreferences(_preferences);
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

  List<TagResource> get visibleResources {
    final spaceId = activeSpaceId;
    if (spaceId == null) {
      return const [];
    }
    final query = searchTerm.trim().toLowerCase();
    final matchingIds = _matchingResourceIds();
    final memberResourceIds = _state.resourceIdsForSpace(spaceId);
    final resources = _state.resources
        .where((resource) => memberResourceIds.contains(resource.id))
        .where(
          (resource) =>
              matchingIds == null || matchingIds.contains(resource.id),
        )
        .where(
          (resource) =>
              query.isEmpty ||
              resource.name.toLowerCase().contains(query) ||
              resource.path.toLowerCase().contains(query),
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

  Future<void> selectSpace(String spaceId) async {
    activePlacementId = null;
    selectedResourceIds.clear();
    showRecent = false;
    showInbox = false;
    await _update(_state.copyWith(activeSpaceId: spaceId));
  }

  void selectPlacement(String? placementId) {
    activePlacementId = placementId;
    showRecent = false;
    showInbox = false;
    notifyListeners();
  }

  void showRecentResources() {
    activePlacementId = null;
    showRecent = true;
    showInbox = false;
    notifyListeners();
  }

  void showInboxResources() {
    activePlacementId = null;
    showRecent = false;
    showInbox = true;
    notifyListeners();
  }

  void setSearchTerm(String value) {
    searchTerm = value;
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
    final contextJson = jsonEncode({
      'memberships': [
        for (final membership in _state.memberships)
          if (membership.resourceId == resourceId) membership.toJson(),
      ],
      'assignments': [
        for (final assignment in _state.assignments)
          if (assignment.resourceId == resourceId) assignment.toJson(),
      ],
      'usageEvents': [
        for (final event in _state.usageEvents)
          if (event.resourceId == resourceId) event.toJson(),
      ],
    });
    final operation = await managedLibrary.restoreToOriginalPath(
      resourceId,
      contextJson: contextJson,
    );
    await _syncManagedResources();
    notifyListeners();
    return operation;
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
    await managedLibrary.undo(operationId);
    await _syncManagedResources();
    if (operation.type == ManagedOperationType.exitRestore &&
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

  Future<void> assignPlacementToSelection(String placementId) async {
    final spaceId = activeSpaceId;
    if (spaceId == null || selectedResourceIds.isEmpty) {
      return;
    }
    final existing = {
      for (final assignment in _state.assignments)
        '${assignment.resourceId}|${assignment.placementId}',
    };
    final assignments = [..._state.assignments];
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
    await _update(
      _state.copyWith(assignments: assignments, usageEvents: events),
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
      },
    );
  }

  Future<void> restoreBackup(String path) async {
    final restored = await store.readBackup(path);
    if (restored.spaces.isEmpty) {
      throw const FormatException('备份内没有标签空间');
    }
    activePlacementId = null;
    selectedResourceIds.clear();
    await _update(restored);
  }

  Set<String>? _matchingResourceIds() {
    if (showRecent) {
      return recentResources.map((resource) => resource.id).toSet();
    }
    if (showInbox) {
      final spaceId = activeSpaceId;
      if (spaceId == null) {
        return <String>{};
      }
      final placementIds = _state
          .placementsForSpace(spaceId)
          .map((placement) => placement.id)
          .toSet();
      final taggedResourceIds = _state.assignments
          .where((assignment) => placementIds.contains(assignment.placementId))
          .map((assignment) => assignment.resourceId)
          .toSet();
      final memberResourceIds = _state.resourceIdsForSpace(spaceId);
      return _state.resources
          .where((resource) => memberResourceIds.contains(resource.id))
          .where((resource) => !taggedResourceIds.contains(resource.id))
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
    return _state.assignments
        .where((assignment) {
          final placement = _state.placementById(assignment.placementId);
          return tagIds.contains(placement.tagId);
        })
        .map((assignment) => assignment.resourceId)
        .toSet();
  }

  Future<void> _update(AppState next) async {
    _state = next;
    notifyListeners();
    await store.save(_state);
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
      usageEvents: _state.usageEvents
          .where(
            (event) =>
                event.resourceId == null ||
                resourceIds.contains(event.resourceId),
          )
          .toList(),
    );
    await store.save(_state);
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
  );
}
