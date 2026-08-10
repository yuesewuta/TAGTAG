import 'package:flutter/services.dart';

class WindowsFloatingDropTarget {
  WindowsFloatingDropTarget({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel =
      MethodChannel('tagtag/windows_floating_drop_target');

  final MethodChannel _channel;

  Future<bool?> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', enabled);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }
}
