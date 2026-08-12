import 'package:flutter/services.dart';

class WindowsCloseBehavior {
  WindowsCloseBehavior({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel =
      MethodChannel('tagtag/windows_close_behavior');

  final MethodChannel _channel;

  Future<bool?> setCloseToTray(bool closeToTray) async {
    try {
      return await _channel.invokeMethod<bool>('setCloseToTray', closeToTray);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }
}
