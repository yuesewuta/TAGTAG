import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/platform/windows_file_actions.dart';

void main() {
  test('open preserves a non-ASCII Windows path for the shell', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-file-actions-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final file = File('${sandbox.path}/测试 副本.txt');
    await file.writeAsString('notes');
    final commands = <({String executable, List<String> arguments})>[];
    final actions = WindowsFileActions(
      launch: (executable, arguments) async {
        commands.add((executable: executable, arguments: arguments));
      },
    );

    await actions.open(file.path);

    final normalizedPath = path.normalize(file.absolute.path);
    expect(commands.single.executable, 'explorer.exe');
    expect(commands.single.arguments, [normalizedPath]);
  });

  test(
    'reveal delegates existing files to Windows Explorer selection',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-file-reveal-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final file = File('${sandbox.path}/notes.txt');
      await file.writeAsString('notes');
      final commands = <({String executable, List<String> arguments})>[];
      final actions = WindowsFileActions(
        launch: (executable, arguments) async {
          commands.add((executable: executable, arguments: arguments));
        },
      );

      await actions.reveal(file.path);

      final normalizedPath = path.normalize(file.absolute.path);
      expect(commands.single.executable, 'explorer.exe');
      expect(commands.single.arguments, ['/select,', normalizedPath]);
    },
  );

  test(
    'missing resources are rejected before launching Windows commands',
    () async {
      var launches = 0;
      final actions = WindowsFileActions(
        launch: (_, _) async {
          launches += 1;
        },
      );

      await expectLater(
        actions.open(r'C:\definitely-missing-tagtag-resource.txt'),
        throwsA(isA<FileSystemException>()),
      );
      expect(launches, 0);
    },
  );
}
