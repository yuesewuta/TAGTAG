import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner owns the tray lifecycle and routes Quick Tag centrally',
      () async {
    final source = await File('windows/runner/flutter_window.cpp').readAsString();

    expect(source, contains('Shell_NotifyIconW(NIM_ADD'));
    expect(source, contains('Shell_NotifyIconW(NIM_DELETE'));
    expect(source, contains('NOTIFYICON_VERSION_4'));
    expect(source, contains('if (message == WM_CLOSE)'));
    expect(source, contains('ShowWindow(hwnd, SW_HIDE)'));
    expect(source, contains('kTrayCommandShow'));
    expect(source, contains('kTrayCommandQuickTag'));
    expect(source, contains('kTrayCommandExit'));
    expect(source, contains('ActivateQuickTag(window)'));
    expect(source, contains('UnregisterHotKey(quick_tag_window_'));
    expect(source, contains('kFloatingDropTargetClassName'));
    expect(source, contains('DragAcceptFiles'));
    expect(source, contains('WM_DROPFILES'));
    expect(source, contains('"tagtag/windows_floating_drop_target"'));
  });
}
