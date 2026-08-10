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

    await tester.tap(find.byTooltip('备份与恢复'));
    await tester.pumpAndSettle();
    expect(find.text('创建完整备份'), findsOneWidget);
    expect(find.text('从完整备份恢复'), findsOneWidget);
    await tester.tapAt(const Offset(80, 160));
    await tester.pumpAndSettle();

    final consistencyButton = find.byTooltip('一致性告警');
    await _pumpUntilFound(tester, consistencyButton);
    await tester.tap(consistencyButton);
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
      await tester.pumpAndSettle();

      expect(find.text('为 1 项添加标签'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Explorer Quick Tag activation opens the import-and-tag dialog', (
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
    await tester.pumpAndSettle();

    expect(find.text('导入并标注 1 个资源'), findsOneWidget);
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
