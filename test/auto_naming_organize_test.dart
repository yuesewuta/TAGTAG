import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/managed_library.dart';
import 'package:tagtag/ui/glass.dart';
import 'package:tagtag/ui/home_screen.dart';
import 'package:tagtag/ui/prototype_dialogs.dart';
import 'package:tagtag/ui/tagtag_theme.dart';

void main() {
  group('naming template rendering', () {
    final date = DateTime(2026, 8, 15, 9, 5, 3);

    test('empty template keeps the original name', () {
      expect(
        TagTagController.applyNamingTemplate(
          template: '',
          sourceName: 'photo.png',
          importDate: date,
        ),
        'photo.png',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '   ',
          sourceName: 'photo.png',
          importDate: date,
        ),
        'photo.png',
      );
    });

    test('placeholders render and the extension is kept', () {
      expect(
        TagTagController.applyNamingTemplate(
          template: '{日期}',
          sourceName: 'photo.png',
          importDate: date,
        ),
        '2026-08-15.png',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '{时间}',
          sourceName: 'photo.png',
          importDate: date,
        ),
        '09-05-03.png',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '{原名}',
          sourceName: 'photo.png',
          importDate: date,
        ),
        'photo.png',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '{原名}-{序号}',
          sourceName: 'photo.png',
          importDate: date,
          index: 3,
        ),
        'photo-3.png',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '{原名}',
          sourceName: 'archive.tar.gz',
          importDate: date,
        ),
        'archive.tar.gz',
      );
    });

    test('tag placeholder joins names and falls back to 未标注', () {
      expect(
        TagTagController.applyNamingTemplate(
          template: '{标签}-{原名}',
          sourceName: 'note.txt',
          importDate: date,
          tagNames: const ['设计', '项目'],
        ),
        '设计、项目-note.txt',
      );
      expect(
        TagTagController.applyNamingTemplate(
          template: '{标签}-{原名}',
          sourceName: 'note.txt',
          importDate: date,
        ),
        '未标注-note.txt',
      );
    });

    test('forbidden characters are sanitized to dashes', () {
      expect(
        TagTagController.applyNamingTemplate(
          template: 'a/b\\c:d*e?f"g<h>i|j-{原名}',
          sourceName: 'photo.png',
          importDate: date,
        ),
        'a-b-c-d-e-f-g-h-i-j-photo.png',
      );
    });

    test('names without extension keep working', () {
      expect(
        TagTagController.applyNamingTemplate(
          template: '{原名}-{序号}',
          sourceName: 'docs',
          importDate: date,
          index: 2,
        ),
        'docs-2',
      );
    });
  });

  group('naming template preference', () {
    test('preference persists, logs 设置变更 and defaults are tolerant', () async {
      final fixture = await _createStateFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;

      await controller.updatePreferences(namingTemplate: '{日期}-{原名}');
      expect(controller.preferences.namingTemplate, '{日期}-{原名}');
      expect(controller.state.logEvents.single.summary, '更新设置：命名模板 已更新');

      await controller.updatePreferences(namingTemplate: '');
      expect(controller.preferences.namingTemplate, '');
      expect(controller.state.logEvents.last.summary, '更新设置：命名模板 已清除');

      await controller.updatePreferences(namingTemplate: '{标签}-{原名}');
      final reloaded = TagTagController(store: fixture.store);
      await reloaded.load();
      expect(reloaded.preferences.namingTemplate, '{标签}-{原名}');
    });

    test('fromJson tolerates a missing namingTemplate key', () {
      expect(
        UserPreferences.fromJson(const {
          'version': 1,
          'moveImportsByDefault': false,
        }).namingTemplate,
        '',
      );
      expect(
        () => UserPreferences.fromJson(const {
          'version': 1,
          'moveImportsByDefault': false,
          'namingTemplate': 42,
        }),
        throwsFormatException,
      );
    });
  });

  group('templated import', () {
    test('importManagedResource applies the rendered name', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final source = File('${fixture.sandbox.path}/external/note.txt');
      await source.create(recursive: true);
      await source.writeAsString('original bytes');

      final resource = await fixture.controller.importManagedResource(
        source: source,
        targetDirectory: 'inbox',
        placementIds: const {'place-project-design'},
        targetName: TagTagController.applyNamingTemplate(
          template: '{原名}-{序号}',
          sourceName: 'note.txt',
          importDate: DateTime(2026, 8, 15),
          index: 1,
        ),
      );

      expect(resource.name, 'note-1.txt');
      expect(
        await File(
          '${fixture.library.root.path}/inbox/note-1.txt',
        ).readAsString(),
        'original bytes',
      );
      expect(fixture.controller.state.resources.single.name, 'note-1.txt');
    });

    test(
      'renamed imports auto-rename on conflicts instead of overwriting',
      () async {
        final fixture = await _createLibraryFixture();
        addTearDown(fixture.dispose);
        final first = File('${fixture.sandbox.path}/external/a.txt');
        await first.create(recursive: true);
        await first.writeAsString('a');
        final second = File('${fixture.sandbox.path}/external/b.txt');
        await second.writeAsString('b');

        await fixture.controller.importManagedResource(
          source: first,
          targetDirectory: 'inbox',
          targetName: 'same.txt',
        );
        final renamed = await fixture.controller.importManagedResource(
          source: second,
          targetDirectory: 'inbox',
          targetName: 'same.txt',
        );

        final now = DateTime.now();
        final dateLabel =
            '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        // Untagged conflicts differentiate with the MM-DD date suffix.
        expect(renamed.name, 'same-$dateLabel.txt');
        expect(
          renamed.path.replaceAll('\\', '/'),
          endsWith('inbox/same-$dateLabel.txt'),
        );
        // The original target keeps its bytes; the new resource carries the
        // second source's bytes under the suffixed name.
        expect(
          await File(
            '${fixture.library.root.path}/inbox/same.txt',
          ).readAsString(),
          'a',
        );
        expect(
          await File(
            '${fixture.library.root.path}/inbox/same-$dateLabel.txt',
          ).readAsString(),
          'b',
        );
        expect(await first.readAsString(), 'a');
        expect(await second.readAsString(), 'b');
        expect(fixture.controller.state.resources, hasLength(2));
      },
    );

    test('library importResource validates the target name', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final source = File('${fixture.sandbox.path}/external/c.txt');
      await source.create(recursive: true);
      await source.writeAsString('c');

      expect(
        () => fixture.library.importResource(
          source: source,
          targetDirectory: '',
          targetName: 'nested/name.txt',
        ),
        throwsArgumentError,
      );
      expect(
        () => fixture.library.importResource(
          source: source,
          targetDirectory: '',
          targetName: '  ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('manual organize', () {
    test('preview reports counts and conflicts; execute moves bytes, keeps the '
        'scan clean and undo restores', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final rootPath = fixture.library.root.path;

      Future<File> createSource(String name, String bytes) async {
        final file = File('${fixture.sandbox.path}/external/$name');
        await file.create(recursive: true);
        await file.writeAsString(bytes);
        return file;
      }

      final first = await createSource('a.txt', 'bytes-a');
      final second = await createSource('b.txt', 'bytes-b');
      final untagged = await createSource('c.txt', 'bytes-c');
      await controller.importManagedResource(
        source: first,
        targetDirectory: 'inbox',
        placementIds: const {'place-project-design'},
      );
      await controller.importManagedResource(
        source: second,
        targetDirectory: 'inbox',
        placementIds: const {'place-project-design'},
      );
      await controller.importManagedResource(
        source: untagged,
        targetDirectory: 'inbox',
      );

      var preview = await controller.previewOrganizeForPlacement(
        'place-project-design',
      );
      expect(preview.targetDirectory, '项目/设计');
      expect(preview.movableResources, hasLength(2));
      expect(preview.alreadyInPlaceCount, 0);
      expect(preview.conflicts, isEmpty);

      // A name conflict at the destination is listed and never overwritten.
      final conflicting = await createSource('conflict.txt', 'managed');
      await controller.importManagedResource(
        source: conflicting,
        targetDirectory: 'inbox',
        placementIds: const {'place-project-design'},
      );
      await Directory('$rootPath/项目/设计').create(recursive: true);
      await File('$rootPath/项目/设计/conflict.txt').writeAsString('external');
      preview = await controller.previewOrganizeForPlacement(
        'place-project-design',
      );
      expect(preview.movableResources, hasLength(2));
      expect(preview.conflicts, hasLength(1));
      expect(preview.conflicts.single.reason, contains('已存在'));

      final summary = await controller.organizeForPlacement(
        'place-project-design',
      );
      expect(summary.movedCount, 2);
      expect(summary.skippedConflictCount, 1);
      expect(await File('$rootPath/项目/设计/a.txt').readAsString(), 'bytes-a');
      expect(await File('$rootPath/项目/设计/b.txt').readAsString(), 'bytes-b');
      expect(await File('$rootPath/inbox/a.txt').exists(), isFalse);
      // Untagged and conflicting resources stay put; nothing is overwritten.
      expect(await File('$rootPath/inbox/c.txt').readAsString(), 'bytes-c');
      expect(
        await File('$rootPath/项目/设计/conflict.txt').readAsString(),
        'external',
      );
      expect(
        controller.state.resources
            .singleWhere((resource) => resource.name == 'a.txt')
            .path
            .replaceAll('\\', '/'),
        contains('项目/设计/a.txt'),
      );
      // The only finding is the manually planted untracked conflict file;
      // the organize moves themselves introduce no scan noise.
      var findings = await controller.scanConsistency();
      expect(findings, hasLength(1));
      expect(findings.single.type, ConsistencyFindingType.untracked);
      expect(findings.single.relativePath, '项目/设计/conflict.txt');

      final operations = (await controller.listOperations())
          .where(
            (operation) => operation.type == ManagedOperationType.organizeMove,
          )
          .toList();
      expect(operations, hasLength(2));
      final logEntries = await controller.listLogEntries();
      expect(
        logEntries.where((entry) => entry.summary.contains('整理资源到标签目录')),
        hasLength(2),
      );

      // Domain undo restores both moves byte-for-byte and stays clean.
      for (final operation in operations) {
        await controller.undoOperation(operation.id);
      }
      expect(await File('$rootPath/inbox/a.txt').readAsString(), 'bytes-a');
      expect(await File('$rootPath/inbox/b.txt').readAsString(), 'bytes-b');
      expect(await File('$rootPath/项目/设计/a.txt').exists(), isFalse);
      findings = await controller.scanConsistency();
      expect(findings, hasLength(1));
      expect(findings.single.type, ConsistencyFindingType.untracked);
      // Nothing managed lives under 项目 anymore, so the whole directory
      // (which only holds the planted conflict file) is the finding.
      expect(findings.single.relativePath, '项目');
    });

    test('resources already in place are skipped', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final source = File('${fixture.sandbox.path}/external/placed.txt');
      await source.create(recursive: true);
      await source.writeAsString('already placed');
      await controller.importManagedResource(
        source: source,
        targetDirectory: '项目/设计',
        placementIds: const {'place-project-design'},
      );

      final preview = await controller.previewOrganizeForPlacement(
        'place-project-design',
      );
      expect(preview.hasWork, isFalse);
      expect(preview.alreadyInPlaceCount, 1);
      expect(preview.movableResources, isEmpty);

      final summary = await controller.organizeForPlacement(
        'place-project-design',
      );
      expect(summary.movedCount, 0);
      expect(summary.alreadyInPlaceCount, 1);
      expect(
        await File(
          '${fixture.library.root.path}/项目/设计/placed.txt',
        ).readAsString(),
        'already placed',
      );
      expect(await controller.scanConsistency(), isEmpty);
    });

    test('effective tags include inherited ones; nested records move with the '
        'folder', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final rootPath = fixture.library.root.path;

      final folder = Directory('${fixture.sandbox.path}/external/docs');
      await Directory('${folder.path}/inner').create(recursive: true);
      await File('${folder.path}/inner/deep.txt').writeAsString('deep');
      final folderResource = await controller.importManagedResource(
        source: folder,
        targetDirectory: 'inbox',
        placementIds: const {'place-project-design'},
      );
      controller.selectResource(folderResource.id);
      await controller.assignPlacementToSelection(
        'place-project-design',
        inheritChildren: true,
      );
      final child = File('${fixture.sandbox.path}/external/z-note.txt');
      await child.writeAsString('child bytes');
      final childResource = await controller.importManagedResource(
        source: child,
        targetDirectory: 'inbox/docs',
      );

      // The child file only carries the tag through folder inheritance.
      final effective = controller.effectiveTagsForResource(childResource.id);
      expect(effective.single.tag.name, '设计');
      expect(effective.single.isInherited, isTrue);

      final preview = await controller.previewOrganizeForPlacement(
        'place-project-design',
      );
      expect(preview.movableResources, hasLength(2));

      final summary = await controller.organizeForPlacement(
        'place-project-design',
      );
      expect(summary.movedCount, 2);
      expect(
        await File('$rootPath/项目/设计/docs/inner/deep.txt').readAsString(),
        'deep',
      );
      expect(
        await File('$rootPath/项目/设计/z-note.txt').readAsString(),
        'child bytes',
      );
      final paths = (await fixture.library.listResources())
          .map((resource) => resource.relativePath)
          .toSet();
      expect(paths, containsAll(['项目/设计/docs', '项目/设计/z-note.txt']));
      expect(await controller.scanConsistency(), isEmpty);
    });

    test('library organizeMove round-trips and undo restores', () async {
      final fixture = await _createLibraryFixture();
      addTearDown(fixture.dispose);
      final library = fixture.library;
      final rootPath = library.root.path;
      final source = File('${fixture.sandbox.path}/external/solo.txt');
      await source.create(recursive: true);
      await source.writeAsString('solo bytes');

      final imported = await library.importResource(
        source: source,
        targetDirectory: 'inbox',
      );
      final operation = await library.organizeMove(imported.id, '项目/设计');

      expect(operation.type, ManagedOperationType.organizeMove);
      expect(
        await File('$rootPath/项目/设计/solo.txt').readAsString(),
        'solo bytes',
      );
      expect(await File('$rootPath/inbox/solo.txt').exists(), isFalse);
      expect(
        (await library.listResources()).single.relativePath,
        '项目/设计/solo.txt',
      );
      expect(await library.scanConsistency(), isEmpty);

      // A conflicting destination is rejected without touching anything:
      // the first resource already occupies 项目/设计/solo.txt.
      final second = await library.importResource(
        source: File('${fixture.sandbox.path}/external/solo.txt'),
        targetDirectory: 'staging',
      );
      expect(() => library.organizeMove(second.id, '项目/设计'), throwsStateError);
      expect(
        await File('$rootPath/项目/设计/solo.txt').readAsString(),
        'solo bytes',
      );

      await library.undo(operation.id);
      expect(
        await File('$rootPath/inbox/solo.txt').readAsString(),
        'solo bytes',
      );
      expect(await File('$rootPath/项目/设计/solo.txt').exists(), isFalse);
      expect(
        (await library.listOperations())
            .singleWhere((item) => item.id == operation.id)
            .undoneAt,
        isNotNull,
      );
    });

    test('a schema v6 library migrates and accepts organize moves', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tagtag-organize-migration-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final root = Directory('${sandbox.path}/library');
      final library = await ManagedLibrary.initialize(root);
      final source = File('${sandbox.path}/external/legacy.txt');
      await source.create(recursive: true);
      await source.writeAsString('legacy');
      final imported = await library.importResource(
        source: source,
        targetDirectory: 'inbox',
      );
      await library.close();
      // Downgrade the marker and reopen: the v6 → v7 migration must rebuild
      // the operations table so it accepts the organize_move type.
      final database = sqlite3.open('${root.path}/.tagtag/tagtag.sqlite');
      database.execute(
        "UPDATE metadata SET value = '6' WHERE key = 'schema_version'",
      );
      database.close();

      final reopened = await ManagedLibrary.open(root);
      addTearDown(reopened.close);
      final operation = await reopened.organizeMove(imported.id, '归档');
      expect(operation.type, ManagedOperationType.organizeMove);
      expect(
        (await reopened.listOperations()).where(
          (item) => item.type == ManagedOperationType.organizeMove,
        ),
        hasLength(1),
      );
      expect(await File('${root.path}/归档/legacy.txt').readAsString(), 'legacy');
      expect(await reopened.scanConsistency(), isEmpty);
    });
  });

  group('widget flows', () {
    testWidgets('settings dialog saves the naming template', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _createWidgetFixture(tester);
      addTearDown(() async {
        try {
          await fixture.sandbox.delete(recursive: true);
        } on PathAccessException {
          // Windows may briefly keep persisted files locked.
        }
      });
      await _pumpWorkspace(tester, fixture.controller);

      await tester.tap(find.byKey(const ValueKey('nav-设置')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入与标注'));
      await tester.pumpAndSettle();

      expect(find.text('导入命名模板'), findsOneWidget);
      expect(find.textContaining('{原名} {日期} {时间} {标签} {序号}'), findsOneWidget);
      expect(find.textContaining('示例：报告.pdf'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('naming-template-field')),
        '{原名}-{序号}',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('示例：报告-1.pdf'), findsOneWidget);

      await tester.tap(find.text('保存设置'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(fixture.controller.preferences.namingTemplate, '{原名}-{序号}');
      expect(
        fixture.controller.state.logEvents.last.summary,
        contains('命名模板 已更新'),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('import dialog shows the rename toggle and preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _createWidgetFixture(tester);
      addTearDown(() async {
        try {
          await fixture.sandbox.delete(recursive: true);
        } on PathAccessException {
          // Windows may briefly keep persisted files locked.
        }
      });
      await tester.runAsync(
        () => fixture.controller.updatePreferences(namingTemplate: '{原名}-{序号}'),
      );
      final external = Directory('${fixture.sandbox.path}/external');
      await tester.runAsync(() async {
        await external.create(recursive: true);
        await File('${external.path}/alpha.txt').writeAsString('a');
        await File('${external.path}/beta.txt').writeAsString('b');
      });
      final sources = [
        File('${external.path}/alpha.txt'),
        File('${external.path}/beta.txt'),
      ];

      PrototypeImportResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTagTagTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPrototypeDialog<PrototypeImportResult>(
                    context: context,
                    builder: (context) => PrototypeImportDialog(
                      controller: fixture.controller,
                      sources: sources,
                      initialMode: ImportMode.copy,
                    ),
                  );
                },
                child: const Text('open-import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-import'));
      await tester.pumpAndSettle();

      expect(find.text('按模板重命名'), findsOneWidget);
      expect(find.textContaining('第一个资源将命名为：alpha-1.txt'), findsOneWidget);

      await tester.tap(find.text('复制并导入'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.renamedSources, {
        sources[0].path: 'alpha-1.txt',
        sources[1].path: 'beta-2.txt',
      });

      // Turning the toggle off imports the batch with original names.
      await tester.tap(find.text('open-import'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PillSwitch));
      await tester.pumpAndSettle();
      expect(find.textContaining('第一个资源将命名为：'), findsNothing);
      await tester.tap(find.text('复制并导入'));
      await tester.pumpAndSettle();
      expect(result!.renamedSources, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('import dialog annotates sources that will auto-rename', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _createWidgetLibraryFixture(tester);
      addTearDown(() async {
        try {
          await fixture.sandbox.delete(recursive: true);
        } on PathAccessException {
          // Windows may briefly keep persisted files locked.
        }
      });
      await tester.runAsync(() async {
        // The dialog targets the storage root by default, so the conflicting
        // managed resource lives there too.
        final managed = File('${fixture.sandbox.path}/managed/alpha.txt');
        await managed.create(recursive: true);
        await managed.writeAsString('managed bytes');
        await fixture.controller.importManagedResource(
          source: managed,
          targetDirectory: '',
        );
        final incoming = File('${fixture.sandbox.path}/incoming/alpha.txt');
        await incoming.create(recursive: true);
        await incoming.writeAsString('incoming bytes');
      });
      final sources = [File('${fixture.sandbox.path}/incoming/alpha.txt')];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTagTagTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await showPrototypeDialog<PrototypeImportResult>(
                    context: context,
                    builder: (context) => PrototypeImportDialog(
                      controller: fixture.controller,
                      sources: sources,
                      initialMode: ImportMode.copy,
                    ),
                  );
                },
                child: const Text('open-import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-import'));
      await tester.pumpAndSettle();

      // The per-source annotation resolves through real file IO; alternate
      // real delays with pumps until the resolved name renders.
      await _settleRealAsync(tester, find.textContaining('→ alpha-'));
      await tester.pumpAndSettle();

      expect(find.textContaining('→ alpha-'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('tag menu organizes resources through the preview dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _createWidgetLibraryFixture(tester);
      addTearDown(() async {
        try {
          await fixture.sandbox.delete(recursive: true);
        } on PathAccessException {
          // Windows may briefly keep persisted files locked.
        }
      });
      await tester.runAsync(() async {
        final source = File('${fixture.sandbox.path}/external/menu-import.txt');
        await source.create(recursive: true);
        await source.writeAsString('menu bytes');
        await fixture.controller.importManagedResource(
          source: source,
          targetDirectory: 'inbox',
          placementIds: const {'place-project-design'},
        );
        fixture.controller.showTagHierarchy();
        fixture.controller.selectPlacement('place-project-design');
      });
      await _pumpWorkspace(tester, fixture.controller);

      await tester.tap(find.byTooltip('标签操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('整理此标签的资源到目录…'));
      // The dialog preview does sequential real file IO; alternate real
      // delays (let IO complete) with pumps (flush fake-zone continuations)
      // until the preview renders, since the loading spinner otherwise
      // never lets pumpAndSettle complete.
      await _settleRealAsync(tester, find.textContaining('将移动'));
      await tester.pumpAndSettle();

      expect(find.text('整理此标签的资源到目录'), findsOneWidget);
      expect(find.textContaining('将移动 1 个资源'), findsOneWidget);
      expect(find.text('项目 / 设计'), findsWidgets);

      await tester.tap(find.text('整理'));
      await _settleRealAsync(tester, find.textContaining('已整理'));
      await tester.pumpAndSettle();

      final moved = File('${fixture.library.root.path}/项目/设计/menu-import.txt');
      expect(await tester.runAsync(moved.exists), isTrue);
      expect(
        fixture.controller.state.resources.single.path.replaceAll('\\', '/'),
        contains('项目/设计'),
      );
      expect(find.textContaining('已整理 1 个资源到“项目/设计”'), findsOneWidget);
      expect(
        await tester.runAsync(fixture.controller.scanConsistency),
        isEmpty,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

Future<
  ({TagTagController controller, LocalStore store, void Function() dispose})
>
_createStateFixture() async {
  final directory = await Directory.systemTemp.createTemp('tagtag-naming-');
  final store = LocalStore(baseDirectory: directory);
  await store.save(AppState.demo());
  final controller = TagTagController(store: store);
  await controller.load();
  return (
    controller: controller,
    store: store,
    dispose: () => directory.delete(recursive: true),
  );
}

Future<
  ({
    Directory sandbox,
    ManagedLibrary library,
    TagTagController controller,
    void Function() dispose,
  })
>
_createLibraryFixture() async {
  final sandbox = await Directory.systemTemp.createTemp('tagtag-organize-');
  final library = await ManagedLibrary.initialize(
    Directory('${sandbox.path}/library'),
  );
  final store = LocalStore(baseDirectory: Directory('${sandbox.path}/config'));
  await store.save(AppState.demo());
  final controller = TagTagController(store: store, library: library);
  await controller.load();
  return (
    sandbox: sandbox,
    library: library,
    controller: controller,
    dispose: () async {
      await library.close();
      await sandbox.delete(recursive: true);
    },
  );
}

Future<({Directory sandbox, TagTagController controller})> _createWidgetFixture(
  WidgetTester tester,
) async {
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('tagtag-naming-ui-'),
  ))!;
  final store = LocalStore(baseDirectory: Directory('${sandbox.path}/config'));
  await tester.runAsync(() => store.save(AppState.demo()));
  final controller = TagTagController(store: store);
  await tester.runAsync(controller.load);
  return (sandbox: sandbox, controller: controller);
}

Future<
  ({Directory sandbox, ManagedLibrary library, TagTagController controller})
>
_createWidgetLibraryFixture(WidgetTester tester) async {
  final sandbox = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('tagtag-organize-ui-'),
  ))!;
  final library = (await tester.runAsync(
    () => ManagedLibrary.initialize(Directory('${sandbox.path}/library')),
  ))!;
  final store = LocalStore(baseDirectory: Directory('${sandbox.path}/config'));
  await tester.runAsync(() => store.save(AppState.demo()));
  final controller = TagTagController(store: store, library: library);
  await tester.runAsync(controller.load);
  return (sandbox: sandbox, library: library, controller: controller);
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  TagTagController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTagTagTheme(),
      home: TagTagHome(
        controller: controller,
        fileActions: WindowsFileActions(),
        onRestoreGlobalBackup: (_, _) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Alternates real event-loop time (so dart:io futures complete) with pumps
/// (so fake-zone continuations flush) until [done] appears.
Future<void> _settleRealAsync(
  WidgetTester tester,
  Finder done, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (done.evaluate().isNotEmpty) {
      return;
    }
  }
}
