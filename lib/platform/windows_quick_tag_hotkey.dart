import 'dart:async';

import 'package:flutter/services.dart';

typedef QuickTagActivationHandler =
    Future<void> Function(List<String> externalPaths);

class WindowsQuickTagHotkey {
  WindowsQuickTagHotkey({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel('tagtag/windows_quick_tag');

  final MethodChannel _channel;
  QuickTagActivationHandler? _onActivated;

  Future<bool?> start(
    QuickTagActivationHandler onActivated, {
    String shortcut = 'Ctrl+Shift+T',
  }) async {
    _onActivated = onActivated;
    _channel.setMethodCallHandler(_handleMethodCall);
    if (shortcut != 'Ctrl+Shift+T') {
      return setShortcut(shortcut);
    }
    try {
      return await _channel.invokeMethod<bool>('isRegistered');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return false;
    }
  }

  Future<bool?> setShortcut(String shortcut) async {
    final binding = _nativeBinding(shortcut);
    try {
      return await _channel.invokeMethod<bool>('setShortcut', binding);
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

  static Map<String, int> _nativeBinding(String shortcut) {
    final parts = shortcut.split('+').map((part) => part.trim()).toList();
    var modifiers = 0x4000;
    for (final part in parts.take(parts.length - 1)) {
      switch (part.toLowerCase()) {
        case 'alt':
          modifiers |= 0x0001;
        case 'ctrl':
          modifiers |= 0x0002;
        case 'shift':
          modifiers |= 0x0004;
        case 'win':
          modifiers |= 0x0008;
      }
    }
    final key = parts.isEmpty ? '' : parts.last.toUpperCase();
    final virtualKey = switch (key) {
      final value when RegExp(r'^[A-Z0-9]$').hasMatch(value) =>
        value.codeUnitAt(0),
      final value when RegExp(r'^F([1-9]|1[0-2])$').hasMatch(value) =>
        0x70 + int.parse(value.substring(1)) - 1,
      _ => throw FormatException('不支持的全局快捷键：$shortcut'),
    };
    return {'modifiers': modifiers, 'virtualKey': virtualKey};
  }
}
