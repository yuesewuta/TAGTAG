import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/services/scheduled_backup.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  group('validateBackupDirectory', () {
    const root = r'D:\library';

    test('accepts a sibling directory', () {
      expect(
        validateBackupDirectory(directory: r'D:\backups', storageRoot: root),
        isNull,
      );
    });

    test('accepts a nested sibling directory', () {
      expect(
        validateBackupDirectory(
          directory: r'D:\backups\tagtag',
          storageRoot: root,
        ),
        isNull,
      );
    });

    test('rejects an empty directory', () {
      expect(
        validateBackupDirectory(directory: '  ', storageRoot: root),
        '请选择备份目录',
      );
    });

    test('rejects the storage root itself', () {
      expect(
        validateBackupDirectory(directory: root, storageRoot: root),
        '备份目录不能与存储根目录相同',
      );
    });

    test('rejects a directory inside the storage root', () {
      expect(
        validateBackupDirectory(
          directory: r'D:\library\backups',
          storageRoot: root,
        ),
        '备份目录不能位于存储根目录内',
      );
    });

    test('rejects an ancestor of the storage root', () {
      expect(
        validateBackupDirectory(directory: r'D:\', storageRoot: root),
        '备份目录不能是存储根目录的上级目录',
      );
      expect(
        validateBackupDirectory(directory: 'D:\\', storageRoot: root),
        '备份目录不能是存储根目录的上级目录',
      );
    });
  });

  group('isBackupDue', () {
    final now = DateTime.utc(2026, 8, 19, 12);

    test('is due when never attempted', () {
      expect(
        isBackupDue(now: now, lastBackupAt: '', intervalHours: 24),
        isTrue,
      );
    });

    test('is due when the timestamp is unparsable', () {
      expect(
        isBackupDue(now: now, lastBackupAt: 'not-a-date', intervalHours: 24),
        isTrue,
      );
    });

    test('is not due within the interval', () {
      final last = now.subtract(const Duration(hours: 23));
      expect(
        isBackupDue(
          now: now,
          lastBackupAt: last.toIso8601String(),
          intervalHours: 24,
        ),
        isFalse,
      );
    });

    test('is due once the interval has elapsed', () {
      final last = now.subtract(const Duration(hours: 24));
      expect(
        isBackupDue(
          now: now,
          lastBackupAt: last.toIso8601String(),
          intervalHours: 24,
        ),
        isTrue,
      );
    });

    test('is not due when the timestamp is in the future', () {
      final last = now.add(const Duration(hours: 1));
      expect(
        isBackupDue(
          now: now,
          lastBackupAt: last.toIso8601String(),
          intervalHours: 24,
        ),
        isFalse,
      );
    });

    test('never due with a non-positive interval', () {
      expect(isBackupDue(now: now, lastBackupAt: '', intervalHours: 0), isFalse);
    });
  });

  group('backup preferences', () {
    test('round-trips the scheduled backup fields', () {
      const preferences = UserPreferences(
        backupEnabled: true,
        backupDirectory: r'D:\backups',
        backupIntervalHours: 12,
        backupIncremental: true,
        lastBackupAt: '2026-08-19T04:00:00.000Z',
      );
      final restored = UserPreferences.fromJson(preferences.toJson());
      expect(restored.backupEnabled, isTrue);
      expect(restored.backupDirectory, r'D:\backups');
      expect(restored.backupIntervalHours, 12);
      expect(restored.backupIncremental, isTrue);
      expect(restored.lastBackupAt, '2026-08-19T04:00:00.000Z');
    });

    test('legacy preferences without backup keys keep the defaults', () {
      final restored = UserPreferences.fromJson(
        const UserPreferences().toJson()..remove('backupEnabled'),
      );
      expect(restored.backupEnabled, isFalse);
      expect(restored.backupDirectory, '');
      expect(restored.backupIntervalHours, 24);
      expect(restored.backupIncremental, isFalse);
      expect(restored.lastBackupAt, '');
    });

    test('rejects invalid backup field values', () {
      Map<String, dynamic> json() => const UserPreferences().toJson();
      expect(
        () => UserPreferences.fromJson(json()..['backupIntervalHours'] = 0),
        throwsFormatException,
      );
      expect(
        () => UserPreferences.fromJson(json()..['lastBackupAt'] = 'garbage'),
        throwsFormatException,
      );
      expect(
        () => UserPreferences.fromJson(json()..['backupEnabled'] = 'yes'),
        throwsFormatException,
      );
    });

    test('updatePreferences describes backup changes in the settings log', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-backup-prefs-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final store = LocalStore(
        baseDirectory: Directory('${sandbox.path}/config'),
      );
      await store.save(AppState.empty());
      final controller = TagTagController(store: store);
      await controller.load();

      await controller.updatePreferences(
        backupEnabled: true,
        backupDirectory: r'D:\backups',
        backupIntervalHours: 12,
        backupIncremental: true,
      );

      expect(controller.preferences.backupEnabled, isTrue);
      final summary = controller.state.logEvents.last.summary;
      expect(summary, contains('定期备份 开启'));
      expect(summary, contains('备份目录 已更新'));
      expect(summary, contains('备份间隔 每 12 小时'));
      expect(summary, contains('备份策略 增量'));

      // Stamping lastBackupAt alone must not write a settings log entry.
      final logCount = controller.state.logEvents.length;
      await controller.updatePreferences(
        lastBackupAt: DateTime.now().toUtc().toIso8601String(),
      );
      expect(controller.state.logEvents.length, logCount);

      final reloaded = TagTagController(store: store);
      await reloaded.load();
      expect(reloaded.preferences.backupEnabled, isTrue);
      expect(reloaded.preferences.backupDirectory, r'D:\backups');
      expect(reloaded.preferences.lastBackupAt, isNotEmpty);
    });
  });

  group('incremental backup', () {
    test('rejects destinations equal to, inside, or above the root', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-incremental-guard-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);

      await expectLater(
        library.createIncrementalBackup(root),
        throwsArgumentError,
      );
      await expectLater(
        library.createIncrementalBackup(Directory('${root.path}/backups')),
        throwsArgumentError,
      );
      await expectLater(
        library.createIncrementalBackup(sandbox),
        throwsArgumentError,
      );
    });

    test(
      'copies only new or changed files and never deletes remote files',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'tagtag-incremental-',
        );
        addTearDown(() => sandbox.delete(recursive: true));
        final root = Directory('${sandbox.path}/library');
        final sourceA = File('${sandbox.path}/a.txt');
        final sourceB = File('${sandbox.path}/b.txt');
        await sourceA.writeAsString('alpha');
        await sourceB.writeAsString('beta');
        final library = await ManagedLibrary.initialize(root);
        addTearDown(library.close);
        await library.importResource(source: sourceA, targetDirectory: 'docs');
        await library.importResource(source: sourceB, targetDirectory: 'docs');

        final destination = Directory('${sandbox.path}/backups');
        final first = await library.createIncrementalBackup(
          destination,
          metadataDocuments: {
            'tag-state.json': jsonEncode(AppState.empty().toJson()),
          },
        );

        expect(first.backupDirectory.path, contains('TAGTAG-incremental'));
        expect(first.copiedFiles, 2);
        expect(first.skippedFiles, 0);
        expect(
          await File(
            '${first.backupDirectory.path}/metadata/tagtag.sqlite',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${first.backupDirectory.path}/metadata/tag-state.json',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${first.backupDirectory.path}/manifest.json',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${first.backupDirectory.path}/resources/docs/a.txt',
          ).readAsString(),
          'alpha',
        );

        // Second run with untouched sources copies nothing.
        final second = await library.createIncrementalBackup(destination);
        expect(second.copiedFiles, 0);
        expect(second.skippedFiles, 2);

        // A leftover remote file is never deleted even though it is no
        // longer part of the library content.
        final leftover = File(
          '${first.backupDirectory.path}/resources/docs/removed.txt',
        );
        await leftover.writeAsString('orphan');

        // Change one source (different size) and add a new one.
        await File('${root.path}/docs/a.txt').writeAsString('alpha-changed!');
        final sourceC = File('${sandbox.path}/c.txt');
        await sourceC.writeAsString('gamma');
        await library.importResource(source: sourceC, targetDirectory: 'docs');

        final third = await library.createIncrementalBackup(destination);
        expect(third.copiedFiles, 2);
        expect(third.skippedFiles, 1);
        expect(
          await File(
            '${first.backupDirectory.path}/resources/docs/a.txt',
          ).readAsString(),
          'alpha-changed!',
        );
        expect(await leftover.readAsString(), 'orphan');

        final manifest =
            jsonDecode(
                  await File(
                    '${first.backupDirectory.path}/manifest.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['strategy'], 'incremental');
        expect(manifest['resourceCount'], 3);
        expect(
          (manifest['entries'] as Map<String, dynamic>).keys,
          containsAll(<String>[
            'resources/docs/a.txt',
            'resources/docs/b.txt',
            'resources/docs/c.txt',
          ]),
        );
      },
    );

    test('folder resources only recopy changed inner files', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-incremental-folder-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final sourceFolder = Directory('${sandbox.path}/folder');
      await Directory('${sourceFolder.path}/sub').create(recursive: true);
      await File('${sourceFolder.path}/sub/one.txt').writeAsString('one');
      await File('${sourceFolder.path}/two.txt').writeAsString('two');
      final library = await ManagedLibrary.initialize(root);
      addTearDown(library.close);
      await library.importResource(
        source: sourceFolder,
        targetDirectory: 'docs',
      );

      final destination = Directory('${sandbox.path}/backups');
      final first = await library.createIncrementalBackup(destination);
      expect(first.copiedFiles, 2);
      expect(
        await File(
          '${first.backupDirectory.path}/resources/docs/folder/sub/one.txt',
        ).readAsString(),
        'one',
      );

      await File(
        '${root.path}/docs/folder/two.txt',
      ).writeAsString('two-changed');
      final second = await library.createIncrementalBackup(destination);
      expect(second.copiedFiles, 1);
      expect(second.skippedFiles, 1);
      expect(
        await File(
          '${first.backupDirectory.path}/resources/docs/folder/two.txt',
        ).readAsString(),
        'two-changed',
      );
    });
  });
}
