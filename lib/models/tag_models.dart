import 'dart:math';

enum ResourceKind { file, folder }

enum UsageEventType { opened, tagged, searched }

enum TagDomainOperationType {
  merge,
  split,
  create,
  edit,
  deletePlacement,
  deleteEntity,
  reparent,
  pin,
  hide,
}

enum SearchKindFilter { all, file, folder }

enum TagNamePolicy { inherit, unique, free }

String newId(String prefix) {
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$random';
}

class TagSpace {
  const TagSpace({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TagSpace.fromJson(Map<String, dynamic> json) => TagSpace(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class TagDefinition {
  const TagDefinition({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    this.namePolicy = TagNamePolicy.inherit,
  });

  final String id;
  final String spaceId;
  final String name;
  final int colorValue;
  final DateTime createdAt;

  /// inherit = follow the global uniqueTagNames preference; unique = never
  /// allow a same-name tag in the space; free = allow even when the global
  /// preference is on.
  final TagNamePolicy namePolicy;

  TagDefinition copyWith({
    String? name,
    int? colorValue,
    TagNamePolicy? namePolicy,
  }) => TagDefinition(
    id: id,
    spaceId: spaceId,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
    namePolicy: namePolicy ?? this.namePolicy,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'namePolicy': namePolicy.name,
  };

  factory TagDefinition.fromJson(Map<String, dynamic> json) => TagDefinition(
    id: json['id'] as String,
    spaceId: json['spaceId'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    namePolicy:
        TagNamePolicy.values.asNameMap()[json['namePolicy'] as String?] ??
        TagNamePolicy.inherit,
  );
}

class TagPlacement {
  const TagPlacement({
    required this.id,
    required this.spaceId,
    required this.tagId,
    required this.parentId,
    required this.sortOrder,
  });

  final String id;
  final String spaceId;
  final String tagId;
  final String? parentId;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'tagId': tagId,
    'parentId': parentId,
    'sortOrder': sortOrder,
  };

  factory TagPlacement.fromJson(Map<String, dynamic> json) => TagPlacement(
    id: json['id'] as String,
    spaceId: json['spaceId'] as String,
    tagId: json['tagId'] as String,
    parentId: json['parentId'] as String?,
    sortOrder: json['sortOrder'] as int,
  );
}

class TagResource {
  const TagResource({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    required this.modifiedAt,
    this.sizeBytes,
    this.createdAt,
  });

  final String id;
  final String name;
  final String path;
  final ResourceKind kind;
  final DateTime modifiedAt;
  final int? sizeBytes;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'kind': kind.name,
    'modifiedAt': modifiedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory TagResource.fromJson(Map<String, dynamic> json) => TagResource(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    kind: ResourceKind.values.byName(json['kind'] as String),
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    sizeBytes: json['sizeBytes'] as int?,
    createdAt: switch (json['createdAt']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
  );
}

class SpaceMembership {
  const SpaceMembership({
    required this.resourceId,
    required this.spaceId,
    required this.createdAt,
  });

  final String resourceId;
  final String spaceId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'resourceId': resourceId,
    'spaceId': spaceId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SpaceMembership.fromJson(Map<String, dynamic> json) =>
      SpaceMembership(
        resourceId: json['resourceId'] as String,
        spaceId: json['spaceId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class TagAssignment {
  const TagAssignment({
    required this.id,
    required this.resourceId,
    required this.placementId,
    required this.createdAt,
  });

  final String id;
  final String resourceId;
  final String placementId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'resourceId': resourceId,
    'placementId': placementId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TagAssignment.fromJson(Map<String, dynamic> json) => TagAssignment(
    id: json['id'] as String,
    resourceId: json['resourceId'] as String,
    placementId: json['placementId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class FolderTagInheritance {
  const FolderTagInheritance({
    required this.id,
    required this.folderResourceId,
    required this.tagId,
    required this.createdAt,
  });

  final String id;
  final String folderResourceId;
  final String tagId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderResourceId': folderResourceId,
    'tagId': tagId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FolderTagInheritance.fromJson(Map<String, dynamic> json) =>
      FolderTagInheritance(
        id: json['id'] as String,
        folderResourceId: json['folderResourceId'] as String,
        tagId: json['tagId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class UsageEvent {
  const UsageEvent({
    required this.id,
    required this.spaceId,
    required this.resourceId,
    required this.placementId,
    required this.type,
    required this.occurredAt,
  });

  final String id;
  final String spaceId;
  final String? resourceId;
  final String? placementId;
  final UsageEventType type;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'resourceId': resourceId,
    'placementId': placementId,
    'type': type.name,
    'occurredAt': occurredAt.toIso8601String(),
  };

  factory UsageEvent.fromJson(Map<String, dynamic> json) => UsageEvent(
    id: json['id'] as String,
    spaceId: json['spaceId'] as String,
    resourceId: json['resourceId'] as String?,
    placementId: json['placementId'] as String?,
    type: UsageEventType.values.byName(json['type'] as String),
    occurredAt: DateTime.parse(json['occurredAt'] as String),
  );
}

class SavedQuery {
  const SavedQuery({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.term,
    required this.kind,
    required this.minimumSizeBytes,
    required this.maximumSizeBytes,
    required this.createdFrom,
    required this.createdTo,
    required this.modifiedFrom,
    required this.modifiedTo,
    required this.andTagIds,
    required this.orTagIds,
    required this.notTagIds,
    required this.includeDescendants,
    required this.createdAt,
  });

  final String id;
  final String spaceId;
  final String name;
  final String term;
  final SearchKindFilter kind;
  final int? minimumSizeBytes;
  final int? maximumSizeBytes;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final DateTime? modifiedFrom;
  final DateTime? modifiedTo;
  final Set<String> andTagIds;
  final Set<String> orTagIds;
  final Set<String> notTagIds;
  final bool includeDescendants;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'name': name,
    'term': term,
    'kind': kind.name,
    'minimumSizeBytes': minimumSizeBytes,
    'maximumSizeBytes': maximumSizeBytes,
    'createdFrom': createdFrom?.toIso8601String(),
    'createdTo': createdTo?.toIso8601String(),
    'modifiedFrom': modifiedFrom?.toIso8601String(),
    'modifiedTo': modifiedTo?.toIso8601String(),
    'andTagIds': andTagIds.toList(),
    'orTagIds': orTagIds.toList(),
    'notTagIds': notTagIds.toList(),
    'includeDescendants': includeDescendants,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedQuery.fromJson(Map<String, dynamic> json) => SavedQuery(
    id: json['id'] as String,
    spaceId: json['spaceId'] as String,
    name: json['name'] as String,
    term: json['term'] as String,
    kind: SearchKindFilter.values.byName(json['kind'] as String),
    minimumSizeBytes: json['minimumSizeBytes'] as int?,
    maximumSizeBytes: json['maximumSizeBytes'] as int?,
    createdFrom: _dateOrNull(json['createdFrom']),
    createdTo: _dateOrNull(json['createdTo']),
    modifiedFrom: _dateOrNull(json['modifiedFrom']),
    modifiedTo: _dateOrNull(json['modifiedTo']),
    andTagIds: (json['andTagIds'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toSet(),
    orTagIds: (json['orTagIds'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toSet(),
    notTagIds: (json['notTagIds'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toSet(),
    includeDescendants: json['includeDescendants'] as bool? ?? true,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

DateTime? _dateOrNull(Object? value) =>
    value is String ? DateTime.parse(value) : null;

class TagDomainOperation {
  const TagDomainOperation({
    required this.id,
    required this.spaceId,
    required this.type,
    required this.summary,
    required this.context,
    required this.createdAt,
    required this.undoneAt,
  });

  final String id;
  final String spaceId;
  final TagDomainOperationType type;
  final String summary;
  final Map<String, dynamic> context;
  final DateTime createdAt;
  final DateTime? undoneAt;

  TagDomainOperation copyWith({DateTime? undoneAt}) => TagDomainOperation(
    id: id,
    spaceId: spaceId,
    type: type,
    summary: summary,
    context: context,
    createdAt: createdAt,
    undoneAt: undoneAt ?? this.undoneAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'type': type.name,
    'summary': summary,
    'context': context,
    'createdAt': createdAt.toIso8601String(),
    'undoneAt': undoneAt?.toIso8601String(),
  };

  factory TagDomainOperation.fromJson(Map<String, dynamic> json) =>
      TagDomainOperation(
        id: json['id'] as String,
        spaceId: json['spaceId'] as String,
        type: TagDomainOperationType.values.byName(json['type'] as String),
        summary: json['summary'] as String,
        context: Map<String, dynamic>.from(json['context'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        undoneAt: switch (json['undoneAt']) {
          final String value => DateTime.parse(value),
          _ => null,
        },
      );
}

enum LogLevel { info, notice, warning }

enum LogCategory { resource, tag, settings, consistency }

/// A lightweight persisted log event for application-level changes that are
/// not managed resource operations or tag operations (settings, consistency).
class AppLogEvent {
  const AppLogEvent({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.summary,
  });

  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final LogCategory category;
  final String summary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'category': category.name,
    'summary': summary,
  };

  factory AppLogEvent.fromJson(Map<String, dynamic> json) => AppLogEvent(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    level: LogLevel.values.byName(json['level'] as String),
    category: LogCategory.values.byName(json['category'] as String),
    summary: json['summary'] as String,
  );
}

class AppState {
  const AppState({
    required this.spaces,
    required this.tags,
    required this.placements,
    required this.resources,
    required this.memberships,
    required this.assignments,
    required this.folderTagInheritances,
    required this.usageEvents,
    required this.activeSpaceId,
    this.tagOperations = const [],
    this.savedQueries = const [],
    this.pinnedPlacementIds = const {},
    this.hiddenPlacementIds = const {},
    this.logEvents = const [],
  });

  final List<TagSpace> spaces;
  final List<TagDefinition> tags;
  final List<TagPlacement> placements;
  final List<TagResource> resources;
  final List<SpaceMembership> memberships;
  final List<TagAssignment> assignments;
  final List<FolderTagInheritance> folderTagInheritances;
  final List<UsageEvent> usageEvents;
  final String? activeSpaceId;
  final List<TagDomainOperation> tagOperations;
  final List<SavedQuery> savedQueries;
  final Set<String> pinnedPlacementIds;
  final Set<String> hiddenPlacementIds;
  final List<AppLogEvent> logEvents;

  factory AppState.empty() => const AppState(
    spaces: [],
    tags: [],
    placements: [],
    resources: [],
    memberships: [],
    assignments: [],
    folderTagInheritances: [],
    usageEvents: [],
    activeSpaceId: null,
    tagOperations: [],
  );

  factory AppState.demo() {
    final now = DateTime.now();
    const spaceId = 'space-design';
    const projectTagId = 'tag-project';
    const designTagId = 'tag-design';
    const sharedReferenceId = 'tag-reference-shared';
    const personalTagId = 'tag-personal';
    const readingTagId = 'tag-reading';
    const independentReferenceId = 'tag-reference-independent';

    const projectPlacementId = 'place-project';
    const designPlacementId = 'place-project-design';
    const projectReferencePlacementId = 'place-project-design-reference';
    const personalPlacementId = 'place-personal';
    const readingPlacementId = 'place-personal-reading';
    const sharedReferencePlacementId = 'place-personal-reading-reference';
    const independentReferencePlacementId =
        'place-personal-reading-reference-independent';

    const architectureResourceId = 'resource-architecture';
    const folderResourceId = 'resource-folder';
    const comparisonResourceId = 'resource-comparison';
    const notesResourceId = 'resource-notes';
    const inboxResourceId = 'resource-inbox';

    return AppState(
      spaces: [TagSpace(id: spaceId, name: '设计空间', createdAt: now)],
      tags: [
        TagDefinition(
          id: projectTagId,
          spaceId: spaceId,
          name: '项目',
          colorValue: 0xff0f766e,
          createdAt: now,
        ),
        TagDefinition(
          id: designTagId,
          spaceId: spaceId,
          name: '设计',
          colorValue: 0xff2563eb,
          createdAt: now,
        ),
        TagDefinition(
          id: sharedReferenceId,
          spaceId: spaceId,
          name: '参考',
          colorValue: 0xff7c3aed,
          createdAt: now,
        ),
        TagDefinition(
          id: personalTagId,
          spaceId: spaceId,
          name: '个人',
          colorValue: 0xffb45309,
          createdAt: now,
        ),
        TagDefinition(
          id: readingTagId,
          spaceId: spaceId,
          name: '阅读',
          colorValue: 0xff0369a1,
          createdAt: now,
        ),
        TagDefinition(
          id: independentReferenceId,
          spaceId: spaceId,
          name: '参考',
          colorValue: 0xffdc2626,
          createdAt: now,
        ),
      ],
      placements: const [
        TagPlacement(
          id: projectPlacementId,
          spaceId: spaceId,
          tagId: projectTagId,
          parentId: null,
          sortOrder: 0,
        ),
        TagPlacement(
          id: designPlacementId,
          spaceId: spaceId,
          tagId: designTagId,
          parentId: projectPlacementId,
          sortOrder: 0,
        ),
        TagPlacement(
          id: projectReferencePlacementId,
          spaceId: spaceId,
          tagId: sharedReferenceId,
          parentId: designPlacementId,
          sortOrder: 0,
        ),
        TagPlacement(
          id: personalPlacementId,
          spaceId: spaceId,
          tagId: personalTagId,
          parentId: null,
          sortOrder: 1,
        ),
        TagPlacement(
          id: readingPlacementId,
          spaceId: spaceId,
          tagId: readingTagId,
          parentId: personalPlacementId,
          sortOrder: 0,
        ),
        TagPlacement(
          id: sharedReferencePlacementId,
          spaceId: spaceId,
          tagId: sharedReferenceId,
          parentId: readingPlacementId,
          sortOrder: 0,
        ),
        TagPlacement(
          id: independentReferencePlacementId,
          spaceId: spaceId,
          tagId: independentReferenceId,
          parentId: readingPlacementId,
          sortOrder: 1,
        ),
      ],
      resources: [
        TagResource(
          id: architectureResourceId,
          name: 'TAGTAG 架构说明.md',
          path:
              r'D:\Documents\codeSpace\TAGTAG\docs\TAGTAG-research-and-product-design.md',
          kind: ResourceKind.file,
          modifiedAt: now.subtract(const Duration(minutes: 18)),
        ),
        TagResource(
          id: folderResourceId,
          name: 'TAGTAG',
          path: r'D:\Documents\codeSpace\TAGTAG',
          kind: ResourceKind.folder,
          modifiedAt: now.subtract(const Duration(hours: 1)),
        ),
        TagResource(
          id: comparisonResourceId,
          name: '竞品对照.xlsx',
          path: r'D:\Projects\Research\竞品对照.xlsx',
          kind: ResourceKind.file,
          modifiedAt: now.subtract(const Duration(days: 1)),
        ),
        TagResource(
          id: notesResourceId,
          name: '读书笔记.md',
          path: r'D:\Notes\读书笔记.md',
          kind: ResourceKind.file,
          modifiedAt: now.subtract(const Duration(days: 3)),
        ),
        TagResource(
          id: inboxResourceId,
          name: '灵感收集',
          path: r'D:\Inbox\灵感收集',
          kind: ResourceKind.folder,
          modifiedAt: now.subtract(const Duration(days: 5)),
        ),
      ],
      memberships: [
        for (final resourceId in [
          architectureResourceId,
          folderResourceId,
          comparisonResourceId,
          notesResourceId,
          inboxResourceId,
        ])
          SpaceMembership(
            resourceId: resourceId,
            spaceId: spaceId,
            createdAt: now,
          ),
      ],
      assignments: [
        TagAssignment(
          id: 'assignment-architecture-project',
          resourceId: architectureResourceId,
          placementId: projectPlacementId,
          createdAt: now,
        ),
        TagAssignment(
          id: 'assignment-architecture-reference',
          resourceId: architectureResourceId,
          placementId: projectReferencePlacementId,
          createdAt: now,
        ),
        TagAssignment(
          id: 'assignment-folder-project',
          resourceId: folderResourceId,
          placementId: projectPlacementId,
          createdAt: now,
        ),
        TagAssignment(
          id: 'assignment-comparison-shared',
          resourceId: comparisonResourceId,
          placementId: sharedReferencePlacementId,
          createdAt: now,
        ),
        TagAssignment(
          id: 'assignment-notes-independent',
          resourceId: notesResourceId,
          placementId: independentReferencePlacementId,
          createdAt: now,
        ),
      ],
      folderTagInheritances: const [],
      usageEvents: [
        UsageEvent(
          id: 'usage-architecture',
          spaceId: spaceId,
          resourceId: architectureResourceId,
          placementId: projectReferencePlacementId,
          type: UsageEventType.tagged,
          occurredAt: now.subtract(const Duration(minutes: 2)),
        ),
        UsageEvent(
          id: 'usage-comparison',
          spaceId: spaceId,
          resourceId: comparisonResourceId,
          placementId: sharedReferencePlacementId,
          type: UsageEventType.opened,
          occurredAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      activeSpaceId: spaceId,
    );
  }

  AppState copyWith({
    List<TagSpace>? spaces,
    List<TagDefinition>? tags,
    List<TagPlacement>? placements,
    List<TagResource>? resources,
    List<SpaceMembership>? memberships,
    List<TagAssignment>? assignments,
    List<FolderTagInheritance>? folderTagInheritances,
    List<UsageEvent>? usageEvents,
    List<TagDomainOperation>? tagOperations,
    List<SavedQuery>? savedQueries,
    Set<String>? pinnedPlacementIds,
    Set<String>? hiddenPlacementIds,
    List<AppLogEvent>? logEvents,
    String? activeSpaceId,
    bool clearActiveSpace = false,
  }) => AppState(
    spaces: spaces ?? this.spaces,
    tags: tags ?? this.tags,
    placements: placements ?? this.placements,
    resources: resources ?? this.resources,
    memberships: memberships ?? this.memberships,
    assignments: assignments ?? this.assignments,
    folderTagInheritances: folderTagInheritances ?? this.folderTagInheritances,
    usageEvents: usageEvents ?? this.usageEvents,
    tagOperations: tagOperations ?? this.tagOperations,
    savedQueries: savedQueries ?? this.savedQueries,
    pinnedPlacementIds: pinnedPlacementIds ?? this.pinnedPlacementIds,
    hiddenPlacementIds: hiddenPlacementIds ?? this.hiddenPlacementIds,
    logEvents: logEvents ?? this.logEvents,
    activeSpaceId: clearActiveSpace
        ? null
        : activeSpaceId ?? this.activeSpaceId,
  );

  TagDefinition tagById(String tagId) =>
      tags.firstWhere((tag) => tag.id == tagId);

  TagPlacement placementById(String placementId) =>
      placements.firstWhere((placement) => placement.id == placementId);

  List<TagPlacement> placementsForSpace(String spaceId) =>
      placements.where((placement) => placement.spaceId == spaceId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<TagPlacement> childrenOf(String? parentId, String spaceId) =>
      placementsForSpace(
        spaceId,
      ).where((placement) => placement.parentId == parentId).toList();

  Set<String> resourceIdsForSpace(String spaceId) => memberships
      .where((membership) => membership.spaceId == spaceId)
      .map((membership) => membership.resourceId)
      .toSet();

  List<TagPlacement> descendantsOf(String placementId) {
    final result = <TagPlacement>[];
    final pending = <String>[placementId];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!seen.add(current)) {
        continue;
      }
      final placement = placements.firstWhere(
        (item) => item.id == current,
        orElse: () => const TagPlacement(
          id: '',
          spaceId: '',
          tagId: '',
          parentId: null,
          sortOrder: 0,
        ),
      );
      if (placement.id.isEmpty) {
        continue;
      }
      result.add(placement);
      pending.addAll(
        placements
            .where((item) => item.parentId == current)
            .map((item) => item.id),
      );
    }
    return result;
  }

  List<String> ancestorTagIds(String? placementId) {
    final result = <String>[];
    final seen = <String>{};
    var currentId = placementId;
    while (currentId != null && seen.add(currentId)) {
      final placement = placements.firstWhere(
        (item) => item.id == currentId,
        orElse: () => const TagPlacement(
          id: '',
          spaceId: '',
          tagId: '',
          parentId: null,
          sortOrder: 0,
        ),
      );
      if (placement.id.isEmpty) {
        break;
      }
      result.add(placement.tagId);
      currentId = placement.parentId;
    }
    return result;
  }

  String pathOf(String placementId) {
    final names = <String>[];
    final seen = <String>{};
    var currentId = placementId;
    while (seen.add(currentId)) {
      final placement = placements.firstWhere(
        (item) => item.id == currentId,
        orElse: () => const TagPlacement(
          id: '',
          spaceId: '',
          tagId: '',
          parentId: null,
          sortOrder: 0,
        ),
      );
      if (placement.id.isEmpty) {
        break;
      }
      names.add(tagById(placement.tagId).name);
      if (placement.parentId == null) {
        break;
      }
      currentId = placement.parentId!;
    }
    return names.reversed.join(' / ');
  }

  Map<String, dynamic> toJson() => {
    'version': 5,
    'activeSpaceId': activeSpaceId,
    'spaces': spaces.map((item) => item.toJson()).toList(),
    'tags': tags.map((item) => item.toJson()).toList(),
    'placements': placements.map((item) => item.toJson()).toList(),
    'resources': resources.map((item) => item.toJson()).toList(),
    'memberships': memberships.map((item) => item.toJson()).toList(),
    'assignments': assignments.map((item) => item.toJson()).toList(),
    'folderTagInheritances': folderTagInheritances
        .map((item) => item.toJson())
        .toList(),
    'usageEvents': usageEvents.map((item) => item.toJson()).toList(),
    'tagOperations': tagOperations.map((item) => item.toJson()).toList(),
    'savedQueries': savedQueries.map((item) => item.toJson()).toList(),
    'pinnedPlacementIds': pinnedPlacementIds.toList(),
    'hiddenPlacementIds': hiddenPlacementIds.toList(),
    'logEvents': logEvents.map((item) => item.toJson()).toList(),
  };

  factory AppState.fromJson(Map<String, dynamic> json) {
    final resourceJson = (json['resources'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final membershipJson = json['memberships'];
    final memberships = membershipJson is List<dynamic>
        ? membershipJson
              .map(
                (item) =>
                    SpaceMembership.fromJson(item as Map<String, dynamic>),
              )
              .toList()
        : [
            for (final resource in resourceJson)
              if (resource['spaceId'] is String)
                SpaceMembership(
                  resourceId: resource['id'] as String,
                  spaceId: resource['spaceId'] as String,
                  createdAt: DateTime.parse(resource['modifiedAt'] as String),
                ),
          ];
    return AppState(
      activeSpaceId: json['activeSpaceId'] as String?,
      spaces: (json['spaces'] as List<dynamic>)
          .map((item) => TagSpace.fromJson(item as Map<String, dynamic>))
          .toList(),
      tags: (json['tags'] as List<dynamic>)
          .map((item) => TagDefinition.fromJson(item as Map<String, dynamic>))
          .toList(),
      placements: (json['placements'] as List<dynamic>)
          .map((item) => TagPlacement.fromJson(item as Map<String, dynamic>))
          .toList(),
      resources: resourceJson.map(TagResource.fromJson).toList(),
      memberships: memberships,
      assignments: (json['assignments'] as List<dynamic>)
          .map((item) => TagAssignment.fromJson(item as Map<String, dynamic>))
          .toList(),
      folderTagInheritances:
          (json['folderTagInheritances'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    FolderTagInheritance.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      usageEvents: (json['usageEvents'] as List<dynamic>)
          .map((item) => UsageEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
      tagOperations: (json['tagOperations'] as List<dynamic>? ?? const [])
          .map(
            (item) => TagDomainOperation.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      savedQueries: (json['savedQueries'] as List<dynamic>? ?? const [])
          .map((item) => SavedQuery.fromJson(item as Map<String, dynamic>))
          .toList(),
      pinnedPlacementIds:
          (json['pinnedPlacementIds'] as List<dynamic>? ?? const [])
              .cast<String>()
              .toSet(),
      hiddenPlacementIds:
          (json['hiddenPlacementIds'] as List<dynamic>? ?? const [])
              .cast<String>()
              .toSet(),
      logEvents: (json['logEvents'] as List<dynamic>? ?? const [])
          .map((item) => AppLogEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
