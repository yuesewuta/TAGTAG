import 'dart:async';

import 'package:flutter/services.dart';

typedef FloatingDropTargetPositionHandler =
    Future<void> Function(double x, double y);

class WindowsFloatingDropTarget {
  WindowsFloatingDropTarget({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel(
    'tagtag/windows_floating_drop_target',
  );

  final MethodChannel _channel;
  FloatingDropTargetPositionHandler? _onSavePosition;

  Future<bool?> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', enabled);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  Future<bool?> setPosition(double x, double y) async {
    try {
      return await _channel.invokeMethod<bool>('setPosition', {'x': x, 'y': y});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  void start(FloatingDropTargetPositionHandler onSavePosition) {
    _onSavePosition = onSavePosition;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> dispose() async {
    _onSavePosition = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final onSavePosition = _onSavePosition;
    if (onSavePosition == null) {
      return;
    }
    if (call.method == 'savePosition') {
      final arguments = call.arguments;
      final x = arguments is Map ? arguments['x'] : null;
      final y = arguments is Map ? arguments['y'] : null;
      if (x is! num || y is! num) {
        throw PlatformException(
          code: 'invalid_position',
          message: 'Floating drop target position must be numeric x/y.',
        );
      }
      // A native one-way event must be acknowledged before its flow ends.
      unawaited(onSavePosition(x.toDouble(), y.toDouble()));
      return;
    }
    throw MissingPluginException(
      'Unsupported floating drop target event: ${call.method}',
    );
  }
}
