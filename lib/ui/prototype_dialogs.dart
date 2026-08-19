import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/tag_models.dart';
import '../services/scheduled_backup.dart';
import '../state/tagtag_controller.dart';
import '../storage/managed_library.dart';
import 'app_toast.dart';
import 'glass.dart';
import 'tagtag_theme.dart';

/// Shows a modal with Liquid Glass motion: 160ms fade plus a springy
/// 0.92 → 1.0 scale (easeOutBack). Honors reduced motion via
/// MediaQuery.disableAnimations.
Future<T?> showPrototypeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  // Dialog routes live on the root navigator, above the home screen's Theme
  // override (dark/light selection). Capture the caller's theme so dialogs
  // follow the selected appearance.
  final theme = Theme.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    barrierColor: const Color(0x7a10161f),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Theme(data: theme, child: builder(context)),
    transitionBuilder: (context, animation, _, child) {
      if (reduceMotion) return child;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 160 / 220),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      );
    },
  );
}

class PrototypeQuickTagResult {
  const PrototypeQuickTagResult({
    required this.placementIds,
    required this.inheritChildren,
  });

  final Set<String> placementIds;
  final bool? inheritChildren;
}

class PrototypeQuickTagDialog extends StatefulWidget {
  const PrototypeQuickTagDialog({
    super.key,
    required this.controller,
    this.editResourceId,
  });

  final TagTagController controller;

  /// When set, the dialog runs in 修改标签 mode for this resource: its current
  /// direct placements are pre-checked (instead of the first placement) and
  /// confirming returns the full desired placement set, so the caller can
  /// unassign the placements that were toggled off.
  final String? editResourceId;

  @override
  State<PrototypeQuickTagDialog> createState() =>
      _PrototypeQuickTagDialogState();
}

class _PrototypeQuickTagDialogState extends State<PrototypeQuickTagDialog> {
  final _queryController = TextEditingController();
  final Set<String> _selectedPlacementIds = {};
  bool _inheritChildren = false;

  bool get _isEditMode => widget.editResourceId != null;

  @override
  void initState() {
    super.initState();
    final editResourceId = widget.editResourceId;
    if (editResourceId != null) {
      _selectedPlacementIds.addAll(
        widget.controller
            .assignmentsForResource(editResourceId)
            .map((placement) => placement.id),
      );
    } else {
      final placements = widget.controller.placementsInActiveSpace;
      if (placements.isNotEmpty) _selectedPlacementIds.add(placements.first.id);
    }
    final folder = widget.controller.selectedFolderForInheritance;
    if (folder != null) {
      _inheritChildren = widget.controller.state.folderTagInheritances.any(
        (rule) => rule.folderResourceId == folder.id,
      );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final allPlacements = widget.controller.placementsInActiveSpace;
    final common = widget.controller.commonPlacements;
    final placements = query.isEmpty
        ? (_isEditMode
              ? allPlacements
              : (common.isEmpty ? allPlacements : common))
        : allPlacements.where((placement) {
            final tag = widget.controller.tagForPlacement(placement);
            return '${tag.name} ${widget.controller.pathOf(placement.id)}'
                .toLowerCase()
                .contains(query);
          }).toList();
    final canInherit = widget.controller.selectedFolderForInheritance != null;
    return PrototypeDialogFrame(
      width: 560,
      desktopHeight: null,
      icon: Icons.sell_outlined,
      title: _isEditMode ? '修改标签' : '快速标注',
      subtitle:
          '${widget.controller.selectedResourceIds.length} 个资源 · ${widget.controller.activeSpace?.name ?? '标签空间'}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _queryController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索标签名称或路径',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isEditMode ? '全部标签' : '常用标签',
                style: _sectionLabelStyle(context),
              ),
            ),
          ),
          Flexible(
            child: placements.isEmpty
                ? SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        '没有匹配的标签',
                        style: TextStyle(color: _muted(context)),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: placements.length,
                    itemExtent: 51,
                    itemBuilder: (context, index) {
                      final placement = placements[index];
                      final tag = widget.controller.tagForPlacement(placement);
                      return PrototypeTagOption(
                        key: ValueKey('quick-tag-${placement.id}'),
                        name: tag.name,
                        path: widget.controller.pathOf(placement.id),
                        color: Color(tag.colorValue),
                        selected: _selectedPlacementIds.contains(placement.id),
                        onTap: () => setState(() {
                          if (!_selectedPlacementIds.add(placement.id)) {
                            _selectedPlacementIds.remove(placement.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _border(context))),
              ),
              child: InkWell(
                onTap: canInherit
                    ? () => setState(() => _inheritChildren = !_inheritChildren)
                    : () => AppToast.show('选择一个文件夹后可启用子项继承'),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 18,
                      color: _muted(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '子项继承',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            canInherit
                                ? '应用到文件夹中的当前和未来子项'
                                : '选择一个文件夹后可应用到当前和未来子项',
                            style: TextStyle(
                              fontSize: 11,
                              color: _muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PillSwitch(
                      value: canInherit && _inheritChildren,
                      onChanged: canInherit
                          ? (value) => setState(() => _inheritChildren = value)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        GlassPrimaryButton.icon(
          onPressed: _selectedPlacementIds.isEmpty && !_isEditMode
              ? null
              : () => Navigator.pop(
                  context,
                  PrototypeQuickTagResult(
                    placementIds: Set.unmodifiable(_selectedPlacementIds),
                    inheritChildren: canInherit ? _inheritChildren : null,
                  ),
                ),
          icon: const Icon(Icons.sell_outlined, size: 17),
          label: Text(
            _isEditMode ? '保存' : '添加 ${_selectedPlacementIds.length} 个标签',
          ),
        ),
      ],
    );
  }
}

class PrototypeImportResult {
  const PrototypeImportResult({
    required this.mode,
    required this.targetDirectory,
    required this.placementIds,
    required this.renamedSources,
    required this.sources,
  });

  final ImportMode mode;
  final String targetDirectory;
  final Set<String> placementIds;

  /// Rename plan produced by the 按模板重命名 toggle: source path → planned
  /// base name rendered from the global naming template. Empty when the
  /// batch imports with original names.
  final Map<String, String> renamedSources;

  /// The final source list after in-dialog removals/reselection; the import
  /// executor must iterate this list, not the originally picked sources.
  final List<FileSystemEntity> sources;
}

enum _ImportReselectKind { files, folder }

class PrototypeImportDialog extends StatefulWidget {
  const PrototypeImportDialog({
    super.key,
    required this.controller,
    required this.sources,
    required this.initialMode,
  });

  final TagTagController controller;
  final List<FileSystemEntity> sources;
  final ImportMode initialMode;

  @override
  State<PrototypeImportDialog> createState() => _PrototypeImportDialogState();
}

class _PrototypeImportDialogState extends State<PrototypeImportDialog> {
  late ImportMode _mode;
  late List<FileSystemEntity> _sources;
  final _tagQueryController = TextEditingController();
  final Set<String> _placementIds = {};
  String _targetDirectory = '';
  String? _targetError;
  bool _renameWithTemplate = true;

  /// Per-source final import names resolved against the target directory
  /// (same-name conflicts auto-rename to `name (2).ext`); keyed by source
  /// path and refreshed whenever the sources, tags, mode or target change.
  Map<String, String> _expectedNames = const {};

  String get _namingTemplate => widget.controller.preferences.namingTemplate;

  bool get _renameAvailable => _namingTemplate.trim().isNotEmpty;

  List<String> get _selectedTagNames => [
    for (final placement in widget.controller.placementsInActiveSpace)
      if (_placementIds.contains(placement.id))
        widget.controller.tagForPlacement(placement).name,
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _sources = [...widget.sources];
    unawaited(_refreshExpectedNames());
  }

  @override
  void dispose() {
    _tagQueryController.dispose();
    super.dispose();
  }

  String? get _renamePreview {
    if (!_renameAvailable || !_renameWithTemplate || _sources.isEmpty) {
      return null;
    }
    return TagTagController.applyNamingTemplate(
      template: _namingTemplate,
      sourceName: path.basename(_sources.first.path),
      importDate: DateTime.now(),
      tagNames: _selectedTagNames,
      index: 1,
    );
  }

  Map<String, String> _buildRenamePlan() {
    if (!_renameAvailable || !_renameWithTemplate) {
      return const {};
    }
    final now = DateTime.now();
    final tagNames = _selectedTagNames;
    return {
      for (var index = 0; index < _sources.length; index++)
        _sources[index].path: TagTagController.applyNamingTemplate(
          template: _namingTemplate,
          sourceName: path.basename(_sources[index].path),
          importDate: now,
          tagNames: tagNames,
          index: index + 1,
        ),
    };
  }

  /// Sources whose final import name differs from the desired name (target
  /// directory conflict or an earlier source of the same batch), mapped to
  /// the resolved name so the rename is never silent.
  Map<String, String> get _renameAnnotations {
    final plan = _buildRenamePlan();
    final annotations = <String, String>{};
    for (final source in _sources) {
      final expected = _expectedNames[source.path];
      if (expected == null) {
        continue;
      }
      final desired = plan[source.path] ?? path.basename(source.path);
      if (expected != desired) {
        annotations[source.path] = expected;
      }
    }
    return annotations;
  }

  /// Resolves each source's final import name through the same library
  /// helper the real import uses, claiming earlier results so batch-internal
  /// duplicates resolve exactly like the sequential imports would.
  Future<void> _refreshExpectedNames() async {
    final library = widget.controller.library;
    if (library == null) {
      return;
    }
    final plan = _buildRenamePlan();
    final expected = <String, String>{};
    final claimed = <String>{};
    final tagNames = [
      for (final placementId in _placementIds.take(1))
        widget.controller
            .tagForPlacement(widget.controller.state.placementById(placementId))
            .name,
    ];
    for (final source in _sources) {
      final resolved = await library.expectedImportName(
        _targetDirectory,
        plan[source.path] ?? path.basename(source.path),
        isFolder: source is Directory,
        tagNames: tagNames,
        importDate: DateTime.now(),
        extraOccupiedNames: claimed,
      );
      expected[source.path] = resolved;
      claimed.add(resolved);
    }
    if (mounted) {
      setState(() => _expectedNames = expected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _tagQueryController.text.trim().toLowerCase();
    final placements = widget.controller.placementsInActiveSpace.where((item) {
      final tag = widget.controller.tagForPlacement(item);
      return query.isEmpty ||
          '${tag.name} ${widget.controller.pathOf(item.id)}'
              .toLowerCase()
              .contains(query);
    }).toList();
    final targetLabel = _targetDirectory.isEmpty
        ? '存储根目录'
        : _targetDirectory.replaceAll('/', ' / ');
    return PrototypeDialogFrame(
      width: 900,
      desktopHeight: 660,
      icon: Icons.file_upload_outlined,
      title: '导入并标注',
      subtitle: '${_sources.length} 个资源 · ${_sourceSizeLabel(_sources)}',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final main = _ImportMain(
            controller: widget.controller,
            sources: _sources,
            placements: placements,
            selectedPlacementIds: _placementIds,
            tagQueryController: _tagQueryController,
            targetLabel: targetLabel,
            targetError: _targetError,
            renameAnnotations: _renameAnnotations,
            onRemoveSource: (source) {
              setState(() => _sources.remove(source));
              unawaited(_refreshExpectedNames());
            },
            onReselect: _reselect,
            onReselectFolder: _reselectFolder,
            onChooseDestination: _chooseTargetDirectory,
            onQueryChanged: () => setState(() {}),
            onTogglePlacement: (placementId) {
              setState(() {
                if (!_placementIds.add(placementId)) {
                  _placementIds.remove(placementId);
                }
              });
              unawaited(_refreshExpectedNames());
            },
          );
          final summary = _ImportSummary(
            mode: _mode,
            sourceCount: _sources.length,
            targetLabel: targetLabel,
            selectedTags: [
              for (final placement in widget.controller.placementsInActiveSpace)
                if (_placementIds.contains(placement.id))
                  widget.controller.tagForPlacement(placement).name,
            ],
            onModeChanged: (mode) => setState(() => _mode = mode),
            renameAvailable: _renameAvailable,
            renameWithTemplate: _renameWithTemplate,
            renamePreview: _renamePreview,
            onRenameChanged: (value) {
              setState(() => _renameWithTemplate = value);
              unawaited(_refreshExpectedNames());
            },
          );
          if (compact) {
            return ListView(
              children: [
                SizedBox(height: 470, child: main),
                summary,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: main),
              SizedBox(width: 250, child: summary),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        GlassPrimaryButton.icon(
          onPressed: _sources.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  PrototypeImportResult(
                    mode: _mode,
                    targetDirectory: _targetDirectory,
                    placementIds: Set.unmodifiable(_placementIds),
                    renamedSources: Map.unmodifiable(_buildRenamePlan()),
                    sources: List.unmodifiable(_sources),
                  ),
                ),
          icon: Icon(
            _mode == ImportMode.copy
                ? Icons.content_copy_outlined
                : Icons.drive_file_move_outline,
            size: 17,
          ),
          label: Text(_mode == ImportMode.copy ? '复制并导入' : '移动并导入'),
        ),
      ],
    );
  }

  Future<void> _reselect() async {
    final selected = await openFiles(confirmButtonText: '导入所选文件');
    if (!mounted || selected.isEmpty) return;
    setState(() => _sources = selected.map((item) => File(item.path)).toList());
    unawaited(_refreshExpectedNames());
  }

  Future<void> _reselectFolder() async {
    final selected = await getDirectoryPath(confirmButtonText: '导入此文件夹');
    if (selected == null || !mounted) return;
    setState(() => _sources = [Directory(selected)]);
    unawaited(_refreshExpectedNames());
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
    if (selected == null || !mounted) return;
    final normalizedRoot = path.normalize(root.path);
    final normalizedSelected = path.normalize(selected);
    if (!path.equals(normalizedRoot, normalizedSelected) &&
        !path.isWithin(normalizedRoot, normalizedSelected)) {
      setState(() => _targetError = '存储位置必须位于存储根目录内');
      return;
    }
    setState(() {
      _targetDirectory = path.equals(normalizedRoot, normalizedSelected)
          ? ''
          : path
                .relative(normalizedSelected, from: normalizedRoot)
                .replaceAll('\\', '/');
      _targetError = null;
    });
    unawaited(_refreshExpectedNames());
  }
}

class _ImportMain extends StatelessWidget {
  const _ImportMain({
    required this.controller,
    required this.sources,
    required this.placements,
    required this.selectedPlacementIds,
    required this.tagQueryController,
    required this.targetLabel,
    required this.targetError,
    required this.renameAnnotations,
    required this.onRemoveSource,
    required this.onReselect,
    required this.onReselectFolder,
    required this.onChooseDestination,
    required this.onQueryChanged,
    required this.onTogglePlacement,
  });

  final TagTagController controller;
  final List<FileSystemEntity> sources;
  final List<TagPlacement> placements;
  final Set<String> selectedPlacementIds;
  final TextEditingController tagQueryController;
  final String targetLabel;
  final String? targetError;
  final Map<String, String> renameAnnotations;
  final ValueChanged<FileSystemEntity> onRemoveSource;
  final Future<void> Function() onReselect;
  final Future<void> Function() onReselectFolder;
  final Future<void> Function() onChooseDestination;
  final VoidCallback onQueryChanged;
  final ValueChanged<String> onTogglePlacement;

  @override
  Widget build(BuildContext context) {
    final rootPath = controller.storageRoot?.path ?? '存储根尚未初始化';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        children: [
          _ImportSection(
            label: '来源',
            action: PopupMenuButton<_ImportReselectKind>(
              popUpAnimationStyle: quickPopupAnimationStyle,
              tooltip: '重新选择',
              onSelected: (kind) => unawaited(
                kind == _ImportReselectKind.files
                    ? onReselect()
                    : onReselectFolder(),
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ImportReselectKind.files,
                  child: Text('重新选择文件'),
                ),
                PopupMenuItem(
                  value: _ImportReselectKind.folder,
                  child: Text('重新选择文件夹'),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '重新选择',
                    style: TextStyle(color: _primary(context), fontSize: 13),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: _primary(context),
                  ),
                ],
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 112),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sources.length,
                itemExtent: 48,
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final folder = source is Directory;
                  final annotation = renameAnnotations[source.path];
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _border(context)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _DialogFileIcon(
                          folder: folder,
                          name: path.basename(source.path),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: path.basename(source.path),
                                  children: [
                                    if (annotation != null)
                                      TextSpan(
                                        text: ' → $annotation',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: _primary(context),
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                path.dirname(source.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '移除',
                          onPressed: () => onRemoveSource(source),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          _ImportSection(
            label: '存储位置',
            child: Column(
              children: [
                InkWell(
                  onTap: () => unawaited(onChooseDestination()),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _subtle(context),
                      border: Border.all(color: _border(context)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 20,
                          color: _primary(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                targetLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _joinRoot(rootPath, targetLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 17),
                      ],
                    ),
                  ),
                ),
                if (targetError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        targetError!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: TagTagColors.destructive,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _ImportSection(
              label: '标签',
              value: '已选择 ${selectedPlacementIds.length} 个',
              expandChild: true,
              child: Column(
                children: [
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: tagQueryController,
                      autofocus: true,
                      onChanged: (_) => onQueryChanged(),
                      decoration: const InputDecoration(
                        hintText: '搜索标签',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 430 ? 2 : 1;
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: 50,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 3,
                              ),
                          itemCount: placements.length,
                          itemBuilder: (context, index) {
                            final placement = placements[index];
                            final tag = controller.tagForPlacement(placement);
                            return PrototypeTagOption(
                              name: tag.name,
                              path: controller.pathOf(placement.id),
                              color: Color(tag.colorValue),
                              selected: selectedPlacementIds.contains(
                                placement.id,
                              ),
                              onTap: () => onTogglePlacement(placement.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportSection extends StatelessWidget {
  const _ImportSection({
    required this.label,
    required this.child,
    this.action,
    this.value,
    this.expandChild = false,
  });

  final String label;
  final Widget child;
  final Widget? action;
  final String? value;
  final bool expandChild;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: [
              Text(label, style: _sectionLabelStyle(context)),
              const Spacer(),
              if (value != null)
                Text(value!, style: _sectionLabelStyle(context)),
              ?action,
            ],
          ),
        ),
        if (expandChild) Expanded(child: child) else child,
      ],
    ),
  );
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({
    required this.mode,
    required this.sourceCount,
    required this.targetLabel,
    required this.selectedTags,
    required this.onModeChanged,
    required this.renameAvailable,
    required this.renameWithTemplate,
    required this.renamePreview,
    required this.onRenameChanged,
  });

  final ImportMode mode;
  final int sourceCount;
  final String targetLabel;
  final List<String> selectedTags;
  final ValueChanged<ImportMode> onModeChanged;
  final bool renameAvailable;
  final bool renameWithTemplate;
  final String? renamePreview;
  final ValueChanged<bool> onRenameChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _subtle(context),
      border: Border(left: BorderSide(color: _border(context))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '导入方式',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        PrototypeSegmented<ImportMode>(
          values: const [ImportMode.copy, ImportMode.move],
          selected: mode,
          label: (value) => value == ImportMode.copy ? '复制' : '移动',
          icon: (value) => value == ImportMode.copy
              ? Icons.content_copy_outlined
              : Icons.drive_file_move_outline,
          onSelected: onModeChanged,
          expanded: true,
        ),
        if (renameAvailable) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '按模板重命名',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '关闭后本批保留原文件名',
                      style: TextStyle(fontSize: 11, color: _muted(context)),
                    ),
                  ],
                ),
              ),
              PillSwitch(value: renameWithTemplate, onChanged: onRenameChanged),
            ],
          ),
          if (renamePreview != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '第一个资源将命名为：$renamePreview',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _muted(context)),
              ),
            ),
        ],
        const SizedBox(height: 18),
        _SummaryRow('资源', '$sourceCount 项'),
        _SummaryRow('位置', targetLabel),
        _SummaryRow(
          '标签',
          selectedTags.isEmpty ? '未选择' : selectedTags.join('、'),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TagTagColors.success.withValues(alpha: 0.08),
            border: Border.all(
              color: TagTagColors.success.withValues(alpha: 0.28),
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 16,
                color: TagTagColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mode == ImportMode.move ? '源资源会移动到存储根目录' : '源文件会保留在原位置',
                  style: TextStyle(fontSize: 11, color: _muted(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: _border(context))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 55,
          child: Text(label, style: TextStyle(color: _muted(context))),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class PrototypeSettingsResult {
  const PrototypeSettingsResult({
    required this.moveImportsByDefault,
    required this.floatingDropTargetEnabled,
    required this.closeToTray,
    required this.autoStartEnabled,
    required this.startupView,
    required this.appearanceTheme,
    required this.interfaceDensity,
    required this.quickTagShortcut,
    required this.uniqueTagNames,
    required this.namingTemplate,
    required this.backupEnabled,
    required this.backupDirectory,
    required this.backupIntervalHours,
    required this.backupIncremental,
  });

  final bool moveImportsByDefault;
  final bool floatingDropTargetEnabled;
  final bool closeToTray;
  final bool autoStartEnabled;
  final String startupView;
  final String appearanceTheme;
  final String interfaceDensity;
  final String quickTagShortcut;
  final bool uniqueTagNames;
  final String namingTemplate;
  final bool backupEnabled;
  final String backupDirectory;
  final int backupIntervalHours;
  final bool backupIncremental;
}

enum PrototypeSettingsSection { general, imports, storage, windows, appearance }

class PrototypeSettingsDialog extends StatefulWidget {
  const PrototypeSettingsDialog({
    super.key,
    required this.controller,
    required this.quickTagRegistered,
    required this.onRevealStorageRoot,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onExportSpacePackage,
    required this.onImportSpacePackage,
    required this.onExportSpaceTemplate,
    required this.onImportSpaceTemplate,
    required this.portabilityBusy,
    required this.onAppearancePreview,
  });

  final TagTagController controller;
  final bool? quickTagRegistered;
  final Future<void> Function() onRevealStorageRoot;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onExportSpacePackage;
  final Future<void> Function() onImportSpacePackage;
  final Future<void> Function() onExportSpaceTemplate;
  final Future<void> Function() onImportSpaceTemplate;
  final bool portabilityBusy;
  final void Function(String theme, String density) onAppearancePreview;

  @override
  State<PrototypeSettingsDialog> createState() =>
      _PrototypeSettingsDialogState();
}

class _PrototypeSettingsDialogState extends State<PrototypeSettingsDialog> {
  late bool _moveImportsByDefault;
  late bool _floatingDropTargetEnabled;
  late bool _closeToTray;
  late bool _autoStartEnabled;
  late String _startupView;
  late String _appearanceTheme;
  late String _interfaceDensity;
  late String _quickTagShortcut;
  late bool _uniqueTagNames;
  late final TextEditingController _namingTemplateController;
  late bool _backupEnabled;
  late String _backupDirectory;
  late int _backupIntervalHours;
  late bool _backupIncremental;
  String? _backupDirectoryError;
  PrototypeSettingsSection _section = PrototypeSettingsSection.general;
  final FocusNode _shortcutFocusNode = FocusNode();
  bool _recording = false;
  String? _shortcutError;

  @override
  void initState() {
    super.initState();
    final preferences = widget.controller.preferences;
    _moveImportsByDefault = preferences.moveImportsByDefault;
    _floatingDropTargetEnabled = preferences.floatingDropTargetEnabled;
    _closeToTray = preferences.closeToTray;
    _autoStartEnabled = preferences.autoStartEnabled;
    _startupView = preferences.startupView;
    _appearanceTheme = preferences.appearanceTheme;
    _interfaceDensity = preferences.interfaceDensity;
    _quickTagShortcut = preferences.quickTagShortcut;
    _uniqueTagNames = preferences.uniqueTagNames;
    _namingTemplateController = TextEditingController(
      text: preferences.namingTemplate,
    );
    _backupEnabled = preferences.backupEnabled;
    _backupDirectory = preferences.backupDirectory;
    _backupIntervalHours = preferences.backupIntervalHours;
    _backupIncremental = preferences.backupIncremental;
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    _namingTemplateController.dispose();
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
        builder: (context) => PrototypeDialogFrame(
          width: 900,
          desktopHeight: 620,
          icon: Icons.settings_outlined,
          title: '设置',
          subtitle: '资料库、导入和 Windows 集成',
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: compact ? 62 : 200,
                    child: _SettingsNavigation(
                      selected: _section,
                      compact: compact,
                      onSelected: (value) => setState(() => _section = value),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 14 : 26,
                        compact ? 18 : 22,
                        compact ? 14 : 26,
                        28,
                      ),
                      child: _settingsPanel(context, compact),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            GlassPrimaryButton.icon(
              onPressed: () => unawaited(_save(context)),
              icon: const Icon(Icons.check, size: 17),
              label: const Text('保存设置'),
            ),
          ],
        ),
      ),
    );
  }

  /// Validates the scheduled-backup fields (when enabled) before closing;
  /// an invalid or uncreatable directory keeps the dialog open with an
  /// inline error in the storage section.
  Future<void> _save(BuildContext context) async {
    if (_backupEnabled) {
      final root = widget.controller.storageRoot;
      var error = root == null
          ? '存储根尚未初始化'
          : validateBackupDirectory(
              directory: _backupDirectory,
              storageRoot: root.path,
            );
      if (error == null) {
        try {
          await Directory(_backupDirectory.trim()).create(recursive: true);
        } on Object {
          error = '备份目录无法创建';
        }
      }
      if (error != null) {
        setState(() {
          _backupDirectoryError = error;
          _section = PrototypeSettingsSection.storage;
        });
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    Navigator.pop(
      context,
      PrototypeSettingsResult(
        moveImportsByDefault: _moveImportsByDefault,
        floatingDropTargetEnabled: _floatingDropTargetEnabled,
        closeToTray: _closeToTray,
        autoStartEnabled: _autoStartEnabled,
        startupView: _startupView,
        appearanceTheme: _appearanceTheme,
        interfaceDensity: _interfaceDensity,
        quickTagShortcut: _quickTagShortcut,
        uniqueTagNames: _uniqueTagNames,
        namingTemplate: _namingTemplateController.text.trim(),
        backupEnabled: _backupEnabled,
        backupDirectory: _backupDirectory.trim(),
        backupIntervalHours: _backupIntervalHours,
        backupIncremental: _backupIncremental,
      ),
    );
  }

  Future<void> _pickBackupDirectory() async {
    final selected = await getDirectoryPath(
      confirmButtonText: '选择备份目录',
      canCreateDirectories: true,
    );
    if (selected == null) {
      return;
    }
    final root = widget.controller.storageRoot;
    setState(() {
      _backupDirectory = selected;
      _backupDirectoryError = root == null
          ? '存储根尚未初始化'
          : validateBackupDirectory(
              directory: selected,
              storageRoot: root.path,
            );
    });
  }

  Widget _settingsPanel(BuildContext context, bool compact) {
    final title = switch (_section) {
      PrototypeSettingsSection.general => ('常规', '应用行为'),
      PrototypeSettingsSection.imports => ('导入与标注', '默认导入流程'),
      PrototypeSettingsSection.storage => ('存储与备份', '全局存储根目录'),
      PrototypeSettingsSection.windows => ('Windows 集成', '系统入口与快捷操作'),
      PrototypeSettingsSection.appearance => ('外观', '主题与界面密度'),
    };
    return Column(
      key: ValueKey(_section),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.$1,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(title.$2, style: TextStyle(fontSize: 11, color: _muted(context))),
        const SizedBox(height: 17),
        ...switch (_section) {
          PrototypeSettingsSection.general => _generalSettings(
            context,
            compact,
          ),
          PrototypeSettingsSection.imports => _importSettings(compact),
          PrototypeSettingsSection.storage => _storageSettings(compact),
          PrototypeSettingsSection.windows => _windowsSettings(compact),
          PrototypeSettingsSection.appearance => _appearanceSettings(compact),
        },
      ],
    );
  }

  List<Widget> _generalSettings(BuildContext context, bool compact) => [
    _SettingRow(
      title: '关闭主窗口时',
      subtitle: 'TAGTAG 继续在系统托盘运行',
      compact: compact,
      trailing: PrototypeSegmented<bool>(
        values: const [true, false],
        selected: _closeToTray,
        label: (value) => value ? '隐藏' : '退出',
        onSelected: (value) => setState(() => _closeToTray = value),
      ),
    ),
    _SettingRow(
      title: '启动视图',
      subtitle: '每次打开 TAGTAG 时显示',
      compact: compact,
      trailing: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _startupView,
            isDense: true,
            items: const [
              DropdownMenuItem(value: 'last', child: Text('上次使用的视图')),
              DropdownMenuItem(value: 'all', child: Text('全部资源')),
              DropdownMenuItem(value: 'inbox', child: Text('待整理')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _startupView = value);
            },
          ),
        ),
      ),
    ),
  ];

  List<Widget> _importSettings(bool compact) => [
    _SettingRow(
      title: '默认导入方式',
      subtitle: '每次导入时仍可切换',
      compact: compact,
      trailing: PrototypeSegmented<bool>(
        values: const [false, true],
        selected: _moveImportsByDefault,
        label: (value) => value ? '移动' : '复制',
        onSelected: (value) => setState(() => _moveImportsByDefault = value),
      ),
    ),
    _namingTemplateSetting(context),
    _SettingRow(
      title: '零标签资源',
      subtitle: '导入后进入当前空间待整理区',
      compact: compact,
      trailing: const Text('允许', style: TextStyle(fontWeight: FontWeight.w600)),
    ),
    _SettingRow(
      title: '标签名称全局唯一',
      subtitle: '同名标签默认唯一；仍可在标签操作中单独豁免',
      compact: compact,
      trailing: PillSwitch(
        value: _uniqueTagNames,
        onChanged: (value) => setState(() => _uniqueTagNames = value),
      ),
    ),
  ];

  /// Naming template field with placeholder help and a live example that
  /// re-renders on every keystroke.
  Widget _namingTemplateSetting(BuildContext context) {
    final template = _namingTemplateController.text;
    final example = TagTagController.applyNamingTemplate(
      template: template,
      sourceName: '报告.pdf',
      importDate: DateTime.now(),
      tagNames: const ['设计', '项目'],
      index: 1,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _border(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('导入命名模板', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '留空则保留原文件名。可用占位符：{原名} {日期} {时间} {标签} {序号}',
            style: TextStyle(fontSize: 11, color: _muted(context)),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 34,
            child: TextField(
              key: const ValueKey('naming-template-field'),
              controller: _namingTemplateController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '例如 {日期}-{标签}-{原名}'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '示例：$example',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: _muted(context)),
          ),
        ],
      ),
    );
  }

  List<Widget> _storageSettings(bool compact) {
    final root = widget.controller.storageRoot;
    final totalBytes = widget.controller.state.resources.fold<int>(
      0,
      (sum, item) => sum + (item.sizeBytes ?? 0),
    );
    return [
      Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _subtle(context),
          border: Border.all(color: _border(context)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.storage_outlined, color: _primary(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    root?.path ?? '尚未初始化',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${widget.controller.state.resources.length} 个资源 · ${_formatBytes(totalBytes)}',
                    style: TextStyle(fontSize: 11, color: _muted(context)),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(widget.onRevealStorageRoot()),
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('打开'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onCreateBackup()),
            child: const Text('创建完整备份'),
          ),
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onRestoreBackup()),
            child: const Text('从备份恢复'),
          ),
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onExportSpacePackage()),
            child: const Text('导出空间包'),
          ),
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onImportSpacePackage()),
            child: const Text('导入空间包'),
          ),
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onExportSpaceTemplate()),
            child: const Text('导出空间模板'),
          ),
          OutlinedButton(
            onPressed: widget.portabilityBusy
                ? null
                : () => unawaited(widget.onImportSpaceTemplate()),
            child: const Text('导入空间模板'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _SettingRow(
        title: '定期备份',
        subtitle: '应用运行时按间隔自动备份资料库',
        compact: compact,
        trailing: PillSwitch(
          value: _backupEnabled,
          onChanged: (value) => setState(() => _backupEnabled = value),
        ),
      ),
      _SettingRow(
        title: '备份目录',
        subtitle: _backupDirectory.trim().isEmpty ? '尚未选择' : _backupDirectory,
        compact: compact,
        trailing: OutlinedButton.icon(
          onPressed: () => unawaited(_pickBackupDirectory()),
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: const Text('选择目录'),
        ),
      ),
      if (_backupDirectoryError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _backupDirectoryError!,
            style: const TextStyle(
              fontSize: 11,
              color: TagTagColors.destructive,
            ),
          ),
        ),
      _SettingRow(
        title: '备份间隔',
        subtitle: '距离上次备份超过该时长后自动执行',
        compact: compact,
        trailing: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _backupIntervalHours,
              isDense: true,
              items: const [
                DropdownMenuItem(value: 6, child: Text('每 6 小时')),
                DropdownMenuItem(value: 12, child: Text('每 12 小时')),
                DropdownMenuItem(value: 24, child: Text('每 24 小时')),
                DropdownMenuItem(value: 72, child: Text('每 72 小时')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _backupIntervalHours = value);
                }
              },
            ),
          ),
        ),
      ),
      _SettingRow(
        title: '备份策略',
        subtitle: '完整备份每次生成新目录；增量备份只复制新增或变化的文件',
        compact: compact,
        trailing: PrototypeSegmented<bool>(
          values: const [false, true],
          selected: _backupIncremental,
          label: (value) => value ? '增量' : '完整',
          onSelected: (value) => setState(() => _backupIncremental = value),
        ),
      ),
      _SettingRow(
        title: '上次备份时间',
        subtitle: '定期备份最近一次执行的时间',
        compact: compact,
        trailing: Text(
          _formatLastBackupAt(widget.controller.preferences.lastBackupAt),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ];
  }

  List<Widget> _windowsSettings(bool compact) => [
    _SettingRow(
      title: '开机自动启动',
      subtitle: '登录 Windows 后自动启动 TAGTAG',
      compact: compact,
      trailing: PillSwitch(
        value: _autoStartEnabled,
        onChanged: (value) => setState(() => _autoStartEnabled = value),
      ),
    ),
    _SettingRow(
      title: '悬浮接收目标',
      subtitle: '将资源拖到悬浮目标开始导入',
      compact: compact,
      trailing: PillSwitch(
        value: _floatingDropTargetEnabled,
        onChanged: (value) =>
            setState(() => _floatingDropTargetEnabled = value),
      ),
    ),
    _SettingRow(
      title: '全局 Quick Tag',
      subtitle: '从任意窗口打开快速标注',
      compact: compact,
      trailing: _StatusLabel(registered: widget.quickTagRegistered != false),
    ),
    const SizedBox(height: 10),
    Focus(
      focusNode: _shortcutFocusNode,
      onKeyEvent: _onShortcutKeyEvent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _recording = !_recording;
                  _shortcutError = null;
                });
                if (_recording) _shortcutFocusNode.requestFocus();
              },
              borderRadius: BorderRadius.circular(5),
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _recording ? _soft(context) : _subtle(context),
                  border: Border.all(
                    color: _recording
                        ? _primary(context)
                        : Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard_outlined,
                      size: 20,
                      color: _recording ? _primary(context) : _muted(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _quickTagShortcut.replaceAll('+', ' + '),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _recording ? '请按下新的组合键' : '点击后按下新的组合键',
                            style: TextStyle(
                              fontSize: 10,
                              color: _muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _resetShortcut, child: const Text('恢复默认')),
        ],
      ),
    ),
    if (_shortcutError != null)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _shortcutError!,
          style: const TextStyle(fontSize: 11, color: TagTagColors.destructive),
        ),
      ),
    _SettingRow(
      title: '资源管理器右键菜单',
      subtitle: '使用 TAGTAG 添加标签',
      compact: compact,
      trailing: const _StatusLabel(registered: true, enabledLabel: '已启用'),
    ),
  ];

  List<Widget> _appearanceSettings(bool compact) => [
    _SettingRow(
      title: '主题',
      subtitle: '应用界面配色',
      compact: compact,
      trailing: PrototypeSegmented<String>(
        values: const ['light', 'dark'],
        selected: _appearanceTheme,
        label: (value) => value == 'light' ? '浅色' : '深色',
        icon: (value) => value == 'light'
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        onSelected: (value) {
          setState(() => _appearanceTheme = value);
          widget.onAppearancePreview(_appearanceTheme, _interfaceDensity);
        },
      ),
    ),
    _SettingRow(
      title: '界面密度',
      subtitle: '资源列表和工具栏间距',
      compact: compact,
      trailing: PrototypeSegmented<String>(
        values: const ['compact', 'comfortable'],
        selected: _interfaceDensity,
        label: (value) => value == 'compact' ? '紧凑' : '舒适',
        onSelected: (value) {
          setState(() => _interfaceDensity = value);
          widget.onAppearancePreview(_appearanceTheme, _interfaceDensity);
        },
      ),
    ),
  ];

  void _resetShortcut() {
    setState(() {
      _quickTagShortcut = 'Ctrl+Shift+T';
      _recording = false;
      _shortcutError = null;
    });
    _shortcutFocusNode.unfocus();
    _showDialogToast(context, '全局快捷键已恢复默认');
  }

  /// While recording, swallow every key event (including Escape) so the
  /// dialog-level shortcuts never see them.
  KeyEventResult _onShortcutKeyEvent(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _recordShortcut(event);
    return KeyEventResult.handled;
  }

  void _recordShortcut(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      _shortcutFocusNode.unfocus();
      return;
    }
    final modifierKeys = {
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifierKeys.contains(event.logicalKey)) return;
    final hardware = HardwareKeyboard.instance;
    if (!hardware.isControlPressed &&
        !hardware.isAltPressed &&
        !hardware.isMetaPressed) {
      setState(() => _shortcutError = '请至少包含 Ctrl、Alt 或 Win 修饰键');
      return;
    }
    final key = _shortcutKeyLabel(event.logicalKey);
    if (key == null) {
      setState(() => _shortcutError = '仅支持字母、数字或 F1-F12');
      return;
    }
    if (hardware.isControlPressed &&
        !hardware.isAltPressed &&
        !hardware.isShiftPressed &&
        !hardware.isMetaPressed &&
        key == 'K') {
      setState(() => _shortcutError = 'Ctrl + K 已用于资源搜索，请使用其他组合键');
      return;
    }
    final parts = <String>[
      if (hardware.isControlPressed) 'Ctrl',
      if (hardware.isAltPressed) 'Alt',
      if (hardware.isShiftPressed) 'Shift',
      if (hardware.isMetaPressed) 'Win',
      key,
    ];
    setState(() {
      _quickTagShortcut = parts.join('+');
      _recording = false;
      _shortcutError = null;
    });
    _shortcutFocusNode.unfocus();
    _showDialogToast(context, '全局快捷键已改为 $_quickTagShortcut');
  }
}

/// Toast used from inside modal dialogs (same styling as the workspace
/// toast; the snack bar renders beneath the dialog barrier).
void _showDialogToast(BuildContext context, String message) {
  AppToast.show(message);
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final PrototypeSettingsSection selected;
  final bool compact;
  final ValueChanged<PrototypeSettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (PrototypeSettingsSection.general, Icons.settings_outlined, '常规'),
      (PrototypeSettingsSection.imports, Icons.file_upload_outlined, '导入与标注'),
      (PrototypeSettingsSection.storage, Icons.storage_outlined, '存储与备份'),
      (
        PrototypeSettingsSection.windows,
        Icons.desktop_windows_outlined,
        'Windows 集成',
      ),
      (PrototypeSettingsSection.appearance, Icons.palette_outlined, '外观'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: _subtle(context),
        border: Border(right: BorderSide(color: _border(context))),
      ),
      child: Column(
        children: [
          for (final item in items)
            Tooltip(
              message: compact ? item.$3 : '',
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  autofocus: item == items.first,
                  onTap: () => onSelected(item.$1),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
                    decoration: BoxDecoration(
                      color: selected == item.$1
                          ? _soft(context)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisAlignment: compact
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          item.$2,
                          size: 17,
                          color: selected == item.$1
                              ? _primary(context)
                              : _muted(context),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.$3,
                              style: TextStyle(
                                color: selected == item.$1
                                    ? _primary(context)
                                    : _muted(context),
                                fontWeight: selected == item.$1
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11, color: _muted(context))),
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _border(context))),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labels,
                const SizedBox(height: 9),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            )
          : Row(
              children: [
                Expanded(child: labels),
                const SizedBox(width: 16),
                trailing,
              ],
            ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.registered, this.enabledLabel = '已注册'});
  final bool registered;
  final String enabledLabel;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: registered ? TagTagColors.success : TagTagColors.destructive,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      Text(
        registered ? enabledLabel : '未注册',
        style: TextStyle(
          color: registered ? TagTagColors.success : TagTagColors.destructive,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class PrototypeDialogFrame extends StatelessWidget {
  const PrototypeDialogFrame({
    super.key,
    required this.width,
    required this.desktopHeight,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.actions,
  });

  final double width;

  /// Fixed height on desktop; when null the dialog sizes to its content
  /// (capped by the available height), like the prototype's quick dialog.
  final double? desktopHeight;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width <= 720;
    final availableHeight = compact
        ? media.size.height - 32
        : media.size.height - 48;
    final fixedHeight = desktopHeight;
    final content = SizedBox(
      width: compact ? media.size.width : width,
      height: fixedHeight?.clamp(0, availableHeight),
      child: Column(
        mainAxisSize: fixedHeight == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: EdgeInsets.symmetric(
              horizontal: media.size.width <= 440 ? 12 : 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _border(context))),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _primary(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: _muted(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          if (fixedHeight == null)
            Flexible(child: body)
          else
            Expanded(child: body),
          Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _subtle(context),
              border: Border(top: BorderSide(color: _border(context))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final action in actions) ...[
                  action,
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Dialog(
      alignment: compact ? Alignment.bottomCenter : Alignment.center,
      insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: compact
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(GlassTokens.dialogRadius),
              ),
            )
          : null,
      child: GlassPanel(
        borderRadius: compact
            ? const BorderRadius.vertical(
                top: Radius.circular(GlassTokens.dialogRadius),
              )
            : BorderRadius.circular(GlassTokens.dialogRadius),
        blur: 22,
        shadow: !compact,
        // Dialogs carry dense text: run a slightly stronger fill than the
        // default panel so muted labels stay readable over the blur.
        fill: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff191c22).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.86),
        child: fixedHeight == null
            ? ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight),
                child: content,
              )
            : content,
      ),
    );
  }
}

class PrototypeTagOption extends StatelessWidget {
  const PrototypeTagOption({
    super.key,
    required this.name,
    required this.path,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String path;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1.5),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _soft(context) : Colors.transparent,
          border: Border.all(
            color: selected
                ? _primary(context).withValues(alpha: 0.32)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: _muted(context),
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 16, color: _primary(context)),
          ],
        ),
      ),
    ),
  );
}

class PrototypeSegmented<T> extends StatelessWidget {
  const PrototypeSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
    this.expanded = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final ValueChanged<T> onSelected;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: _subtle(context),
      border: Border.all(color: _border(context)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final value in values)
          if (expanded)
            Expanded(child: _segment(context, value))
          else
            _segment(context, value),
      ],
    ),
  );

  Widget _segment(BuildContext context, T value) {
    final active = value == selected;
    return InkWell(
      onTap: () => onSelected(value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon!(value), size: 14),
              const SizedBox(width: 5),
            ],
            Text(
              label(value),
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogFileIcon extends StatelessWidget {
  const _DialogFileIcon({required this.folder, required this.name});
  final bool folder;
  final String name;

  @override
  Widget build(BuildContext context) {
    final image = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
    }.contains(path.extension(name).toLowerCase());
    final color = folder
        ? TagTagColors.folder
        : image
        ? TagTagColors.purple
        : _muted(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(
        folder
            ? Icons.folder_outlined
            : image
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: 18,
        color: color,
      ),
    );
  }
}

String? _shortcutKeyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel.toUpperCase();
  if (RegExp(r'^[A-Z0-9]$').hasMatch(label)) return label;
  final match = RegExp(r'^F([1-9]|1[0-2])$').firstMatch(label);
  return match == null ? null : label;
}

String _sourceSizeLabel(List<FileSystemEntity> sources) {
  var total = 0;
  for (final source in sources) {
    if (source is File) {
      try {
        total += source.lengthSync();
      } on FileSystemException {
        return '大小未知';
      }
    }
  }
  return total == 0 ? '大小未知' : _formatBytes(total);
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _formatLastBackupAt(String lastBackupAt) {
  if (lastBackupAt.isEmpty) {
    return '从未备份';
  }
  final parsed = DateTime.tryParse(lastBackupAt);
  if (parsed == null) {
    return '从未备份';
  }
  return parsed.toLocal().toString().split('.').first;
}

String _joinRoot(String rootPath, String targetLabel) => targetLabel == '存储根目录'
    ? rootPath
    : path.join(rootPath, targetLabel.replaceAll(' / ', path.separator));

TextStyle _sectionLabelStyle(BuildContext context) => TextStyle(
  color: _faint(context),
  fontSize: 11,
  fontWeight: FontWeight.w600,
);
Color _primary(BuildContext context) => Theme.of(context).colorScheme.primary;
Color _soft(BuildContext context) =>
    Theme.of(context).colorScheme.primaryContainer;
Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
Color _faint(BuildContext context) => _muted(context).withValues(alpha: 0.82);
Color _border(BuildContext context) =>
    Theme.of(context).colorScheme.outlineVariant;
Color _subtle(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow;

/// Opens the rename dialog for [resource]. Quick suffix chips only edit the
/// text field; nothing is renamed until 保存 is pressed. Returns true when a
/// rename actually happened.
Future<bool?> showRenameResourceDialog(
  BuildContext context, {
  required TagTagController controller,
  required TagResource resource,
}) {
  return showPrototypeDialog<bool>(
    context: context,
    builder: (context) =>
        _RenameResourceDialog(controller: controller, resource: resource),
  );
}

class _RenameResourceDialog extends StatefulWidget {
  const _RenameResourceDialog({
    required this.controller,
    required this.resource,
  });

  final TagTagController controller;
  final TagResource resource;

  @override
  State<_RenameResourceDialog> createState() => _RenameResourceDialogState();
}

class _RenameResourceDialogState extends State<_RenameResourceDialog> {
  late final TextEditingController _nameController;
  String? _error;

  bool get _isFolder => widget.resource.kind == ResourceKind.folder;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.resource.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _firstTagName {
    final placements = widget.controller.assignmentsForResource(
      widget.resource.id,
    );
    if (placements.isEmpty) return '';
    return widget.controller.tagForPlacement(placements.first).name;
  }

  String _withSuffix(String name, String suffix) {
    if (_isFolder) return '$name$suffix';
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '$name$suffix';
    return '${name.substring(0, dot)}$suffix${name.substring(dot)}';
  }

  int _indexCounter = 1;

  // Quick chips always compose from the ORIGINAL name, so each chip picks
  // its suffix kind instead of stacking onto whatever the field holds.
  void _applySuffix(String suffix) {
    setState(() {
      _error = null;
      _nameController.text = _withSuffix(widget.resource.name, suffix);
    });
  }

  void _addDateSuffix() {
    final now = DateTime.now();
    String two(int unit) => unit.toString().padLeft(2, '0');
    _applySuffix('-${two(now.month)}-${two(now.day)}');
  }

  void _addTagSuffix() {
    final tagName = _firstTagName;
    if (tagName.isEmpty) return;
    _applySuffix('-$tagName');
  }

  void _addIndexSuffix() {
    setState(() {
      _indexCounter += 1;
      _error = null;
      _nameController.text = _withSuffix(
        widget.resource.name,
        ' ($_indexCounter)',
      );
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名称不能为空');
      return;
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      setState(() => _error = '名称不能包含 \\ / : * ? " < > | 字符');
      return;
    }
    if (name == widget.resource.name) {
      Navigator.pop(context);
      return;
    }
    try {
      await widget.controller.renameResource(widget.resource.id, name);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagName = _firstTagName;
    return PrototypeDialogFrame(
      width: 460,
      desktopHeight: null,
      icon: Icons.drive_file_rename_outline,
      title: '重命名',
      subtitle: widget.resource.name,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('rename-field'),
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: '新名称'),
              onSubmitted: (_) => unawaited(_save()),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('时间后缀'),
                  onPressed: _addDateSuffix,
                ),
                ActionChip(
                  label: Text(tagName.isEmpty ? 'TAG后缀' : 'TAG后缀（$tagName）'),
                  onPressed: tagName.isEmpty ? null : _addTagSuffix,
                ),
                ActionChip(
                  label: const Text('序号后缀'),
                  onPressed: _addIndexSuffix,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => unawaited(_save()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
