import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tagtag/storage/library_locator.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  test(
    'initialized library reopens empty without managing file bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('tagtag-library-');
      addTearDown(() => root.delete(recursive: true));

      final library = await ManagedLibrary.initialize(root);
      expect(library.root.path, root.absolute.path);
      expect(await library.listResources(), isEmpty);
      expect(await File('${root.path}/.tagtag/tagtag.sqlite').exists(), isTrue);
      await library.close();

      final reopened = await ManagedLibrary.open(root);
      expect(reopened.root.path, root.absolute.path);
      expect(await reopened.listResources(), isEmpty);
      await reopened.close();
    },
  );

  test(
    'copy import keeps the source and stores original bytes under root',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-import-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/source.txt');
      await source.writeAsString('plain file content');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);

      final imported = await library.importResource(
        source:
            FileSystemEntity.typeSync(source.path) == FileSystemEntityType.file
            ? source
            : throw StateError('test source is not a file'),
        targetDirectory: 'documents',
        mode: ImportMode.copy,
      );

      expect(await source.readAsString(), 'plain file content');
      expect(imported.relativePath, 'documents/source.txt');
      expect(
        await File('${root.path}/documents/source.txt').readAsString(),
        'plain file content',
      );
      expect((await library.listResources()).single.id, imported.id);
    },
  );

  test(
    'move import removes the source and remembers its original path',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-move-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/move-me.txt');
      await source.writeAsString('move without wrapping bytes');
      final originalPath = source.absolute.path;
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);

      final imported = await library.importResource(
        source: source,
        targetDirectory: '',
        mode: ImportMode.move,
      );

      expect(await source.exists(), isFalse);
      expect(imported.originalPath, path.normalize(originalPath));
      expect(
        await File('${root.path}/move-me.txt').readAsString(),
        'move without wrapping bytes',
      );
    },
  );

  test(
    'folder import preserves the folder and its complete hierarchy',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-folder-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = Directory('${sandbox.path}/source-folder');
      await Directory('${source.path}/nested/deeper').create(recursive: true);
      await File(
        '${source.path}/nested/deeper/note.txt',
      ).writeAsString('nested');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);

      final imported = await library.importResource(
        source: source,
        targetDirectory: 'incoming',
      );

      expect(imported.kind, ManagedResourceKind.folder);
      expect(imported.relativePath, 'incoming/source-folder');
      expect(await source.exists(), isTrue);
      expect(
        await File(
          '${root.path}/incoming/source-folder/nested/deeper/note.txt',
        ).readAsString(),
        'nested',
      );
    },
  );

  test('undoing a copy import removes only the managed copy', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-undo-copy-');
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/keep-source.txt');
    await source.writeAsString('keep me');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);

    await library.importResource(source: source, targetDirectory: 'inbox');
    final operation = (await library.listOperations()).single;
    await library.undo(operation.id);

    expect(await source.readAsString(), 'keep me');
    expect(await File('${root.path}/inbox/keep-source.txt').exists(), isFalse);
    expect(await library.listResources(), isEmpty);
    expect((await library.listOperations()).single.undoneAt, isNotNull);
  });

  test('move undo never overwrites a conflict at the original path', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-conflict-');
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/original.txt');
    await source.writeAsString('managed version');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    await library.importResource(
      source: source,
      targetDirectory: '',
      mode: ImportMode.move,
    );
    await source.writeAsString('conflicting version');
    final operation = (await library.listOperations()).single;

    await expectLater(
      library.undo(operation.id),
      throwsA(isA<FileSystemException>()),
    );

    expect(await source.readAsString(), 'conflicting version');
    expect(
      await File('${root.path}/original.txt').readAsString(),
      'managed version',
    );
    expect(await library.listResources(), hasLength(1));
    expect((await library.listOperations()).single.undoneAt, isNull);
  });

  test('move undo restores the original path when it is free', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-undo-move-');
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/restore-me.txt');
    await source.writeAsString('restore me');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );
    final operation = (await library.listOperations()).single;

    await library.undo(operation.id);

    expect(await source.readAsString(), 'restore me');
    expect(await File('${root.path}/managed/restore-me.txt').exists(), isFalse);
    expect(await library.listResources(), isEmpty);
    expect((await library.listOperations()).single.undoneAt, isNotNull);
  });

  test(
    'consistency scan reports untracked and missing resources only',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-scan-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/managed.txt');
      await source.writeAsString('initial');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final managed = await library.importResource(
        source: source,
        targetDirectory: '',
      );

      await File('${root.path}/managed.txt').writeAsString('normal edit');
      expect(await library.scanConsistency(), isEmpty);

      await File('${root.path}/managed.txt').delete();
      await File(
        '${root.path}/outside-addition.txt',
      ).writeAsString('untracked');
      final findings = await library.scanConsistency();

      expect(
        findings
            .where((item) => item.type == ConsistencyFindingType.missing)
            .single
            .resourceId,
        managed.id,
      );
      expect(
        findings
            .where((item) => item.type == ConsistencyFindingType.untracked)
            .single
            .relativePath,
        'outside-addition.txt',
      );
    },
  );

  test(
    'backup contains a consistent metadata snapshot and original files',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-backup-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/backup-me.txt');
      await source.writeAsString('original backup bytes');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      await library.importResource(source: source, targetDirectory: 'docs');

      final backup = await library.createBackup(
        Directory('${sandbox.path}/backups'),
        metadataDocuments: const {
          'tag-state.json': '{"activeSpaceId":"space-design"}',
        },
      );

      expect(await File('${backup.path}/manifest.json').exists(), isTrue);
      expect(
        await File('${backup.path}/metadata/tagtag.sqlite').exists(),
        isTrue,
      );
      expect(
        await File(
          '${backup.path}/resources/docs/backup-me.txt',
        ).readAsString(),
        'original backup bytes',
      );
      expect(
        await File('${backup.path}/metadata/tag-state.json').readAsString(),
        '{"activeSpaceId":"space-design"}',
      );
    },
  );

  test(
    'library locator persists the initialized root across restart',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('tagtag-locator-');
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      await root.create();

      final locator = LibraryLocator(
        configDirectory: Directory('${sandbox.path}/config'),
      );
      await locator.saveRoot(root);

      final restartedLocator = LibraryLocator(
        configDirectory: Directory('${sandbox.path}/config'),
      );
      expect(
        (await restartedLocator.loadRoot())?.path,
        path.normalize(root.absolute.path),
      );
    },
  );
}
