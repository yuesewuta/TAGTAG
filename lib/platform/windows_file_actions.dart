import 'dart:io';

import 'package:path/path.dart' as path;

typedef WindowsCommandLauncher =
    Future<void> Function(String executable, List<String> arguments);

class WindowsFileActions {
  WindowsFileActions({WindowsCommandLauncher? launch})
    : _launch = launch ?? _launchDetached;

  final WindowsCommandLauncher _launch;

  Future<void> open(String resourcePath) async {
    final resolved = await _resolveExisting(resourcePath);
    await _launch('rundll32.exe', [
      'url.dll,FileProtocolHandler',
      Uri.file(resolved.path).toString(),
    ]);
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
}
