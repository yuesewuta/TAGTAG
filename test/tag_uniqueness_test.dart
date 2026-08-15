import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/data/local_store.dart';
import 'package:tagtag/models/tag_models.dart';
import 'package:tagtag/state/tagtag_controller.dart';

void main() {
  test('duplicate names are allowed by default and reported', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    // Demo state already contains two independent 参考 tags.
    expect(controller.duplicateTagNamesInActiveSpace, contains('参考'));

    // No policy blocks another same-name tag by default.
    final placementId = await controller.createPlacement(
      name: '参考',
      colorValue: 0,
    );
    expect(controller.state.placementById(placementId).tagId, isNot('tag-reference-shared'));
  });

  test('global unique setting blocks same-name creation', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.updatePreferences(uniqueTagNames: true);
    expect(
      () => controller.createPlacement(name: '设计', colorValue: 0),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('同名唯一标签'),
        ),
      ),
    );
    // The setting change is logged as a settings entry.
    expect(
      controller.state.logEvents.map((event) => event.summary).join('\n'),
      contains('标签名称全局唯一 开启'),
    );
  });

  test('per-tag unique policy blocks duplicates with the global setting off', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.setTagNamePolicy('tag-design', TagNamePolicy.unique);
    expect(controller.tagNamePolicyOf('tag-design'), TagNamePolicy.unique);
    expect(
      () => controller.createPlacement(name: '设计', colorValue: 0),
      throwsA(isA<StateError>()),
    );
    // Non-unique names still work.
    await controller.createPlacement(name: '全新标签', colorValue: 0);
  });

  test('free policy exempts a tag while the global setting is on', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.updatePreferences(uniqueTagNames: true);
    await controller.setTagNamePolicy('tag-design', TagNamePolicy.free);
    final placementId = await controller.createPlacement(
      name: '设计',
      colorValue: 0,
    );
    expect(
      controller.state.placementById(placementId).tagId,
      isNot('tag-design'),
    );
  });

  test('policy changes are logged and persist across reload', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;

    await controller.setTagNamePolicy('tag-design', TagNamePolicy.unique);
    expect(
      controller.state.tagOperations.map((operation) => operation.summary),
      contains('标记标签“设计”为唯一标签'),
    );

    final reloaded = TagTagController(store: fixture.store);
    await reloaded.load();
    expect(reloaded.tagNamePolicyOf('tag-design'), TagNamePolicy.unique);

    // Restoring the default policy is a no-op-safe edit.
    await reloaded.setTagNamePolicy('tag-design', TagNamePolicy.inherit);
    expect(reloaded.tagNamePolicyOf('tag-design'), TagNamePolicy.inherit);
  });
}

Future<({TagTagController controller, LocalStore store, void Function() dispose})>
    _fixture() async {
  final directory = await Directory.systemTemp.createTemp('tagtag-unique-');
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
