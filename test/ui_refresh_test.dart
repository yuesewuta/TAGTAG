import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/ui/home_screen.dart';
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
    expect(find.byTooltip('导入文件'), findsOneWidget);
    expect(find.byTooltip('导入文件夹'), findsOneWidget);
    expect(find.byTooltip('切换标签空间'), findsOneWidget);
    expect(find.text('资源详情'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

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
    expect(find.text('设置标签层级'), findsOneWidget);
    expect(find.text('上级标签'), findsOneWidget);
    expect(find.text('应用层级'), findsOneWidget);

    await tester.tap(find.text('设计'));
    await tester.pumpAndSettle();
    expect(find.text('设计'), findsWidgets);
    expect(find.text('已选择“设计”'), findsOneWidget);

    // The hierarchy shortcut button focuses the parent selector.
    await tester.tap(find.byTooltip('设置标签层级'));
    await tester.pumpAndSettle();
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
