import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
import 'package:tagtag/models/tag_models.dart';
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
    'moving a managed resource to a specified path exits management',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-exit-move-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/specified-source.txt');
      final destination = File('${sandbox.path}/exports/renamed.txt');
      await source.writeAsString('move to specified path');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final imported = await library.importResource(
        source: source,
        targetDirectory: 'managed',
        mode: ImportMode.move,
      );

      final operation = await library.moveToSpecifiedPath(
        imported.id,
        destination.path,
      );

      expect(await destination.readAsString(), 'move to specified path');
      expect(
        await File('${root.path}/managed/specified-source.txt').exists(),
        isFalse,
      );
      expect(await library.listResources(), isEmpty);
      expect(operation.type, ManagedOperationType.exitMove);
      expect(operation.resourceId, imported.id);
      expect(operation.sourcePath, path.normalize(destination.absolute.path));
      expect(operation.destinationRelativePath, imported.relativePath);
      expect(operation.undoneAt, isNull);
    },
  );

  test('specified-path exit never overwrites an existing resource', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-exit-move-conflict-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/move-conflict-source.txt');
    final destination = File('${sandbox.path}/exports/conflict.txt');
    await source.writeAsString('managed version');
    await destination.create(recursive: true);
    await destination.writeAsString('existing version');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );

    await expectLater(
      library.moveToSpecifiedPath(imported.id, destination.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(await destination.readAsString(), 'existing version');
    expect(
      await File(
        '${root.path}/managed/move-conflict-source.txt',
      ).readAsString(),
      'managed version',
    );
    expect((await library.listResources()).single.id, imported.id);
    expect(
      (await library.listOperations()).where(
        (operation) => operation.type == ManagedOperationType.exitMove,
      ),
      isEmpty,
    );
  });

  test('undoing a specified-path exit restores the managed resource', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-undo-exit-move-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/undo-move-source.txt');
    final destination = File('${sandbox.path}/exports/renamed.txt');
    await source.writeAsString('undo specified move');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );
    final exitOperation = await library.moveToSpecifiedPath(
      imported.id,
      destination.path,
    );

    await library.undo(exitOperation.id);

    expect(await destination.exists(), isFalse);
    expect(
      await File('${root.path}/managed/undo-move-source.txt').readAsString(),
      'undo specified move',
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
  });

  test('specified-path folder exit and undo preserve its hierarchy', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-folder-exit-move-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = Directory('${sandbox.path}/folder-source');
    final destination = Directory('${sandbox.path}/exports/renamed-folder');
    await Directory('${source.path}/nested').create(recursive: true);
    await File('${source.path}/nested/note.txt').writeAsString('folder move');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );

    final operation = await library.moveToSpecifiedPath(
      imported.id,
      destination.path,
    );

    expect(
      await File('${destination.path}/nested/note.txt').readAsString(),
      'folder move',
    );

    await library.undo(operation.id);

    expect(await destination.exists(), isFalse);
    expect(
      await File(
        '${root.path}/managed/folder-source/nested/note.txt',
      ).readAsString(),
      'folder move',
    );
  });

  test('recycle-bin exit and undo restore the same managed resource', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-exit-recycle-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/recycle-source.txt');
    await source.writeAsString('recycle and undo');
    final recycleBin = _FakeRecycleBin(Directory('${sandbox.path}/recycle'));
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );

    final operation = await library.moveToRecycleBin(
      imported.id,
      recycleBin: recycleBin,
    );

    expect(operation.type, ManagedOperationType.exitRecycle);
    expect(await library.listResources(), isEmpty);
    expect(
      await File('${root.path}/managed/recycle-source.txt').exists(),
      isFalse,
    );
    expect(await recycleBin.contains(operation.sourcePath), isTrue);

    await library.undo(operation.id, recycleBin: recycleBin);

    expect(await recycleBin.contains(operation.sourcePath), isFalse);
    expect(
      await File('${root.path}/managed/recycle-source.txt').readAsString(),
      'recycle and undo',
    );
    final restored = (await library.listResources()).single;
    expect(restored.id, imported.id);
    expect(restored.originalPath, imported.originalPath);
  });

  test('recycle-bin undo never overwrites the managed path', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-undo-recycle-conflict-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/recycle-conflict-source.txt');
    await source.writeAsString('recycled version');
    final recycleBin = _FakeRecycleBin(Directory('${sandbox.path}/recycle'));
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'managed',
      mode: ImportMode.move,
    );
    final operation = await library.moveToRecycleBin(
      imported.id,
      recycleBin: recycleBin,
    );
    final managedPath = File(
      '${root.path}/managed/recycle-conflict-source.txt',
    );
    await managedPath.writeAsString('conflicting version');

    await expectLater(
      library.undo(operation.id, recycleBin: recycleBin),
      throwsA(isA<FileSystemException>()),
    );

    expect(await managedPath.readAsString(), 'conflicting version');
    expect(await recycleBin.contains(operation.sourcePath), isTrue);
    expect(await library.listResources(), isEmpty);
    expect(
      (await library.listOperations())
          .singleWhere((item) => item.id == operation.id)
          .undoneAt,
      isNull,
    );
  });

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
    'opening a schema v2 library enables specified-path exit logs',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-schema-v2-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/schema-v2.txt');
      final destination = File('${sandbox.path}/exports/schema-v2.txt');
      await source.writeAsString('schema v2');
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
        database.execute('ALTER TABLE operations RENAME TO operations_v3');
        database.execute('''
        CREATE TABLE operations (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL CHECK (
            type IN ('import_copy', 'import_move', 'exit_restore')
          ),
          resource_id TEXT NOT NULL,
          source_path TEXT NOT NULL,
          destination_relative_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          undone_at TEXT,
          context_json TEXT
        )
      ''');
        database.execute('''
        INSERT INTO operations(
          id, type, resource_id, source_path,
          destination_relative_path, created_at, undone_at, context_json
        )
        SELECT id, type, resource_id, source_path,
               destination_relative_path, created_at, undone_at, context_json
        FROM operations_v3
      ''');
        database.execute('DROP TABLE operations_v3');
        database.execute(
          "UPDATE metadata SET value = '2' WHERE key = 'schema_version'",
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

      final operation = await migrated.moveToSpecifiedPath(
        imported.id,
        destination.path,
      );

      expect(operation.type, ManagedOperationType.exitMove);
      expect(await destination.readAsString(), 'schema v2');
    },
  );

  test('opening a schema v3 library enables recycle exit logs', () async {
    final sandbox = await Directory.systemTemp.createTemp('tagtag-schema-v3-');
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/schema-v3.txt');
    await source.writeAsString('schema v3');
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
      database.execute('ALTER TABLE operations RENAME TO operations_v4');
      database.execute('''
        CREATE TABLE operations (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL CHECK (
            type IN (
              'import_copy', 'import_move', 'exit_restore', 'exit_move'
            )
          ),
          resource_id TEXT NOT NULL,
          source_path TEXT NOT NULL,
          destination_relative_path TEXT NOT NULL,
          created_at TEXT NOT NULL,
          undone_at TEXT,
          context_json TEXT
        )
      ''');
      database.execute('''
        INSERT INTO operations(
          id, type, resource_id, source_path,
          destination_relative_path, created_at, undone_at, context_json
        )
        SELECT id, type, resource_id, source_path,
               destination_relative_path, created_at, undone_at, context_json
        FROM operations_v4
      ''');
      database.execute('DROP TABLE operations_v4');
      database.execute(
        "UPDATE metadata SET value = '3' WHERE key = 'schema_version'",
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
    final recycleBin = _FakeRecycleBin(Directory('${sandbox.path}/recycle'));

    final operation = await migrated.moveToRecycleBin(
      imported.id,
      recycleBin: recycleBin,
    );

    expect(operation.type, ManagedOperationType.exitRecycle);
    expect(await recycleBin.contains(operation.sourcePath), isTrue);
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
      final refreshed = (await library.listResources()).single;
      expect(refreshed.status, ManagedResourceStatus.managed);
      expect(refreshed.sizeBytes, 'normal edit'.length);

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
      expect(
        (await library.listResources()).single.status,
        ManagedResourceStatus.missing,
      );
    },
  );

  test('taking over untracked content is logged and undoable', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-takeover-untracked-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final untracked = File('${root.path}/incoming/接管.txt');
    await untracked.create(recursive: true);
    await untracked.writeAsString('take over without moving');

    final resource = await library.takeOverUntracked('incoming/接管.txt');

    expect(resource.relativePath, 'incoming/接管.txt');
    expect(resource.originalPath, isNull);
    expect(await untracked.readAsString(), 'take over without moving');
    expect(await library.scanConsistency(), isEmpty);
    final operation = (await library.listOperations()).first;
    expect(operation.type, ManagedOperationType.takeover);
    expect(operation.resourceId, resource.id);

    await library.undo(operation.id);

    expect(await untracked.readAsString(), 'take over without moving');
    expect(await library.listResources(), isEmpty);
    expect(
      (await library.scanConsistency()).single.type,
      ConsistencyFindingType.untracked,
    );
  });

  test(
    'moving untracked content outside the root is logged and undoable',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-move-untracked-out-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final untracked = Directory('${root.path}/folder');
      await untracked.create(recursive: true);
      await File('${untracked.path}/note.txt').writeAsString('move out');
      final destination = Directory('${sandbox.path}/outside/renamed-folder');

      final operation = await library.moveUntrackedOutside(
        'folder',
        destination.path,
      );

      expect(operation.type, ManagedOperationType.untrackedMoveOut);
      expect(await untracked.exists(), isFalse);
      expect(
        await File('${destination.path}/note.txt').readAsString(),
        'move out',
      );
      expect(await library.scanConsistency(), isEmpty);

      await library.undo(operation.id);

      expect(await destination.exists(), isFalse);
      expect(
        await File('${untracked.path}/note.txt').readAsString(),
        'move out',
      );
      expect((await library.scanConsistency()).single.relativePath, 'folder');
    },
  );

  test(
    'moving untracked content never overwrites an external target',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-untracked-move-conflict-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final untracked = File('${root.path}/untracked.txt');
      final destination = File('${sandbox.path}/outside.txt');
      await untracked.writeAsString('keep inside');
      await destination.writeAsString('keep outside');

      await expectLater(
        library.moveUntrackedOutside('untracked.txt', destination.path),
        throwsA(isA<FileSystemException>()),
      );

      expect(await untracked.readAsString(), 'keep inside');
      expect(await destination.readAsString(), 'keep outside');
      expect(await library.listOperations(), isEmpty);
    },
  );

  test(
    'accepting an explicitly paired external move preserves identity',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-accept-external-move-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/source.txt');
      await source.writeAsString('externally moved');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final resource = await library.importResource(
        source: source,
        targetDirectory: '',
      );
      final oldPath = File('${root.path}/source.txt');
      final newPath = File('${root.path}/external/new-name.txt');
      await newPath.parent.create(recursive: true);
      await oldPath.rename(newPath.path);
      await library.scanConsistency();

      final operation = await library.acceptExternalMove(
        resource.id,
        'external/new-name.txt',
      );

      final accepted = (await library.listResources()).single;
      expect(accepted.id, resource.id);
      expect(accepted.relativePath, 'external/new-name.txt');
      expect(accepted.status, ManagedResourceStatus.managed);
      expect(operation.type, ManagedOperationType.externalMoveAccept);
      expect(await library.scanConsistency(), isEmpty);

      await library.undo(operation.id);

      final restoredRecord = (await library.listResources()).single;
      expect(restoredRecord.id, resource.id);
      expect(restoredRecord.relativePath, 'source.txt');
      expect(restoredRecord.status, ManagedResourceStatus.missing);
      expect(await newPath.readAsString(), 'externally moved');
      final findings = await library.scanConsistency();
      expect(
        findings.map((finding) => finding.type),
        containsAll(<ConsistencyFindingType>[
          ConsistencyFindingType.missing,
          ConsistencyFindingType.untracked,
        ]),
      );
    },
  );

  test('restoring an explicitly paired external move is undoable', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-restore-external-move-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/source.txt');
    await source.writeAsString('restore external move');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final resource = await library.importResource(
      source: source,
      targetDirectory: '',
    );
    final recordedPath = File('${root.path}/source.txt');
    final movedPath = File('${root.path}/renamed.txt');
    await recordedPath.rename(movedPath.path);
    await library.scanConsistency();

    final operation = await library.restoreExternalMove(
      resource.id,
      'renamed.txt',
    );

    final restored = (await library.listResources()).single;
    expect(restored.id, resource.id);
    expect(restored.relativePath, 'source.txt');
    expect(restored.status, ManagedResourceStatus.managed);
    expect(operation.type, ManagedOperationType.externalMoveRestore);
    expect(await movedPath.exists(), isFalse);
    expect(await recordedPath.readAsString(), 'restore external move');
    expect(await library.scanConsistency(), isEmpty);

    await library.undo(operation.id);

    final missingAgain = (await library.listResources()).single;
    expect(missingAgain.id, resource.id);
    expect(missingAgain.relativePath, 'source.txt');
    expect(missingAgain.status, ManagedResourceStatus.missing);
    expect(await recordedPath.exists(), isFalse);
    expect(await movedPath.readAsString(), 'restore external move');
  });

  test(
    'restoring an external move never overwrites the recorded path',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-external-restore-conflict-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final source = File('${sandbox.path}/source.txt');
      await source.writeAsString('managed content');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      final resource = await library.importResource(
        source: source,
        targetDirectory: '',
      );
      final recordedPath = File('${root.path}/source.txt');
      final movedPath = File('${root.path}/renamed.txt');
      await recordedPath.rename(movedPath.path);
      await recordedPath.writeAsString('conflicting content');

      await expectLater(
        library.restoreExternalMove(resource.id, 'renamed.txt'),
        throwsA(isA<StateError>()),
      );

      expect(await recordedPath.readAsString(), 'conflicting content');
      expect(await movedPath.readAsString(), 'managed content');
      expect(
        (await library.listOperations()).where(
          (operation) =>
              operation.type == ManagedOperationType.externalMoveRestore,
        ),
        isEmpty,
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
        metadataDocuments: {
          'tag-state.json': jsonEncode(AppState.empty().toJson()),
        },
      );

      final validation = await ManagedLibrary.validateBackup(backup);

      expect(await File('${backup.path}/manifest.json').exists(), isTrue);
      expect(validation.formatVersion, 2);
      expect(validation.resourceCount, 1);
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
        jsonEncode(AppState.empty().toJson()),
      );

      await File(
        '${backup.path}/resources/docs/backup-me.txt',
      ).writeAsString('tampered backup bytes');
      await expectLater(
        ManagedLibrary.validateBackup(backup),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('a validated global backup restores into a new empty root', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-backup-restore-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final sourceRoot = Directory('${sandbox.path}/source-library');
    final source = Directory('${sandbox.path}/source-folder');
    await source.create();
    await File('${source.path}/note.txt').writeAsString('restored bytes');
    final library = await ManagedLibrary.initialize(sourceRoot);
    final imported = await library.importResource(
      source: source,
      targetDirectory: 'docs',
      mode: ImportMode.move,
    );
    final tagStateJson = jsonEncode(AppState.empty().toJson());
    final backup = await library.createBackup(
      Directory('${sandbox.path}/backups'),
      metadataDocuments: {'tag-state.json': tagStateJson},
    );
    await library.close();
    final targetRoot = Directory('${sandbox.path}/restored-library');
    await targetRoot.create();

    final restored = await ManagedLibrary.restoreBackup(backup, targetRoot);

    expect(restored.root.path, path.normalize(targetRoot.absolute.path));
    expect(restored.tagStateJson, tagStateJson);
    expect(
      await File(
        '${targetRoot.path}/docs/source-folder/note.txt',
      ).readAsString(),
      'restored bytes',
    );
    final reopened = await ManagedLibrary.open(targetRoot);
    addTearDown(reopened.close);
    expect((await reopened.listResources()).single.id, imported.id);
    expect(await reopened.scanConsistency(), isEmpty);
  });

  test('global backup restore refuses a non-empty target root', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-backup-restore-conflict-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final library = await ManagedLibrary.initialize(
      Directory('${sandbox.path}/library'),
    );
    final backup = await library.createBackup(
      Directory('${sandbox.path}/backups'),
      metadataDocuments: {
        'tag-state.json': jsonEncode(AppState.empty().toJson()),
      },
    );
    await library.close();
    final targetRoot = Directory('${sandbox.path}/occupied');
    await targetRoot.create();
    final existing = File('${targetRoot.path}/existing.txt');
    await existing.writeAsString('do not overwrite');

    await expectLater(
      ManagedLibrary.restoreBackup(backup, targetRoot),
      throwsA(isA<FileSystemException>()),
    );

    expect(await existing.readAsString(), 'do not overwrite');
  });

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

class _FakeRecycleBin implements RecycleBinGateway {
  _FakeRecycleBin(this.directory);

  final Directory directory;

  @override
  Future<String> recycle(String resourcePath) async {
    await directory.create(recursive: true);
    final token = path.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}-${path.basename(resourcePath)}',
    );
    await _rename(resourcePath, token);
    return token;
  }

  @override
  Future<void> restore(String token, String destinationPath) async {
    await Directory(path.dirname(destinationPath)).create(recursive: true);
    await _rename(token, destinationPath);
  }

  Future<bool> contains(String token) async {
    return await FileSystemEntity.type(token) != FileSystemEntityType.notFound;
  }

  static Future<void> _rename(String source, String destination) async {
    final type = await FileSystemEntity.type(source);
    if (type == FileSystemEntityType.file) {
      await File(source).rename(destination);
      return;
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(destination);
      return;
    }
    throw FileSystemException('找不到回收站测试资源', source);
  }
}
