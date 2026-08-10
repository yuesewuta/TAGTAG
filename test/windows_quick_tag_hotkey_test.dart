import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/platform/windows_quick_tag_hotkey.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tagtag/windows_quick_tag');

  test('reads registration status and forwards native activation', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final activations = <List<String>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isRegistered');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final hotkey = WindowsQuickTagHotkey(channel: channel);

    expect(await hotkey.start((paths) async => activations.add(paths)), isTrue);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('activated')),
      (_) {},
    );

    expect(activations, [isEmpty]);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('externalPaths', [r'C:\资料\项目.txt']),
      ),
      (_) {},
    );
    expect(activations, [isEmpty, [r'C:\资料\项目.txt']]);
    await hotkey.dispose();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('activated')),
      (_) {},
    );
    expect(activations, [isEmpty, [r'C:\资料\项目.txt']]);
  });

  test('acknowledges native activation before its UI workflow completes', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final uiWorkflow = Completer<void>();
    final activation = Completer<List<String>>();
    addTearDown(() {
      if (!uiWorkflow.isCompleted) {
        uiWorkflow.complete();
      }
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isRegistered');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final hotkey = WindowsQuickTagHotkey(channel: channel);
    await hotkey.start((paths) async {
      activation.complete(paths);
      await uiWorkflow.future;
    });

    final response = messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('activated')),
      (_) {},
    );

    expect(await activation.future, isEmpty);
    await expectLater(
      response.timeout(const Duration(milliseconds: 100)),
      completes,
    );
    expect(uiWorkflow.isCompleted, isFalse);

    uiWorkflow.complete();
    await hotkey.dispose();
  });
}
