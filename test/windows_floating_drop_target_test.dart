import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/platform/windows_floating_drop_target.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forwards the persisted floating-target setting to Windows', () async {
    const channel = MethodChannel('tagtag/windows_floating_drop_target');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setEnabled');
      expect(call.arguments, isTrue);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final target = WindowsFloatingDropTarget(channel: channel);

    expect(await target.setEnabled(true), isTrue);
  });
}
