import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'data/local_store.dart';
import 'platform/windows_file_actions.dart';
import 'state/tagtag_controller.dart';
import 'storage/library_locator.dart';
import 'storage/managed_library.dart';
import 'ui/home_screen.dart';

typedef StorageRootPicker = Future<String?> Function();

Future<String?> _pickStorageRoot() {
  return getDirectoryPath(confirmButtonText: '选择此文件夹');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TagTagApp(locator: LibraryLocator()));
}

class TagTagApp extends StatefulWidget {
  const TagTagApp({
    super.key,
    required this.locator,
    this.storageRootPicker = _pickStorageRoot,
  });

  final LibraryLocator locator;
  final StorageRootPicker storageRootPicker;

  @override
  State<TagTagApp> createState() => _TagTagAppState();
}

class _TagTagAppState extends State<TagTagApp> {
  TagTagController? _controller;
  ManagedLibrary? _library;
  bool _loading = true;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLibrary());
  }

  @override
  void dispose() {
    final library = _library;
    if (library != null) {
      unawaited(library.close());
    }
    super.dispose();
  }

  Future<void> _restoreLibrary() async {
    try {
      final root = await widget.locator.loadRoot();
      if (root == null) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      final library = await ManagedLibrary.open(root);
      await _activate(library);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开已配置的存储根：$error';
        });
      }
    }
  }

  Future<void> _chooseAndInitialize() async {
    if (_initializing) {
      return;
    }
    setState(() {
      _initializing = true;
      _error = null;
    });
    ManagedLibrary? library;
    try {
      final selectedPath = await widget.storageRootPicker();
      if (!mounted) {
        return;
      }
      if (selectedPath == null) {
        setState(() => _initializing = false);
        return;
      }
      library = await ManagedLibrary.initialize(Directory(selectedPath));
      await widget.locator.saveRoot(library.root);
      await _activate(library);
    } catch (error) {
      if (library != null) {
        await library.close();
      }
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = '无法选择或初始化存储根：$error';
        });
      }
    }
  }

  Future<void> _activate(ManagedLibrary library) async {
    final controller = TagTagController(store: LocalStore(), library: library);
    await controller.load();
    if (!mounted) {
      await library.close();
      return;
    }
    setState(() {
      _library = library;
      _controller = controller;
      _loading = false;
      _initializing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff0f766e);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xfff8fafc),
          surfaceContainer: const Color(0xfff1f5f9),
          outlineVariant: const Color(0xffd7dee8),
        );
    return MaterialApp(
      title: 'TAGTAG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfff8fafc),
        useMaterial3: true,
        dividerTheme: const DividerThemeData(
          color: Color(0xffd7dee8),
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xffcbd5e1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xffcbd5e1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = _controller;
    if (controller != null) {
      return TagTagHome(
        controller: controller,
        fileActions: WindowsFileActions(),
      );
    }
    return _LibrarySetupScreen(
      busy: _initializing,
      error: _error,
      onChoose: _chooseAndInitialize,
    );
  }
}

class _LibrarySetupScreen extends StatelessWidget {
  const _LibrarySetupScreen({
    required this.busy,
    required this.error,
    required this.onChoose,
  });

  final bool busy;
  final String? error;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfff8fafc),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'TAGTAG',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.folder_special_outlined,
                  size: 46,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  '初始化存储根目录',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '选择一个可写文件夹。TAGTAG 导入的原始文件和文件夹将存放在这里。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: busy ? null : onChoose,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(busy ? '正在初始化' : '选择存储根目录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
