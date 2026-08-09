import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/platform/windows_file_actions.dart';

void main() {
  test(
    'open and reveal delegate existing files to Windows shell commands',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-file-actions-',
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

      await actions.open(file.path);
      await actions.reveal(file.path);

      final normalizedPath = path.normalize(file.absolute.path);
      expect(commands[0].executable, 'rundll32.exe');
      expect(commands[0].arguments, [
        'url.dll,FileProtocolHandler',
        Uri.file(normalizedPath).toString(),
      ]);
      expect(commands[1].executable, 'explorer.exe');
      expect(commands[1].arguments, ['/select,', normalizedPath]);
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
