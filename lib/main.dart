import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/local_store.dart';
import 'platform/windows_close_behavior.dart';
import 'platform/windows_file_actions.dart';
import 'platform/windows_floating_drop_target.dart';
import 'services/global_backup_restorer.dart';
import 'services/windows_integration_sync.dart';
import 'state/tagtag_controller.dart';
import 'storage/library_locator.dart';
import 'storage/managed_library.dart';
import 'ui/glass.dart';
import 'ui/home_screen.dart';
import 'ui/prototype_dialogs.dart';
import 'ui/tagtag_theme.dart';

typedef StorageRootPicker = Future<String?> Function();

Future<String?> _pickStorageRoot() {
  return getDirectoryPath(confirmButtonText: '选择此文件夹');
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(320, 360),
      center: true,
      title: 'TAGTAG',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(
    TagTagApp(
      locator: LibraryLocator(),
      initialExternalQuickTagPaths: _quickTagPathsFromArguments(arguments),
    ),
  );
}

List<String> _quickTagPathsFromArguments(List<String> arguments) {
  final flagIndex = arguments.indexOf('--quick-tag');
  if (flagIndex == -1) {
    return const [];
  }
  return arguments
      .skip(flagIndex + 1)
      .where((path) => path.isNotEmpty)
      .toList();
}

class TagTagApp extends StatefulWidget {
  const TagTagApp({
    super.key,
    required this.locator,
    this.storageRootPicker = _pickStorageRoot,
    this.store,
    this.initialExternalQuickTagPaths = const [],
  });

  final LibraryLocator locator;
  final StorageRootPicker storageRootPicker;
  final LocalStore? store;
  final List<String> initialExternalQuickTagPaths;

  @override
  State<TagTagApp> createState() => _TagTagAppState();
}

class _TagTagAppState extends State<TagTagApp> {
  late final WindowsFileActions _fileActions;
  TagTagController? _controller;
  ManagedLibrary? _library;

  /// Library initialized by wizard step 1, waiting for the step-2 settings
  /// before it becomes the active library.
  ManagedLibrary? _pendingLibrary;
  bool _loading = true;
  bool _initializing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fileActions = WindowsFileActions();
    unawaited(_restoreLibrary());
  }

  @override
  void dispose() {
    final library = _library;
    if (library != null) {
      unawaited(library.close());
    }
    final pendingLibrary = _pendingLibrary;
    if (pendingLibrary != null && pendingLibrary != library) {
      unawaited(pendingLibrary.close());
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
      // Step 1 done: hold the library while the wizard collects key settings.
      setState(() {
        _pendingLibrary = library;
        _initializing = false;
      });
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

  Future<void> _backToStorageRootStep() async {
    final pendingLibrary = _pendingLibrary;
    if (pendingLibrary != null) {
      setState(() => _pendingLibrary = null);
      await pendingLibrary.close();
    }
  }

  Future<void> _completeWizard(SetupWizardChoices choices) async {
    final library = _pendingLibrary;
    if (_initializing || library == null) {
      return;
    }
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final controller = TagTagController(
        store: widget.store ?? LocalStore(),
        library: library,
        recycleBin: _fileActions,
      );
      await controller.load();
      await controller.updatePreferences(
        appearanceTheme: choices.appearanceTheme,
        moveImportsByDefault: choices.moveImportsByDefault,
        floatingDropTargetEnabled: choices.floatingDropTargetEnabled,
        autoStartEnabled: choices.autoStartEnabled,
      );
      // Apply the wizard's Windows integration choices immediately; the home
      // screen re-applies the same preferences on startup.
      final closeBehavior = WindowsCloseBehavior();
      final floatingDropTarget = WindowsFloatingDropTarget();
      try {
        await applyWindowsIntegrationPreferences(
          preferences: controller.preferences,
          closeBehavior: closeBehavior,
          floatingDropTarget: floatingDropTarget,
        );
      } finally {
        await floatingDropTarget.dispose();
      }
      if (!mounted) {
        await library.close();
        return;
      }
      setState(() {
        _library = library;
        _controller = controller;
        _pendingLibrary = null;
        _loading = false;
        _initializing = false;
        _error = null;
      });
    } catch (error) {
      await library.close();
      if (mounted) {
        setState(() {
          _pendingLibrary = null;
          _initializing = false;
          _error = '无法完成初始设置：$error';
        });
      }
    }
  }

  Future<void> _activate(ManagedLibrary library) async {
    final previousLibrary = _library;
    final controller = TagTagController(
      store: widget.store ?? LocalStore(),
      library: library,
      recycleBin: _fileActions,
    );
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
    if (previousLibrary != null && previousLibrary != library) {
      await previousLibrary.close();
    }
  }

  Future<void> _restoreGlobalBackup(
    Directory backupDirectory,
    Directory targetRoot,
  ) async {
    final currentController = _controller;
    final currentLibrary = _library;
    if (currentController == null || currentLibrary == null) {
      throw StateError('TAGTAG 存储根尚未初始化');
    }
    final session =
        await GlobalBackupRestorer(
          locator: widget.locator,
          store: currentController.store,
        ).restore(
          backupDirectory: backupDirectory,
          targetRoot: targetRoot,
          currentRoot: currentLibrary.root,
          recycleBin: _fileActions,
        );
    if (!mounted) {
      await session.library.close();
      return;
    }
    final previousLibrary = _library;
    setState(() {
      _library = session.library;
      _controller = session.controller;
      _error = null;
    });
    if (previousLibrary != null && previousLibrary != session.library) {
      await previousLibrary.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TAGTAG',
      debugShowCheckedModeBanner: false,
      theme: buildTagTagTheme(),
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
        fileActions: _fileActions,
        onRestoreGlobalBackup: _restoreGlobalBackup,
        initialExternalQuickTagPaths: widget.initialExternalQuickTagPaths,
      );
    }
    return _LibrarySetupWizard(
      busy: _initializing,
      error: _error,
      step: _pendingLibrary == null ? 1 : 2,
      onChoose: _chooseAndInitialize,
      onBack: _backToStorageRootStep,
      onComplete: _completeWizard,
    );
  }
}

/// Key settings collected by wizard step 2.
class SetupWizardChoices {
  const SetupWizardChoices({
    required this.appearanceTheme,
    required this.moveImportsByDefault,
    required this.floatingDropTargetEnabled,
    required this.autoStartEnabled,
  });

  final String appearanceTheme;
  final bool moveImportsByDefault;
  final bool floatingDropTargetEnabled;
  final bool autoStartEnabled;
}

/// First-run setup wizard. Step 1 picks the storage root (the library is
/// initialized before advancing); step 2 collects key settings, which 完成
/// persists and applies.
class _LibrarySetupWizard extends StatefulWidget {
  const _LibrarySetupWizard({
    required this.busy,
    required this.error,
    required this.step,
    required this.onChoose,
    required this.onBack,
    required this.onComplete,
  });

  final bool busy;
  final String? error;
  final int step;
  final VoidCallback onChoose;
  final VoidCallback onBack;
  final Future<void> Function(SetupWizardChoices choices) onComplete;

  @override
  State<_LibrarySetupWizard> createState() => _LibrarySetupWizardState();
}

class _LibrarySetupWizardState extends State<_LibrarySetupWizard> {
  String _appearanceTheme = 'light';
  bool _moveImportsByDefault = false;
  bool _floatingDropTargetEnabled = false;
  bool _autoStartEnabled = false;

  @override
  Widget build(BuildContext context) {
    final brightness = _appearanceTheme == 'dark'
        ? Brightness.dark
        : Brightness.light;
    return Theme(
      data: buildTagTagTheme(brightness: brightness),
      child: Builder(
        builder: (context) => Scaffold(
          body: GlassCanvas(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: GlassPanel(
                    radius: GlassTokens.dialogRadius,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: widget.step == 1
                          ? _buildStorageRootStep(context)
                          : _buildSettingsStep(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorageRootStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '第 1 步，共 2 步',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '选择一个可写文件夹。TAGTAG 导入的原始文件和文件夹将存放在这里。',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 18),
          Text(
            widget.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 28),
        GlassPrimaryButton.icon(
          onPressed: widget.busy ? null : widget.onChoose,
          icon: widget.busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open_outlined),
          label: Text(widget.busy ? '正在初始化' : '选择存储根目录'),
        ),
      ],
    );
  }

  Widget _buildSettingsStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.tune_outlined,
          size: 46,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          '关键设置',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '第 2 步，共 2 步 · 稍后均可在设置中修改',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _WizardSettingRow(
          title: '外观',
          trailing: PrototypeSegmented<String>(
            values: const ['light', 'dark'],
            selected: _appearanceTheme,
            label: (value) => value == 'light' ? '浅色' : '深色',
            icon: (value) => value == 'light'
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            onSelected: (value) => setState(() => _appearanceTheme = value),
          ),
        ),
        _WizardSettingRow(
          title: '默认导入方式',
          trailing: PrototypeSegmented<bool>(
            values: const [false, true],
            selected: _moveImportsByDefault,
            label: (value) => value ? '移动' : '复制',
            onSelected: (value) =>
                setState(() => _moveImportsByDefault = value),
          ),
        ),
        const _WizardSettingRow(
          title: 'Quick Tag 快捷键',
          trailing: Text(
            'Ctrl + Shift + T',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        _WizardSettingRow(
          title: '悬浮接收目标',
          trailing: PillSwitch(
            value: _floatingDropTargetEnabled,
            onChanged: (value) =>
                setState(() => _floatingDropTargetEnabled = value),
          ),
        ),
        _WizardSettingRow(
          title: '开机自动启动',
          trailing: PillSwitch(
            value: _autoStartEnabled,
            onChanged: (value) => setState(() => _autoStartEnabled = value),
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            TextButton(
              onPressed: widget.busy ? null : widget.onBack,
              child: const Text('上一步'),
            ),
            const Spacer(),
            GlassPrimaryButton.icon(
              onPressed: widget.busy
                  ? null
                  : () => unawaited(
                      widget.onComplete(
                        SetupWizardChoices(
                          appearanceTheme: _appearanceTheme,
                          moveImportsByDefault: _moveImportsByDefault,
                          floatingDropTargetEnabled:
                              _floatingDropTargetEnabled,
                          autoStartEnabled: _autoStartEnabled,
                        ),
                      ),
                    ),
              icon: widget.busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 17),
              label: Text(widget.busy ? '正在完成' : '完成'),
            ),
          ],
        ),
      ],
    );
  }
}

class _WizardSettingRow extends StatelessWidget {
  const _WizardSettingRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}
