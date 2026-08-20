import 'dart:convert';
import 'dart:io';

import 'package:motrgem/src/utils/Text_extractor.dart';
import 'package:motrgem/src/utils/arb_manager.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

ExtractedText _text(
  String id,
  String text, {
  List<String> placeholders = const [],
}) {
  return ExtractedText(
    text: text,
    filePath: '/tmp/main.dart',
    offset: 0,
    length: 0,
    line: 1,
    column: 1,
    widgetType: 'Text',
    generatedId: id,
    placeholders: placeholders,
  );
}

void main() {
  late String projectPath;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('motrgem_arb_test_');
    projectPath = dir.path;
    await Directory(path.join(projectPath, 'lib', 'l10n'))
        .create(recursive: true);
  });

  tearDown(() async {
    await Directory(projectPath).delete(recursive: true);
  });

  Future<Map<String, dynamic>> readArb([String locale = 'en']) async {
    final arbFile =
        File(path.join(projectPath, 'lib', 'l10n', 'app_$locale.arb'));
    return json.decode(await arbFile.readAsString()) as Map<String, dynamic>;
  }

  group('ArbManager.addTextsToArb', () {
    test('writes a placeholders metadata block for multi-arg entries',
        () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([
        _text('dateRange', '{value1} – {value2} ({value3}h)',
            placeholders: const ['start', 'end', 'hours']),
      ]);

      final arbContent = await readArb();
      expect(arbContent['dateRange'], '{value1} – {value2} ({value3}h)');
      final meta = arbContent['@dateRange'] as Map<String, dynamic>;
      final placeholders = meta['placeholders'] as Map<String, dynamic>;
      expect(placeholders.keys.toList(), ['value1', 'value2', 'value3']);
    });

    test('omits placeholders metadata for plain text entries', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([_text('helloWorld', 'Hello world')]);

      final arbContent = await readArb();
      final meta = arbContent['@helloWorld'] as Map<String, dynamic>;
      expect(meta.containsKey('placeholders'), isFalse);
    });

    test('seeds a fresh file with @@locale when none exists', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([_text('hello', 'Hello')]);

      final arbContent = await readArb();
      expect(arbContent['@@locale'], 'en');
    });

    test('merges into an existing file and skips already-present ids',
        () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([_text('hello', 'Hello')]);
      await arbManager.addTextsToArb([
        _text('hello', 'A different value for the same id'),
        _text('world', 'World'),
      ]);

      final arbContent = await readArb();
      // First write wins; the id is not overwritten on a later pass.
      expect(arbContent['hello'], 'Hello');
      expect(arbContent['world'], 'World');
    });
  });

  group('ArbManager.getExistingIds', () {
    test('returns an empty set when the ARB file does not exist', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      expect(await arbManager.getExistingIds(), isEmpty);
    });

    test('returns only the non-metadata keys', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([_text('hello', 'Hello')]);

      final ids = await arbManager.getExistingIds();
      expect(ids, {'hello'});
    });
  });

  group('ArbManager.getStatistics', () {
    test('returns zeros when the ARB file does not exist', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      expect(
        await arbManager.getStatistics(),
        {'total': 0, 'withMetadata': 0},
      );
    });

    test('counts entries and metadata blocks', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([
        _text('hello', 'Hello'),
        _text('world', 'World'),
      ]);

      expect(
        await arbManager.getStatistics(),
        {'total': 2, 'withMetadata': 2},
      );
    });
  });

  group('ArbManager.createLocaleFile', () {
    test('skips when the locale file already exists', () async {
      final localeFile = File(path.join(projectPath, 'lib', 'l10n', 'app_fr.arb'));
      await localeFile.writeAsString('{"@@locale": "fr"}');

      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.createLocaleFile('fr');

      // Untouched: still exactly the seed content, not regenerated.
      expect(await localeFile.readAsString(), '{"@@locale": "fr"}');
    });

    test('does nothing when the template ARB file is missing', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.createLocaleFile('fr');

      final localeFile = File(path.join(projectPath, 'lib', 'l10n', 'app_fr.arb'));
      expect(localeFile.existsSync(), isFalse);
    });

    test('copies template keys verbatim when translate is false', () async {
      final arbManager = ArbManager(projectPath: projectPath);
      await arbManager.addTextsToArb([
        _text('hello', 'Hello'),
        _text('world', 'World'),
      ]);

      await arbManager.createLocaleFile('fr', translate: false);

      final frContent = await readArb('fr');
      expect(frContent['@@locale'], 'fr');
      expect(frContent['hello'], 'Hello');
      expect(frContent['world'], 'World');
    });
  });
}
