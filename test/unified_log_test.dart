import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';
import 'package:tagtag/storage/managed_library.dart';

void main() {
  test('settings changes are logged with a field-level summary', () async {
    final fixture = await _createStateFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.updatePreferences(moveImportsByDefault: true);
    await controller.updatePreferences(appearanceTheme: 'dark');
    // No-op change must not produce an entry.
    await controller.updatePreferences(appearanceTheme: 'dark');

    final events = controller.state.logEvents;
    expect(events, hasLength(2));
    expect(events[0].category, LogCategory.settings);
    expect(events[0].level, LogLevel.info);
    expect(events[0].summary, contains('默认导入方式 复制 → 移动'));
    expect(events[1].summary, contains('外观 深色'));
  });

  test('floating target position writes do not log settings entries', () async {
    final fixture = await _createStateFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    expect(controller.state.logEvents, isEmpty);

    await controller.updatePreferences(
      floatingTargetX: 32,
      floatingTargetY: 400,
    );
    expect(controller.preferences.floatingTargetX, 32.0);
    expect(controller.preferences.floatingTargetY, 400.0);
    expect(controller.state.logEvents, isEmpty);

    // A real settings change right after still logs exactly one entry.
    await controller.updatePreferences(closeToTray: false);
    expect(controller.state.logEvents, hasLength(1));
    expect(controller.state.logEvents.single.summary, contains('关闭主窗口时 退出'));
  });

  test('tag lifecycle actions are recorded as tag log operations', () async {
    final fixture = await _createStateFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    final placementId = await controller.createPlacement(
      name: '临时',
      colorValue: 0xff2563eb,
    );
    final tagId = controller.state.placementById(placementId).tagId;
    await controller.updateTag(tagId: tagId, name: '临时改名', colorValue: 0);
    await controller.reparentPlacement(placementId, 'place-project');
    await controller.togglePlacementPinned(placementId);
    await controller.togglePlacementHidden(placementId);
    // The shared 参考 tag has two placements, so one position can be removed.
    await controller.deletePlacement('place-project-design-reference');
    await controller.deleteTagEntity(tagId);

    final types = controller.state.tagOperations
        .map((operation) => operation.type)
        .toList();
    expect(types, [
      TagDomainOperationType.create,
      TagDomainOperationType.edit,
      TagDomainOperationType.reparent,
      TagDomainOperationType.pin,
      TagDomainOperationType.hide,
      TagDomainOperationType.deletePlacement,
      TagDomainOperationType.deleteEntity,
    ]);
    final summaries = controller.state.tagOperations
        .map((operation) => operation.summary)
        .join('\n');
    expect(summaries, contains('新建标签“临时”'));
    expect(summaries, contains('重命名标签“临时”为“临时改名”'));
    expect(summaries, contains('调整标签“临时改名”的层级至“项目”'));
    expect(summaries, contains('固定常用标签“临时改名”'));
    expect(summaries, contains('隐藏常用标签“临时改名”'));
    expect(summaries, contains('删除标签位置“项目 / 设计 / 参考”'));
    expect(summaries, contains('删除标签实体“临时改名”'));
  });

  test('consistency findings log once per change and log recovery', () async {
    final root = await Directory.systemTemp.createTemp('tagtag-log-lib-');
    final library = await ManagedLibrary.initialize(root);
    addTearDown(() async {
      await library.close();
      await root.delete(recursive: true);
    });
    final store = LocalStore(baseDirectory: Directory('${root.path}/config'));
    final controller = TagTagController(store: store, library: library);

    // Clean baseline scan logs nothing.
    await controller.scanConsistency();
    expect(controller.state.logEvents, isEmpty);

    // An external file produces one deduplicated notice.
    File('${root.path}/external.txt').writeAsStringSync('hello');
    await controller.scanConsistency();
    await controller.scanConsistency();
    var consistency = controller.state.logEvents
        .where((event) => event.category == LogCategory.consistency)
        .toList();
    expect(consistency, hasLength(1));
    expect(consistency.single.level, LogLevel.notice);
    expect(consistency.single.summary, contains('1 项外部新增'));

    // Removing the file logs the recovery once.
    File('${root.path}/external.txt').deleteSync();
    await controller.scanConsistency();
    await controller.scanConsistency();
    consistency = controller.state.logEvents
        .where((event) => event.category == LogCategory.consistency)
        .toList();
    expect(consistency, hasLength(2));
    expect(consistency.last.level, LogLevel.info);
    expect(consistency.last.summary, contains('告警已清除'));
  });

  test('unified log merges sources ordered by time with levels', () async {
    final fixture = await _createStateFixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.createPlacement(name: '第一条', colorValue: 0);
    await controller.updatePreferences(closeToTray: false);
    await controller.deletePlacement('place-project-design-reference');

    final entries = await controller.listLogEntries();
    expect(entries.length, 3);
    expect(entries.map((entry) => entry.category), [
      LogCategory.tag, // deletePlacement is the latest
      LogCategory.settings,
      LogCategory.tag,
    ]);
    expect(entries.first.level, LogLevel.notice);
    expect(entries.first.summary, contains('删除标签位置'));
    expect(entries[1].summary, contains('关闭主窗口时 退出'));
    expect(entries.last.level, LogLevel.info);
  });
}

Future<({TagTagController controller, void Function() dispose})>
_createStateFixture() async {
  final directory = await Directory.systemTemp.createTemp('tagtag-log-');
  final store = LocalStore(baseDirectory: directory);
  await store.save(AppState.demo());
  final controller = TagTagController(store: store);
  await controller.load();
  return (
    controller: controller,
    dispose: () => directory.delete(recursive: true),
  );
}
