import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_close_behavior.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/ui/glass.dart';
import 'package:tagtag/ui/home_screen.dart';
import 'package:tagtag/ui/tagtag_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tagtag/windows_close_behavior');

  test('forwards setAutoStart and isAutoStart to Windows', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'setAutoStart' || 'isAutoStart' => true,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final behavior = WindowsCloseBehavior(channel: channel);

    expect(await behavior.setAutoStart(true), isTrue);
    expect(await behavior.setAutoStart(false), isTrue);
    expect(await behavior.isAutoStart(), isTrue);
    expect(calls.map((call) => call.method), [
      'setAutoStart',
      'setAutoStart',
      'isAutoStart',
    ]);
    expect(calls[0].arguments, isTrue);
    expect(calls[1].arguments, isFalse);
  });

  test('auto-start preference round-trips and tolerates legacy data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tagtag-autostart-prefs-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalStore(baseDirectory: directory);

    // The default for a fresh install is off.
    expect((await store.loadPreferences()).autoStartEnabled, isFalse);

    await store.savePreferences(const UserPreferences(autoStartEnabled: true));

    final loaded = await LocalStore(baseDirectory: directory).loadPreferences();
    expect(loaded.autoStartEnabled, isTrue);

    // Legacy settings without the key parse tolerantly as disabled, while a
    // malformed value is rejected like the other fields.
    final legacy = UserPreferences.fromJson(const {
      'version': 1,
      'moveImportsByDefault': false,
    });
    expect(legacy.autoStartEnabled, isFalse);
    expect(
      () => UserPreferences.fromJson(const {
        'version': 1,
        'moveImportsByDefault': false,
        'autoStartEnabled': 'yes',
      }),
      throwsFormatException,
    );
  });

  test(
    'auto-start preference changes are logged as settings entries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tagtag-autostart-log-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(baseDirectory: directory);
      await store.save(AppState.demo());
      final controller = TagTagController(store: store);
      await controller.load();

      await controller.updatePreferences(autoStartEnabled: true);
      await controller.updatePreferences(autoStartEnabled: false);

      final summaries = controller.state.logEvents
          .map((event) => event.summary)
          .toList();
      expect(summaries, contains(contains('开机自动启动 开启')));
      expect(summaries, contains(contains('开机自动启动 关闭')));
    },
  );

  test('native runner and installer cover the Run key lifecycle', () async {
    final runner = await File(
      'windows/runner/flutter_window.cpp',
    ).readAsString();

    expect(
      runner,
      contains(r'Software\\Microsoft\\Windows\\CurrentVersion\\Run'),
    );
    expect(runner, contains('GetModuleFileNameW'));
    expect(runner, contains('RegSetValueExW'));
    expect(runner, contains('RegDeleteValueW'));
    expect(runner, contains('"setAutoStart"'));
    expect(runner, contains('"isAutoStart"'));

    final installer = await File('installer/tagtag.iss').readAsString();
    expect(
      installer,
      contains(
        r'Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run";'
        r' ValueName: "TAGTAG"; Flags: uninsdeletevalue',
      ),
    );
  });

  testWidgets('settings dialog toggles and saves 开机自动启动', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tagtag-autostart-ui-'),
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
    await tester.runAsync(() => store.save(AppState.demo()));
    final controller = TagTagController(store: store);
    await tester.runAsync(controller.load);
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
    await tester.tap(find.text('Windows 集成'));
    await tester.pumpAndSettle();

    expect(find.text('开机自动启动'), findsOneWidget);
    expect(find.text('登录 Windows 后自动启动 TAGTAG'), findsOneWidget);

    // The 开机自动启动 row is the first switch in the Windows section.
    await tester.tap(find.byType(PillSwitch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(controller.preferences.autoStartEnabled, isTrue);
    expect(controller.state.logEvents.last.summary, contains('开机自动启动 开启'));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
