import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/ui/home_screen.dart';
import 'package:tagtag/ui/prototype_dialogs.dart';
import 'package:tagtag/ui/tagtag_theme.dart';

void main() {
  testWidgets('search page saves, applies and deletes a saved query', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    await _pumpWorkspace(tester, fixture.controller);
    final controller = fixture.controller;

    await tester.tap(find.byKey(const ValueKey('nav-搜索')));
    await tester.pumpAndSettle();

    // Disabled until there is an active condition.
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存查询'))
          .enabled,
      isFalse,
    );

    await tester.enterText(find.widgetWithText(TextField, '搜索名称、路径或标签'), '架构');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-search-query')));
    await tester.pumpAndSettle();
    expect(find.text('保存查询'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, '查询名称'), '  架构文件  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('架构文件'), findsOneWidget);
    expect(controller.savedQueriesInActiveSpace.single.name, '架构文件');

    // Applying restores the condition and the visible query text.
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(controller.searchTerm, isEmpty);

    await tester.tap(find.text('架构文件'));
    await tester.pumpAndSettle();
    expect(controller.searchTerm, '架构');
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '搜索名称、路径或标签'))
          .controller
          ?.text,
      '架构',
    );

    final queryId = controller.savedQueriesInActiveSpace.single.id;
    await tester.tap(find.byKey(ValueKey('delete-saved-query-$queryId')));
    await tester.pumpAndSettle();
    expect(find.text('架构文件'), findsNothing);
    expect(controller.savedQueriesInActiveSpace, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hierarchy tag menu pin and hide labels follow state', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    fixture.controller.showTagHierarchy();
    await _pumpWorkspace(tester, fixture.controller);
    final controller = fixture.controller;

    await tester.tap(find.text('设计'));
    await tester.pumpAndSettle();
    final placementId = controller.activePlacementId!;

    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    expect(find.text('固定到常用'), findsOneWidget);
    expect(find.text('从常用隐藏'), findsOneWidget);

    await tester.tap(find.text('固定到常用'));
    await tester.pumpAndSettle();
    expect(controller.isPlacementPinned(placementId), isTrue);

    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消固定'), findsOneWidget);

    await tester.tap(find.text('从常用隐藏'));
    await tester.pumpAndSettle();
    expect(controller.isPlacementHidden(placementId), isTrue);

    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消固定'), findsOneWidget);
    expect(find.text('取消隐藏'), findsOneWidget);
    await tester.tap(find.text('取消隐藏'));
    await tester.pumpAndSettle();
    expect(controller.isPlacementHidden(placementId), isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Quick Tag lists pinned placements in the frequent section', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    await _pumpWorkspace(tester, fixture.controller);
    final controller = fixture.controller;

    // Pin a placement with no usage events; it must lead the 常用标签 list.
    await tester.runAsync(
      () => controller.togglePlacementPinned('place-project'),
    );
    controller.selectResource(controller.state.resources.first.id);
    await tester.pumpAndSettle();

    await tester.tap(find.text('快速标注'));
    await tester.pumpAndSettle();

    expect(find.text('常用标签'), findsOneWidget);
    expect(find.text('最近使用'), findsNothing);
    final firstOption = tester
        .widgetList(find.byType(PrototypeTagOption))
        .first;
    expect((firstOption as PrototypeTagOption).name, '项目');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('history tab clears usage history after confirmation', (
    tester,
  ) async {
    final fixture = await _createFixture(tester);
    addTearDown(() => fixture.sandbox.delete(recursive: true));
    await _pumpWorkspace(tester, fixture.controller);
    final controller = fixture.controller;
    expect(controller.state.usageEvents, isNotEmpty);

    await tester.tap(find.text('资料库正常'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('操作日志'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clear-usage-history')));
    await tester.pumpAndSettle();
    expect(find.text('清空历史记录？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.state.usageEvents, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('clear-usage-history')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('清空'));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(controller.state.usageEvents, isEmpty);
    expect(find.text('清空历史记录？'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<({Directory sandbox, TagTagController controller})> _createFixture(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('tagtag-savedq-ui-'),
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
