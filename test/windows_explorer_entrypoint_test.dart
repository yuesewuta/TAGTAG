import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Explorer bridge forwards paths without owning TAGTAG domain behavior',
      () async {
    final protocol = await File(
      'windows/runner/tagtag_entrypoint_protocol.cpp',
    ).readAsString();
    final bridge = await File(
      'windows/entrypoints/tagtag_explorer_bridge.cpp',
    ).readAsString();
    final runner = await File('windows/runner/flutter_window.cpp').readAsString();
    final installer = await File('installer/tagtag.iss').readAsString();

    expect(protocol, contains('kExplorerPathsCopyDataId'));
    expect(protocol, contains('SendMessageTimeoutW'));
    expect(protocol, contains('WM_COPYDATA'));
    expect(bridge, contains('tagtag::SendExplorerPaths'));
    expect(bridge, contains('CreateProcessW'));
    expect(bridge, isNot(contains('sqlite')));
    expect(runner, contains('message == WM_COPYDATA'));
    expect(runner, contains('ActivateExternalQuickTag'));
    expect(runner, contains('"externalPaths"'));
    expect(installer, contains('tagtag_explorer_bridge.exe'));
    expect(installer, contains('MultiSelectModel'));
    expect(installer, contains('uninsdeletekey'));
  });
}
