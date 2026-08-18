import 'package:flutter/services.dart';

class WindowsCloseBehavior {
  WindowsCloseBehavior({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel('tagtag/windows_close_behavior');

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

  Future<bool?> setAutoStart(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setAutoStart', enabled);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  Future<bool?> isAutoStart() async {
    try {
      return await _channel.invokeMethod<bool>('isAutoStart');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }
}
