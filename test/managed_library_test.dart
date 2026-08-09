import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
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
    'restoring a managed resource to its original path exits management',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-exit-restore-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/restore-after-exit.txt');
      await source.writeAsString('restore after exit');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final imported = await library.importResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
      );

      final operation = await library.restoreToOriginalPath(imported.id);

      expect(await source.readAsString(), 'restore after exit');
      expect(
        await File('${root.path}/managed/restore-after-exit.txt').exists(),
        isFalse,
      );
      expect(await library.listResources(), isEmpty);
      expect(operation.type, ManagedOperationType.exitRestore);
      expect(operation.resourceId, imported.id);
      expect(operation.sourcePath, path.normalize(source.absolute.path));
      expect(operation.destinationRelativePath, imported.relativePath);
      expect(operation.undoneAt, isNull);
    },
  );

  test(
    'restore exit never overwrites a conflict at the original path',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-exit-conflict-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/conflict.txt');
      await source.writeAsString('managed version');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final imported = await library.importResource(
        source: source,
        targetDirectory: '',
        mode: ImportMode.move,
      );
      await source.writeAsString('conflicting version');

      await expectLater(
        library.restoreToOriginalPath(imported.id),
        throwsA(isA<FileSystemException>()),
      );

      expect(await source.readAsString(), 'conflicting version');
      expect(
        await File('${root.path}/conflict.txt').readAsString(),
        'managed version',
      );
      expect((await library.listResources()).single.id, imported.id);
      expect(
        (await library.listOperations()).where(
          (operation) => operation.type == ManagedOperationType.exitRestore,
        ),
        isEmpty,
      );
    },
  );

  test(
    'undoing a restore exit returns the resource to its managed path',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-undo-exit-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/undo-exit.txt');
      await source.writeAsString('undo exit');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final imported = await library.importResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
      );
      final exitOperation = await library.restoreToOriginalPath(imported.id);

      await library.undo(exitOperation.id);

      expect(await source.exists(), isFalse);
      expect(
        await File('${root.path}/managed/undo-exit.txt').readAsString(),
        'undo exit',
      );
      final restored = (await library.listResources()).single;
      expect(restored.id, imported.id);
      expect(restored.relativePath, imported.relativePath);
      expect(restored.originalPath, imported.originalPath);
      expect(
        (await library.listOperations())
            .singleWhere((operation) => operation.id == exitOperation.id)
            .undoneAt,
        isNotNull,
      );
    },
  );

  test(
    'folder restore exit and undo preserve the complete hierarchy',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-folder-exit-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = Directory('${sandbox.path}/folder-to-restore');
      await Directory('${source.path}/nested').create(recursive: true);
      await File('${source.path}/nested/note.txt').writeAsString('folder exit');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final imported = await library.importResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
      );

      final exitOperation = await library.restoreToOriginalPath(imported.id);

      expect(
        await File('${source.path}/nested/note.txt').readAsString(),
        'folder exit',
      );
      expect(
        await Directory('${root.path}/managed/folder-to-restore').exists(),
        isFalse,
      );

      await library.undo(exitOperation.id);

      expect(await source.exists(), isFalse);
      expect(
        await File(
          '${root.path}/managed/folder-to-restore/nested/note.txt',
        ).readAsString(),
        'folder exit',
      );
    },
  );

  test('opening a schema v1 library migrates its operation history', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-schema-v1-');
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/schema-v1.txt');
    await source.writeAsString('schema v1');
    final library = await ManagedLibrary.initialize(root);
    final imported = await library.importResource(
      source: source,
      targetDirectory: '',
      mode: ImportMode.move,
    );
    await library.close();

    final database = sqlite3.open('${root.path}/.tagtag/tagtag.sqlite');
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute('ALTER TABLE operations RENAME TO operations_v2');
      database.execute('''
        CREATE TABLE operations (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL CHECK (type IN ('import_copy', 'import_move')),
          resource_id TEXT NOT NULL,
          source_path TEXT NOT NULL,
          destination_relative_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          undone_at TEXT
        )
      ''');
      database.execute('''
        INSERT INTO operations(
          id, type, resource_id, source_path,
          destination_relative_path, created_at, undone_at
        )
        SELECT id, type, resource_id, source_path,
               destination_relative_path, created_at, undone_at
        FROM operations_v2
      ''');
      database.execute('DROP TABLE operations_v2');
      database.execute(
        "UPDATE metadata SET value = '1' WHERE key = 'schema_version'",
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      database.close();
    }

    final migrated = await ManagedLibrary.open(root);
    addTearDown(migrated.close);
    expect(
      (await migrated.listOperations()).single.type,
      ManagedOperationType.importMove,
    );

    final exitOperation = await migrated.restoreToOriginalPath(imported.id);

    expect(exitOperation.type, ManagedOperationType.exitRestore);
    expect(await source.readAsString(), 'schema v1');
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
