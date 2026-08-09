import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class LibraryLocator {
  LibraryLocator({this.configDirectory});

  final Directory? configDirectory;

  Future<Directory?> loadRoot() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['storageRoot'] is! String) {
      throw const FormatException('TAGTAG 存储根配置无效');
    }
    return Directory(path.normalize(decoded['storageRoot'] as String));
  }

  Future<void> saveRoot(Directory root) async {
    final normalizedRoot = Directory(path.normalize(root.absolute.path));
    if (!await normalizedRoot.exists()) {
      throw FileSystemException('存储根目录不存在', normalizedRoot.path);
    }
    final probe = File(
      path.join(
        normalizedRoot.path,
        '.tagtag-write-probe-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probe.writeAsString('TAGTAG', flush: true);
    } finally {
      if (await probe.exists()) {
        await probe.delete();
      }
    }

    final file = await _configFile(createParent: true);
    final temporary = File('${file.path}.tmp');
    final previous = File('${file.path}.previous');
    await temporary.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'version': 1, 'storageRoot': normalizedRoot.path}),
      flush: true,
    );
    try {
      if (await previous.exists()) {
        await previous.delete();
      }
      if (await file.exists()) {
        await file.rename(previous.path);
      }
      await temporary.rename(file.path);
      if (await previous.exists()) {
        await previous.delete();
      }
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  Future<File> _configFile({bool createParent = false}) async {
    final directory = configDirectory ?? _defaultConfigDirectory();
    if (createParent) {
      await directory.create(recursive: true);
    }
    return File(path.join(directory.path, 'library.json'));
  }

  static Directory _defaultConfigDirectory() {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    return Directory(path.join(base, 'TAGTAG'));
  }
}
