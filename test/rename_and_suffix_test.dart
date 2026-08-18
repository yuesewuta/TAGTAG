import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  test(
    'import conflicts differentiate by tag, then date, then number',
    () async {
      final root = await Directory.systemTemp.createTemp('tagtag-suffix-');
      addTearDown(() => root.delete(recursive: true));
      final library = await ManagedLibrary.initialize(root);
      addTearDown(() => library.close());

      final sourceDir = await Directory.systemTemp.createTemp('tagtag-src-');
      addTearDown(() => sourceDir.delete(recursive: true));
      final source = File('${sourceDir.path}/probe.txt')
        ..writeAsStringSync('probe');

      // Baseline: free name imports as-is.
      final first = await library.importResource(
        source: source,
        targetDirectory: '',
      );
      expect(first.name, 'probe.txt');

      // Tag suffix is the first differentiator.
      final second = await library.importResource(
        source: source,
        targetDirectory: '',
        tagNames: const ['品牌'],
        importDate: DateTime(2026, 8, 18),
      );
      expect(second.name, 'probe-品牌.txt');

      // With the tag variant taken, the MM-DD date suffix applies.
      final third = await library.importResource(
        source: source,
        targetDirectory: '',
        tagNames: const ['品牌'],
        importDate: DateTime(2026, 8, 18),
      );
      expect(third.name, 'probe-08-18.txt');

      // Numeric suffix is the last resort.
      final fourth = await library.importResource(
        source: source,
        targetDirectory: '',
        tagNames: const ['品牌'],
        importDate: DateTime(2026, 8, 18),
      );
      expect(fourth.name, 'probe (2).txt');

      for (final resource in [first, second, third, fourth]) {
        expect(
          File('${root.path}/${resource.relativePath}').readAsStringSync(),
          'probe',
        );
      }
    },
  );

  test('rename updates the managed path and supports undo', () async {
    final root = await Directory.systemTemp.createTemp('tagtag-rename-');
    addTearDown(() => root.delete(recursive: true));
    final library = await ManagedLibrary.initialize(root);
    addTearDown(() => library.close());

    final sourceDir = await Directory.systemTemp.createTemp('tagtag-src2-');
    addTearDown(() => sourceDir.delete(recursive: true));
    final source = File('${sourceDir.path}/probe2.txt')
      ..writeAsStringSync('data');
    final imported = await library.importResource(
      source: source,
      targetDirectory: '',
    );

    final operation = await library.renameResource(imported.id, '新名字.txt');
    expect(operation.type, ManagedOperationType.rename);
    var resources = await library.listResources();
    expect(resources.single.relativePath, '新名字.txt');
    expect(File('${root.path}/新名字.txt').readAsStringSync(), 'data');
    expect(File('${root.path}/probe2.txt').existsSync(), isFalse);

    // Renaming onto an occupied name never overwrites.
    File('${root.path}/占用.txt').writeAsStringSync('keep');
    expect(
      () => library.renameResource(imported.id, '占用.txt'),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${root.path}/占用.txt').readAsStringSync(), 'keep');

    await library.undo(operation.id);
    resources = await library.listResources();
    expect(resources.single.relativePath, 'probe2.txt');
    expect(File('${root.path}/probe2.txt').readAsStringSync(), 'data');
    // The probe file we dropped into the root is untracked, not an error.
    await File('${root.path}/占用.txt').delete();
  });
}
