import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import '../models/tag_models.dart';
import '../state/tagtag_controller.dart';
import '../storage/managed_library.dart';
import 'prototype_dialogs.dart';
import 'tagtag_theme.dart';

typedef ResourceAction = Future<void> Function(TagResource resource);

/// Prototype motion curve (styles.css: cubic-bezier(0.2, 0.7, 0.2, 1)).
const _motionCurve = Cubic(0.2, 0.7, 0.2, 1);

/// Zeroes the duration when the platform requests reduced motion.
Duration _motionDuration(BuildContext context, int milliseconds) {
  return MediaQuery.of(context).disableAnimations
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// Shows the prototype's success toast (styles.css toast: dark surface,
/// green check, 2600ms). Colors come from snackBarTheme in tagtag_theme.
void showPrototypeToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, size: 17, color: Color(0xff80d2a5)),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      duration: const Duration(milliseconds: 2600),
    ),
  );
}

class PrototypeWorkspace extends StatefulWidget {
  const PrototypeWorkspace({
    super.key,
    required this.controller,
    required this.searchController,
    required this.searchFocusNode,
    required this.comfortableDensity,
    required this.dragging,
    required this.draggingCount,
    required this.consistencyFindings,
    required this.onQuickTag,
    required this.onImport,
    required this.onImportFolder,
    required this.onCreateSpace,
    required this.onOpenConsistency,
    required this.onSettings,
    required this.onOperationLog,
    required this.onCreateBackup,
    required this.onOpenResource,
    required this.onRevealResource,
    required this.onAddTag,
    required this.onClearTags,
    required this.onRestoreResource,
    required this.onMoveResource,
    required this.onRecycleResource,
    required this.onCreateTag,
    required this.onEditTag,
    required this.onMergeTag,
    required this.onSplitTag,
    required this.onDeleteTag,
  });

  final TagTagController controller;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool comfortableDensity;
  final bool dragging;
  final int draggingCount;
  final List<ConsistencyFinding> consistencyFindings;
  final Future<void> Function() onQuickTag;
  final Future<void> Function() onImport;
  final Future<void> Function() onImportFolder;
  final Future<void> Function() onCreateSpace;
  final Future<void> Function() onOpenConsistency;
  final Future<void> Function() onSettings;
  final Future<void> Function() onOperationLog;
  final Future<void> Function() onCreateBackup;
  final ResourceAction onOpenResource;
  final ResourceAction onRevealResource;
  final ResourceAction onAddTag;
  final ResourceAction onClearTags;
  final ResourceAction onRestoreResource;
  final ResourceAction onMoveResource;
  final ResourceAction onRecycleResource;
  final Future<void> Function(String? parentId) onCreateTag;
  final Future<void> Function(String placementId) onEditTag;
  final Future<void> Function(String placementId) onMergeTag;
  final Future<void> Function(String placementId) onSplitTag;
  final Future<void> Function(String placementId) onDeleteTag;

  @override
  State<PrototypeWorkspace> createState() => _PrototypeWorkspaceState();
}

class _PrototypeWorkspaceState extends State<PrototypeWorkspace>
    with SingleTickerProviderStateMixin {
  String? _inspectedResourceId;
  bool _navigationOpen = false;
  bool _inspectorOpen = false;
  bool _statusOpen = false;
  _StatusTab _statusTab = _StatusTab.health;
  late final AnimationController _statusAnimation = AnimationController(
    vsync: this,
  );

  TagTagController get controller => widget.controller;

  @override
  void dispose() {
    _statusAnimation.dispose();
    super.dispose();
  }

  void _setStatusOpen(bool open) {
    if (open == _statusOpen) return;
    setState(() => _statusOpen = open);
    _statusAnimation.duration = _motionDuration(context, 220);
    if (open) {
      _statusAnimation.forward();
    } else {
      _statusAnimation.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeTopLayer,
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: _palette(context).surface,
          child: Column(
            children: [
              _WindowBar(spaceName: controller.activeSpace?.name ?? '标签空间'),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final wide = width >= 1280;
                    final rail = width >= 960 && !wide;
                    final navigationWidth = wide ? 232.0 : 72.0;
                    final inspector = _inspectedResource();
                    return Stack(
                      children: [
                        Row(
                          children: [
                            if (width >= 960)
                              SizedBox(
                                key: const ValueKey('primary-navigation'),
                                width: navigationWidth,
                                child: _Navigation(
                                  controller: controller,
                                  collapsed: rail,
                                  findings: widget.consistencyFindings.length,
                                  onNavigate: _navigate,
                                  onCreateSpace: widget.onCreateSpace,
                                  onSettings: widget.onSettings,
                                  onStatus: () {
                                    _navigationOpen = false;
                                    _setStatusOpen(!_statusOpen);
                                  },
                                  statusExpanded: _statusOpen,
                                ),
                              ),
                            Expanded(
                              child: _MainWorkspace(
                                controller: controller,
                                searchController: widget.searchController,
                                searchFocusNode: widget.searchFocusNode,
                                comfortableDensity: widget.comfortableDensity,
                                windowWidth: width,
                                inspectedResourceId: inspector?.id,
                                onInspect: (resource) => setState(() {
                                  _inspectedResourceId = resource.id;
                                  if (!wide) _inspectorOpen = true;
                                }),
                                onToggleInspector: () => setState(
                                  () => _inspectorOpen = !_inspectorOpen,
                                ),
                                onOpenNavigation: () =>
                                    setState(() => _navigationOpen = true),
                                onQuickTag: _quickTag,
                                onImport: widget.onImport,
                                onImportFolder: widget.onImportFolder,
                                onOpenResource: widget.onOpenResource,
                                onRevealResource: widget.onRevealResource,
                                onAddTag: widget.onAddTag,
                                onClearTags: widget.onClearTags,
                                onRestoreResource: widget.onRestoreResource,
                                onMoveResource: widget.onMoveResource,
                                onRecycleResource: widget.onRecycleResource,
                                onCreateTag: widget.onCreateTag,
                                onEditTag: widget.onEditTag,
                                onMergeTag: widget.onMergeTag,
                                onSplitTag: widget.onSplitTag,
                                onDeleteTag: widget.onDeleteTag,
                              ),
                            ),
                            if (wide)
                              SizedBox(
                                width: 300,
                                child: _Inspector(
                                  controller: controller,
                                  resource: inspector,
                                  onClose: null,
                                  onOpen: widget.onOpenResource,
                                  onReveal: widget.onRevealResource,
                                  onEditTags: widget.onAddTag,
                                ),
                              ),
                          ],
                        ),
                        if (width < 960) ...[
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !_navigationOpen,
                              child: ExcludeSemantics(
                                excluding: !_navigationOpen,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _navigationOpen = false),
                                  child: AnimatedOpacity(
                                    opacity: _navigationOpen ? 1 : 0,
                                    duration: _motionDuration(context, 200),
                                    curve: _motionCurve,
                                    child: ColoredBox(
                                      color: Colors.black.withValues(
                                        alpha: 0.40,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 232,
                            child: IgnorePointer(
                              ignoring: !_navigationOpen,
                              child: ExcludeSemantics(
                                excluding: !_navigationOpen,
                                child: AnimatedSlide(
                                  offset: _navigationOpen
                                      ? Offset.zero
                                      : const Offset(-1.05, 0),
                                  duration: _motionDuration(context, 200),
                                  curve: _motionCurve,
                                  child: _Navigation(
                                    controller: controller,
                                    collapsed: false,
                                    findings: widget.consistencyFindings.length,
                                    onNavigate: _navigate,
                                    onCreateSpace: widget.onCreateSpace,
                                    onSettings: widget.onSettings,
                                    onStatus: () {
                                      _navigationOpen = false;
                                      _setStatusOpen(!_statusOpen);
                                    },
                                    statusExpanded: _statusOpen,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (!wide)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: width < 440 ? width : 320,
                            child: IgnorePointer(
                              ignoring: !_inspectorOpen,
                              child: ExcludeSemantics(
                                excluding: !_inspectorOpen,
                                child: AnimatedSlide(
                                  offset: _inspectorOpen
                                      ? Offset.zero
                                      : const Offset(1.05, 0),
                                  duration: _motionDuration(context, 200),
                                  curve: _motionCurve,
                                  child: Material(
                                    elevation: 18,
                                    color: _palette(context).surfaceSubtle,
                                    child: _Inspector(
                                      controller: controller,
                                      resource: inspector,
                                      onClose: () => setState(
                                        () => _inspectorOpen = false,
                                      ),
                                      onOpen: widget.onOpenResource,
                                      onReveal: widget.onRevealResource,
                                      onEditTags: widget.onAddTag,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: width < 420 ? width : 420,
                          child: AnimatedBuilder(
                            animation: _statusAnimation,
                            child: IgnorePointer(
                              ignoring: !_statusOpen,
                              child: ExcludeSemantics(
                                excluding: !_statusOpen,
                                child: _StatusDrawer(
                                  controller: controller,
                                  findings: widget.consistencyFindings,
                                  selectedTab: _statusTab,
                                  onTabSelected: (tab) =>
                                      setState(() => _statusTab = tab),
                                  onClose: () => _setStatusOpen(false),
                                  onCreateBackup: widget.onCreateBackup,
                                  onOpenFullLog: widget.onOperationLog,
                                  onOpenConsistency: widget.onOpenConsistency,
                                ),
                              ),
                            ),
                            builder: (context, child) {
                              if (_statusAnimation.isDismissed) {
                                return const SizedBox.shrink();
                              }
                              return SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(1.05, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: _statusAnimation,
                                        curve: _motionCurve,
                                        reverseCurve: _motionCurve,
                                      ),
                                    ),
                                child: child!,
                              );
                            },
                          ),
                        ),
                        if (widget.dragging)
                          _DropOverlay(count: widget.draggingCount),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _closeTopLayer() {
    if (_statusOpen) {
      _setStatusOpen(false);
    } else if (_inspectorOpen) {
      setState(() => _inspectorOpen = false);
    } else if (_navigationOpen) {
      setState(() => _navigationOpen = false);
    }
  }

  TagResource? _inspectedResource() {
    final resources = controller.visibleResources;
    final all = controller.state.resources;
    final id = _inspectedResourceId;
    if (id != null) {
      final matches = all.where((resource) => resource.id == id);
      if (matches.isNotEmpty) return matches.first;
    }
    return resources.isEmpty
        ? (all.isEmpty ? null : all.first)
        : resources.first;
  }

  void _navigate(ResourceView view) {
    widget.searchController.clear();
    controller.setSearchTerm('');
    switch (view) {
      case ResourceView.all:
        controller.showAllResources();
      case ResourceView.hierarchy:
        controller.showTagHierarchy();
      case ResourceView.inbox:
        controller.showInboxResources();
      case ResourceView.recent:
        controller.showRecentResources();
      case ResourceView.search:
        controller.showSearchResources();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.searchFocusNode.requestFocus(),
        );
    }
    setState(() => _navigationOpen = false);
  }

  Future<void> _quickTag() async {
    if (controller.selectedResourceIds.isEmpty) {
      final inspected = _inspectedResource();
      if (inspected != null) controller.selectResource(inspected.id);
    }
    await widget.onQuickTag();
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.spaceName});

  final String spaceName;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return SizedBox(
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.navigation,
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      const _Logo(size: 20, radius: 4),
                      const SizedBox(width: 8),
                      const Text(
                        'TAGTAG',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (MediaQuery.sizeOf(context).width > 720)
                        Text(
                          spaceName,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _CaptionButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onPressed: Platform.isWindows ? windowManager.minimize : null,
            ),
            _CaptionButton(
              icon: Icons.crop_square,
              tooltip: '最大化或还原',
              onPressed: Platform.isWindows
                  ? () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    }
                  : null,
            ),
            _CaptionButton(
              icon: Icons.close,
              tooltip: '关闭',
              destructive: true,
              onPressed: Platform.isWindows ? windowManager.close : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function()? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final width = windowWidth <= 720
        ? 34.0
        : windowWidth <= 959
        ? 40.0
        : 46.0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed == null ? null : () => unawaited(onPressed!()),
        hoverColor: destructive ? const Color(0xffc42b1c) : Colors.black12,
        child: SizedBox(width: width, height: 32, child: Icon(icon, size: 14)),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'TAGTAG 标志',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/branding/tagtag-logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.controller,
    required this.collapsed,
    required this.findings,
    required this.onNavigate,
    required this.onCreateSpace,
    required this.onSettings,
    required this.onStatus,
    required this.statusExpanded,
  });

  final TagTagController controller;
  final bool collapsed;
  final int findings;
  final ValueChanged<ResourceView> onNavigate;
  final Future<void> Function() onCreateSpace;
  final Future<void> Function() onSettings;
  final VoidCallback onStatus;
  final bool statusExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Material(
      color: palette.navigation,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          collapsed ? 8 : 10,
          14,
          collapsed ? 8 : 10,
          10,
        ),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: palette.border)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  const _Logo(size: 32, radius: 6),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TAGTAG',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text('本地资料库', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SpaceMenu(
              controller: controller,
              collapsed: collapsed,
              onCreateSpace: onCreateSpace,
            ),
            const SizedBox(height: 14),
            if (!collapsed) const _NavHeading('资料库'),
            _NavButton(
              key: const ValueKey('nav-全部资源'),
              icon: Icons.folder_outlined,
              label: '全部资源',
              count:
                  '${controller.visibleResourceCountForSpace(controller.activeSpaceId)}',
              selected: controller.activeView == ResourceView.all,
              collapsed: collapsed,
              onTap: () => onNavigate(ResourceView.all),
            ),
            _NavButton(
              key: const ValueKey('nav-待整理'),
              icon: Icons.inbox_outlined,
              label: '待整理',
              badge:
                  '${controller.inboxCountForSpace(controller.activeSpaceId)}',
              selected: controller.activeView == ResourceView.inbox,
              collapsed: collapsed,
              onTap: () => onNavigate(ResourceView.inbox),
            ),
            _NavButton(
              key: const ValueKey('nav-最近'),
              icon: Icons.schedule_outlined,
              label: '最近',
              selected: controller.activeView == ResourceView.recent,
              collapsed: collapsed,
              onTap: () => onNavigate(ResourceView.recent),
            ),
            _NavButton(
              key: const ValueKey('nav-搜索'),
              icon: Icons.search,
              label: '搜索',
              selected: controller.activeView == ResourceView.search,
              collapsed: collapsed,
              onTap: () => onNavigate(ResourceView.search),
            ),
            const SizedBox(height: 15),
            if (!collapsed) const _NavHeading('组织'),
            _NavButton(
              key: const ValueKey('nav-标签层级'),
              icon: Icons.sell_outlined,
              label: '标签层级',
              selected: controller.activeView == ResourceView.hierarchy,
              collapsed: collapsed,
              onTap: () => onNavigate(ResourceView.hierarchy),
            ),
            const Spacer(),
            Divider(color: palette.border, height: 17),
            _HealthButton(
              collapsed: collapsed,
              findings: findings,
              expanded: statusExpanded,
              onTap: onStatus,
            ),
            _NavButton(
              key: const ValueKey('nav-设置'),
              icon: Icons.settings_outlined,
              label: '设置',
              collapsed: collapsed,
              onTap: () => unawaited(onSettings()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceMenu extends StatefulWidget {
  const _SpaceMenu({
    required this.controller,
    required this.collapsed,
    required this.onCreateSpace,
  });

  static const _createSpaceValue = '__create_space__';

  final TagTagController controller;
  final bool collapsed;
  final Future<void> Function() onCreateSpace;

  @override
  State<_SpaceMenu> createState() => _SpaceMenuState();
}

class _SpaceMenuState extends State<_SpaceMenu> {
  final _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  TagTagController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSpace;
    final palette = _palette(context);
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _menuKey.currentState?.showButtonMenu();
            return null;
          },
        ),
      },
      child: PopupMenuButton<String>(
        key: _menuKey,
        tooltip: '切换标签空间',
        onSelected: (id) {
          if (id == _SpaceMenu._createSpaceValue) {
            unawaited(widget.onCreateSpace());
            return;
          }
          unawaited(controller.selectSpace(id));
          final space = controller.state.spaces
              .where((candidate) => candidate.id == id)
              .firstOrNull;
          if (space != null) {
            showPrototypeToast(context, '已切换到“${space.name}”');
          }
        },
        offset: Offset(widget.collapsed ? 57 : 0, widget.collapsed ? -38 : 42),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
        itemBuilder: (context) => [
          for (final space in controller.state.spaces)
            PopupMenuItem(
              value: space.id,
              height: 52,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: space.id == active?.id
                          ? TagTagColors.purple
                          : TagTagColors.success,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          space.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${controller.visibleResourceCountForSpace(space.id)} 个资源',
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (space.id == active?.id)
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: TagTagColors.primary,
                    ),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _SpaceMenu._createSpaceValue,
            height: 44,
            child: Row(
              children: [
                Icon(Icons.add, size: 18, color: palette.textMuted),
                const SizedBox(width: 9),
                const Text('新建标签空间'),
              ],
            ),
          ),
        ],
        child: Container(
          key: const ValueKey('space-switcher'),
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 10),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.borderStrong),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: TagTagColors.purple,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    active?.name ?? '标签空间',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavHeading extends StatelessWidget {
  const _NavHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 5),
      child: Text(
        label,
        style: TextStyle(
          color: _palette(context).textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
    this.selected = false,
    this.count,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback onTap;
  final bool selected;
  final String? count;
  final String? badge;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final foreground = widget.selected ? palette.primary : palette.textMuted;
    final button = FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 10),
          decoration: BoxDecoration(
            color: widget.selected ? palette.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: _focused
                ? Border.all(color: palette.primary, width: 2)
                : null,
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (widget.selected)
                Transform.translate(
                  offset: Offset(widget.collapsed ? -20 : -10, 0),
                  child: Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              Icon(widget.icon, size: 20, color: foreground),
              if (!widget.collapsed) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.badge != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: TagTagColors.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (widget.count != null)
                  Text(
                    widget.count!,
                    style: TextStyle(fontSize: 12, color: palette.textFaint),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: widget.collapsed
          ? Tooltip(message: widget.label, child: button)
          : button,
    );
  }
}

class _HealthButton extends StatelessWidget {
  const _HealthButton({
    required this.collapsed,
    required this.findings,
    required this.expanded,
    required this.onTap,
  });

  final bool collapsed;
  final int findings;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final healthy = findings == 0;
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: healthy ? TagTagColors.success : TagTagColors.warning,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (healthy ? TagTagColors.success : TagTagColors.warning)
                .withValues(alpha: 0.16),
            spreadRadius: 3,
          ),
        ],
      ),
    );
    return Tooltip(
      message: healthy ? '资料库正常，上次扫描 1 分钟前' : '$findings 个一致性告警',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 50,
          padding: collapsed
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: expanded ? palette.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              dot,
              if (!collapsed) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy ? '资料库正常' : '$findings 个一致性告警',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: expanded ? palette.primary : null,
                        ),
                      ),
                      Text(
                        '上次扫描 1 分钟前',
                        style: TextStyle(
                          fontSize: 10,
                          color: palette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 15, color: palette.textFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MainWorkspace extends StatelessWidget {
  const _MainWorkspace({
    required this.controller,
    required this.searchController,
    required this.searchFocusNode,
    required this.comfortableDensity,
    required this.windowWidth,
    required this.inspectedResourceId,
    required this.onInspect,
    required this.onToggleInspector,
    required this.onOpenNavigation,
    required this.onQuickTag,
    required this.onImport,
    required this.onImportFolder,
    required this.onOpenResource,
    required this.onRevealResource,
    required this.onAddTag,
    required this.onClearTags,
    required this.onRestoreResource,
    required this.onMoveResource,
    required this.onRecycleResource,
    required this.onCreateTag,
    required this.onEditTag,
    required this.onMergeTag,
    required this.onSplitTag,
    required this.onDeleteTag,
  });

  final TagTagController controller;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool comfortableDensity;
  final double windowWidth;
  final String? inspectedResourceId;
  final ValueChanged<TagResource> onInspect;
  final VoidCallback onToggleInspector;
  final VoidCallback onOpenNavigation;
  final Future<void> Function() onQuickTag;
  final Future<void> Function() onImport;
  final Future<void> Function() onImportFolder;
  final ResourceAction onOpenResource;
  final ResourceAction onRevealResource;
  final ResourceAction onAddTag;
  final ResourceAction onClearTags;
  final ResourceAction onRestoreResource;
  final ResourceAction onMoveResource;
  final ResourceAction onRecycleResource;
  final Future<void> Function(String? parentId) onCreateTag;
  final Future<void> Function(String placementId) onEditTag;
  final Future<void> Function(String placementId) onMergeTag;
  final Future<void> Function(String placementId) onSplitTag;
  final Future<void> Function(String placementId) onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final view = controller.activeView;
    return Material(
      color: palette.surface,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: EdgeInsets.symmetric(
              horizontal: windowWidth < 720 ? 10 : 18,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                if (windowWidth < 960) ...[
                  _SmallIconButton(
                    icon: Icons.menu,
                    tooltip: '打开导航',
                    onPressed: onOpenNavigation,
                  ),
                  const SizedBox(width: 6),
                ],
                if (windowWidth >= 440)
                  Text(
                    '本地资料库',
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                if (windowWidth >= 440) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.chevron_right, size: 13),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    controller.activeSpace?.name ?? '标签空间',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<_ImportMenuAction>(
                  tooltip: '导入',
                  onSelected: (action) => unawaited(
                    action == _ImportMenuAction.files
                        ? onImport()
                        : onImportFolder(),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ImportMenuAction.files,
                      child: _MenuLabel(Icons.note_add_outlined, '导入文件'),
                    ),
                    PopupMenuItem(
                      value: _ImportMenuAction.folder,
                      child: _MenuLabel(
                        Icons.create_new_folder_outlined,
                        '导入文件夹',
                      ),
                    ),
                  ],
                  child: Container(
                    height: 34,
                    padding: EdgeInsets.symmetric(
                      horizontal: windowWidth < 440 ? 8 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 17,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        if (windowWidth >= 440) ...[
                          const SizedBox(width: 6),
                          Text(
                            '导入',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: BoxConstraints(minHeight: windowWidth < 720 ? 76 : 84),
            padding: EdgeInsets.fromLTRB(
              windowWidth < 720 ? 12 : 20,
              windowWidth < 720 ? 11 : 14,
              windowWidth < 720 ? 12 : 20,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _viewTitle(view),
                        style: TextStyle(
                          fontSize: windowWidth < 720 ? 18 : 20,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _viewSubtitle(controller),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _PrototypeButton(
                  icon: Icons.sell_outlined,
                  label: windowWidth < 720 ? null : '快速标注',
                  tooltip: '快速标注',
                  onPressed: () => unawaited(onQuickTag()),
                ),
              ],
            ),
          ),
          if (view == ResourceView.hierarchy)
            Expanded(
              child: _TagWorkbench(
                controller: controller,
                windowWidth: windowWidth,
                onOpen: onOpenResource,
                onCreateTag: onCreateTag,
                onEditTag: onEditTag,
                onMergeTag: onMergeTag,
                onSplitTag: onSplitTag,
                onDeleteTag: onDeleteTag,
              ),
            )
          else ...[
            _CommandBar(
              controller: controller,
              searchController: searchController,
              searchFocusNode: searchFocusNode,
              windowWidth: windowWidth,
              onQuickTag: onQuickTag,
              onToggleInspector: onToggleInspector,
            ),
            if (view == ResourceView.search)
              _SearchFilterStrip(
                controller: controller,
                windowWidth: windowWidth,
                onClearSearch: () {
                  searchController.clear();
                  controller.setSearchTerm('');
                  controller.clearSearchFilters();
                },
              ),
            if (view == ResourceView.inbox)
              _InboxScopeStrip(
                controller: controller,
                windowWidth: windowWidth,
              ),
            Expanded(
              child: _ResourceTable(
                controller: controller,
                searchTerm: searchController.text,
                comfortableDensity: comfortableDensity,
                windowWidth: windowWidth,
                inspectedResourceId: inspectedResourceId,
                onClearSearch: () {
                  searchController.clear();
                  controller.setSearchTerm('');
                  controller.clearSearchFilters();
                },
                onInspect: onInspect,
                onOpen: onOpenResource,
                onReveal: onRevealResource,
                onAddTag: onAddTag,
                onClearTags: onClearTags,
                onRestore: onRestoreResource,
                onMove: onMoveResource,
                onRecycle: onRecycleResource,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.controller,
    required this.searchController,
    required this.searchFocusNode,
    required this.windowWidth,
    required this.onQuickTag,
    required this.onToggleInspector,
  });

  final TagTagController controller;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final double windowWidth;
  final Future<void> Function() onQuickTag;
  final VoidCallback onToggleInspector;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final selectedCount = controller.selectedResourceIds.length;
    return Container(
      height: 46,
      padding: EdgeInsets.fromLTRB(windowWidth < 720 ? 10 : 20, 6, 14, 6),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 120,
              maxWidth: windowWidth < 720 ? double.infinity : 430,
            ),
            child: SizedBox(
              width: windowWidth < 720 ? double.infinity : 430,
              height: 34,
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: controller.setSearchTerm,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索名称、路径或标签',
                  prefixIcon: const Icon(Icons.search, size: 17),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () {
                            searchController.clear();
                            controller.setSearchTerm('');
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 9),
                ),
              ),
            ),
          ),
          if (windowWidth >= 720) ...[
            const Spacer(),
            if (selectedCount > 0)
              Text(
                '已选 $selectedCount 项',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            const SizedBox(width: 7),
            TextButton.icon(
              onPressed: selectedCount == 0
                  ? null
                  : () => unawaited(onQuickTag()),
              icon: const Icon(Icons.sell_outlined, size: 17),
              label: const Text('添加标签'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 34)),
            ),
          ],
          const SizedBox(width: 4),
          _SmallIconButton(
            icon: Icons.vertical_split_outlined,
            tooltip: '显示资源详情',
            onPressed: onToggleInspector,
          ),
        ],
      ),
    );
  }
}

class _ResourceTable extends StatelessWidget {
  const _ResourceTable({
    required this.controller,
    required this.searchTerm,
    required this.comfortableDensity,
    required this.windowWidth,
    required this.inspectedResourceId,
    required this.onClearSearch,
    required this.onInspect,
    required this.onOpen,
    required this.onReveal,
    required this.onAddTag,
    required this.onClearTags,
    required this.onRestore,
    required this.onMove,
    required this.onRecycle,
  });

  final TagTagController controller;
  final String searchTerm;
  final bool comfortableDensity;
  final double windowWidth;
  final String? inspectedResourceId;
  final VoidCallback onClearSearch;
  final ValueChanged<TagResource> onInspect;
  final ResourceAction onOpen;
  final ResourceAction onReveal;
  final ResourceAction onAddTag;
  final ResourceAction onClearTags;
  final ResourceAction onRestore;
  final ResourceAction onMove;
  final ResourceAction onRecycle;

  @override
  Widget build(BuildContext context) {
    final query = searchTerm.trim().toLowerCase();
    final resources = controller.visibleResources.where((resource) {
      if (query.isEmpty) return true;
      final tags = controller
          .effectiveTagsForResource(resource.id)
          .map((item) => item.tag.name)
          .join(' ');
      return '${resource.name} ${resource.path} $tags'.toLowerCase().contains(
        query,
      );
    }).toList();
    if (resources.isEmpty) {
      return _EmptyResources(onClear: onClearSearch);
    }
    final palette = _palette(context);
    return Column(
      children: [
        Container(
          height: 34,
          color: palette.surfaceSubtle,
          child: _TableCells(
            windowWidth: windowWidth,
            checkbox: _TableCheckbox(
              value: resources.every(
                (resource) =>
                    controller.selectedResourceIds.contains(resource.id),
              ),
              tristate: true,
              onChanged: (value) {
                final select = value ?? true;
                for (final resource in resources) {
                  controller.toggleResourceSelection(resource.id, select);
                }
              },
            ),
            name: const _HeaderLabel('名称'),
            tags: const _HeaderLabel('有效标签'),
            type: const _HeaderLabel('类型'),
            size: const _HeaderLabel('大小'),
            modified: const _HeaderLabel('修改时间'),
            actions: const SizedBox.shrink(),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: resources.length,
            itemExtent: comfortableDensity ? 64 : 54,
            itemBuilder: (context, index) {
              final resource = resources[index];
              return _ResourceTableRow(
                controller: controller,
                resource: resource,
                windowWidth: windowWidth,
                inspected: resource.id == inspectedResourceId,
                onInspect: onInspect,
                onOpen: onOpen,
                onReveal: onReveal,
                onAddTag: onAddTag,
                onClearTags: onClearTags,
                onRestore: onRestore,
                onMove: onMove,
                onRecycle: onRecycle,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResourceTableRow extends StatefulWidget {
  const _ResourceTableRow({
    required this.controller,
    required this.resource,
    required this.windowWidth,
    required this.inspected,
    required this.onInspect,
    required this.onOpen,
    required this.onReveal,
    required this.onAddTag,
    required this.onClearTags,
    required this.onRestore,
    required this.onMove,
    required this.onRecycle,
  });

  final TagTagController controller;
  final TagResource resource;
  final double windowWidth;
  final bool inspected;
  final ValueChanged<TagResource> onInspect;
  final ResourceAction onOpen;
  final ResourceAction onReveal;
  final ResourceAction onAddTag;
  final ResourceAction onClearTags;
  final ResourceAction onRestore;
  final ResourceAction onMove;
  final ResourceAction onRecycle;

  @override
  State<_ResourceTableRow> createState() => _ResourceTableRowState();
}

class _ResourceTableRowState extends State<_ResourceTableRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final selected = widget.controller.selectedResourceIds.contains(
      widget.resource.id,
    );
    final effectiveTags = widget.controller.effectiveTagsForResource(
      widget.resource.id,
    );
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onInspect(widget.resource);
            return null;
          },
        ),
      },
      child: InkWell(
        onTap: () => widget.onInspect(widget.resource),
        onDoubleTap: () => unawaited(widget.onOpen(widget.resource)),
        child: Container(
          foregroundDecoration: _focused
              ? BoxDecoration(
                  border: Border.all(color: palette.primary, width: 2),
                )
              : null,
          decoration: BoxDecoration(
            color: widget.inspected ? palette.primarySoft : palette.surface,
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: _TableCells(
            windowWidth: widget.windowWidth,
            checkbox: _TableCheckbox(
              value: selected,
              onChanged: (value) => widget.controller.toggleResourceSelection(
                widget.resource.id,
                value ?? false,
              ),
            ),
            name: _ResourceIdentity(
              resource: widget.resource,
              tight: widget.windowWidth <= 440,
              storageRoot: widget.controller.storageRoot?.path,
            ),
            tags: _EffectiveTags(tags: effectiveTags),
            type: Text(_resourceType(widget.resource)),
            size: Text(_formatBytes(widget.resource.sizeBytes)),
            modified: Text(_formatDate(widget.resource.modifiedAt)),
            actions: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered || widget.inspected ? 1 : 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.windowWidth >= 720)
                    _SmallIconButton(
                      icon: widget.resource.kind == ResourceKind.folder
                          ? Icons.folder_open_outlined
                          : Icons.open_in_new,
                      tooltip: '打开',
                      size: 29,
                      onPressed: () =>
                          unawaited(widget.onOpen(widget.resource)),
                    ),
                  SizedBox(
                    width: 34,
                    height: 29,
                    child: PopupMenuButton<_ResourceMenuAction>(
                      tooltip: '更多操作',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 18),
                      constraints: const BoxConstraints(minWidth: 190),
                      onSelected: (action) {
                        switch (action) {
                          case _ResourceMenuAction.reveal:
                            unawaited(widget.onReveal(widget.resource));
                          case _ResourceMenuAction.addTag:
                            unawaited(widget.onAddTag(widget.resource));
                          case _ResourceMenuAction.clearTags:
                            unawaited(widget.onClearTags(widget.resource));
                          case _ResourceMenuAction.restore:
                            unawaited(widget.onRestore(widget.resource));
                          case _ResourceMenuAction.move:
                            unawaited(widget.onMove(widget.resource));
                          case _ResourceMenuAction.recycle:
                            unawaited(widget.onRecycle(widget.resource));
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _ResourceMenuAction.reveal,
                          child: _MenuLabel(
                            Icons.folder_open_outlined,
                            '在资源管理器中定位',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _ResourceMenuAction.addTag,
                          child: _MenuLabel(Icons.sell_outlined, '添加标签'),
                        ),
                        if (widget.controller
                            .assignmentsForResource(widget.resource.id)
                            .isNotEmpty)
                          const PopupMenuItem(
                            value: _ResourceMenuAction.clearTags,
                            child: _MenuLabel(
                              Icons.label_off_outlined,
                              '清除全部直接标签',
                            ),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: _ResourceMenuAction.restore,
                          child: _MenuLabel(Icons.restore, '恢复先前路径并退出管理'),
                        ),
                        const PopupMenuItem(
                          value: _ResourceMenuAction.move,
                          child: _MenuLabel(
                            Icons.drive_file_move_outline,
                            '移动到指定位置并退出',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _ResourceMenuAction.recycle,
                          child: _MenuLabel(Icons.delete_outline, '移入回收站并退出'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 15px checkbox matching the prototype's `accent-color` checkbox.
class _TableCheckbox extends StatelessWidget {
  const _TableCheckbox({
    required this.value,
    this.tristate = false,
    required this.onChanged,
  });

  final bool? value;
  final bool tristate;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 15,
      height: 15,
      child: Transform.scale(
        scale: 15 / 18,
        child: Checkbox(
          value: value,
          tristate: tristate,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          activeColor: _palette(context).primary,
        ),
      ),
    );
  }
}

class _TableCells extends StatelessWidget {
  const _TableCells({
    required this.windowWidth,
    required this.checkbox,
    required this.name,
    required this.tags,
    required this.type,
    required this.size,
    required this.modified,
    required this.actions,
  });

  final double windowWidth;
  final Widget checkbox;
  final Widget name;
  final Widget tags;
  final Widget type;
  final Widget size;
  final Widget modified;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final narrow = windowWidth < 720;
    final tight = windowWidth <= 440;
    final cellPadding = EdgeInsets.symmetric(horizontal: tight ? 6 : 10);
    return Row(
      children: [
        SizedBox(
          width: narrow ? 34 : 40,
          child: Center(child: checkbox),
        ),
        Expanded(
          flex: narrow ? 1 : 30,
          child: Padding(padding: cellPadding, child: name),
        ),
        if (windowWidth >= 720)
          Expanded(
            flex: 24,
            child: Padding(padding: cellPadding, child: tags),
          ),
        if (windowWidth >= 960)
          Expanded(
            flex: 13,
            child: Padding(padding: cellPadding, child: type),
          ),
        if (windowWidth > 1020)
          Expanded(
            flex: 9,
            child: Padding(padding: cellPadding, child: size),
          ),
        if (windowWidth >= 720)
          Expanded(
            flex: 14,
            child: Padding(padding: cellPadding, child: modified),
          ),
        SizedBox(width: narrow ? 38 : 84, child: actions),
      ],
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: _palette(context).textFaint,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _ResourceIdentity extends StatelessWidget {
  const _ResourceIdentity({
    required this.resource,
    this.tight = false,
    this.storageRoot,
  });
  final TagResource resource;
  final bool tight;
  final String? storageRoot;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Row(
      children: [
        _ResourceIcon(resource: resource, size: 30),
        SizedBox(width: tight ? 7 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resource.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: tight ? 185 : double.infinity,
                ),
                child: Text(
                  _displayParent(resource.path, storageRoot),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.textFaint),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResourceIcon extends StatelessWidget {
  const _ResourceIcon({required this.resource, required this.size});
  final TagResource resource;
  final double size;

  @override
  Widget build(BuildContext context) {
    final extension = path.extension(resource.name).toLowerCase();
    final folder = resource.kind == ResourceKind.folder;
    final color = folder
        ? TagTagColors.folder
        : extension == '.pdf'
        ? TagTagColors.destructive
        : {'.png', '.jpg', '.jpeg', '.gif', '.webp'}.contains(extension)
        ? TagTagColors.purple
        : {'.xls', '.xlsx', '.csv'}.contains(extension)
        ? TagTagColors.success
        : extension == '.fig'
        ? _palette(context).primary
        : _palette(context).textMuted;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(size >= 48 ? 7 : 5),
      ),
      child: Icon(
        folder
            ? Icons.folder_outlined
            : {'.png', '.jpg', '.jpeg', '.gif', '.webp'}.contains(extension)
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: size >= 48 ? 25 : 17,
        color: color,
      ),
    );
  }
}

class _EffectiveTags extends StatelessWidget {
  const _EffectiveTags({required this.tags});
  final List<EffectiveTagView> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const Text(
        '未标注',
        style: TextStyle(
          color: TagTagColors.warning,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return ClipRect(
      child: Row(
        children: [
          for (final tag in tags.take(2)) ...[
            Flexible(child: _TagChip(tag: tag)),
            const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});
  final EffectiveTagView tag;

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.tag.colorValue);
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      height: 23,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _palette(context).surface,
        border: Border.all(
          color: tag.isInherited
              ? color.withValues(alpha: 0.55)
              : _palette(context).border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag.isInherited)
            Icon(Icons.account_tree_outlined, size: 12, color: color)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tag.tag.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.controller,
    required this.resource,
    required this.onClose,
    required this.onOpen,
    required this.onReveal,
    required this.onEditTags,
  });

  final TagTagController controller;
  final TagResource? resource;
  final VoidCallback? onClose;
  final ResourceAction onOpen;
  final ResourceAction onReveal;
  final ResourceAction onEditTags;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final item = resource;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 16, right: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '资源详情',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onClose != null)
                  _SmallIconButton(
                    icon: Icons.close,
                    tooltip: '关闭资源详情',
                    onPressed: onClose!,
                  ),
              ],
            ),
          ),
          if (item == null)
            const Expanded(child: Center(child: Text('选择一个资源查看详情')))
          else
            Expanded(
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                    color: palette.surface,
                    child: Column(
                      children: [
                        _ResourceIcon(resource: item, size: 48),
                        const SizedBox(height: 11),
                        Text(
                          item.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_resourceType(item)} · ${_formatBytes(item.sizeBytes)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PrototypeButton(
                              icon: Icons.open_in_new,
                              label: '打开',
                              primary: true,
                              onPressed: () => unawaited(onOpen(item)),
                            ),
                            const SizedBox(width: 7),
                            _PrototypeButton(
                              icon: Icons.folder_open_outlined,
                              label: '定位',
                              onPressed: () => unawaited(onReveal(item)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _InspectorSection(
                    title: '有效标签',
                    action: _SmallIconButton(
                      icon: Icons.add,
                      tooltip: '编辑标签',
                      onPressed: () => unawaited(onEditTags(item)),
                      size: 28,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _EffectiveTags(
                        tags: controller.effectiveTagsForResource(item.id),
                      ),
                    ),
                  ),
                  _InspectorSection(
                    title: '位置',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: InkWell(
                        onTap: () => unawaited(onReveal(item)),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            border: Border.all(color: palette.border),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 15),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _displayLocation(
                                    item.path,
                                    controller.storageRoot?.path,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textMuted,
                                  ),
                                ),
                              ),
                              const Icon(Icons.open_in_new, size: 15),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _InspectorSection(
                    title: '信息',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        children: [
                          _MetadataRow('类型', _resourceType(item)),
                          _MetadataRow('大小', _formatBytes(item.sizeBytes)),
                          _MetadataRow('修改时间', _formatDate(item.modifiedAt)),
                          _MetadataRow(
                            '空间成员',
                            _spaceNames(controller, item.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _InspectorSection(
                    title: '标签来源',
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Icon(Icons.sell_outlined, color: palette.primary),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '直接标注',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  controller
                                      .assignmentsForResource(item.id)
                                      .map(
                                        (p) =>
                                            controller.tagForPlacement(p).name,
                                      )
                                      .join('、'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({
    required this.title,
    required this.child,
    this.action,
  });
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.textFaint,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(color: _palette(context).textFaint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _TagWorkbench extends StatefulWidget {
  const _TagWorkbench({
    required this.controller,
    required this.windowWidth,
    required this.onOpen,
    required this.onCreateTag,
    required this.onEditTag,
    required this.onMergeTag,
    required this.onSplitTag,
    required this.onDeleteTag,
  });

  final TagTagController controller;
  final double windowWidth;
  final ResourceAction onOpen;
  final Future<void> Function(String? parentId) onCreateTag;
  final Future<void> Function(String placementId) onEditTag;
  final Future<void> Function(String placementId) onMergeTag;
  final Future<void> Function(String placementId) onSplitTag;
  final Future<void> Function(String placementId) onDeleteTag;

  @override
  State<_TagWorkbench> createState() => _TagWorkbenchState();
}

class _TagWorkbenchState extends State<_TagWorkbench> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final placements = controller.placementsInActiveSpace;
    final selected = placements.where(
      (item) => item.id == controller.activePlacementId,
    );
    final active = selected.isEmpty
        ? (placements.isEmpty ? null : placements.first)
        : selected.first;
    if (active != null && controller.activePlacementId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.selectPlacement(active.id);
      });
    }
    final tree = _TagTreePanel(controller: controller, selected: active);
    if (widget.windowWidth < 720) return tree;
    return Row(
      children: [
        SizedBox(
          width: (widget.windowWidth * 0.34).clamp(220, 360),
          child: tree,
        ),
        Expanded(
          child: _TagResultPanel(
            controller: controller,
            placement: active,
            onOpen: widget.onOpen,
            onCreateTag: widget.onCreateTag,
            onEditTag: widget.onEditTag,
            onMergeTag: widget.onMergeTag,
            onSplitTag: widget.onSplitTag,
            onDeleteTag: widget.onDeleteTag,
          ),
        ),
      ],
    );
  }
}

class _TagTreePanel extends StatefulWidget {
  const _TagTreePanel({required this.controller, required this.selected});

  final TagTagController controller;
  final TagPlacement? selected;

  @override
  State<_TagTreePanel> createState() => _TagTreePanelState();
}

class _TagTreePanelState extends State<_TagTreePanel> {
  static const int _maxIndentDepth = 6;

  String? _draggingId;

  late final Set<String> _expandedIds = {
    for (final root in widget.controller.rootPlacements)
      if (widget.controller.childrenOf(root.id).isNotEmpty) root.id,
  };

  void _dropOn(TagPlacement dragged, String? newParentId) {
    if (dragged.parentId == newParentId) return;
    // reparentPlacement validates and updates state synchronously, then
    // persists asynchronously; surface persistence/validation errors late.
    unawaited(
      widget.controller.reparentPlacement(dragged.id, newParentId).catchError((
        error,
      ) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('调整标签层级失败：$error')));
        }
      }),
    );
    setState(() {
      if (newParentId != null) _expandedIds.add(newParentId);
    });
    widget.controller.selectPlacement(dragged.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已更新：${widget.controller.pathOf(dragged.id)}'),
      ),
    );
  }

  void _expandToLevels(int levels) {
    final controller = widget.controller;
    final expanded = <String>{};
    void walk(TagPlacement placement, int depth) {
      if (depth >= levels - 1) return;
      final children = controller.childrenOf(placement.id);
      if (children.isEmpty) return;
      expanded.add(placement.id);
      for (final child in children) {
        walk(child, depth + 1);
      }
    }

    for (final root in controller.rootPlacements) {
      walk(root, 0);
    }
    setState(() => _expandedIds
      ..clear()
      ..addAll(expanded));
  }

  void _expandAll() => _expandToLevels(1 << 30);

  Set<String> _ancestorsOf(TagPlacement? placement) {
    final ancestors = <String>{};
    final byId = {
      for (final item in widget.controller.state.placements) item.id: item,
    };
    var current = placement == null ? null : byId[placement.id];
    while (current?.parentId != null) {
      final parent = byId[current!.parentId];
      if (parent == null || !ancestors.add(parent.id)) break;
      current = parent;
    }
    return ancestors;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = _palette(context);
    // The selected placement must stay visible even after a global collapse.
    final expanded = {..._expandedIds, ..._ancestorsOf(widget.selected)};
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '标签层级',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${controller.state.tags.where((tag) => tag.spaceId == controller.activeSpaceId).length} 个标签实体 · ${controller.placementsInActiveSpace.length} 个位置',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: '展开层级',
                  icon: const Icon(Icons.unfold_more, size: 18),
                  onSelected: (levels) {
                    if (levels <= 0) {
                      _expandAll();
                    } else {
                      _expandToLevels(levels);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 1, child: Text('仅显示顶层')),
                    PopupMenuItem(value: 2, child: Text('展开到第 2 层')),
                    PopupMenuItem(value: 3, child: Text('展开到第 3 层')),
                    PopupMenuItem(value: 5, child: Text('展开到第 5 层')),
                    PopupMenuItem(value: 0, child: Text('全部展开')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final root in controller.rootPlacements)
                  _TagTreeNode(
                    controller: controller,
                    placement: root,
                    depth: 0,
                    expandedIds: expanded,
                    maxIndentDepth: _maxIndentDepth,
                    onToggle: (id) => setState(() {
                      if (!_expandedIds.remove(id)) {
                        _expandedIds.add(id);
                      }
                    }),
                    onDrop: (dragged, target) =>
                        _dropOn(dragged, target.id),
                    onDragStateChange: (id) =>
                        setState(() => _draggingId = id),
                  ),
                if (_draggingId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DragTarget<TagPlacement>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.parentId != null,
                      onAcceptWithDetails: (details) =>
                          _dropOn(details.data, null),
                      builder: (context, candidates, rejected) {
                        final highlighted = candidates.isNotEmpty;
                        return Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: highlighted
                                ? palette.primarySoft
                                : Colors.transparent,
                            border: Border.all(
                              color: highlighted
                                  ? palette.primary
                                  : palette.border,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '拖到此处设为顶层',
                            style: TextStyle(
                              fontSize: 11,
                              color: highlighted
                                  ? palette.primary
                                  : palette.textFaint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagTreeNode extends StatelessWidget {
  const _TagTreeNode({
    required this.controller,
    required this.placement,
    required this.depth,
    required this.expandedIds,
    required this.maxIndentDepth,
    required this.onToggle,
    required this.onDrop,
    required this.onDragStateChange,
  });
  final TagTagController controller;
  final TagPlacement placement;
  final int depth;
  final Set<String> expandedIds;
  final int maxIndentDepth;
  final ValueChanged<String> onToggle;
  final void Function(TagPlacement dragged, TagPlacement target) onDrop;
  final ValueChanged<String?> onDragStateChange;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final tag = controller.tagForPlacement(placement);
    final children = controller.childrenOf(placement.id);
    final selected = controller.activePlacementId == placement.id;
    final expanded = expandedIds.contains(placement.id);
    final indent = 7 + (depth > maxIndentDepth ? maxIndentDepth : depth) * 20;
    final row = InkWell(
      onTap: () => controller.selectPlacement(placement.id),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 36,
        padding: EdgeInsets.only(left: indent.toDouble(), right: 7),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: children.isEmpty
                  ? null
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onToggle(placement.id),
                      child: Tooltip(
                        message: expanded ? '收起' : '展开',
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14,
                        ),
                      ),
                    ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Color(tag.colorValue),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                tag.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? palette.primary : palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${controller.resourcesForPlacement(placement).length}',
              style: TextStyle(fontSize: 11, color: palette.textFaint),
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        DragTarget<TagPlacement>(
          onWillAcceptWithDetails: (details) {
            final dragged = details.data;
            if (dragged.id == placement.id) return false;
            if (dragged.parentId == placement.id) return false;
            return !_placementDescendants(
              controller,
              dragged.id,
            ).contains(placement.id);
          },
          onAcceptWithDetails: (details) => onDrop(details.data, placement),
          builder: (context, candidates, rejected) {
            final highlighted = candidates.isNotEmpty;
            return Container(
              decoration: highlighted
                  ? BoxDecoration(
                      color: palette.primarySoft,
                      border: Border.all(color: palette.primary),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Draggable<TagPlacement>(
                data: placement,
                onDragStarted: () => onDragStateChange(placement.id),
                onDragEnd: (_) => onDragStateChange(null),
                onDraggableCanceled: (_, _) => onDragStateChange(null),
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      border: Border.all(color: palette.primary),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(blurRadius: 12, color: Color(0x33000000)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Color(tag.colorValue),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tag.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.35, child: row),
                child: row,
              ),
            );
          },
        ),
        if (expanded)
          for (final child in children)
            _TagTreeNode(
              controller: controller,
              placement: child,
              depth: depth + 1,
              expandedIds: expandedIds,
              maxIndentDepth: maxIndentDepth,
              onToggle: onToggle,
              onDrop: onDrop,
              onDragStateChange: onDragStateChange,
            ),
      ],
    );
  }
}

class _TagResultPanel extends StatelessWidget {
  const _TagResultPanel({
    required this.controller,
    required this.placement,
    required this.onOpen,
    required this.onCreateTag,
    required this.onEditTag,
    required this.onMergeTag,
    required this.onSplitTag,
    required this.onDeleteTag,
  });

  final TagTagController controller;
  final TagPlacement? placement;
  final ResourceAction onOpen;
  final Future<void> Function(String? parentId) onCreateTag;
  final Future<void> Function(String placementId) onEditTag;
  final Future<void> Function(String placementId) onMergeTag;
  final Future<void> Function(String placementId) onSplitTag;
  final Future<void> Function(String placementId) onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final item = placement;
    if (item == null) return const Center(child: Text('选择一个标签'));
    final tag = controller.tagForPlacement(item);
    final sameTagPlacements = controller.state.placements
        .where((p) => p.tagId == tag.id)
        .toList();
    final resources = controller.resourcesForPlacement(item);
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(tag.colorValue),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            tag.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sameTagPlacements.length > 1
                          ? '唯一标签 · ${sameTagPlacements.length} 个位置共享同一资源集合'
                          : '层级位置 · 可在“标签操作”中更改上级标签',
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_TagMenuAction>(
                tooltip: '标签操作',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) {
                  switch (action) {
                    case _TagMenuAction.addRoot:
                      unawaited(onCreateTag(null));
                    case _TagMenuAction.addChild:
                      unawaited(onCreateTag(item.id));
                    case _TagMenuAction.edit:
                      unawaited(onEditTag(item.id));
                    case _TagMenuAction.reparent:
                      unawaited(_reparent(context, item));
                    case _TagMenuAction.merge:
                      unawaited(onMergeTag(item.id));
                    case _TagMenuAction.split:
                      unawaited(onSplitTag(item.id));
                    case _TagMenuAction.delete:
                      unawaited(onDeleteTag(item.id));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _TagMenuAction.addRoot,
                    child: Text('新建根标签'),
                  ),
                  PopupMenuItem(
                    value: _TagMenuAction.addChild,
                    child: Text('新建子标签'),
                  ),
                  PopupMenuItem(
                    value: _TagMenuAction.edit,
                    child: Text('编辑标签'),
                  ),
                  PopupMenuItem(
                    value: _TagMenuAction.reparent,
                    child: Text('更改上级标签…'),
                  ),
                  PopupMenuItem(
                    value: _TagMenuAction.merge,
                    child: Text('合并标签'),
                  ),
                  PopupMenuItem(
                    value: _TagMenuAction.split,
                    child: Text('拆分标签'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _TagMenuAction.delete,
                    child: Text('删除标签'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              Text(
                '标签位置',
                style: TextStyle(fontSize: 11, color: palette.textFaint),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final placement in sameTagPlacements)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            height: 26,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: palette.primarySoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              controller.pathOf(placement.id),
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: resources.length,
            itemBuilder: (context, index) {
              final resource = resources[index];
              return InkWell(
                onDoubleTap: () => unawaited(onOpen(resource)),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: palette.border)),
                  ),
                  child: Row(
                    children: [
                      _ResourceIcon(resource: resource, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ResourceIdentity(
                          resource: resource,
                          storageRoot: controller.storageRoot?.path,
                        ),
                      ),
                      Text(
                        _formatDate(resource.modifiedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _reparent(BuildContext context, TagPlacement placement) async {
    final updated = await showReparentTagDialog(
      context,
      controller: controller,
      placement: placement,
    );
    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${controller.tagForPlacement(placement).name}”的上级标签已更新',
          ),
        ),
      );
    }
  }
}

class _SearchFilterStrip extends StatelessWidget {
  const _SearchFilterStrip({
    required this.controller,
    required this.windowWidth,
    required this.onClearSearch,
  });
  final TagTagController controller;
  final double windowWidth;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final tags = controller.state.tags
        .where((tag) => tag.spaceId == controller.activeSpaceId)
        .take(3)
        .toList();
    return Container(
      height: 46,
      padding: EdgeInsets.symmetric(
        horizontal: windowWidth < 720 ? 10 : 20,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Segmented<SearchKindFilter>(
            values: const [
              SearchKindFilter.all,
              SearchKindFilter.file,
              SearchKindFilter.folder,
            ],
            selected: controller.searchKind,
            label: (value) => switch (value) {
              SearchKindFilter.all => '全部',
              SearchKindFilter.file => '文件',
              SearchKindFilter.folder => '文件夹',
            },
            onSelected: controller.setSearchKind,
          ),
          const SizedBox(width: 8),
          for (final tag in tags) ...[
            _FilterChip(controller: controller, tag: tag),
            const SizedBox(width: 8),
          ],
          TextButton(onPressed: onClearSearch, child: const Text('清除')),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.controller, required this.tag});
  final TagTagController controller;
  final TagDefinition tag;

  @override
  Widget build(BuildContext context) {
    final condition = controller.searchConditionForTag(tag.id);
    final label = switch (condition) {
      SearchTagCondition.none => tag.name,
      SearchTagCondition.and => '${tag.name} · AND',
      SearchTagCondition.or => '${tag.name} · OR',
      SearchTagCondition.not => '${tag.name} · NOT',
    };
    return OutlinedButton(
      onPressed: () =>
          controller.setSearchTagCondition(tag.id, switch (condition) {
            SearchTagCondition.none => SearchTagCondition.and,
            SearchTagCondition.and => SearchTagCondition.or,
            SearchTagCondition.or => SearchTagCondition.not,
            SearchTagCondition.not => SearchTagCondition.none,
          }),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: condition == SearchTagCondition.not
            ? TagTagColors.destructive
            : condition == SearchTagCondition.none
            ? _palette(context).textMuted
            : _palette(context).primary,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _InboxScopeStrip extends StatelessWidget {
  const _InboxScopeStrip({required this.controller, required this.windowWidth});
  final TagTagController controller;
  final double windowWidth;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      height: 46,
      padding: EdgeInsets.symmetric(
        horizontal: windowWidth < 720 ? 10 : 20,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          _Segmented<InboxScope>(
            values: const [InboxScope.currentSpace, InboxScope.global],
            selected: controller.inboxScope,
            label: (value) => value == InboxScope.currentSpace ? '当前空间' : '全局',
            onSelected: controller.setInboxScope,
          ),
          const SizedBox(width: 8),
          Text(
            '${controller.visibleResources.length} 个资源没有有效标签',
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          for (final value in values)
            InkWell(
              onTap: () => onSelected(value),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: value == selected
                      ? palette.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label(value),
                  style: TextStyle(
                    fontSize: 12,
                    color: value == selected ? palette.text : palette.textMuted,
                    fontWeight: value == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _StatusTab { health, history }

class _StatusDrawer extends StatelessWidget {
  const _StatusDrawer({
    required this.controller,
    required this.findings,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onClose,
    required this.onCreateBackup,
    required this.onOpenFullLog,
    required this.onOpenConsistency,
  });

  final TagTagController controller;
  final List<ConsistencyFinding> findings;
  final _StatusTab selectedTab;
  final ValueChanged<_StatusTab> onTabSelected;
  final VoidCallback onClose;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onOpenFullLog;
  final Future<void> Function() onOpenConsistency;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Material(
      elevation: 18,
      color: palette.surfaceRaised,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.border)),
        ),
        child: Column(
          children: [
            Container(
              height: 70,
              padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: TagTagColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '资料库状态',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          controller.storageRoot?.path ?? '存储根尚未初始化',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SmallIconButton(
                    icon: Icons.close,
                    tooltip: '关闭状态中心',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Container(
              height: 43,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  _DrawerTab(
                    label: '健康状态',
                    selected: selectedTab == _StatusTab.health,
                    onTap: () => onTabSelected(_StatusTab.health),
                  ),
                  const SizedBox(width: 18),
                  _DrawerTab(
                    label: '操作日志',
                    selected: selectedTab == _StatusTab.history,
                    onTap: () => onTabSelected(_StatusTab.history),
                  ),
                ],
              ),
            ),
            Expanded(
              child: selectedTab == _StatusTab.health
                  ? _HealthPanel(
                      controller: controller,
                      findings: findings,
                      onCreateBackup: onCreateBackup,
                      onOpenConsistency: onOpenConsistency,
                    )
                  : _HistoryPanel(
                      controller: controller,
                      onOpenFullLog: onOpenFullLog,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTab extends StatelessWidget {
  const _DrawerTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 43,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: selected
              ? Border(bottom: BorderSide(width: 2, color: palette.primary))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? palette.primary : palette.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({
    required this.controller,
    required this.findings,
    required this.onCreateBackup,
    required this.onOpenConsistency,
  });
  final TagTagController controller;
  final List<ConsistencyFinding> findings;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onOpenConsistency;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          color: TagTagColors.success.withValues(alpha: 0.09),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 28,
                color: TagTagColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      findings.isEmpty
                          ? '所有受管资源均可访问'
                          : '${findings.length} 项需要处理',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '上次完整扫描：刚刚',
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _StatusSection(
          title: '一致性',
          child: InkWell(
            onTap: () => unawaited(onOpenConsistency()),
            borderRadius: BorderRadius.circular(5),
            child: Tooltip(
              message: '打开一致性告警列表',
              child: _StatusRow(
                icon: findings.isEmpty
                    ? Icons.check
                    : Icons.warning_amber_outlined,
                title: findings.isEmpty
                    ? '${controller.state.resources.length} 个资源已核对'
                    : '${findings.length} 个一致性告警',
                subtitle: findings.isEmpty ? '没有孤立内容或缺失资源' : '打开完整告警列表进行处理',
              ),
            ),
          ),
        ),
        _StatusSection(
          title: '存储',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${controller.state.resources.length} 个受管资源'),
                  Text(
                    _formatBytes(
                      controller.state.resources.fold<int>(
                        0,
                        (sum, item) => sum + (item.sizeBytes ?? 0),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已使用 ${_formatBytes(controller.state.resources.fold<int>(0, (sum, item) => sum + (item.sizeBytes ?? 0)))}',
                  style: TextStyle(
                    fontSize: 11,
                    color: _palette(context).textFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
        _StatusSection(
          title: '备份',
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _StatusRow(
                      icon: Icons.storage_outlined,
                      title: '完整备份',
                      subtitle: '包含资源、索引与操作日志',
                    ),
                  ),
                  _PrototypeButton(
                    label: '创建备份',
                    onPressed: () => unawaited(onCreateBackup()),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '尚未创建备份',
                  style: TextStyle(
                    fontSize: 11,
                    color: _palette(context).textFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel({required this.controller, required this.onOpenFullLog});
  final TagTagController controller;
  final Future<void> Function() onOpenFullLog;

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  late Future<List<ManagedOperation>> _managedOperations;
  String? _undoingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managedOperations = widget.controller.listOperations();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManagedOperation>>(
      future: _managedOperations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('读取操作日志失败：${snapshot.error}'));
        }
        final entries = <_HistoryEntry>[
          for (final operation in snapshot.data ?? const <ManagedOperation>[])
            _HistoryEntry.managed(operation),
          for (final operation in widget.controller.tagOperations)
            _HistoryEntry.tag(operation),
        ]..sort((first, second) => second.createdAt.compareTo(first.createdAt));
        final latestActiveTagId = widget.controller.tagOperations
            .where((operation) => operation.undoneAt == null)
            .map((operation) => operation.id)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: TagTagColors.destructive),
                ),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('暂无操作记录')),
              )
            else
              for (final (index, entry) in entries.take(8).toList().indexed)
                _TimelineItem(
                  icon: entry.icon,
                  title: entry.title,
                  subtitle: entry.subtitle,
                  undone: entry.undone,
                  undoing: _undoingId == entry.id,
                  showConnector: index < entries.take(8).length - 1,
                  onUndo:
                      entry.undone ||
                          _undoingId != null ||
                          entry.tagOperation && entry.id != latestActiveTagId
                      ? null
                      : () => _undo(entry),
                ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => unawaited(widget.onOpenFullLog()),
              icon: const Icon(Icons.history_outlined, size: 17),
              label: const Text('查看完整操作日志'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _undo(_HistoryEntry entry) async {
    setState(() {
      _undoingId = entry.id;
      _error = null;
    });
    try {
      if (entry.tagOperation) {
        await widget.controller.undoTagOperation(entry.id);
      } else {
        await widget.controller.undoOperation(entry.id);
      }
      if (!mounted) return;
      setState(() {
        _undoingId = null;
        _managedOperations = widget.controller.listOperations();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _undoingId = null;
        _error = '撤销失败：$error';
      });
    }
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: palette.textFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.primarySoft,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 16, color: palette.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.undone,
    required this.undoing,
    required this.showConnector,
    required this.onUndo,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool undone;
  final bool undoing;
  final bool showConnector;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.primarySoft,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(icon, size: 16, color: palette.primary),
                  ),
                  if (showConnector)
                    Expanded(
                      child: Container(
                        width: 1,
                        margin: const EdgeInsets.only(top: 3),
                        color: palette.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ],
              ),
            ),
            if (undone)
              Text(
                '已撤销',
                style: TextStyle(fontSize: 11, color: palette.textFaint),
              )
            else if (undoing)
              const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (onUndo != null)
              TextButton(onPressed: onUndo, child: const Text('撤销')),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.undone,
    required this.tagOperation,
  });

  factory _HistoryEntry.managed(ManagedOperation operation) {
    final (icon, title) = switch (operation.type) {
      ManagedOperationType.importCopy => (
        Icons.content_copy_outlined,
        '复制导入资源',
      ),
      ManagedOperationType.importMove => (
        Icons.drive_file_move_outline,
        '移动导入资源',
      ),
      ManagedOperationType.exitRestore => (Icons.restore, '恢复原路径并退出管理'),
      ManagedOperationType.exitMove => (
        Icons.drive_file_move_outline,
        '移动到指定位置并退出',
      ),
      ManagedOperationType.exitRecycle => (Icons.delete_outline, '移入回收站并退出'),
      ManagedOperationType.takeover => (Icons.add_task_outlined, '接管未受管内容'),
      ManagedOperationType.untrackedMoveOut => (
        Icons.drive_file_move_outline,
        '移出未受管内容',
      ),
      ManagedOperationType.externalMoveAccept => (
        Icons.link_outlined,
        '接受外部移动',
      ),
      ManagedOperationType.externalMoveRestore => (
        Icons.settings_backup_restore,
        '恢复记录路径',
      ),
    };
    return _HistoryEntry(
      id: operation.id,
      icon: icon,
      title: title,
      subtitle:
          '${_formatDate(operation.createdAt)} · ${operation.destinationRelativePath}',
      createdAt: operation.createdAt,
      undone: operation.undoneAt != null,
      tagOperation: false,
    );
  }

  factory _HistoryEntry.tag(TagDomainOperation operation) => _HistoryEntry(
    id: operation.id,
    icon: operation.type == TagDomainOperationType.merge
        ? Icons.merge_type
        : Icons.call_split,
    title: operation.summary,
    subtitle: _formatDate(operation.createdAt),
    createdAt: operation.createdAt,
    undone: operation.undoneAt != null,
    tagOperation: true,
  );

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool undone;
  final bool tagOperation;
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.12),
            border: Border.all(color: palette.primary, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(blurRadius: 30, color: Colors.black26),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_upload_outlined,
                  size: 28,
                  color: palette.primary,
                ),
                const SizedBox(height: 6),
                const Text(
                  '释放以导入并标注',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  count > 0 ? '$count 个资源' : '资源将进入导入确认窗口',
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyResources extends StatelessWidget {
  const _EmptyResources({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search, size: 30),
        const SizedBox(height: 9),
        const Text('没有符合条件的资源', style: TextStyle(fontWeight: FontWeight.w600)),
        TextButton(onPressed: onClear, child: const Text('清除搜索')),
      ],
    ),
  );
}

class _PrototypeButton extends StatelessWidget {
  const _PrototypeButton({
    this.icon,
    this.label,
    required this.onPressed,
    this.primary = false,
    this.tooltip,
  });
  final IconData? icon;
  final String? label;
  final VoidCallback onPressed;
  final bool primary;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: 34,
      child: primary
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: icon == null
                  ? const SizedBox.shrink()
                  : Icon(icon, size: 17),
              label: label == null ? const SizedBox.shrink() : Text(label!),
              style: FilledButton.styleFrom(
                minimumSize: Size(label == null ? 34 : 44, 34),
                padding: EdgeInsets.symmetric(
                  horizontal: label == null ? 8 : 12,
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: icon == null
                  ? const SizedBox.shrink()
                  : Icon(icon, size: 17),
              label: label == null ? const SizedBox.shrink() : Text(label!),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(label == null ? 34 : 44, 34),
                padding: EdgeInsets.symmetric(
                  horizontal: label == null ? 8 : 12,
                ),
              ),
            ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 34,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

enum _ResourceMenuAction { reveal, addTag, clearTags, restore, move, recycle }

enum _ImportMenuAction { files, folder }

enum _TagMenuAction { addRoot, addChild, edit, reparent, merge, split, delete }

class _Palette {
  const _Palette({
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.canvas,
    required this.navigation,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
  });
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color canvas;
  final Color navigation;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;
}

_Palette _palette(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return _Palette(
    primary: dark ? const Color(0xff7da6ff) : TagTagColors.primary,
    primarySoft: dark ? const Color(0xff1b2c4f) : TagTagColors.primarySoft,
    text: dark ? const Color(0xffedf1f7) : TagTagColors.foreground,
    textMuted: dark ? const Color(0xffaab4c2) : TagTagColors.secondaryText,
    textFaint: dark ? const Color(0xff8792a0) : TagTagColors.textFaint,
    canvas: dark ? const Color(0xff171a1f) : TagTagColors.canvas,
    navigation: dark ? const Color(0xff1d2128) : TagTagColors.navigation,
    surface: dark ? const Color(0xff22262e) : TagTagColors.surface,
    surfaceSubtle: dark ? const Color(0xff1d2128) : TagTagColors.surfaceSubtle,
    surfaceRaised: dark ? const Color(0xff282d36) : TagTagColors.surface,
    border: dark ? const Color(0xff353b45) : TagTagColors.border,
    borderStrong: dark ? const Color(0xff49515e) : TagTagColors.borderStrong,
  );
}

String _viewTitle(ResourceView view) => switch (view) {
  ResourceView.all => '全部资源',
  ResourceView.hierarchy => '标签层级',
  ResourceView.inbox => '待整理',
  ResourceView.recent => '最近',
  ResourceView.search => '搜索',
};

String _viewSubtitle(TagTagController controller) =>
    switch (controller.activeView) {
      ResourceView.all => '当前空间中的 ${controller.visibleResources.length} 个受管资源',
      ResourceView.hierarchy => '按标签实体与位置浏览资源',
      ResourceView.inbox => '没有有效标签的受管资源',
      ResourceView.recent => '最近打开、导入和标注的资源',
      ResourceView.search => '按名称、路径、类型、时间和标签组合检索',
    };

String _resourceType(TagResource resource) {
  if (resource.kind == ResourceKind.folder) return '文件夹';
  final extension = path
      .extension(resource.name)
      .replaceFirst('.', '')
      .toUpperCase();
  if (extension.isEmpty) return '文件';
  return switch (extension) {
    'TXT' => '文本文档',
    'JPG' || 'JPEG' => 'JPEG 图像',
    'PNG' => 'PNG 图像',
    'PDF' => 'PDF 文档',
    'XLS' || 'XLSX' => 'Excel 工作簿',
    _ => '$extension 文件',
  };
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '今天 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month} 月 ${local.day} 日';
}

String _spaceNames(TagTagController controller, String resourceId) {
  final spaces = controller.spacesForResource(resourceId);
  if (spaces.isEmpty) return '—';
  return spaces.map((space) => space.name).join('、');
}

/// Inspector location line: prototype shows "存储根 / Design / Brand"
/// (the containing folder, prefixed with the storage root).
String _displayLocation(String value, String? storageRoot) {
  final parent = path.dirname(value);
  final root = storageRoot;
  if (root != null &&
      (parent == root ||
          parent.startsWith('$root\\') ||
          parent.startsWith('$root/'))) {
    if (parent == root) return '存储根';
    return '存储根 / ${path.split(parent.substring(root.length + 1)).join(' / ')}';
  }
  return parent;
}

String _displayParent(String value, String? storageRoot) {
  final parent = path.dirname(value);
  final root = storageRoot;
  if (root != null &&
      (parent == root ||
          parent.startsWith('$root\\') ||
          parent.startsWith('$root/'))) {
    if (parent == root) return '存储根';
    final relative = parent.substring(root.length + 1);
    return path.split(relative).join(' / ');
  }
  final parts = path.split(parent);
  if (parts.length <= 2) return parent;
  return parts.skip(parts.length - 2).join(' / ');
}

Set<String> _placementDescendants(
  TagTagController controller,
  String placementId,
) {
  final result = <String>{};
  void visit(String id) {
    for (final child in controller.childrenOf(id)) {
      if (result.add(child.id)) visit(child.id);
    }
  }

  visit(placementId);
  return result;
}

/// Opens the reparent dialog for [placement] and reports whether the
/// hierarchy was actually updated.
Future<bool?> showReparentTagDialog(
  BuildContext context, {
  required TagTagController controller,
  required TagPlacement placement,
}) {
  return showPrototypeDialog<bool>(
    context: context,
    builder: (context) =>
        _ReparentTagDialog(controller: controller, placement: placement),
  );
}

class _ReparentTagDialog extends StatefulWidget {
  const _ReparentTagDialog({required this.controller, required this.placement});

  final TagTagController controller;
  final TagPlacement placement;

  @override
  State<_ReparentTagDialog> createState() => _ReparentTagDialogState();
}

class _ReparentTagDialogState extends State<_ReparentTagDialog> {
  late String? _pendingParentId = widget.placement.parentId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final placement = widget.placement;
    final tag = controller.tagForPlacement(placement);
    final descendants = _placementDescendants(controller, placement.id);
    final changed = _pendingParentId != placement.parentId;
    return PrototypeDialogFrame(
      width: 480,
      desktopHeight: null,
      icon: Icons.account_tree_outlined,
      title: '更改上级标签',
      subtitle: '调整“${tag.name}”在标签层级中的位置',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当前位置：${controller.pathOf(placement.id)}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '上级标签',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            DropdownButtonFormField<String>(
              key: ValueKey('${placement.id}|$_pendingParentId'),
              initialValue: _pendingParentId ?? '',
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('无上级（顶层）')),
                for (final candidate in controller.placementsInActiveSpace)
                  if (candidate.id != placement.id &&
                      !descendants.contains(candidate.id))
                    DropdownMenuItem(
                      value: candidate.id,
                      child: Text(
                        controller.pathOf(candidate.id),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (value) => setState(() {
                _pendingParentId = value == null || value.isEmpty
                    ? null
                    : value;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: changed ? _apply : null,
          child: const Text('应用'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    try {
      await widget.controller.reparentPlacement(
        widget.placement.id,
        _pendingParentId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    }
  }
}
