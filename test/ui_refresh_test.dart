import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/ui/home_screen.dart';
import 'package:tagtag/ui/prototype_dialogs.dart';
import 'package:tagtag/ui/tagtag_theme.dart';

void main() {
  testWidgets('wide workspace uses expanded modern navigation', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    expect(
      tester.getSize(find.byKey(const ValueKey('primary-navigation'))).width,
      232,
    );
    expect(find.text('本地资料库'), findsWidgets);
    expect(find.bySemanticsLabel('TAGTAG 标志'), findsWidgets);
    expect(find.byTooltip('导入'), findsOneWidget);
    expect(find.byTooltip('切换标签空间'), findsOneWidget);
    expect(find.text('资源详情'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // The merged import entry offers both source kinds.
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入文件'), findsOneWidget);
    expect(find.text('导入文件夹'), findsOneWidget);
    await tester.tapAt(const Offset(8, 400));
    await tester.pumpAndSettle();

    // The space switcher keeps the create-space entry point.
    await tester.tap(find.byKey(const ValueKey('space-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('设计空间'), findsWidgets);
    expect(find.text('新建标签空间'), findsOneWidget);

    await tester.tap(find.text('新建标签空间'));
    await tester.pumpAndSettle();
    expect(find.text('空间名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact navigation preserves the dedicated search page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    expect(
      tester.getSize(find.byKey(const ValueKey('primary-navigation'))).width,
      72,
    );
    expect(find.byTooltip('全部资源'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-搜索')));
    await tester.pump();

    expect(fixture.controller.activeView, ResourceView.search);
    expect(find.text('搜索'), findsWidgets);
    expect(find.widgetWithText(TextField, '搜索名称、路径或标签'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hierarchy and settings use structured desktop workspaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    fixture.controller.showTagHierarchy();

    await _pumpWorkspace(tester, fixture.controller);

    expect(find.text('标签层级'), findsWidgets);
    expect(find.byTooltip('展开层级'), findsOneWidget);

    await tester.tap(find.text('设计'));
    await tester.pumpAndSettle();
    expect(find.text('设计'), findsWidgets);

    // Reparenting now lives in the per-tag action menu.
    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更改上级标签…'));
    await tester.pumpAndSettle();
    expect(find.text('更改上级标签'), findsOneWidget);
    expect(find.text('上级标签'), findsOneWidget);
    expect(find.textContaining('当前位置：'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // The expansion dialog collapses and re-expands the tree.
    expect(find.text('阅读'), findsOneWidget);
    await tester.tap(find.byTooltip('展开层级'));
    await tester.pumpAndSettle();
    expect(find.text('设置标签树展开的深度'), findsOneWidget);
    await tester.tap(find.text('仅显示顶层'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsNothing);
    expect(find.text('个人'), findsOneWidget);
    await tester.tap(find.byTooltip('展开层级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部展开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-设置')));
    await tester.pumpAndSettle();
    expect(find.text('常规'), findsWidgets);
    expect(find.text('存储与备份'), findsOneWidget);
    expect(find.text('Windows 集成'), findsOneWidget);

    await tester.tap(find.text('存储与备份'));
    await tester.pumpAndSettle();
    expect(find.text('创建完整备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.text('导出空间包'), findsOneWidget);
    expect(find.text('导入空间包'), findsOneWidget);
    expect(find.text('导出空间模板'), findsOneWidget);
    expect(find.text('导入空间模板'), findsOneWidget);

    await tester.tap(find.text('Windows 集成'));
    await tester.pumpAndSettle();
    expect(find.text('悬浮接收目标'), findsOneWidget);
    expect(find.text('Ctrl + Shift + T'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ctrl+K opens the search view with a focused query field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(fixture.controller.activeView, ResourceView.search);
    final field = find.widgetWithText(TextField, '搜索名称、路径或标签');
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tag tree drag reparents a tag onto another tag', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() async {
      // Windows may keep the just-persisted JSON briefly locked; leave the
      // system temp directory for OS cleanup instead of failing the test.
      try {
        await fixture.sandbox.delete(recursive: true);
      } on PathAccessException {
        // Ignored.
      }
    });
    fixture.controller.showTagHierarchy();

    await _pumpWorkspace(tester, fixture.controller);

    TagPlacement placementOf(String id) => fixture.controller.state.placements
        .firstWhere((placement) => placement.id == id);
    expect(placementOf('place-project-design').parentId, 'place-project');

    // Drag 设计 one row down onto 个人.
    await tester.drag(find.text('设计'), const Offset(0, 36));
    // Let the background persistence finish before the sandbox is deleted.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(placementOf('place-project-design').parentId, 'place-personal');
    expect(find.textContaining('已更新：'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('log page filters entries by level, category, and keyword', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    await tester.runAsync(() async {
      await fixture.controller.createPlacement(name: '筛选目标', colorValue: 0);
      await fixture.controller.updatePreferences(appearanceTheme: 'dark');
    });

    await _pumpWorkspace(tester, fixture.controller);

    await tester.tap(find.byKey(const ValueKey('nav-日志')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('log-panel'));
    expect(panel, findsOneWidget);
    expect(find.textContaining('新建标签“筛选目标”'), findsOneWidget);
    expect(find.textContaining('更新设置：外观 深色'), findsOneWidget);

    // Category filter composes (via the compact dropdown).
    await tester.tap(find.byKey(const ValueKey('log-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('新建标签“筛选目标”'), findsNothing);
    expect(find.textContaining('更新设置：外观 深色'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('log-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部类别').last);
    await tester.pumpAndSettle();

    // Keyword filter.
    await tester.enterText(find.widgetWithText(TextField, '筛选日志内容'), '筛选目标');
    await tester.pumpAndSettle();
    expect(find.textContaining('新建标签“筛选目标”'), findsOneWidget);
    expect(find.textContaining('更新设置：外观 深色'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dialogs follow the selected dark appearance', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    await tester.runAsync(
      () => fixture.controller.updatePreferences(appearanceTheme: 'dark'),
    );

    await _pumpWorkspace(tester, fixture.controller);

    await tester.tap(find.byTooltip('快速标注'));
    await tester.pumpAndSettle();

    final dialog = find.byType(PrototypeQuickTagDialog);
    expect(dialog, findsOneWidget);
    expect(
      Theme.of(tester.element(dialog)).brightness,
      Brightness.dark,
      reason: 'dialogs must inherit the selected dark theme',
    );
    // Tooltips stay readable in dark mode (dark background, light text).
    final tooltipTheme = Theme.of(tester.element(dialog)).tooltipTheme;
    final decoration = tooltipTheme.decoration as BoxDecoration;
    expect(decoration.color, TagTagColors.foreground);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tag menu exposes the uniqueness policy and duplicate badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() async {
      // Windows may keep the just-persisted JSON briefly locked; leave the
      // system temp directory for OS cleanup instead of failing the test.
      try {
        await fixture.sandbox.delete(recursive: true);
      } on PathAccessException {
        // Ignored.
      }
    });
    fixture.controller.showTagHierarchy();

    await _pumpWorkspace(tester, fixture.controller);

    // Expand everything so the duplicated 参考 tags become visible.
    await tester.tap(find.byTooltip('展开层级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部展开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('同名'), findsWidgets);

    await tester.tap(find.text('设计'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    expect(find.text('设为唯一标签'), findsOneWidget);
    await tester.tap(find.text('设为唯一标签'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      fixture.controller.tagNamePolicyOf('tag-design'),
      TagNamePolicy.unique,
    );

    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消唯一标记'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('advanced search dialog applies size filters', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    await tester.tap(find.byKey(const ValueKey('nav-搜索')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('高级筛选'));
    await tester.pumpAndSettle();

    expect(find.text('大小（MB）'), findsWidgets);
    expect(find.text('创建时间'), findsWidgets);
    expect(find.text('修改时间'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('advanced-min-size')),
      '2',
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(fixture.controller.searchMinimumSizeBytes, 2 * 1024 * 1024);
    expect(fixture.controller.hasAdvancedSearchFilters, isTrue);

    // Reopen and clear everything.
    await tester.tap(find.byTooltip('高级筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除全部条件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(fixture.controller.searchMinimumSizeBytes, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resource rows expose a right-click menu with rename', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    await tester.tapAt(
      tester.getCenter(find.text('竞品对照.xlsx')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    for (final label in ['打开', '在资源管理器中定位', '添加新标签', '重命名…']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('恢复先前路径并退出管理'), findsOneWidget);
    expect(find.text('移入回收站并退出'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Escape closes the status drawer before anything else', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));

    await _pumpWorkspace(tester, fixture.controller);

    await tester.tap(find.text('资料库正常'));
    await tester.pumpAndSettle();
    expect(find.text('资料库状态'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('资料库状态'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<({Directory sandbox, TagTagController controller})> _createFixture(
  WidgetTester tester,
) async {
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('tagtag-ui-refresh-'),
  ))!;
  final store = LocalStore(baseDirectory: Directory('${sandbox.path}/config'));
  await tester.runAsync(() => store.save(AppState.demo()));
  final controller = TagTagController(store: store);
  await tester.runAsync(controller.load);
  return (sandbox: sandbox, controller: controller);
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  TagTagController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTagTagTheme(),
      home: TagTagHome(
        controller: controller,
        fileActions: WindowsFileActions(),
        onRestoreGlobalBackup: (_, _) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}
