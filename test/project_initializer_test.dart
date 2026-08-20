import 'dart:convert';
import 'dart:io';

import 'package:motrgem/src/utils/project_initializer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _createProject(String pubspec) async {
  final dir =
      await Directory.systemTemp.createTemp('motrgem_init_test_');
  await File(path.join(dir.path, 'pubspec.yaml')).writeAsString(pubspec);
  return dir.path;
}

void main() {
  group('ProjectInitializer.initialize', () {
    test('sets up a bare project from scratch', () async {
      final projectPath = await _createProject('''
name: sample_app
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final result = await ProjectInitializer(projectPath).initialize();

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.results, hasLength(4));

      final pubspecContent =
          await File(path.join(projectPath, 'pubspec.yaml')).readAsString();
      final yaml = loadYaml(pubspecContent);
      expect((yaml['dependencies'] as YamlMap).containsKey('flutter_localizations'), isTrue);
      expect((yaml['dependencies'] as YamlMap).containsKey('intl'), isTrue);
      final devDeps = yaml['dev_dependencies'] as YamlMap;
      expect(devDeps.containsKey('analyzer'), isTrue);
      expect(devDeps.containsKey('path'), isTrue);
      expect(devDeps.containsKey('args'), isTrue);
      expect(devDeps.containsKey('yaml'), isTrue);
      expect(pubspecContent, contains('generate: true'));

      expect(
        File(path.join(projectPath, 'l10n.yaml')).existsSync(),
        isTrue,
      );
      expect(
        Directory(path.join(projectPath, 'lib', 'l10n')).existsSync(),
        isTrue,
      );
      final arbFile =
          File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'));
      expect(arbFile.existsSync(), isTrue);
      final arbContent =
          json.decode(await arbFile.readAsString()) as Map<String, dynamic>;
      expect(arbContent['@@locale'], 'en');
    });

    test('reports an error and fails when pubspec.yaml is missing',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('motrgem_init_test_');
      addTearDown(() => Directory(dir.path).delete(recursive: true));

      final result = await ProjectInitializer(dir.path).initialize();

      expect(result.success, isFalse);
      expect(result.errors, isNotEmpty);
      expect(result.errors.first, contains('pubspec.yaml'));
      // The other three steps (l10n.yaml, lib/l10n, ARB file) don't depend
      // on pubspec.yaml and still succeed independently.
      expect(result.results, hasLength(3));
    });

    test('skips steps whose artifacts already exist', () async {
      final projectPath = await _createProject('''
name: sample_app
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
dev_dependencies:
  analyzer: any
  path: any
  args: any
  yaml: any
flutter:
  generate: true
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      await File(path.join(projectPath, 'l10n.yaml')).writeAsString('existing');
      await Directory(path.join(projectPath, 'lib', 'l10n'))
          .create(recursive: true);
      await File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'))
          .writeAsString('existing');

      final beforePubspec =
          await File(path.join(projectPath, 'pubspec.yaml')).readAsString();

      final result = await ProjectInitializer(projectPath).initialize();

      expect(result.success, isTrue);
      // pubspec.yaml already had everything, so it should be left untouched.
      final afterPubspec =
          await File(path.join(projectPath, 'pubspec.yaml')).readAsString();
      expect(afterPubspec, beforePubspec);
      // The pre-existing placeholder files must not have been overwritten.
      expect(
        await File(path.join(projectPath, 'l10n.yaml')).readAsString(),
        'existing',
      );
      expect(
        await File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'))
            .readAsString(),
        'existing',
      );
    });

    test('adds a dependencies/flutter section and generate flag when none '
        'of them exist yet', () async {
      final projectPath = await _createProject('''
name: sample_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final result = await ProjectInitializer(projectPath).initialize();

      expect(result.success, isTrue);
      final pubspecContent =
          await File(path.join(projectPath, 'pubspec.yaml')).readAsString();
      final yaml = loadYaml(pubspecContent);
      expect((yaml['dependencies'] as YamlMap).containsKey('flutter_localizations'), isTrue);
      expect((yaml['dev_dependencies'] as YamlMap).containsKey('analyzer'), isTrue);
      expect(pubspecContent, contains('flutter:\n  generate: true'));
    });
  });
}
