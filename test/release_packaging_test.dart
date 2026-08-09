import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'release workflow produces and validates both Windows packages',
    () async {
      final source = await File('.github/workflows/release.yml').readAsString();
      final workflow = loadYaml(source) as YamlMap;
      final jobs = workflow['jobs'] as YamlMap;
      final job = jobs['build-windows'] as YamlMap;
      final steps = job['steps'] as YamlList;
      final byName = <String, YamlMap>{
        for (final step in steps.cast<YamlMap>())
          if (step['name'] case final String name) name: step,
      };

      expect(byName, contains('Package Windows portable release'));
      expect(byName, contains('Build Windows installer'));
      expect(byName, contains('Verify portable archive'));
      expect(
        byName,
        contains('Verify installer install, upgrade, and uninstall'),
      );

      final installerBuild = byName['Build Windows installer']!;
      expect(installerBuild['id'], 'installer');
      expect(installerBuild['run'], contains('ISCC.exe'));
      expect(installerBuild['run'], contains('/DSourceDir='));
      expect(installerBuild['run'], contains('/DOutputDir='));

      final lifecycle =
          byName['Verify installer install, upgrade, and uninstall']!['run']
              as String;
      expect(lifecycle, contains('@("install", "upgrade")'));
      expect(lifecycle, contains('unins000.exe'));

      for (final name in [
        'Upload workflow artifact',
        'Publish GitHub Release',
      ]) {
        final step = byName[name]!;
        final configuration = step['with'] as YamlMap;
        final assets = name == 'Upload workflow artifact'
            ? configuration['path'] as String
            : configuration['files'] as String;
        expect(assets, contains('steps.package.outputs.portable'));
        expect(assets, contains('steps.installer.outputs.setup'));
      }

      if (Platform.isWindows) {
        for (final step in steps.cast<YamlMap>()) {
          final script = step['run'];
          if (step['shell'] == 'pwsh' && script is String) {
            await _expectValidPowerShell(step['name'] as String, script);
          }
        }
      }
    },
  );

  test('installer preserves per-user data and shares the app mutex', () async {
    final installer = await File('installer/tagtag.iss').readAsString();
    final chineseMessages = await File(
      'installer/languages/ChineseSimplified.isl',
    ).readAsString();
    final runner = await File('windows/runner/main.cpp').readAsString();
    final mutexMatch = RegExp(
      r'kSingleInstanceMutexName\[\]\s*=\s*L"([^"]+)"',
    ).firstMatch(runner);
    expect(mutexMatch, isNotNull);
    final runnerMutex = mutexMatch!
        .group(1)!
        .replaceAll(r'\\', String.fromCharCode(92));

    expect(
      _setting(installer, 'AppId'),
      '{{82F13D35-24D8-4B89-B8A8-E44EF4C40A8E}',
    );
    expect(_setting(installer, 'AppMutex'), runnerMutex);
    expect(_setting(installer, 'PrivilegesRequired'), 'lowest');
    expect(
      _setting(installer, 'DefaultDirName'),
      r'{localappdata}\Programs\TAGTAG',
    );
    expect(installer, contains(r'Source: "{#SourceDir}\*"'));
    expect(
      installer,
      contains(r'MessagesFile: "languages\ChineseSimplified.isl"'),
    );
    expect(chineseMessages, startsWith('; *** Inno Setup version 6.5.0+'));
    expect(installer, isNot(contains('[UninstallDelete]')));
  });
}

String _setting(String source, String name) {
  return LineSplitter.split(
    source,
  ).firstWhere((line) => line.startsWith('$name=')).substring(name.length + 1);
}

Future<void> _expectValidPowerShell(String name, String script) async {
  final substituted = script.replaceAll(
    RegExp(r'\$\{\{.*?\}\}', dotAll: true),
    'github_value',
  );
  final encoded = base64Encode(utf8.encode(substituted));
  final parser =
      r'$tokens = $null; $errors = $null; '
      r'$source = [Text.Encoding]::UTF8.GetString('
      '[Convert]::FromBase64String("$encoded")); '
      r'[System.Management.Automation.Language.Parser]::ParseInput('
      r'$source, [ref]$tokens, [ref]$errors) | Out-Null; '
      r'if ($errors.Count -gt 0) { '
      r'$errors | ForEach-Object { Write-Error $_.Message }; exit 1 }';
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    parser,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Invalid PowerShell in workflow step "$name": ${result.stderr}',
  );
}
