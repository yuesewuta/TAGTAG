import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/main.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/platform/windows_file_actions.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/library_locator.dart';
import 'package:tagtag/storage/managed_library.dart';
import 'package:tagtag/ui/home_screen.dart';

void main() {
  testWidgets('shows a useful error when the storage root picker fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      TagTagApp(
        locator: _EmptyLibraryLocator(),
        storageRootPicker: () async => throw StateError('picker unavailable'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择存储根目录'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('picker unavailable'), findsOneWidget);
  });

  testWidgets('consistency dialog exposes explicit actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sandbox = await Directory.systemTemp.createTemp(
      'tagtag-consistency-dialog-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final root = Directory('${sandbox.path}/library');
    final source = File('${sandbox.path}/source.txt');
    await source.writeAsString('external move');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(library.close);
    final store = LocalStore(
      baseDirectory: Directory('${sandbox.path}/config'),
    );
    await store.save(AppState.demo());
    final controller = TagTagController(store: store, library: library);
    await controller.load();
    final imported = await controller.importManagedResource(
      source: source,
      targetDirectory: '',
    );
    await File(imported.path).rename('${root.path}/renamed.txt');

    await tester.pumpWidget(
      MaterialApp(
        home: TagTagHome(
          controller: controller,
          fileActions: WindowsFileActions(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('一致性告警'));
    await tester.pumpAndSettle();

    expect(find.text('发现未受管内容'), findsOneWidget);
    expect(find.text('受管资源被外部删除或移动'), findsOneWidget);
    expect(find.text('接管'), findsOneWidget);
    expect(find.text('移出'), findsOneWidget);
    expect(find.text('接受新路径'), findsOneWidget);
    expect(find.text('恢复记录路径'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EmptyLibraryLocator extends LibraryLocator {
  @override
  Future<Directory?> loadRoot() async => null;
}
