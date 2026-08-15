import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/platform/windows_floating_drop_target.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tagtag/windows_floating_drop_target');

  test('forwards the persisted floating-target setting to Windows', () async {
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

  test('forwards a restored floating-target position to Windows', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setPosition');
      expect(call.arguments, {'x': 132.0, 'y': 640.0});
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final target = WindowsFloatingDropTarget(channel: channel);

    expect(await target.setPosition(132, 640), isTrue);
  });

  test('routes native drag-end positions to the save handler', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final positions = <(double, double)>[];
    final target = WindowsFloatingDropTarget(channel: channel);

    target.start((x, y) async => positions.add((x, y)));
    addTearDown(target.dispose);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('savePosition', {'x': 32.0, 'y': 412.0}),
      ),
      (_) {},
    );

    expect(positions, [(32.0, 412.0)]);

    await target.dispose();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('savePosition', {'x': 40.0, 'y': 500.0}),
      ),
      (_) {},
    );
    expect(positions, hasLength(1));
  });
}
