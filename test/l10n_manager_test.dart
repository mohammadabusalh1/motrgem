import 'dart:convert';
import 'dart:io';

import 'package:motrgem/src/utils/l10n_manager.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Minimal local stand-ins for the Flutter widgets used in test fixtures
/// (see the note in text_extractor_test.dart for why these are needed
/// instead of a real Flutter SDK dependency).
const _widgetStubs = '''
class BuildContext {}

class Text {
  Text(String data);
}
''';

Future<String> _createProject(String mainDartSource) async {
  final dir = await Directory.systemTemp.createTemp('motrgem_l10n_test_');
  final libDir = Directory(path.join(dir.path, 'lib'));
  await libDir.create(recursive: true);
  await File(path.join(dir.path, 'pubspec.yaml')).writeAsString('''
name: sample_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  await File(path.join(libDir.path, 'main.dart'))
      .writeAsString('$_widgetStubs\n$mainDartSource');
  return dir.path;
}

void main() {
  group('L10nManager.processProject', () {
    test('reports zero extracted texts for an already-localized project',
        () async {
      final projectPath = await _createProject('''
void build() {
  someUnrelatedCall();
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result = await manager.processProject();

      expect(result.extractedCount, 0);
      expect(result.replacedCount, 0);
      expect(result.hasErrors, isFalse);
    });

    test('dry run extracts texts but writes nothing to disk', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Text('Hello world');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result =
          await manager.processProject(dryRun: true, replaceInCode: true);

      expect(result.extractedCount, 1);
      expect(result.replacedCount, 0);

      final arbFile =
          File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'));
      expect(arbFile.existsSync(), isFalse);

      final content =
          await File(path.join(projectPath, 'lib', 'main.dart'))
              .readAsString();
      expect(content, contains("Text('Hello world')"));
    });

    test(
        'replaceInCode writes the ARB file, rewrites the call site, strips '
        'const, and adds the AppLocalizations import', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return const Text('Continue');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result = await manager.processProject(replaceInCode: true);

      expect(result.extractedCount, 1);
      expect(result.replacedCount, 1);

      final arbContent = json.decode(
        await File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'))
            .readAsString(),
      ) as Map<String, dynamic>;
      // "Continue" collides with a Dart keyword, so the id must be suffixed.
      expect(arbContent.keys, contains('continueLabel'));
      expect(arbContent['continueLabel'], 'Continue');

      final content =
          await File(path.join(projectPath, 'lib', 'main.dart'))
              .readAsString();
      expect(
        content,
        contains('AppLocalizations.of(context)!.continueLabel'),
      );
      // The const keyword must be stripped since its subtree is no longer
      // a compile-time constant.
      expect(content, isNot(contains('const Text')));
      expect(
        content,
        contains(
          "import 'package:sample_app/l10n/app_localizations.dart';",
        ),
      );
    });

    test(
        'reports possible hardcoded text in a custom widget even when zero '
        'SDK-widget texts are found (no false "fully localized" signal)',
        () async {
      final projectPath = await _createProject('''
class MyStatCard {
  MyStatCard({String? label});
}

void useWidgets() {
  MyStatCard(label: 'Bookings');
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result = await manager.processProject();

      // The primary auto-fix path still finds nothing to extract...
      expect(result.extractedCount, 0);

      // ...but the possible-hardcoded-text report catches it instead of
      // staying silent.
      final reportFile = File(
        path.join(projectPath, 'lib', 'l10n', 'possible_hardcoded_texts.txt'),
      );
      expect(reportFile.existsSync(), isTrue);
      final report = await reportFile.readAsString();
      expect(report, contains('Bookings'));
      expect(report, contains('MyStatCard'));
    });

    test(
        'reports SDK-widget text with no BuildContext in scope instead of '
        'emitting a broken AppLocalizations.of(context) call', () async {
      final projectPath = await _createProject('''
class MyChart {
  Widget build(BuildContext context) {
    return _getTitleWidget(1.0, 2.0);
  }

  Text _getTitleWidget(double value, double meta) {
    return Text('\${value}/\${meta}');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result = await manager.processProject(replaceInCode: true);

      expect(result.extractedCount, 0);
      expect(result.replacedCount, 0);

      // The source is untouched — no broken AppLocalizations.of(context)
      // call was emitted where `context` isn't actually in scope.
      final content =
          await File(path.join(projectPath, 'lib', 'main.dart'))
              .readAsString();
      expect(content, isNot(contains('AppLocalizations')));

      final report = await File(
        path.join(projectPath, 'lib', 'l10n', 'possible_hardcoded_texts.txt'),
      ).readAsString();
      expect(report, contains('noBuildContextInScope'));
      expect(report, contains('{value1}/{value2}'));
    });

    test(
        'motrgem.yaml extra_widgets makes a custom widget fully '
        'extracted/replaced instead of only reported', () async {
      final projectPath = await _createProject('''
class MyStatCard {
  MyStatCard({String? label});
}

class MyWidget {
  Widget build(BuildContext context) {
    return MyStatCard(label: 'Bookings');
  }
}
''');
      await File(path.join(projectPath, 'motrgem.yaml')).writeAsString('''
extra_widgets:
  MyStatCard:
    - label
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      final result = await manager.processProject(replaceInCode: true);

      expect(result.extractedCount, 1);
      expect(result.replacedCount, 1);

      final content =
          await File(path.join(projectPath, 'lib', 'main.dart'))
              .readAsString();
      expect(content, contains('AppLocalizations.of(context)!.bookings'));

      // Configured sinks are treated as handled, so they must not also
      // appear in the possible-hardcoded-text report.
      final reportFile = File(
        path.join(projectPath, 'lib', 'l10n', 'possible_hardcoded_texts.txt'),
      );
      if (reportFile.existsSync()) {
        expect(await reportFile.readAsString(), isNot(contains('Bookings')));
      }
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('L10nManager.addLocale', () {
    test('creates a locale ARB file with the same keys as the template',
        () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Text('Hello world');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final manager = L10nManager(projectPath);
      await manager.processProject(replaceInCode: true);
      await manager.addLocale('fr');

      final frFile = File(path.join(projectPath, 'lib', 'l10n', 'app_fr.arb'));
      expect(frFile.existsSync(), isTrue);

      final enContent = json.decode(
        await File(path.join(projectPath, 'lib', 'l10n', 'app_en.arb'))
            .readAsString(),
      ) as Map<String, dynamic>;
      final frContent =
          json.decode(await frFile.readAsString()) as Map<String, dynamic>;

      expect(frContent['@@locale'], 'fr');
      final enKeys = enContent.keys.where((k) => !k.startsWith('@'));
      for (final key in enKeys) {
        expect(frContent.containsKey(key), isTrue);
      }
    });
    // The GoogleTranslator call itself (success path) needs network access
    // and isn't exercised here; offline it still completes via the
    // per-key catch-and-fallback-to-original-text branch in
    // ArbManager.createLocaleFile.
  }, timeout: const Timeout(Duration(seconds: 90)));
}
