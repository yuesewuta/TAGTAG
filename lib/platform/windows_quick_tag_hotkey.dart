import 'dart:async';

import 'package:flutter/services.dart';

typedef QuickTagActivationHandler = Future<void> Function(
  List<String> externalPaths,
);

class WindowsQuickTagHotkey {
  WindowsQuickTagHotkey({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel('tagtag/windows_quick_tag');

  final MethodChannel _channel;
  QuickTagActivationHandler? _onActivated;

  Future<bool?> start(QuickTagActivationHandler onActivated) async {
    _onActivated = onActivated;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      return await _channel.invokeMethod<bool>('isRegistered');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  Future<void> dispose() async {
    _onActivated = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final onActivated = _onActivated;
    if (onActivated == null) {
      return;
    }
    if (call.method == 'activated') {
      // A native one-way activation must be acknowledged before its UI flow ends.
      unawaited(onActivated(const []));
      return;
    }
    if (call.method == 'externalPaths') {
      final arguments = call.arguments;
      if (arguments is! List || arguments.any((item) => item is! String)) {
        throw PlatformException(
          code: 'invalid_external_paths',
          message: 'Quick Tag external paths must be a string list.',
        );
      }
      unawaited(onActivated(arguments.cast<String>()));
      return;
    }
    throw MissingPluginException('Unsupported Quick Tag event: ${call.method}');
  }
}
