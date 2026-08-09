import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/tag_models.dart';
import '../platform/windows_file_actions.dart';
import '../state/tagtag_controller.dart';
import '../storage/managed_library.dart';

class TagTagHome extends StatefulWidget {
  const TagTagHome({
    super.key,
    required this.controller,
    required this.fileActions,
  });

  final TagTagController controller;
  final WindowsFileActions fileActions;

  @override
  State<TagTagHome> createState() => _TagTagHomeState();
}

class _TagTagHomeState extends State<TagTagHome> {
  late final TextEditingController _searchController;
  bool _dragging = false;
  bool _importDialogOpen = false;
  bool _scanningConsistency = false;
  List<ConsistencyFinding> _consistencyFindings = const [];
  Timer? _consistencyTimer;

  TagTagController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: controller.searchTerm);
    unawaited(_scanConsistency());
    _consistencyTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_scanConsistency()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _consistencyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true):
            _showQuickTag,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(),
          body: DropTarget(
            enable: !_importDialogOpen,
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              setState(() => _dragging = false);
              unawaited(
                _handleDroppedPaths(details.files.map((item) => item.path)),
              );
            },
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 1120;
                        return Column(
                          children: [
                            _buildCommandBar(compact),
                            const Divider(height: 1),
                            Expanded(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: compact ? 244 : 288,
                                    child: _NavigationPane(
                                      controller: controller,
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(child: _buildResourcePane(compact)),
                                  if (!compact) ...[
                                    const VerticalDivider(width: 1),
                                    SizedBox(
                                      width: 324,
                                      child: _InspectorPane(
                                        controller: controller,
                                        onQuickTag: _showQuickTag,
                                        onClearTags: _clearTags,
                                        onEditTag: _editActiveTag,
                                        onDeleteTag: _deleteActiveTag,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                if (_dragging)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.10),
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.move_to_inbox_outlined),
                                SizedBox(width: 10),
                                Text('释放以导入并标注'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: const Color(0xfff8fafc),
      titleSpacing: 18,
      title: const Row(
        children: [
          _BrandMark(),
          SizedBox(width: 10),
          Text('TAGTAG', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        if (_consistencyFindings.isNotEmpty)
          Badge.count(
            count: _consistencyFindings.length,
            child: IconButton(
              tooltip: '一致性告警',
              onPressed: _showConsistencyFindings,
              icon: Icon(
                Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        Tooltip(
          message: '新建标签空间',
          child: IconButton(
            onPressed: _showCreateSpace,
            icon: const Icon(Icons.layers_outlined),
          ),
        ),
        Tooltip(
          message: '创建备份',
          child: IconButton(
            onPressed: _createBackup,
            icon: const Icon(Icons.backup_outlined),
          ),
        ),
        Tooltip(
          message: '操作日志',
          child: IconButton(
            onPressed: _showOperationLog,
            icon: const Icon(Icons.history_outlined),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildCommandBar(bool compact) {
    final activePath = controller.activePlacementId == null
        ? controller.showRecent
              ? '最近使用'
              : controller.showInbox
              ? '待整理'
              : '全部资源'
        : controller.pathOf(controller.activePlacementId!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: controller.setSearchTerm,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '搜索名称或路径',
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          controller.setSearchTerm('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (!compact)
            Flexible(
              child: Text(
                activePath,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<_ImportSourceKind>(
            tooltip: '导入资源',
            icon: const Icon(Icons.add_to_drive_outlined),
            onSelected: (value) => unawaited(_chooseImportSource(value)),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ImportSourceKind.files,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.description_outlined),
                  title: Text('导入文件'),
                ),
              ),
              PopupMenuItem(
                value: _ImportSourceKind.folder,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.folder_outlined),
                  title: Text('导入文件夹'),
                ),
              ),
            ],
          ),
          if (controller.selectedResourceIds.isNotEmpty) ...[
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _showQuickTag,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('打标签'),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: '清除所选资源的直接标签',
              child: IconButton(
                onPressed: _clearTags,
                icon: const Icon(Icons.label_off_outlined),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResourcePane(bool compact) {
    final resources = controller.visibleResources;
    final activePlacement = controller.activePlacementId == null
        ? null
        : controller.state.placementById(controller.activePlacementId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  controller.showRecent
                      ? '最近使用'
                      : controller.showInbox
                      ? '待整理'
                      : activePlacement == null
                      ? '全部资源'
                      : controller.pathOf(activePlacement.id),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (activePlacement != null)
                FilterChip(
                  label: const Text('包含后代'),
                  selected: controller.includeDescendants,
                  onSelected: controller.setIncludeDescendants,
                ),
              if (compact && controller.selectedResourceIds.isNotEmpty)
                Tooltip(
                  message: '查看所选资源的直接标签',
                  child: IconButton(
                    onPressed: _showCompactInspector,
                    icon: const Icon(Icons.info_outline),
                  ),
                ),
            ],
          ),
        ),
        _ResourceHeader(compact: compact),
        const Divider(height: 1),
        Expanded(
          child: resources.isEmpty
              ? _EmptyResourceState(
                  hasFilter:
                      controller.activePlacementId != null ||
                      controller.searchTerm.isNotEmpty,
                  onClear: () {
                    _searchController.clear();
                    controller.setSearchTerm('');
                    controller.selectPlacement(null);
                  },
                )
              : ListView.separated(
                  itemCount: resources.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _ResourceRow(
                    resource: resources[index],
                    selected: controller.selectedResourceIds.contains(
                      resources[index].id,
                    ),
                    compact: compact,
                    tags: controller.assignmentsForResource(
                      resources[index].id,
                    ),
                    controller: controller,
                    onSelectionChanged: (value) => controller
                        .toggleResourceSelection(resources[index].id, value),
                    onOpen: () async {
                      try {
                        await widget.fileActions.open(resources[index].path);
                        await controller.recordOpen(resources[index].id);
                      } catch (error) {
                        if (mounted) {
                          _showMessage('打开失败：$error', error: true);
                        }
                      }
                    },
                    onReveal: () => _revealResource(resources[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showQuickTag() async {
    if (controller.selectedResourceIds.isEmpty) {
      _showMessage('先选择至少一个文件或文件夹。');
      return;
    }
    final placementId = await showDialog<String>(
      context: context,
      builder: (context) => _QuickTagDialog(controller: controller),
    );
    if (placementId == null) {
      return;
    }
    await _runAction(
      () => controller.assignPlacementToSelection(placementId),
      successMessage: '已添加直接标签：${controller.pathOf(placementId)}',
    );
  }

  Future<void> _revealResource(TagResource resource) async {
    try {
      await widget.fileActions.reveal(resource.path);
    } catch (error) {
      if (mounted) {
        _showMessage('定位失败：$error', error: true);
      }
    }
  }

  Future<void> _clearTags() async {
    if (controller.selectedResourceIds.isEmpty) {
      return;
    }
    final confirmed = await _confirm(
      title: '清除直接标签？',
      message: '此操作只删除 TAGTAG 中的直接标签，不会移动或重命名任何文件。',
      actionLabel: '清除标签',
    );
    if (!confirmed) {
      return;
    }
    await _runAction(
      controller.clearSelectedTags,
      successMessage: '已清除所选资源的直接标签。',
    );
  }

  Future<void> _showCreateSpace() async {
    final name = await _showTextDialog(
      title: '新建标签空间',
      label: '空间名称',
      actionLabel: '创建',
    );
    if (name == null) {
      return;
    }
    await _runAction(
      () => controller.createSpace(name),
      successMessage: '已创建标签空间：${name.trim()}',
    );
  }

  Future<void> _chooseImportSource(_ImportSourceKind kind) async {
    if (kind == _ImportSourceKind.files) {
      final files = await openFiles(confirmButtonText: '导入所选文件');
      await _showImportDialog(files.map((item) => File(item.path)).toList());
      return;
    }
    final directoryPath = await getDirectoryPath(confirmButtonText: '导入此文件夹');
    if (directoryPath != null) {
      await _showImportDialog([Directory(directoryPath)]);
    }
  }

  Future<void> _handleDroppedPaths(Iterable<String> droppedPaths) async {
    final sources = <FileSystemEntity>[];
    for (final droppedPath in droppedPaths) {
      final type = await FileSystemEntity.type(droppedPath);
      if (type == FileSystemEntityType.file) {
        sources.add(File(droppedPath));
      } else if (type == FileSystemEntityType.directory) {
        sources.add(Directory(droppedPath));
      }
    }
    await _showImportDialog(sources);
  }

  Future<void> _showImportDialog(List<FileSystemEntity> sources) async {
    if (sources.isEmpty || _importDialogOpen) {
      return;
    }
    if (controller.activeSpaceId == null) {
      _showMessage('请先创建一个标签空间。', error: true);
      return;
    }
    final managedIds = <String>[];
    for (final source in sources) {
      final normalized = path.normalize(source.absolute.path);
      final matches = controller.state.resources.where(
        (resource) => path.equals(path.normalize(resource.path), normalized),
      );
      if (matches.isNotEmpty) {
        managedIds.add(matches.first.id);
      }
    }
    if (managedIds.isNotEmpty) {
      if (managedIds.length != sources.length) {
        _showMessage('请将已受管资源与外部资源分开处理。', error: true);
        return;
      }
      controller.clearSelection();
      for (final resourceId in managedIds) {
        controller.toggleResourceSelection(resourceId, true);
      }
      await _showQuickTag();
      return;
    }

    setState(() => _importDialogOpen = true);
    final result = await showDialog<_ImportDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ImportDialog(controller: controller, sources: sources),
    );
    if (mounted) {
      setState(() => _importDialogOpen = false);
    }
    if (result == null) {
      return;
    }

    var importedCount = 0;
    try {
      for (final source in sources) {
        await controller.importManagedResource(
          source: source,
          targetDirectory: result.targetDirectory,
          mode: result.mode,
          placementIds: result.placementIds,
        );
        importedCount += 1;
      }
      if (mounted) {
        _showMessage('已导入 $importedCount 个资源。');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          importedCount == 0
              ? '导入失败：$error'
              : '已导入 $importedCount 个资源，其余资源失败：$error',
          error: true,
        );
      }
    }
  }

  Future<void> _showCreateTag({String? parentId}) async {
    final result = await showDialog<_TagDraft>(
      context: context,
      builder: (context) => _TagDialog(
        title: parentId == null ? '新建根标签' : '新建子标签',
        tags: controller.state.tags
            .where((tag) => tag.spaceId == controller.activeSpaceId)
            .toList(),
      ),
    );
    if (result == null) {
      return;
    }
    await _runAction(
      () => controller.createPlacement(
        name: result.name,
        colorValue: result.colorValue,
        parentId: parentId,
        reuseTagId: result.reuseTagId,
      ),
      successMessage: result.reuseTagId == null ? '已创建标签。' : '已复用已有标签实体。',
    );
  }

  Future<void> _editActiveTag() async {
    final placementId = controller.activePlacementId;
    if (placementId == null) {
      return;
    }
    final placement = controller.state.placementById(placementId);
    final tag = controller.tagForPlacement(placement);
    final result = await showDialog<_TagDraft>(
      context: context,
      builder: (context) => _TagDialog(
        title: '编辑标签实体',
        initialName: tag.name,
        initialColor: tag.colorValue,
        tags: const [],
        allowReuse: false,
      ),
    );
    if (result == null) {
      return;
    }
    await _runAction(
      () => controller.updateTag(
        tagId: tag.id,
        name: result.name,
        colorValue: result.colorValue,
      ),
      successMessage: '已更新标签实体；所有复用位置同步显示。',
    );
  }

  Future<void> _deleteActiveTag() async {
    final placementId = controller.activePlacementId;
    if (placementId == null) {
      return;
    }
    final placement = controller.state.placementById(placementId);
    final tag = controller.tagForPlacement(placement);
    final placementCount = controller.placementsInActiveSpace
        .where((item) => item.tagId == tag.id)
        .length;
    final path = controller.pathOf(placementId);
    if (placementCount == 1) {
      final confirmed = await _confirm(
        title: '删除标签实体？',
        message: '“${tag.name}”只剩这一个位置。删除后会移除该实体的全部直接标注并提升子位置，但不会移动或删除任何资源。',
        actionLabel: '删除实体',
        destructive: true,
      );
      if (!confirmed) {
        return;
      }
      await _runAction(
        () => controller.deleteTagEntity(tag.id),
        successMessage: '已删除标签实体；失去标签的资源已进入待整理区。',
      );
      return;
    }
    final confirmed = await _confirm(
      title: '删除标签位置？',
      message: '将只删除“$path”这个位置；直接子位置会提升，标签实体和资源标注保留。',
      actionLabel: '删除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await _runAction(
      () => controller.deletePlacement(placementId),
      successMessage: '已删除标签位置。',
    );
  }

  Future<void> _createBackup() async {
    final destination = await getDirectoryPath(
      confirmButtonText: '保存备份到此目录',
      canCreateDirectories: true,
    );
    if (destination == null) {
      return;
    }
    try {
      final backup = await controller.createBackup(Directory(destination));
      if (mounted) {
        _showMessage('备份已保存到：${backup.path}');
      }
    } catch (error) {
      _showMessage('备份失败：$error', error: true);
    }
  }

  Future<void> _showOperationLog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _OperationLogDialog(controller: controller),
    );
  }

  Future<void> _scanConsistency() async {
    if (_scanningConsistency) {
      return;
    }
    _scanningConsistency = true;
    try {
      final findings = await controller.scanConsistency();
      if (mounted) {
        setState(() => _consistencyFindings = findings);
      }
    } finally {
      _scanningConsistency = false;
    }
  }

  Future<void> _showConsistencyFindings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('存储一致性告警'),
        content: SizedBox(
          width: 660,
          height: 420,
          child: ListView.separated(
            itemCount: _consistencyFindings.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final finding = _consistencyFindings[index];
              final missing = finding.type == ConsistencyFindingType.missing;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  missing
                      ? Icons.link_off_outlined
                      : Icons.add_to_drive_outlined,
                  color: missing
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(missing ? '受管资源被外部删除' : '发现未受管内容'),
                subtitle: Text(
                  '存储根 / ${finding.relativePath}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _scanConsistency();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCompactInspector() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: 390,
        child: _InspectorPane(
          controller: controller,
          onQuickTag: _showQuickTag,
          onClearTags: _clearTags,
          onEditTag: _editActiveTag,
          onDeleteTag: _deleteActiveTag,
        ),
      ),
    );
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) {
        _showMessage(successMessage);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('$error', error: true);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _showTextDialog({
    required String title,
    required String label,
    required String actionLabel,
  }) async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    textController.dispose();
    return result;
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          content: Text(message),
        ),
      );
  }
}

class _OperationLogDialog extends StatefulWidget {
  const _OperationLogDialog({required this.controller});

  final TagTagController controller;

  @override
  State<_OperationLogDialog> createState() => _OperationLogDialogState();
}

class _OperationLogDialogState extends State<_OperationLogDialog> {
  late Future<List<ManagedOperation>> _operations;
  String? _error;
  String? _undoingId;

  @override
  void initState() {
    super.initState();
    _operations = widget.controller.listOperations();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('操作日志'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(
          children: [
            if (_error != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: FutureBuilder<List<ManagedOperation>>(
                future: _operations,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('读取操作日志失败：${snapshot.error}'));
                  }
                  final operations = snapshot.data ?? const [];
                  if (operations.isEmpty) {
                    return const Center(child: Text('还没有受管操作记录'));
                  }
                  return ListView.separated(
                    itemCount: operations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final operation = operations[index];
                      final undone = operation.undoneAt != null;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          operation.type == ManagedOperationType.importCopy
                              ? Icons.content_copy_outlined
                              : Icons.drive_file_move_outline,
                        ),
                        title: Text(
                          operation.type == ManagedOperationType.importCopy
                              ? '复制导入'
                              : '移动导入',
                        ),
                        subtitle: Text(
                          '${operation.sourcePath}\n存储根 / ${operation.destinationRelativePath}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: undone
                            ? const Text('已撤销')
                            : IconButton(
                                tooltip: '撤销此操作',
                                onPressed: _undoingId == null
                                    ? () => _undo(operation.id)
                                    : null,
                                icon: _undoingId == operation.id
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.undo),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _undo(String operationId) async {
    setState(() {
      _undoingId = operationId;
      _error = null;
    });
    try {
      await widget.controller.undoOperation(operationId);
      if (mounted) {
        setState(() {
          _undoingId = null;
          _operations = widget.controller.listOperations();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _undoingId = null;
          _error = '撤销失败：$error';
        });
      }
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.sell_outlined, color: Colors.white, size: 17),
    );
  }
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({required this.controller});

  final TagTagController controller;

  @override
  Widget build(BuildContext context) {
    final activeSpaceId = controller.activeSpaceId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: DropdownButtonFormField<String>(
            initialValue: activeSpaceId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.space_dashboard_outlined, size: 20),
            ),
            items: controller.state.spaces
                .map(
                  (space) => DropdownMenuItem(
                    value: space.id,
                    child: Text(space.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                unawaited(controller.selectSpace(value));
              }
            },
          ),
        ),
        _NavItem(
          icon: Icons.folder_copy_outlined,
          label: '全部资源',
          selected:
              controller.activePlacementId == null &&
              !controller.showRecent &&
              !controller.showInbox,
          onTap: () => controller.selectPlacement(null),
        ),
        _NavItem(
          icon: Icons.inbox_outlined,
          label: '待整理',
          selected: controller.showInbox,
          onTap: controller.showInboxResources,
        ),
        _NavItem(
          icon: Icons.history_outlined,
          label: '最近',
          selected: controller.showRecent,
          onTap: controller.showRecentResources,
        ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '标签层级',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Tooltip(
                message: '新建根标签',
                child: IconButton(
                  iconSize: 19,
                  onPressed: () => _home(context)?._showCreateTag(),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 10),
            children: controller.rootPlacements
                .map(
                  (placement) => _TagNode(
                    controller: controller,
                    placement: placement,
                    depth: 0,
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(height: 1),
        _CommonTags(controller: controller),
      ],
    );
  }

  _TagTagHomeState? _home(BuildContext context) =>
      context.findAncestorStateOfType<_TagTagHomeState>();
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      leading: Icon(icon, size: 19),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      onTap: onTap,
    );
  }
}

class _TagNode extends StatelessWidget {
  const _TagNode({
    required this.controller,
    required this.placement,
    required this.depth,
  });

  final TagTagController controller;
  final TagPlacement placement;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final tag = controller.tagForPlacement(placement);
    final children = controller.childrenOf(placement.id);
    final isActive = controller.activePlacementId == placement.id;
    final isReused =
        controller.placementsInActiveSpace
            .where((item) => item.tagId == placement.tagId)
            .length >
        1;
    final content = ListTile(
      dense: true,
      selected: isActive,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      contentPadding: EdgeInsets.only(left: 14 + depth * 18.0, right: 6),
      leading: _TagDot(colorValue: tag.colorValue),
      title: Row(
        children: [
          Expanded(child: Text(tag.name, overflow: TextOverflow.ellipsis)),
          if (isReused)
            const Tooltip(
              message: '该标签实体复用在多条路径中',
              child: Icon(Icons.link, size: 15),
            ),
        ],
      ),
      trailing: PopupMenuButton<_TagAction>(
        tooltip: '标签操作',
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (action) {
          final home = context.findAncestorStateOfType<_TagTagHomeState>();
          switch (action) {
            case _TagAction.addChild:
              unawaited(
                home?._showCreateTag(parentId: placement.id) ??
                    Future<void>.value(),
              );
              break;
            case _TagAction.edit:
              controller.selectPlacement(placement.id);
              unawaited(home?._editActiveTag() ?? Future<void>.value());
              break;
            case _TagAction.delete:
              controller.selectPlacement(placement.id);
              unawaited(home?._deleteActiveTag() ?? Future<void>.value());
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: _TagAction.addChild, child: Text('新建子标签')),
          PopupMenuItem(value: _TagAction.edit, child: Text('编辑标签实体')),
          PopupMenuItem(value: _TagAction.delete, child: Text('删除此位置')),
        ],
      ),
      onTap: () => controller.selectPlacement(placement.id),
    );
    if (children.isEmpty) {
      return content;
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: content,
      children: children
          .map(
            (child) => _TagNode(
              controller: controller,
              placement: child,
              depth: depth + 1,
            ),
          )
          .toList(),
    );
  }
}

enum _TagAction { addChild, edit, delete }

class _CommonTags extends StatelessWidget {
  const _CommonTags({required this.controller});

  final TagTagController controller;

  @override
  Widget build(BuildContext context) {
    final placements = controller.commonPlacements;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '常用标签',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          if (placements.isEmpty)
            const Text('标注后会出现在这里', style: TextStyle(fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: placements
                  .map(
                    (placement) => ActionChip(
                      avatar: _TagDot(
                        colorValue: controller
                            .tagForPlacement(placement)
                            .colorValue,
                        size: 10,
                      ),
                      label: Text(controller.tagForPlacement(placement).name),
                      onPressed: () => controller.selectPlacement(placement.id),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ResourceHeader extends StatelessWidget {
  const _ResourceHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      child: Row(
        children: [
          const SizedBox(width: 42),
          const Expanded(flex: 4, child: _ColumnLabel('名称')),
          if (!compact) const Expanded(flex: 3, child: _ColumnLabel('直接标签')),
          const Expanded(flex: 2, child: _ColumnLabel('修改时间')),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.resource,
    required this.selected,
    required this.compact,
    required this.tags,
    required this.controller,
    required this.onSelectionChanged,
    required this.onOpen,
    required this.onReveal,
  });

  final TagResource resource;
  final bool selected;
  final bool compact;
  final List<TagPlacement> tags;
  final TagTagController controller;
  final ValueChanged<bool> onSelectionChanged;
  final Future<void> Function() onOpen;
  final Future<void> Function() onReveal;

  @override
  Widget build(BuildContext context) {
    final isFolder = resource.kind == ResourceKind.folder;
    return Material(
      color: selected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.42)
          : Colors.transparent,
      child: InkWell(
        onTap: () => onSelectionChanged(!selected),
        onDoubleTap: () => unawaited(onOpen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Checkbox(
                  value: selected,
                  onChanged: (value) => onSelectionChanged(value ?? false),
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(
                      isFolder
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                      color: isFolder
                          ? const Color(0xffd97706)
                          : Theme.of(context).colorScheme.primary,
                      size: 21,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resource.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            resource.path,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                Expanded(
                  flex: 3,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: tags
                        .take(3)
                        .map(
                          (placement) => _PlacementChip(
                            label: controller.tagForPlacement(placement).name,
                            colorValue: controller
                                .tagForPlacement(placement)
                                .colorValue,
                            tooltip: controller.pathOf(placement.id),
                          ),
                        )
                        .toList(),
                  ),
                ),
              Expanded(
                flex: 2,
                child: Text(
                  _dateLabel(resource.modifiedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: PopupMenuButton<_ResourceAction>(
                  tooltip: '资源操作',
                  icon: const Icon(Icons.more_horiz, size: 19),
                  onSelected: (action) {
                    switch (action) {
                      case _ResourceAction.open:
                        unawaited(onOpen());
                        break;
                      case _ResourceAction.reveal:
                        unawaited(onReveal());
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ResourceAction.open,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.open_in_new),
                        title: Text('打开'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ResourceAction.reveal,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.folder_open_outlined),
                        title: Text('在资源管理器中定位'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResourceAction { open, reveal }

class _PlacementChip extends StatelessWidget {
  const _PlacementChip({
    required this.label,
    required this.colorValue,
    required this.tooltip,
  });

  final String label;
  final int colorValue;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 118),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Color(colorValue).withValues(alpha: 0.55)),
          color: Color(colorValue).withValues(alpha: 0.09),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TagDot(colorValue: colorValue, size: 8),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.colorValue, this.size = 13});

  final int colorValue;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: Color(colorValue), shape: BoxShape.circle),
  );
}

class _EmptyResourceState extends StatelessWidget {
  const _EmptyResourceState({required this.hasFilter, required this.onClear});

  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 34,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(hasFilter ? '没有符合当前条件的资源' : '这个空间还没有资源'),
          if (hasFilter) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('清除筛选')),
          ],
        ],
      ),
    );
  }
}

class _InspectorPane extends StatelessWidget {
  const _InspectorPane({
    required this.controller,
    required this.onQuickTag,
    required this.onClearTags,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final TagTagController controller;
  final VoidCallback onQuickTag;
  final VoidCallback onClearTags;
  final VoidCallback onEditTag;
  final VoidCallback onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final selectedResources = controller.state.resources
        .where(
          (resource) => controller.selectedResourceIds.contains(resource.id),
        )
        .toList();
    final activePlacement = controller.activePlacementId == null
        ? null
        : controller.state.placementById(controller.activePlacementId!);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedResources.isEmpty
                      ? '检查器'
                      : '已选 ${selectedResources.length} 项',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (activePlacement != null) ...[
                Tooltip(
                  message: '编辑标签实体',
                  child: IconButton(
                    onPressed: onEditTag,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                ),
                Tooltip(
                  message: '删除标签位置',
                  child: IconButton(
                    onPressed: onDeleteTag,
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ),
              ],
            ],
          ),
          if (activePlacement != null) ...[
            const SizedBox(height: 8),
            Text('当前标签路径', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 5),
            Text(controller.pathOf(activePlacement.id)),
            const Divider(height: 26),
          ],
          if (selectedResources.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  '选择资源后可查看和修改直接标签。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Text('直接标签', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectionTags(selectedResources),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onQuickTag,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('添加标签'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onClearTags,
              icon: const Icon(Icons.label_off_outlined, size: 18),
              label: const Text('清除直接标签'),
            ),
            const Divider(height: 28),
            Text('所选资源', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: selectedResources.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    selectedResources[index].name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  '普通标注只更新 TAGTAG 本地数据，不移动或重命名文件。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _selectionTags(List<TagResource> resources) {
    final placementIds = <String>{};
    for (final resource in resources) {
      placementIds.addAll(
        controller
            .assignmentsForResource(resource.id)
            .map((placement) => placement.id),
      );
    }
    if (placementIds.isEmpty) {
      return const [Text('没有直接标签', style: TextStyle(fontSize: 13))];
    }
    return placementIds
        .map((id) => controller.state.placementById(id))
        .map(
          (placement) => _PlacementChip(
            label: controller.tagForPlacement(placement).name,
            colorValue: controller.tagForPlacement(placement).colorValue,
            tooltip: controller.pathOf(placement.id),
          ),
        )
        .toList();
  }
}

class _QuickTagDialog extends StatefulWidget {
  const _QuickTagDialog({required this.controller});

  final TagTagController controller;

  @override
  State<_QuickTagDialog> createState() => _QuickTagDialogState();
}

class _QuickTagDialogState extends State<_QuickTagDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final placements = widget.controller.placementsInActiveSpace.where((
      placement,
    ) {
      final path = widget.controller.pathOf(placement.id).toLowerCase();
      return path.contains(query.toLowerCase());
    }).toList();
    return AlertDialog(
      title: Text('为 ${widget.controller.selectedResourceIds.length} 项添加标签'),
      content: SizedBox(
        width: 520,
        height: 410,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 19),
                hintText: '搜索标签路径',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: placements.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final placement = placements[index];
                  final tag = widget.controller.tagForPlacement(placement);
                  return ListTile(
                    dense: true,
                    leading: _TagDot(colorValue: tag.colorValue),
                    title: Text(tag.name),
                    subtitle: Text(widget.controller.pathOf(placement.id)),
                    trailing: const Icon(Icons.add),
                    onTap: () => Navigator.pop(context, placement.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({
    required this.title,
    required this.tags,
    this.initialName = '',
    this.initialColor = 0xff0f766e,
    this.allowReuse = true,
  });

  final String title;
  final List<TagDefinition> tags;
  final String initialName;
  final int initialColor;
  final bool allowReuse;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  static const colors = [
    0xff0f766e,
    0xff2563eb,
    0xff7c3aed,
    0xffb45309,
    0xffdc2626,
    0xff0369a1,
  ];

  late final TextEditingController _nameController;
  late int _colorValue;
  bool _reuse = false;
  String? _reuseTagId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _colorValue = widget.initialColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.allowReuse) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('复用已有标签实体'),
                subtitle: const Text('在另一条路径显示同一个标签'),
                value: _reuse,
                onChanged: (value) => setState(() {
                  _reuse = value;
                  _reuseTagId = null;
                }),
              ),
              const SizedBox(height: 8),
            ],
            if (_reuse)
              DropdownButtonFormField<String>(
                initialValue: _reuseTagId,
                decoration: const InputDecoration(labelText: '已有标签实体'),
                items: widget.tags
                    .map(
                      (tag) => DropdownMenuItem(
                        value: tag.id,
                        child: Text('${tag.name} (${tag.id.split('-').last})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _reuseTagId = value),
              )
            else ...[
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '标签名称'),
              ),
              const SizedBox(height: 16),
              const Text('颜色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: colors
                    .map(
                      (value) => Tooltip(
                        message: '选择颜色',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _colorValue = value),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(value),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _colorValue == value
                                    ? Colors.black
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_reuse && _reuseTagId == null) {
              return;
            }
            Navigator.pop(
              context,
              _TagDraft(
                name: _nameController.text,
                colorValue: _colorValue,
                reuseTagId: _reuse ? _reuseTagId : null,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.controller, required this.sources});

  final TagTagController controller;
  final List<FileSystemEntity> sources;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  ImportMode _mode = ImportMode.copy;
  String _targetDirectory = '';
  String? _targetError;
  final Set<String> _placementIds = {};

  @override
  Widget build(BuildContext context) {
    final placements = widget.controller.placementsInActiveSpace;
    return AlertDialog(
      title: Text('导入并标注 ${widget.sources.length} 个资源'),
      content: SizedBox(
        width: 620,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ImportMode>(
              segments: const [
                ButtonSegment(
                  value: ImportMode.copy,
                  icon: Icon(Icons.content_copy_outlined),
                  label: Text('复制'),
                ),
                ButtonSegment(
                  value: ImportMode.move,
                  icon: Icon(Icons.drive_file_move_outline),
                  label: Text('移动'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 18),
            Text('来源', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SizedBox(
              height: 88,
              child: ListView.builder(
                itemCount: widget.sources.length,
                itemBuilder: (context, index) {
                  final source = widget.sources[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      source is Directory
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                      size: 20,
                    ),
                    title: Text(
                      path.basename(source.path),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      source.path,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text('存储位置', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _chooseTargetDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(
                  _targetDirectory.isEmpty
                      ? '存储根目录'
                      : '存储根目录 / $_targetDirectory',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_targetError != null) ...[
              const SizedBox(height: 4),
              Text(
                _targetError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text('标签', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  _placementIds.isEmpty
                      ? '未选择，导入后进入待整理区'
                      : '已选择 ${_placementIds.length} 个路径',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: placements.isEmpty
                  ? const Center(child: Text('当前空间还没有标签'))
                  : ListView.builder(
                      itemCount: placements.length,
                      itemBuilder: (context, index) {
                        final placement = placements[index];
                        final tag = widget.controller.tagForPlacement(
                          placement,
                        );
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary: _TagDot(colorValue: tag.colorValue),
                          title: Text(tag.name),
                          subtitle: Text(
                            widget.controller.pathOf(placement.id),
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: _placementIds.contains(placement.id),
                          onChanged: (selected) => setState(() {
                            if (selected ?? false) {
                              _placementIds.add(placement.id);
                            } else {
                              _placementIds.remove(placement.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _ImportDraft(
              mode: _mode,
              targetDirectory: _targetDirectory,
              placementIds: Set.unmodifiable(_placementIds),
            ),
          ),
          icon: Icon(
            _mode == ImportMode.copy
                ? Icons.content_copy_outlined
                : Icons.drive_file_move_outline,
          ),
          label: Text(_mode == ImportMode.copy ? '复制并导入' : '移动并导入'),
        ),
      ],
    );
  }

  Future<void> _chooseTargetDirectory() async {
    final root = widget.controller.storageRoot;
    if (root == null) {
      setState(() => _targetError = '存储根尚未初始化');
      return;
    }
    final selected = await getDirectoryPath(
      initialDirectory: root.path,
      confirmButtonText: '选择存储位置',
      canCreateDirectories: true,
    );
    if (selected == null || !mounted) {
      return;
    }
    final normalizedRoot = path.normalize(root.path);
    final normalizedSelected = path.normalize(selected);
    if (!path.equals(normalizedRoot, normalizedSelected) &&
        !path.isWithin(normalizedRoot, normalizedSelected)) {
      setState(() => _targetError = '存储位置必须位于存储根目录内');
      return;
    }
    final relative = path.equals(normalizedRoot, normalizedSelected)
        ? ''
        : path.relative(normalizedSelected, from: normalizedRoot);
    setState(() {
      _targetDirectory = relative.replaceAll('\\', '/');
      _targetError = null;
    });
  }
}

class _TagDraft {
  const _TagDraft({
    required this.name,
    required this.colorValue,
    required this.reuseTagId,
  });

  final String name;
  final int colorValue;
  final String? reuseTagId;
}

enum _ImportSourceKind { files, folder }

class _ImportDraft {
  const _ImportDraft({
    required this.mode,
    required this.targetDirectory,
    required this.placementIds,
  });

  final ImportMode mode;
  final String targetDirectory;
  final Set<String> placementIds;
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
