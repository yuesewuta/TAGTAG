import 'dart:io';

import 'package:path/path.dart' as path;

import '../data/local_store.dart';
import '../state/tagtag_controller.dart';
import '../storage/library_locator.dart';
import '../storage/managed_library.dart';

class GlobalBackupRestoreSession {
  const GlobalBackupRestoreSession({
    required this.library,
    required this.controller,
  });

  final ManagedLibrary library;
  final TagTagController controller;
}

class GlobalBackupRestorer {
  const GlobalBackupRestorer({required this.locator, required this.store});

  final LibraryLocator locator;
  final LocalStore store;

  Future<GlobalBackupRestoreSession> restore({
    required Directory backupDirectory,
    required Directory targetRoot,
    required Directory currentRoot,
    RecycleBinGateway? recycleBin,
  }) async {
    final normalizedCurrent = path.normalize(currentRoot.absolute.path);
    final normalizedTarget = path.normalize(targetRoot.absolute.path);
    if (path.equals(normalizedCurrent, normalizedTarget) ||
        path.isWithin(normalizedCurrent, normalizedTarget)) {
      throw ArgumentError.value(
        targetRoot.path,
        'targetRoot',
        '恢复目标不能是当前存储根或其子目录',
      );
    }

    final previousRoot = await locator.loadRoot();
    ManagedLibrary? restoredLibrary;
    try {
      final restored = await ManagedLibrary.restoreBackup(
        backupDirectory,
        targetRoot,
      );
      restoredLibrary = await ManagedLibrary.open(restored.root);
      final controller = TagTagController(
        store: store,
        library: restoredLibrary,
        recycleBin: recycleBin,
      );
      await controller.persistRestoredBackupMetadata(restored);
      await locator.saveRoot(restored.root);
      await controller.load();
      return GlobalBackupRestoreSession(
        library: restoredLibrary,
        controller: controller,
      );
    } catch (_) {
      await restoredLibrary?.close();
      if (previousRoot != null) {
        await locator.saveRoot(previousRoot);
      }
      rethrow;
    }
  }
}
