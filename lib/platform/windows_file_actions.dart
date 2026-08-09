import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../storage/managed_library.dart';

typedef WindowsCommandLauncher =
    Future<void> Function(String executable, List<String> arguments);
typedef WindowsRecycleAction = Future<String> Function(String resourcePath);
typedef WindowsRestoreAction =
    Future<void> Function(String token, String destinationPath);

class WindowsFileActions implements RecycleBinGateway {
  WindowsFileActions({
    WindowsCommandLauncher? launch,
    WindowsRecycleAction? recycle,
    WindowsRestoreAction? restore,
  }) : _launch = launch ?? _launchDetached,
       _recycle = recycle ?? _recycleNative,
       _restore = restore ?? _restoreNative;

  static const _recycleBinChannel = MethodChannel('tagtag/windows_recycle_bin');

  final WindowsCommandLauncher _launch;
  final WindowsRecycleAction _recycle;
  final WindowsRestoreAction _restore;

  Future<void> open(String resourcePath) async {
    final resolved = await _resolveExisting(resourcePath);
    await _launch('explorer.exe', [resolved.path]);
  }

  Future<void> reveal(String resourcePath) async {
    final resolved = await _resolveExisting(resourcePath);
    await _launch(
      'explorer.exe',
      resolved.type == FileSystemEntityType.directory
          ? [resolved.path]
          : ['/select,', resolved.path],
    );
  }

  @override
  Future<String> recycle(String resourcePath) async {
    final resolved = await _resolveExisting(resourcePath);
    final token = await _recycle(resolved.path);
    if (token.isEmpty) {
      throw StateError('Windows 回收站没有返回可撤销标识');
    }
    return token;
  }

  @override
  Future<void> restore(String token, String destinationPath) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', '回收站标识不能为空');
    }
    final resolvedDestination = path.normalize(
      File(destinationPath).absolute.path,
    );
    if (await FileSystemEntity.type(resolvedDestination) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('恢复目标已存在同名资源，TAGTAG 不会覆盖', resolvedDestination);
    }
    await _restore(token, resolvedDestination);
  }

  static Future<({String path, FileSystemEntityType type})> _resolveExisting(
    String resourcePath,
  ) async {
    final resolvedPath = path.normalize(File(resourcePath).absolute.path);
    final type = await FileSystemEntity.type(resolvedPath);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('资源不存在或不是普通文件/文件夹', resolvedPath);
    }
    return (path: resolvedPath, type: type);
  }

  static Future<void> _launchDetached(
    String executable,
    List<String> arguments,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前文件操作适配器仅支持 Windows');
    }
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }

  static Future<String> _recycleNative(String resourcePath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前回收站适配器仅支持 Windows');
    }
    final token = await _recycleBinChannel.invokeMethod<String>('recycle', {
      'path': resourcePath,
    });
    if (token == null || token.isEmpty) {
      throw StateError('Windows 回收站没有返回可撤销标识');
    }
    return token;
  }

  static Future<void> _restoreNative(
    String token,
    String destinationPath,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前回收站适配器仅支持 Windows');
    }
    await _recycleBinChannel.invokeMethod<void>('restore', {
      'token': token,
      'destinationPath': destinationPath,
    });
  }
}
