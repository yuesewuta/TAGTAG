import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/tag_models.dart';
import '../platform/windows_close_behavior.dart';
import '../platform/windows_file_actions.dart';
import '../platform/windows_floating_drop_target.dart';
import '../platform/windows_quick_tag_hotkey.dart';
import '../services/space_portability.dart';
import '../state/tagtag_controller.dart';
import '../storage/managed_library.dart';
import 'glass.dart';
import 'prototype_dialogs.dart';
import 'prototype_workspace.dart';
import 'tagtag_theme.dart';

class TagTagHome extends StatefulWidget {
  const TagTagHome({
    super.key,
    required this.controller,
    required this.fileActions,
    required this.onRestoreGlobalBackup,
    this.quickTagHotkey,
    this.floatingDropTarget,
    this.initialExternalQuickTagPaths = const [],
  });

  final TagTagController controller;
  final WindowsFileActions fileActions;
  final Future<void> Function(Directory backup, Directory targetRoot)
  onRestoreGlobalBackup;
  final WindowsQuickTagHotkey? quickTagHotkey;
  final WindowsFloatingDropTarget? floatingDropTarget;
  final List<String> initialExternalQuickTagPaths;

  @override
  State<TagTagHome> createState() => _TagTagHomeState();
}

class _TagTagHomeState extends State<TagTagHome> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final WindowsQuickTagHotkey _quickTagHotkey;
  late final WindowsFloatingDropTarget _floatingDropTarget;
  late final WindowsCloseBehavior _closeBehavior;
  bool _dragging = false;
  int _draggingCount = 0;
  bool _importDialogOpen = false;
  bool _scanningConsistency = false;
  bool _restoringBackup = false;
  bool _portabilityBusy = false;
  late String _appearanceTheme;
  late String _interfaceDensity;
  bool? _quickTagRegistered;
  List<ConsistencyFinding> _consistencyFindings = const [];
  Timer? _consistencyTimer;

  TagTagController get controller => widget.controller;

  // Context below the appearance Theme override; dialog routes are inserted
  // into the root navigator, so calls must start from here to keep the
  // selected brightness.
  late BuildContext _dialogContext;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: controller.searchTerm);
    _searchFocusNode = FocusNode();
    _appearanceTheme = controller.preferences.appearanceTheme;
    _interfaceDensity = controller.preferences.interfaceDensity;
    _quickTagHotkey = widget.quickTagHotkey ?? WindowsQuickTagHotkey();
    _floatingDropTarget =
        widget.floatingDropTarget ?? WindowsFloatingDropTarget();
    _floatingDropTarget.start(
      (x, y) =>
          controller.updatePreferences(floatingTargetX: x, floatingTargetY: y),
    );
    _closeBehavior = WindowsCloseBehavior();
    unawaited(
      _closeBehavior.setCloseToTray(controller.preferences.closeToTray),
    );
    unawaited(_configureGlobalQuickTag());
    unawaited(_configureFloatingDropTarget());
    if (widget.initialExternalQuickTagPaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            _handleExternalQuickTagPaths(widget.initialExternalQuickTagPaths),
          );
        }
      });
    }
    unawaited(_scanConsistency());
    _consistencyTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_scanConsistency()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _consistencyTimer?.cancel();
    unawaited(_quickTagHotkey.dispose());
    unawaited(_floatingDropTarget.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _appearanceTheme == 'dark'
        ? Brightness.dark
        : Brightness.light;
    return Theme(
      data: buildTagTagTheme(brightness: brightness),
      child: Builder(
        builder: (themedContext) {
          _dialogContext = themedContext;
          return CallbackShortcuts(
            bindings: {
              _quickTagActivator(controller.preferences.quickTagShortcut):
                  _showQuickTag,
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _focusSearch,
            },
            child: Scaffold(
              body: DropTarget(
                enable: !_importDialogOpen,
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (details) {
                  setState(() {
                    _dragging = false;
                    _draggingCount = details.files.length;
                  });
                  unawaited(
                    _handleDroppedPaths(details.files.map((item) => item.path)),
                  );
                },
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => PrototypeWorkspace(
                    controller: controller,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    comfortableDensity: _interfaceDensity == 'comfortable',
                    dragging: _dragging,
                    draggingCount: _draggingCount,
                    consistencyFindings: _consistencyFindings,
                    onQuickTag: _showQuickTag,
                    onImport: () =>
                        _chooseImportSource(_ImportSourceKind.files),
                    onImportFolder: () =>
                        _chooseImportSource(_ImportSourceKind.folder),
                    onCreateSpace: _showCreateSpace,
                    onOpenConsistency: _showConsistencyFindings,
                    onSettings: _showSettings,
                    onCreateBackup: _createBackup,
                    onOpenResource: _openResource,
                    onRevealResource: _revealResource,
                    onAddTag: _addTagToResource,
                    onClearTags: _clearTagsForResource,
                    onRestoreResource: _restoreResource,
                    onMoveResource: _moveResourceToSpecifiedPath,
                    onRecycleResource: _recycleResource,
                    onCreateTag: (parentId) =>
                        _showCreateTag(parentId: parentId),
                    onEditTag: (placementId) async {
                      controller.selectPlacement(placementId);
                      await _editActiveTag();
                    },
                    onMergeTag: _showMergeTag,
                    onSplitTag: _showSplitTag,
                    onDeleteTag: (placementId) async {
                      controller.selectPlacement(placementId);
                      await _deleteActiveTag();
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _focusSearch() {
    controller.showSearchResources();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _showSettings() async {
    final previousTheme = _appearanceTheme;
    final previousDensity = _interfaceDensity;
    final result = await showPrototypeDialog<PrototypeSettingsResult>(
      context: _dialogContext,
      builder: (context) => PrototypeSettingsDialog(
        controller: controller,
        quickTagRegistered: _quickTagRegistered,
        onRevealStorageRoot: _revealStorageRoot,
        onCreateBackup: _createBackup,
        onRestoreBackup: _restoreGlobalBackup,
        onExportSpacePackage: () =>
            _exportSpaceArchive(SpaceArchiveKind.package),
        onImportSpacePackage: () =>
            _importSpaceArchive(SpaceArchiveKind.package),
        onExportSpaceTemplate: () =>
            _exportSpaceArchive(SpaceArchiveKind.template),
        onImportSpaceTemplate: () =>
            _importSpaceArchive(SpaceArchiveKind.template),
        portabilityBusy: _restoringBackup || _portabilityBusy,
        onAppearancePreview: (theme, density) => setState(() {
          _appearanceTheme = theme;
          _interfaceDensity = density;
        }),
      ),
    );
    if (result == null) {
      setState(() {
        _appearanceTheme = previousTheme;
        _interfaceDensity = previousDensity;
      });
      return;
    }
    final shortcutChanged =
        result.quickTagShortcut != controller.preferences.quickTagShortcut;
    final shortcutRegistered = shortcutChanged
        ? await _quickTagHotkey.setShortcut(result.quickTagShortcut)
        : _quickTagRegistered;
    await controller.updatePreferences(
      moveImportsByDefault: result.moveImportsByDefault,
      floatingDropTargetEnabled: result.floatingDropTargetEnabled,
      closeToTray: result.closeToTray,
      startupView: result.startupView,
      appearanceTheme: result.appearanceTheme,
      interfaceDensity: result.interfaceDensity,
      uniqueTagNames: result.uniqueTagNames,
      quickTagShortcut: shortcutRegistered == false
          ? controller.preferences.quickTagShortcut
          : result.quickTagShortcut,
    );
    final floatingTargetEnabled = await _applyFloatingDropTarget(
      result.floatingDropTargetEnabled,
    );
    unawaited(_closeBehavior.setCloseToTray(result.closeToTray));
    if (mounted) {
      setState(() {
        _appearanceTheme = result.appearanceTheme;
        _interfaceDensity = result.interfaceDensity;
        _quickTagRegistered = shortcutRegistered;
      });
      _showMessage(
        shortcutRegistered == false
            ? '设置已保存，但新的 Quick Tag 快捷键已被占用，继续使用原快捷键。'
            : floatingTargetEnabled == false && result.floatingDropTargetEnabled
            ? '设置已保存，但悬浮接收目标未能启动。'
            : '设置已保存。',
        error:
            shortcutRegistered == false ||
            floatingTargetEnabled == false && result.floatingDropTargetEnabled,
      );
    }
  }

  Future<void> _revealStorageRoot() async {
    final root = controller.storageRoot;
    if (root == null) {
      _showMessage('存储根尚未初始化。', error: true);
      return;
    }
    try {
      await widget.fileActions.reveal(root.path);
    } catch (error) {
      if (mounted) {
        _showMessage('打开存储根失败：$error', error: true);
      }
    }
  }

  Future<void> _openResource(TagResource resource) async {
    try {
      await widget.fileActions.open(resource.path);
      await controller.recordOpen(resource.id);
    } catch (error) {
      if (mounted) {
        _showMessage('打开失败：$error', error: true);
      }
    }
  }

  Future<void> _addTagToResource(TagResource resource) async {
    controller.selectResource(resource.id);
    await _showQuickTag();
  }

  Future<void> _clearTagsForResource(TagResource resource) async {
    controller.selectResource(resource.id);
    await _clearTags();
  }

  Future<void> _restoreResource(TagResource resource) async {
    controller.selectResource(resource.id);
    await _restoreSelectedToOriginalPath();
  }

  Future<void> _moveResourceToSpecifiedPath(TagResource resource) async {
    var directoryPath = await getDirectoryPath(
      confirmButtonText: '移动到此文件夹',
      canCreateDirectories: true,
    );
    while (directoryPath != null) {
      final selectedDirectory = directoryPath;
      var destinationPath = path.join(selectedDirectory, resource.name);
      while (await FileSystemEntity.type(destinationPath) !=
          FileSystemEntityType.notFound) {
        if (!mounted) {
          return;
        }
        final choice = await showPrototypeDialog<_MoveConflictChoice>(
          context: _dialogContext,
          builder: (context) => AlertDialog(
            title: const Text('目标位置存在同名资源'),
            content: Text(
              '“${path.basename(destinationPath)}”已存在，TAGTAG 不会覆盖。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _MoveConflictChoice.chooseOther),
                child: const Text('改到其他位置'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, _MoveConflictChoice.rename),
                child: const Text('重命名后放入'),
              ),
            ],
          ),
        );
        if (choice == null) {
          return;
        }
        if (choice == _MoveConflictChoice.chooseOther) {
          directoryPath = await getDirectoryPath(
            confirmButtonText: '移动到此文件夹',
            canCreateDirectories: true,
          );
          break;
        }
        final newName = await _showTextDialog(
          title: '重命名后放入',
          label: '新名称',
          actionLabel: '使用此名称',
        );
        if (newName == null) {
          return;
        }
        final cleanName = newName.trim();
        if (cleanName.isEmpty ||
            cleanName == '.' ||
            cleanName == '..' ||
            path.basename(cleanName) != cleanName) {
          _showMessage('请输入不包含路径分隔符的有效名称。', error: true);
          continue;
        }
        destinationPath = path.join(selectedDirectory, cleanName);
      }
      if (directoryPath == null) {
        return;
      }
      if (await FileSystemEntity.type(destinationPath) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      final confirmed = await _confirm(
        title: '移动到指定位置并退出管理？',
        message:
            '“${resource.name}”将移动到“$destinationPath”，并从 TAGTAG 删除标签和空间关系。',
        actionLabel: '移动并退出',
      );
      if (!confirmed) {
        return;
      }
      await _runAction(() async {
        await controller.moveResourceToSpecifiedPath(
          resource.id,
          destinationPath,
        );
      }, successMessage: '已移动到指定位置并退出 TAGTAG 管理。');
      return;
    }
  }

  Future<void> _recycleResource(TagResource resource) async {
    final confirmed = await _confirm(
      title: '移入 Windows 回收站并退出管理？',
      message:
          '“${resource.name}”将从 TAGTAG 删除标签和空间关系，并移入 Windows 回收站；清空系统回收站后将无法恢复。',
      actionLabel: '移入回收站',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await _runAction(() async {
      await controller.recycleResource(resource.id);
    }, successMessage: '已移入 Windows 回收站并退出 TAGTAG 管理。');
  }

  Future<void> _showQuickTag() async {
    if (controller.selectedResourceIds.isEmpty) {
      final visible = controller.visibleResources;
      final all = controller.state.resources;
      final fallback = visible.isNotEmpty
          ? visible.first
          : (all.isEmpty ? null : all.first);
      if (fallback == null) {
        _showMessage('资料库中还没有可标注的资源。');
        return;
      }
      controller.selectResource(fallback.id);
    }
    final result = await showPrototypeDialog<PrototypeQuickTagResult>(
      context: _dialogContext,
      builder: (context) => PrototypeQuickTagDialog(controller: controller),
    );
    if (result == null) {
      return;
    }
    await _runAction(() async {
      for (final placementId in result.placementIds) {
        await controller.assignPlacementToSelection(
          placementId,
          inheritChildren: result.inheritChildren,
        );
      }
    }, successMessage: '已添加 ${result.placementIds.length} 个标签。');
  }

  Future<void> _configureGlobalQuickTag() async {
    final registered = await _quickTagHotkey.start(
      _handleGlobalQuickTag,
      shortcut: controller.preferences.quickTagShortcut,
    );
    if (mounted) setState(() => _quickTagRegistered = registered);
    if (mounted && registered == false) {
      _showMessage('全局 Quick Tag 未能注册。Ctrl+Shift+T 可能已被其他程序占用。', error: true);
    }
  }

  Future<void> _configureFloatingDropTarget() async {
    final enabled = controller.preferences.floatingDropTargetEnabled;
    final applied = await _applyFloatingDropTarget(enabled);
    if (mounted && enabled && applied == false) {
      _showMessage('悬浮接收目标未能启动。', error: true);
    }
  }

  Future<bool?> _applyFloatingDropTarget(bool enabled) async {
    final x = controller.preferences.floatingTargetX;
    final y = controller.preferences.floatingTargetY;
    if (x != null && y != null) {
      await _floatingDropTarget.setPosition(x, y);
    }
    return _floatingDropTarget.setEnabled(enabled);
  }

  Future<void> _handleGlobalQuickTag(List<String> externalPaths) async {
    if (_importDialogOpen || _restoringBackup) {
      if (mounted && externalPaths.isNotEmpty) {
        _showMessage('当前操作尚未完成，请稍后再次使用 Explorer 右键添加标签。', error: true);
      }
      return;
    }
    if (externalPaths.isNotEmpty) {
      await _handleExternalQuickTagPaths(externalPaths);
      return;
    }
    if (controller.selectedResourceIds.isNotEmpty) {
      await _showQuickTag();
      return;
    }
    await _chooseImportSource(_ImportSourceKind.files);
  }

  Future<void> _handleExternalQuickTagPaths(List<String> externalPaths) async {
    final sources = <FileSystemEntity>[];
    final seenPaths = <String>{};
    for (final externalPath in externalPaths) {
      final normalizedPath = path.normalize(File(externalPath).absolute.path);
      if (!seenPaths.add(normalizedPath)) {
        continue;
      }
      final type = await FileSystemEntity.type(normalizedPath);
      if (type == FileSystemEntityType.file) {
        sources.add(File(normalizedPath));
      } else if (type == FileSystemEntityType.directory) {
        sources.add(Directory(normalizedPath));
      }
    }
    if (sources.isEmpty) {
      if (mounted) {
        _showMessage('Explorer 所选资源已不存在，无法添加标签。', error: true);
      }
      return;
    }
    await _showImportDialog(sources);
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

  Future<void> _restoreSelectedToOriginalPath() async {
    if (controller.selectedResourceIds.length != 1) {
      _showMessage('恢复先前路径时一次只能选择一个资源。');
      return;
    }
    final resourceId = controller.selectedResourceIds.single;
    final resource = controller.state.resources.singleWhere(
      (item) => item.id == resourceId,
    );
    final confirmed = await _confirm(
      title: '恢复先前路径并退出管理？',
      message:
          '“${resource.name}”将移动到导入前的位置，并从 TAGTAG 删除标签和空间关系。'
          '目标存在同名资源时不会覆盖。',
      actionLabel: '恢复并退出',
    );
    if (!confirmed) {
      return;
    }
    await _runAction(() async {
      await controller.restoreResourceToOriginalPath(resourceId);
    }, successMessage: '已恢复到先前路径并退出 TAGTAG 管理。');
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
    final result = await showPrototypeDialog<PrototypeImportResult>(
      context: _dialogContext,
      builder: (context) => PrototypeImportDialog(
        controller: controller,
        sources: sources,
        initialMode: controller.preferences.moveImportsByDefault
            ? ImportMode.move
            : ImportMode.copy,
      ),
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
    final result = await showPrototypeDialog<_TagDraft>(
      context: _dialogContext,
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
    final result = await showPrototypeDialog<_TagDraft>(
      context: _dialogContext,
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

  Future<void> _showMergeTag(String placementId) async {
    final placement = controller.state.placementById(placementId);
    final sourceTag = controller.tagForPlacement(placement);
    final targets = controller.state.tags
        .where(
          (tag) =>
              tag.spaceId == controller.activeSpaceId && tag.id != sourceTag.id,
        )
        .toList();
    if (targets.isEmpty) {
      _showMessage('当前空间没有可作为合并目标的其他标签实体。', error: true);
      return;
    }
    final targetTagId = await showPrototypeDialog<String>(
      context: _dialogContext,
      builder: (context) => _MergeTagDialog(
        controller: controller,
        sourceTag: sourceTag,
        targets: targets,
      ),
    );
    if (targetTagId == null) {
      return;
    }
    await _runAction(() async {
      await controller.mergeTags(
        targetTagId: targetTagId,
        sourceTagIds: {sourceTag.id},
      );
    }, successMessage: '标签实体已合并。');
  }

  Future<void> _showSplitTag(String placementId) async {
    final placement = controller.state.placementById(placementId);
    final tag = controller.tagForPlacement(placement);
    final placements = controller.placementsInActiveSpace
        .where((item) => item.tagId == tag.id)
        .toList();
    if (placements.length < 2) {
      _showMessage('该标签实体只有一个位置，无需拆分。', error: true);
      return;
    }
    final draft = await showPrototypeDialog<_SplitTagDraft>(
      context: _dialogContext,
      builder: (context) => _SplitTagDialog(
        controller: controller,
        tag: tag,
        placements: placements,
        initialPlacementId: placementId,
      ),
    );
    if (draft == null) {
      return;
    }
    await _runAction(() async {
      await controller.splitTagPlacements(
        placementIds: draft.placementIds,
        newName: draft.name,
      );
    }, successMessage: '所选位置已拆分为独立标签实体。');
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

  Future<void> _restoreGlobalBackup() async {
    final backupPath = await getDirectoryPath(confirmButtonText: '选择完整备份目录');
    if (backupPath == null || !mounted) {
      return;
    }
    BackupValidationResult validation;
    try {
      validation = await controller.validateGlobalBackup(Directory(backupPath));
    } catch (error) {
      _showMessage('备份校验失败：$error', error: true);
      return;
    }
    final targetPath = await getDirectoryPath(
      initialDirectory: controller.storageRoot?.parent.path,
      confirmButtonText: '选择新的空存储根',
      canCreateDirectories: true,
    );
    if (targetPath == null || !mounted) {
      return;
    }
    final confirmed = await _confirm(
      title: '恢复完整备份？',
      message:
          '备份时间：${validation.createdAt.toLocal()}\n'
          '资源数量：${validation.resourceCount}\n'
          '新存储根：$targetPath\n\n'
          '只允许恢复到空目录。成功后 TAGTAG 将切换到新存储根。',
      actionLabel: '校验并恢复',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _restoringBackup = true);
    try {
      await widget.onRestoreGlobalBackup(
        validation.backupDirectory,
        Directory(targetPath),
      );
      if (mounted) {
        _showMessage('完整备份恢复成功。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _restoringBackup = false);
        _showMessage('恢复失败：$error', error: true);
      }
    }
  }

  Future<void> _exportSpaceArchive(SpaceArchiveKind kind) async {
    final activeSpace = controller.activeSpace;
    if (activeSpace == null) {
      _showMessage('请先创建或选择标签空间。', error: true);
      return;
    }
    final isPackage = kind == SpaceArchiveKind.package;
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final location = await getSaveLocation(
      suggestedName: isPackage
          ? 'tagtag-space-package-$timestamp.zip'
          : 'tagtag-space-template-$timestamp.zip',
      acceptedTypeGroups: [
        XTypeGroup(
          label: isPackage ? 'TAGTAG 空间包' : 'TAGTAG 空间模板',
          extensions: const ['zip'],
        ),
      ],
      confirmButtonText: isPackage ? '导出空间包' : '导出空间模板',
      canCreateDirectories: true,
    );
    if (location == null || !mounted) {
      return;
    }
    setState(() => _portabilityBusy = true);
    try {
      final destination = File(location.path);
      final exported = isPackage
          ? await controller.exportActiveSpacePackage(destination)
          : await controller.exportActiveSpaceTemplate(destination);
      if (mounted) {
        _showMessage(
          isPackage ? '空间包已导出到：${exported.path}' : '空间模板已导出到：${exported.path}',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          isPackage ? '空间包导出失败：$error' : '空间模板导出失败：$error',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _portabilityBusy = false);
      }
    }
  }

  Future<void> _importSpaceArchive(SpaceArchiveKind expectedKind) async {
    final isPackage = expectedKind == SpaceArchiveKind.package;
    final selected = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: isPackage ? 'TAGTAG 空间包' : 'TAGTAG 空间模板',
          extensions: const ['zip'],
        ),
      ],
      confirmButtonText: isPackage ? '选择空间包' : '选择空间模板',
    );
    if (selected == null || !mounted) {
      return;
    }
    SpaceArchiveSummary summary;
    try {
      summary = await controller.inspectSpaceArchive(File(selected.path));
      if (summary.kind != expectedKind) {
        throw FormatException(isPackage ? '所选文件不是空间导出包' : '所选文件不是空间模板');
      }
    } catch (error) {
      _showMessage('归档校验失败：$error', error: true);
      return;
    }
    var targetDirectory = '';
    if (isPackage) {
      final root = controller.storageRoot;
      if (root == null) {
        _showMessage('存储根尚未初始化。', error: true);
        return;
      }
      final selectedTarget = await getDirectoryPath(
        initialDirectory: root.path,
        confirmButtonText: '选择空间包资源存储位置',
        canCreateDirectories: true,
      );
      if (selectedTarget == null || !mounted) {
        return;
      }
      final normalizedRoot = path.normalize(root.path);
      final normalizedTarget = path.normalize(selectedTarget);
      if (!path.equals(normalizedRoot, normalizedTarget) &&
          !path.isWithin(normalizedRoot, normalizedTarget)) {
        _showMessage('空间包资源必须导入到存储根目录内。', error: true);
        return;
      }
      targetDirectory = path.equals(normalizedRoot, normalizedTarget)
          ? ''
          : path
                .relative(normalizedTarget, from: normalizedRoot)
                .replaceAll('\\', '/');
    }
    final confirmed = await _confirm(
      title: isPackage ? '导入空间包？' : '从模板新建空间？',
      message: isPackage
          ? '来源空间：${summary.spaceName}\n'
                '导出时间：${summary.createdAt.toLocal()}\n'
                '标签数量：${summary.tagCount}\n'
                '资源数量：${summary.resourceCount}\n'
                '资源位置：存储根${targetDirectory.isEmpty ? '' : ' / $targetDirectory'}\n\n'
                '将校验全部文件并保留稳定资源 ID；不会覆盖已有资源。'
          : '模板空间：${summary.spaceName}\n'
                '导出时间：${summary.createdAt.toLocal()}\n'
                '标签数量：${summary.tagCount}\n\n'
                '将创建新的空间、标签和层级身份，不导入资源或历史。',
      actionLabel: isPackage ? '校验并导入' : '新建空间',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _portabilityBusy = true);
    try {
      await controller.importSpaceArchive(
        archiveFile: File(selected.path),
        expectedKind: expectedKind,
        targetDirectory: targetDirectory,
      );
      if (mounted) {
        _showMessage(isPackage ? '空间包导入成功。' : '已从模板新建空间。');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          isPackage ? '空间包导入失败：$error' : '空间模板导入失败：$error',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _portabilityBusy = false);
      }
    }
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
    final findings = await showPrototypeDialog<List<ConsistencyFinding>>(
      context: _dialogContext,
      barrierDismissible: false,
      builder: (context) => _ConsistencyDialog(
        controller: controller,
        initialFindings: _consistencyFindings,
      ),
    );
    if (findings != null && mounted) {
      setState(() => _consistencyFindings = findings);
    }
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
    return await showPrototypeDialog<bool>(
          context: _dialogContext,
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
    return showPrototypeDialog<String>(
      context: _dialogContext,
      builder: (context) => _TextPromptDialog(
        title: title,
        label: label,
        actionLabel: actionLabel,
      ),
    );
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          duration: const Duration(milliseconds: 2600),
          content: error
              ? Text(message)
              : Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 17,
                      color: Color(0xff80d2a5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(message)),
                  ],
                ),
        ),
      );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
  });

  final String title;
  final String label;
  final String actionLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _textController,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _textController.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _ConsistencyDialog extends StatefulWidget {
  const _ConsistencyDialog({
    required this.controller,
    required this.initialFindings,
  });

  final TagTagController controller;
  final List<ConsistencyFinding> initialFindings;

  @override
  State<_ConsistencyDialog> createState() => _ConsistencyDialogState();
}

class _ConsistencyDialogState extends State<_ConsistencyDialog> {
  late List<ConsistencyFinding> _findings;
  final Map<String, String> _candidateByResourceId = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _findings = widget.initialFindings;
  }

  @override
  Widget build(BuildContext context) {
    final untracked = _findings
        .where((finding) => finding.type == ConsistencyFindingType.untracked)
        .toList();
    return AlertDialog(
      title: const Text('存储一致性告警'),
      content: SizedBox(
        width: 760,
        height: 500,
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
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _findings.isEmpty
                  ? const Center(child: Text('当前没有存储一致性异常'))
                  : ListView.separated(
                      itemCount: _findings.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final finding = _findings[index];
                        return finding.type == ConsistencyFindingType.untracked
                            ? _buildUntrackedRow(finding)
                            : _buildMissingRow(finding, untracked);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _findings),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildUntrackedRow(ConsistencyFinding finding) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.add_to_drive_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发现未受管内容',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '存储根 / ${finding.relativePath}',
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _runAction(
                    () => widget.controller.takeOverUntracked(
                      finding.relativePath,
                    ),
                    '已接管该内容。',
                  ),
            icon: const Icon(Icons.add_task_outlined, size: 18),
            label: const Text('接管'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _moveUntrackedOut(finding),
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: const Text('移出'),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingRow(
    ConsistencyFinding finding,
    List<ConsistencyFinding> untracked,
  ) {
    final resourceId = finding.resourceId;
    final selected = resourceId == null
        ? null
        : _candidateByResourceId[resourceId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.link_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '受管资源被外部删除或移动',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '记录路径：存储根 / ${finding.relativePath}',
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (untracked.isEmpty)
                  Text(
                    '当前没有可配对的未受管内容',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '选择实际移动到的路径',
                      isDense: true,
                    ),
                    items: [
                      for (final candidate in untracked)
                        DropdownMenuItem(
                          value: candidate.relativePath,
                          child: Text(
                            '存储根 / ${candidate.relativePath}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy || resourceId == null
                        ? null
                        : (value) => setState(() {
                            if (value == null) {
                              _candidateByResourceId.remove(resourceId);
                            } else {
                              _candidateByResourceId[resourceId] = value;
                            }
                          }),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || resourceId == null || selected == null
                      ? null
                      : () => _runAction(
                          () => widget.controller.acceptExternalMove(
                            resourceId,
                            selected,
                          ),
                          '已接受资源的新路径。',
                        ),
                  icon: const Icon(Icons.link_outlined, size: 18),
                  label: const Text('接受新路径'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy || resourceId == null || selected == null
                      ? null
                      : () => _runAction(
                          () => widget.controller.restoreExternalMove(
                            resourceId,
                            selected,
                          ),
                          '已恢复到记录路径。',
                        ),
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: const Text('恢复记录路径'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _moveUntrackedOut(ConsistencyFinding finding) async {
    final destinationDirectory = await getDirectoryPath(
      initialDirectory: widget.controller.storageRoot?.parent.path,
      confirmButtonText: '移动到此目录',
      canCreateDirectories: true,
    );
    if (destinationDirectory == null) {
      return;
    }
    final destinationPath = path.join(
      destinationDirectory,
      path.posix.basename(finding.relativePath),
    );
    await _runAction(
      () => widget.controller.moveUntrackedOutside(
        finding.relativePath,
        destinationPath,
      ),
      '已将未受管内容移出存储根。',
    );
  }

  Future<void> _runAction(
    Future<Object?> Function() action,
    String successMessage,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh(showProgress: false);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh({bool showProgress = true}) async {
    if (showProgress) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final findings = await widget.controller.scanConsistency();
      if (!mounted) {
        return;
      }
      final validResourceIds = findings
          .where((finding) => finding.resourceId != null)
          .map((finding) => finding.resourceId!)
          .toSet();
      final validCandidates = findings
          .where((finding) => finding.type == ConsistencyFindingType.untracked)
          .map((finding) => finding.relativePath)
          .toSet();
      setState(() {
        _findings = findings;
        _candidateByResourceId.removeWhere(
          (resourceId, candidate) =>
              !validResourceIds.contains(resourceId) ||
              !validCandidates.contains(candidate),
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = '刷新失败：$error');
      }
    } finally {
      if (showProgress && mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _MergeTagDialog extends StatefulWidget {
  const _MergeTagDialog({
    required this.controller,
    required this.sourceTag,
    required this.targets,
  });

  final TagTagController controller;
  final TagDefinition sourceTag;
  final List<TagDefinition> targets;

  @override
  State<_MergeTagDialog> createState() => _MergeTagDialogState();
}

class _MergeTagDialogState extends State<_MergeTagDialog> {
  late String _targetTagId;
  TagIdentityImpact? _impact;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetTagId = widget.targets.first.id;
    _refreshImpact();
  }

  void _refreshImpact() {
    try {
      _impact = widget.controller.previewTagMerge(
        targetTagId: _targetTagId,
        sourceTagIds: {widget.sourceTag.id},
      );
      _error = null;
    } catch (error) {
      _impact = null;
      _error = '$error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('合并标签实体'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('来源：${widget.sourceTag.name}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _targetTagId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '保留的目标标签实体'),
              items: [
                for (final tag in widget.targets)
                  DropdownMenuItem(
                    value: tag.id,
                    child: Text('${tag.name}  ·  ${tag.id}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _targetTagId = value;
                  _refreshImpact();
                });
              },
            ),
            const SizedBox(height: 16),
            if (_impact case final impact?)
              _TagImpactSummary(impact: impact)
            else
              Text(
                _error ?? '无法计算影响',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: _impact == null
              ? null
              : () => Navigator.pop(context, _targetTagId),
          icon: const Icon(Icons.merge_type),
          label: const Text('确认合并'),
        ),
      ],
    );
  }
}

class _SplitTagDialog extends StatefulWidget {
  const _SplitTagDialog({
    required this.controller,
    required this.tag,
    required this.placements,
    required this.initialPlacementId,
  });

  final TagTagController controller;
  final TagDefinition tag;
  final List<TagPlacement> placements;
  final String initialPlacementId;

  @override
  State<_SplitTagDialog> createState() => _SplitTagDialogState();
}

class _SplitTagDialogState extends State<_SplitTagDialog> {
  late final TextEditingController _nameController;
  late final Set<String> _selectedPlacementIds;
  TagIdentityImpact? _impact;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tag.name);
    _selectedPlacementIds = {widget.initialPlacementId};
    _refreshImpact();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _refreshImpact() {
    try {
      _impact = widget.controller.previewTagSplit(_selectedPlacementIds);
      _error = null;
    } catch (error) {
      _impact = null;
      _error = '$error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('拆分标签位置'),
      content: SizedBox(
        width: 580,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '新标签实体名称'),
            ),
            const SizedBox(height: 12),
            Text(
              '拆分位置',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  for (final placement in widget.placements)
                    CheckboxListTile(
                      value: _selectedPlacementIds.contains(placement.id),
                      title: Text(widget.controller.pathOf(placement.id)),
                      subtitle: Text(placement.id),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (selected) {
                        setState(() {
                          if (selected ?? false) {
                            _selectedPlacementIds.add(placement.id);
                          } else {
                            _selectedPlacementIds.remove(placement.id);
                          }
                          _refreshImpact();
                        });
                      },
                    ),
                ],
              ),
            ),
            if (_impact case final impact?)
              _TagImpactSummary(impact: impact)
            else
              Text(
                _error ?? '无法计算影响',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: _impact == null
              ? null
              : () => Navigator.pop(
                  context,
                  _SplitTagDraft(
                    placementIds: Set.of(_selectedPlacementIds),
                    name: _nameController.text,
                  ),
                ),
          icon: const Icon(Icons.call_split),
          label: const Text('确认拆分'),
        ),
      ],
    );
  }
}

class _TagImpactSummary extends StatelessWidget {
  const _TagImpactSummary({required this.impact});

  final TagIdentityImpact impact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '影响预览',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Chip(label: Text('${impact.placementCount} 个标签位置')),
            Chip(label: Text('${impact.assignmentCount} 条直接标注')),
            Chip(label: Text('${impact.resourceCount} 个资源')),
            Chip(label: Text('${impact.inheritanceRuleCount} 条继承规则')),
          ],
        ),
      ],
    );
  }
}

class _SplitTagDraft {
  const _SplitTagDraft({required this.placementIds, required this.name});

  final Set<String> placementIds;
  final String name;
}

enum _MoveConflictChoice { rename, chooseOther }

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
              InkWell(
                onTap: () => setState(() {
                  _reuse = !_reuse;
                  _reuseTagId = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '复用已有标签实体',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '在另一条路径显示同一个标签',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      PillSwitch(
                        value: _reuse,
                        onChanged: (value) => setState(() {
                          _reuse = value;
                          _reuseTagId = null;
                        }),
                      ),
                    ],
                  ),
                ),
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

/// Builds the in-window Quick Tag binding from the stored preference string
/// (the same `Ctrl+Shift+T`-style format produced by the settings recorder).
SingleActivator _quickTagActivator(String shortcut) {
  const fallback = SingleActivator(
    LogicalKeyboardKey.keyT,
    control: true,
    shift: true,
  );
  final parts = shortcut
      .split('+')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return fallback;
  final key = _logicalKeyForShortcutLabel(parts.last);
  if (key == null) return fallback;
  var control = false;
  var alt = false;
  var shift = false;
  var meta = false;
  for (final part in parts.take(parts.length - 1)) {
    switch (part.toLowerCase()) {
      case 'ctrl':
        control = true;
      case 'alt':
        alt = true;
      case 'shift':
        shift = true;
      case 'win':
        meta = true;
    }
  }
  // The settings recorder requires at least one of Ctrl, Alt or Win.
  if (!control && !alt && !meta) return fallback;
  return SingleActivator(
    key,
    control: control,
    alt: alt,
    shift: shift,
    meta: meta,
  );
}

LogicalKeyboardKey? _logicalKeyForShortcutLabel(String label) {
  final upper = label.toUpperCase();
  if (upper.length == 1) {
    final code = upper.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      // Letter key ids use the lowercase code point.
      return LogicalKeyboardKey(code + 32);
    }
    if (code >= 48 && code <= 57) {
      return LogicalKeyboardKey(code);
    }
    return null;
  }
  final functionMatch = RegExp(r'^F([1-9]|1[0-2])$').firstMatch(upper);
  if (functionMatch != null) {
    const functionKeys = [
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f2,
      LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4,
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7,
      LogicalKeyboardKey.f8,
      LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f10,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.f12,
    ];
    return functionKeys[int.parse(functionMatch.group(1)!) - 1];
  }
  return null;
}
