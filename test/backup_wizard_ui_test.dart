import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/main.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/library_locator.dart';
import 'package:tagtag/storage/managed_library.dart';
import 'package:tagtag/ui/glass.dart';
import 'package:tagtag/ui/home_screen.dart';
import 'package:tagtag/ui/tagtag_theme.dart';

void main() {
  testWidgets('settings storage section exposes scheduled backup rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await tester.runAsync(() async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-backup-settings-',
      );
      final library = await ManagedLibrary.initialize(
        Directory('${sandbox.path}/library'),
      );
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await store.save(AppState.demo());
      final controller = TagTagController(store: store, library: library);
      await controller.load();
      return (sandbox: sandbox, library: library, controller: controller);
    });
    final sandbox = fixture!.sandbox;
    addTearDown(() async {
      try {
        await sandbox.delete(recursive: true);
      } on PathAccessException {
        // Windows may briefly keep persisted files locked.
      }
    });
    addTearDown(fixture.library.close);
    final controller = fixture.controller;

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

    await tester.tap(find.byKey(const ValueKey('nav-设置')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存储与备份'));
    await tester.pumpAndSettle();

    expect(find.text('定期备份'), findsOneWidget);
    expect(find.text('备份目录'), findsOneWidget);
    expect(find.text('备份间隔'), findsOneWidget);
    expect(find.text('备份策略'), findsOneWidget);
    expect(find.text('上次备份时间'), findsOneWidget);
    expect(find.text('从未备份'), findsOneWidget);

    // Enabling 定期备份 without a directory blocks saving with an inline error.
    await tester.tap(find.byType(PillSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(find.text('请选择备份目录'), findsOneWidget);
    expect(find.text('定期备份'), findsOneWidget);

    // Turning it back off and changing the interval saves successfully.
    await tester.tap(find.byType(PillSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每 24 小时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每 12 小时').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(controller.preferences.backupEnabled, isFalse);
    expect(controller.preferences.backupIntervalHours, 12);
    expect(
      controller.state.logEvents.last.summary,
      contains('备份间隔 每 12 小时'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first-run wizard goes from storage root to settings to done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-wizard-'),
    ))!;
    addTearDown(() async {
      try {
        await sandbox.delete(recursive: true);
      } on PathAccessException {
        // Windows may briefly keep persisted files locked.
      }
    });
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    final rootPath = '${sandbox.path}/library';

    await tester.pumpWidget(
      TagTagApp(
        locator: _EmptyLibraryLocator(),
        storageRootPicker: () async => rootPath,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: storage root.
    expect(find.text('初始化存储根目录'), findsOneWidget);
    expect(find.text('第 1 步，共 2 步'), findsOneWidget);
    await tester.tap(find.text('选择存储根目录'));
    await _pumpUntilFound(tester, find.text('关键设置'));

    // Step 2: key settings.
    expect(find.text('关键设置'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('默认导入方式'), findsOneWidget);
    expect(find.text('Quick Tag 快捷键'), findsOneWidget);
    expect(find.text('Ctrl + Shift + T'), findsOneWidget);
    expect(find.text('悬浮接收目标'), findsOneWidget);
    expect(find.text('开机自动启动'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();
    // The last switch on step 2 is 开机自动启动.
    await tester.tap(find.byType(PillSwitch).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    final navSettings = find.byKey(const ValueKey('nav-设置'));
    await _pumpUntilFound(tester, navSettings);

    // The wizard finishes initialization and lands on the workspace.
    expect(navSettings, findsOneWidget);
    final controller = tester
        .widget<TagTagHome>(find.byType(TagTagHome))
        .controller;
    expect(controller.preferences.appearanceTheme, 'dark');
    expect(controller.preferences.moveImportsByDefault, isTrue);
    expect(controller.preferences.autoStartEnabled, isTrue);
    expect(controller.preferences.floatingDropTargetEnabled, isFalse);
    expect(controller.preferences.quickTagShortcut, 'Ctrl+Shift+T');

    // The choices were persisted into the library metadata.
    final preferencesJson = await tester.runAsync(
      () async => (await controller.library!.readTagDomainMetadata())
          ?.preferencesJson,
    );
    final persisted = UserPreferences.fromJson(
      jsonDecode(preferencesJson!) as Map<String, dynamic>,
    );
    expect(persisted.appearanceTheme, 'dark');
    expect(persisted.moveImportsByDefault, isTrue);
    expect(persisted.autoStartEnabled, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EmptyLibraryLocator extends LibraryLocator {
  @override
  Future<Directory?> loadRoot() async => null;
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for the expected widget');
}
