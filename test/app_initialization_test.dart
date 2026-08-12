import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/main.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/platform/windows_quick_tag_hotkey.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/library_locator.dart';
import 'package:tagtag/storage/managed_library.dart';
import 'package:tagtag/ui/home_screen.dart';

void main() {
  testWidgets('shows a useful error when the storage root picker fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      TagTagApp(
        locator: _EmptyLibraryLocator(),
        storageRootPicker: () async => throw StateError('picker unavailable'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择存储根目录'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('picker unavailable'), findsOneWidget);
  });

  testWidgets('consistency dialog exposes explicit actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await tester.runAsync(() async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-consistency-dialog-',
      );
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/source.txt');
      await source.writeAsString('external move');
      final library = await ManagedLibrary.initialize(root);
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await store.save(AppState.demo());
      final controller = TagTagController(store: store, library: library);
      await controller.load();
      final imported = await controller.importManagedResource(
        source: source,
        targetDirectory: '',
      );
      await File(imported.path).rename('${root.path}/renamed.txt');
      return (sandbox: sandbox, library: library, controller: controller);
    });
    final sandbox = fixture!.sandbox;
    final library = fixture.library;
    final controller = fixture.controller;
    addTearDown(() => sandbox.delete(recursive: true));
    addTearDown(library.close);

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Backup and space portability commands live in the settings dialog.
    await tester.tap(find.byKey(const ValueKey('nav-设置')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存储与备份'));
    await tester.pumpAndSettle();
    expect(find.text('创建完整备份'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.text('导出空间包'), findsOneWidget);
    expect(find.text('导入空间包'), findsOneWidget);
    expect(find.text('导出空间模板'), findsOneWidget);
    expect(find.text('导入空间模板'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // The health button opens the status drawer; its consistency row opens
    // the full consistency dialog.
    final healthButton = find.byTooltip('2 个一致性告警');
    await _pumpUntilFound(tester, healthButton);
    await tester.tap(healthButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开完整告警列表进行处理'));
    await tester.pumpAndSettle();

    expect(find.text('发现未受管内容'), findsOneWidget);
    expect(find.text('受管资源被外部删除或移动'), findsOneWidget);
    expect(find.text('接管'), findsOneWidget);
    expect(find.text('移出'), findsOneWidget);
    expect(find.text('接受新路径'), findsOneWidget);
    expect(find.text('恢复记录路径'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'native Quick Tag activation reuses the selected-resource dialog',
    (tester) async {
      const channel = MethodChannel('tagtag/windows_quick_tag');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isRegistered');
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final sandbox = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tagtag-global-quick-tag-'),
      ))!;
      addTearDown(() => sandbox.delete(recursive: true));
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await tester.runAsync(() => store.save(AppState.demo()));
      final controller = TagTagController(store: store);
      await tester.runAsync(controller.load);
      controller.selectResource('resource-architecture');

      await tester.pumpWidget(
        MaterialApp(
          home: TagTagHome(
            controller: controller,
            fileActions: WindowsFileActions(),
            quickTagHotkey: WindowsQuickTagHotkey(channel: channel),
            onRestoreGlobalBackup: (_, _) async {},
          ),
        ),
      );
      await tester.pump();
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('activated')),
        (_) {},
      );
      final quickTagDialog = find.text('快速标注');
      await _pumpUntilFound(tester, quickTagDialog);

      expect(quickTagDialog, findsWidgets);
      expect(find.text('1 个资源 · 设计空间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('folder Quick Tag exposes its current inheritance rule', (
    tester,
  ) async {
    const channel = MethodChannel('tagtag/windows_quick_tag');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isRegistered');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-folder-quick-tag-'),
    ))!;
    addTearDown(() => sandbox.delete(recursive: true));
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);
    controller.selectResource('resource-folder');
    await tester.runAsync(
      () => controller.assignPlacementToSelection(
        'place-project',
        inheritChildren: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          quickTagHotkey: WindowsQuickTagHotkey(channel: channel),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pump();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('activated')),
      (_) {},
    );
    await _pumpUntilFound(tester, find.text('快速标注'));

    // The dialog exposes the folder's current inheritance rule.
    expect(find.text('子项继承'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('添加 1 个标签'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('search filters and global inbox controls stay in their pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-search-ui-'),
    ))!;
    addTearDown(() => sandbox.delete(recursive: true));
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);
    controller.showSearchResources();

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pump();
    // The dedicated search page exposes tag-condition chips and a reset.
    await tester.tap(find.widgetWithText(OutlinedButton, '项目'));
    await tester.pump();
    expect(
      controller.searchConditionForTag('tag-project'),
      SearchTagCondition.and,
    );
    await tester.tap(find.text('清除'));
    await tester.pump();
    expect(
      controller.searchConditionForTag('tag-project'),
      SearchTagCondition.none,
    );

    controller.showInboxResources();
    await tester.pump();
    await tester.tap(find.text('全局'));
    await tester.pump();
    expect(controller.inboxScope, InboxScope.global);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tag identity operations appear in the operation log and undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-tag-log-ui-'),
    ))!;
    addTearDown(() => sandbox.delete(recursive: true));
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);
    await tester.runAsync(
      () => controller.splitTagPlacements(
        placementIds: const {'place-project-design-reference'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pump();
    // The operation log is reachable from the status drawer's history tab.
    await tester.tap(find.byTooltip('资料库正常，上次扫描 1 分钟前'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('操作日志'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('查看完整操作日志'));
    await tester.tap(find.text('查看完整操作日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签操作'));
    await tester.pump();

    expect(find.text('拆分标签'), findsWidgets);
    expect(find.textContaining('拆分 1 个位置'), findsWidgets);
    await tester.tap(find.byTooltip('撤销此标签操作'));
    await tester.pumpAndSettle();

    expect(controller.tagOperations.single.undoneAt, isNotNull);
    expect(find.text('已撤销'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tag hierarchy exposes merge and split impact previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-tag-impact-ui-'),
    ))!;
    addTearDown(() => sandbox.delete(recursive: true));
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);
    controller.showTagHierarchy();

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selectPlacement('place-project-design-reference');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拆分标签'));
    await tester.pumpAndSettle();

    expect(find.text('拆分标签位置'), findsOneWidget);
    expect(find.text('影响预览'), findsWidgets);
    expect(find.text('1 个标签位置'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    controller.selectPlacement('place-personal-reading-reference-independent');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('标签操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并标签'));
    await tester.pumpAndSettle();

    expect(find.text('合并标签实体'), findsOneWidget);
    expect(find.text('影响预览'), findsWidgets);
    expect(find.text('确认合并'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Explorer Quick Tag activation opens the import-and-tag dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('tagtag/windows_quick_tag');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isRegistered');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-explorer-quick-tag-'),
    ))!;
    addTearDown(() => sandbox.delete(recursive: true));
    final source = File('${sandbox.path}/外部资源.txt');
    await tester.runAsync(() => source.writeAsString('external resource'));
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
          quickTagHotkey: WindowsQuickTagHotkey(channel: channel),
          onRestoreGlobalBackup: (_, _) async {},
        ),
      ),
    );
    await tester.pump();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall('externalPaths', [source.path]),
      ),
      (_) {},
    );

    final importDialog = find.text('导入并标注');
    await _pumpUntilFound(tester, importDialog);
    expect(importDialog, findsOneWidget);
    expect(find.textContaining('1 个资源'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EmptyLibraryLocator extends LibraryLocator {
  @override
  Future<Directory?> loadRoot() async => null;
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for the expected widget');
}
