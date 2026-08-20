import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:motrgem/src/utils/Text_extractor.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Minimal local stand-ins for the Flutter widgets used in test fixtures.
/// The analyzer only parses a call like `Text('...')` as an
/// InstanceCreationExpression (rather than an unresolved MethodInvocation)
/// when `Text` resolves to an actual class, so these fixtures declare their
/// own tiny widget stubs instead of depending on the Flutter SDK.
const _widgetStubs = '''
class BuildContext {}

class Text {
  Text(String data);
}

class AppBar {
  AppBar({String? title});
}

class Tooltip {
  Tooltip({String? message});
}

class Chip {
  Chip({String? label});
}

class SnackBar {
  SnackBar({String? content});
}

class InputDecoration {
  InputDecoration({
    String? labelText,
    String? hintText,
    String? helperText,
    String? errorText,
    String? counterText,
    String? prefixText,
    String? suffixText,
  });
}

class Dropdown {
  Dropdown({List<DropdownMenuItem>? items});
}

class DropdownMenuItem {
  DropdownMenuItem({Text? child});
}
''';

/// Creates a throwaway project directory with the given `lib/main.dart`
/// source (widget stubs prepended) and returns its path.
Future<String> _createProject(String source) async {
  final dir = await Directory.systemTemp.createTemp('motrgem_test_');
  final libDir = Directory(path.join(dir.path, 'lib'));
  await libDir.create(recursive: true);
  await File(path.join(libDir.path, 'main.dart'))
      .writeAsString('$_widgetStubs\n$source');
  return dir.path;
}

void main() {
  group('ExtractedText', () {
    test('toString and toJson expose all fields', () {
      final text = ExtractedText(
        text: 'Hello',
        filePath: '/tmp/main.dart',
        offset: 10,
        length: 7,
        line: 2,
        column: 5,
        widgetType: 'Text',
        generatedId: 'hello',
        placeholders: const ['a'],
      );

      expect(text.toString(), '/tmp/main.dart:2:5 - [Text] "Hello" -> hello');
      expect(text.toJson(), {
        'text': 'Hello',
        'filePath': '/tmp/main.dart',
        'offset': 10,
        'length': 7,
        'line': 2,
        'column': 5,
        'widgetType': 'Text',
        'generatedId': 'hello',
        'placeholders': ['a'],
        'contextExpression': 'context',
      });
    });
  });

  group('generateTextId', () {
    test('suffixes ids that collide with Dart reserved words', () async {
      final extractor = TextExtractor();
      final id = await extractor.generateTextId('Continue');
      expect(id, isNot('continue'));
      expect(id, 'continueLabel');
    });

    test('leaves ordinary ids untouched', () async {
      final extractor = TextExtractor();
      final id = await extractor.generateTextId('Hello world');
      expect(id, 'helloWorld');
    });

    test('caps camelCase composition at 5 words', () async {
      final extractor = TextExtractor();
      final id = await extractor
          .generateTextId('Hello there my friend today please');
      expect(id, 'helloThereMyFriendToday');
    });

    test('prefixes ids that would start with a digit', () async {
      final extractor = TextExtractor();
      final id = await extractor.generateTextId('123 items');
      expect(id, 'text123Items');
    });
  });

  group('widget and builder-method extraction', () {
    test(
        'extracts from named text parameters on recognized widgets, '
        'positional args on builder methods, and skips non-widgets/'
        'non-text-params/non-builder methods', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Column(children: [
      AppBar(title: 'App Title'),
      Tooltip(message: 'Tip text'),
      Chip(label: 'Chip label'),
      // 'content' is not a recognized text parameter name.
      SnackBar(content: 'Not extracted'),
      InputDecoration(
        labelText: 'Label text',
        hintText: 'Hint text',
        helperText: 'Helper text',
        errorText: 'Error text',
        counterText: 'Counter text',
        prefixText: 'Prefix text',
        suffixText: 'Suffix text',
      ),
      // Dropdown/DropdownMenuItem are not in the recognized widget set, so
      // their arguments are never scanned regardless of param name.
      Dropdown(items: [DropdownMenuItem(child: 'Not extracted either')]),
      _buildHeader('Header text'),
      _createLabel('Created text'),
      _makeCaption('Made text'),
      _getFooterWidget('Footer text'),
      _helperMethod('Not a builder method'),
    ]);
  }

  Text _buildHeader(String s) => Text(s);
  Text _createLabel(String s) => Text(s);
  Text _makeCaption(String s) => Text(s);
  Text _getFooterWidget(String s) => Text(s);
  Text _helperMethod(String s) => Text(s);
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);
      final values = texts.map((t) => t.text).toSet();

      expect(values, containsAll(<String>[
        'App Title',
        'Tip text',
        'Chip label',
        'Label text',
        'Hint text',
        'Helper text',
        'Error text',
        'Counter text',
        'Prefix text',
        'Suffix text',
        'Header text',
        'Created text',
        'Made text',
        'Footer text',
      ]));
      expect(values, isNot(contains('Not extracted')));
      expect(values, isNot(contains('Not extracted either')));
      expect(values, isNot(contains('Not a builder method')));
    });

    test('extracts both branches of a conditional expression and unwraps '
        'parenthesized expressions', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context, bool isError) {
    return Column(children: [
      Text(isError ? 'Error state' : 'OK state'),
      Text(('Wrapped text')),
    ]);
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);
      final values = texts.map((t) => t.text).toSet();

      expect(
        values,
        containsAll(<String>['Error state', 'OK state', 'Wrapped text']),
      );
    });

    test('skips technical-looking strings (URLs, constants, digits, '
        'format strings, and too-short strings)', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Column(children: [
      Text('https://example.com'),
      Text('MY_CONSTANT'),
      Text('12345'),
      Text('Value: %s'),
      Text('a'),
      Text('Real label text'),
    ]);
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);
      final values = texts.map((t) => t.text).toSet();

      expect(values, {'Real label text'});
    });
  });

  group('interpolation placeholder extraction', () {
    test('gives each distinct interpolation a unique placeholder', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Text('\${start} – \${end} (\${hours}h)');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);

      expect(texts, hasLength(1));
      final text = texts.single;
      expect(text.placeholders, ['start', 'end', 'hours']);
      expect(text.text, '{value1} – {value2} ({value3}h)');
    });

    test(
        'collects args across adjacent string-literal parts without dropping any',
        () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    return Text(
      '\${start} – '
      '\${end} (\${hours}h)',
    );
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);

      expect(texts, hasLength(1));
      final text = texts.single;
      expect(text.placeholders, ['start', 'end', 'hours']);
      expect(text.text, '{value1} – {value2} ({value3}h)');

      // replaceTextByName must now emit the full arg list at the call site.
      final withId = ExtractedText(
        text: text.text,
        filePath: text.filePath,
        offset: text.offset,
        length: text.length,
        line: text.line,
        column: text.column,
        widgetType: text.widgetType,
        generatedId: 'dateRange',
        placeholders: text.placeholders,
      );
      final success = await extractor.replaceTextByName(text.filePath, withId);
      expect(success, isTrue);

      final content = await File(text.filePath).readAsString();
      expect(
        content,
        contains(
          'AppLocalizations.of(context)!.dateRange(start, end, hours)',
        ),
      );
    });
  });

  group('replaceTextByName failure paths', () {
    test('returns false when the file does not exist', () async {
      final extractor = TextExtractor();
      final missing = ExtractedText(
        text: 'Hello',
        filePath: path.join(Directory.systemTemp.path, 'does_not_exist.dart'),
        offset: 0,
        length: 5,
        line: 1,
        column: 1,
        widgetType: 'Text',
        generatedId: 'hello',
      );

      final success =
          await extractor.replaceTextByName(missing.filePath, missing);
      expect(success, isFalse);
    });

    test('returns false and leaves the file untouched when the offset is '
        'out of range', () async {
      final dir = await Directory.systemTemp.createTemp('motrgem_test_');
      addTearDown(() => Directory(dir.path).delete(recursive: true));
      final filePath = path.join(dir.path, 'main.dart');
      const original = "Text('Hi')";
      await File(filePath).writeAsString(original);

      final extractor = TextExtractor();
      final outOfRange = ExtractedText(
        text: 'Hi',
        filePath: filePath,
        offset: 1000,
        length: 5,
        line: 1,
        column: 1,
        widgetType: 'Text',
        generatedId: 'hi',
      );

      final success =
          await extractor.replaceTextByName(filePath, outOfRange);
      expect(success, isFalse);
      expect(await File(filePath).readAsString(), original);
    });
  });

  group('removeConstKeywords', () {
    test('returns 0 when the file does not exist', () async {
      final extractor = TextExtractor();
      final removed = await extractor.removeConstKeywords(
        path.join(Directory.systemTemp.path, 'does_not_exist.dart'),
      );
      expect(removed, 0);
    });

    test('returns 0 when there is nothing to remove', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build() {
    return Text('Plain, no const anywhere');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final filePath = path.join(projectPath, 'lib', 'main.dart');
      final removed = await extractor.removeConstKeywords(filePath);
      expect(removed, 0);
    });

    test('strips const from a list literal whose child was localized',
        () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build() {
    return Dropdown(
      items: const [
        DropdownMenuItem(child: AppLocalizations.of(context)!.literal),
      ],
    );
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final filePath = path.join(projectPath, 'lib', 'main.dart');
      final removed = await extractor.removeConstKeywords(filePath);

      expect(removed, 1);
      final content = await File(filePath).readAsString();
      expect(content, isNot(contains('const [')));
    });

    test('strips const from a set literal whose child was localized',
        () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build() {
    return Dropdown(
      items: const {
        DropdownMenuItem(child: AppLocalizations.of(context)!.literal),
      },
    );
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final filePath = path.join(projectPath, 'lib', 'main.dart');
      final removed = await extractor.removeConstKeywords(filePath);

      expect(removed, 1);
      final content = await File(filePath).readAsString();
      expect(content, isNot(contains('const {')));
    });

    test('strips const from a widget nested inside a named argument',
        () async {
      final projectPath = await _createProject('''
class Scaffold {
  Scaffold({AppBar? appBar});
}

class MyWidget {
  Widget build() {
    return Scaffold(
      appBar: const AppBar(title: AppLocalizations.of(context)!.title),
    );
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final filePath = path.join(projectPath, 'lib', 'main.dart');
      final removed = await extractor.removeConstKeywords(filePath);

      expect(removed, 1);
      final content = await File(filePath).readAsString();
      expect(content, isNot(contains('const AppBar')));
    });
  });

  group('containsAppLocalizations / isAppLocalizationsCall', () {
    Expression parseExpressionSource(String source) {
      final result = parseString(content: source);
      final function = result.unit.declarations.first as FunctionDeclaration;
      final body = function.functionExpression.body as ExpressionFunctionBody;
      return body.expression;
    }

    test('recognizes a direct AppLocalizations.of(context)!.key call', () {
      final extractor = TextExtractor();
      final expr = parseExpressionSource(
        'get x => AppLocalizations.of(context)!.title;',
      );
      expect(extractor.containsAppLocalizations(expr), isTrue);
    });

    test('recognizes AppLocalizations passed as a constructor argument', () {
      final extractor = TextExtractor();
      final expr = parseExpressionSource(
        'get x => Text(AppLocalizations.of(context)!.title);',
      );
      expect(extractor.containsAppLocalizations(expr), isTrue);
    });

    test('recognizes AppLocalizations inside a list literal element', () {
      final extractor = TextExtractor();
      final expr = parseExpressionSource(
        'get x => [AppLocalizations.of(context)!.title];',
      );
      expect(extractor.containsAppLocalizations(expr), isTrue);
    });

    test('returns false for unrelated expressions', () {
      final extractor = TextExtractor();
      final expr = parseExpressionSource("get x => Text('plain');");
      expect(extractor.containsAppLocalizations(expr), isFalse);
    });

    test('returns false for a null expression', () {
      final extractor = TextExtractor();
      expect(extractor.containsAppLocalizations(null), isFalse);
    });
  });

  group('findPossibleHardcodedTexts', () {
    test(
        'flags string args on locally-declared class constructors '
        '(named, positional, and via throw) but not on SDK widgets',
        () async {
      final projectPath = await _createProject('''
class MyStatCard {
  MyStatCard({String? label, String? subtitle});
}

class MyBadge {
  MyBadge(String text);
}

class AuthError {
  AuthError(String code, {String? message});
}

void useWidgets() {
  MyStatCard(label: 'Bookings', subtitle: 'Total bookings');
  MyBadge('Positional label text');
  throw AuthError('session', message: 'Your session has expired.');
  Text('Not flagged, this is an SDK widget');
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final findings = await extractor.findPossibleHardcodedTexts(projectPath);
      final texts = findings.map((f) => f.text).toSet();

      expect(texts, containsAll(<String>[
        'Bookings',
        'Total bookings',
        'Positional label text',
        'Your session has expired.',
      ]));
      expect(texts, isNot(contains('Not flagged, this is an SDK widget')));
      expect(
        findings.every(
          (f) => f.category == PossibleHardcodedTextCategory.customConstructorArg,
        ),
        isTrue,
      );
    });

    test(
        'skips named args that look like non-display data (key/id/value/'
        'color/url/...) — regression fixture from the StatCard bug report',
        () async {
      final projectPath = await _createProject('''
class StatCard {
  StatCard({
    required String label,
    String? subtitle,
    String? key,
    String? iconUrl,
    String? routeKey,
  });
}

void useWidgets() {
  StatCard(
    label: 'Bookings',
    subtitle: 'Total bookings',
    key: 'card-key',
    iconUrl: 'https-not-even-technical-but-named-like-data',
    routeKey: 'bookings-route',
  );
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final findings = await extractor.findPossibleHardcodedTexts(projectPath);
      final texts = findings.map((f) => f.text).toSet();

      // Real display copy is still reported — --dry-run no longer silently
      // implies full coverage for this widget.
      expect(texts, containsAll(<String>['Bookings', 'Total bookings']));
      // Params that look like non-display data are skipped, even though
      // their values are plain string literals.
      expect(texts, isNot(contains('card-key')));
      expect(
        texts,
        isNot(contains('https-not-even-technical-but-named-like-data')),
      );
      expect(texts, isNot(contains('bookings-route')));
    });

    test('excludes widgets explicitly configured as extra sinks', () async {
      final projectPath = await _createProject('''
class MyStatCard {
  MyStatCard({String? label});
}

class AuthError {
  AuthError({String? message});
}

void useWidgets() {
  MyStatCard(label: 'Bookings');
  AuthError(message: 'Your session has expired.');
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final findings = await extractor.findPossibleHardcodedTexts(
        projectPath,
        extraWidgets: {
          'MyStatCard': ['label'],
        },
      );
      final texts = findings.map((f) => f.text).toSet();

      // MyStatCard is now a configured sink (handled by extractTextFromProject
      // instead), so it must not also show up in the possible-text report.
      expect(texts, isNot(contains('Bookings')));
      // AuthError was never configured, so it's still reported.
      expect(texts, contains('Your session has expired.'));
    });

    test('flags strings inside a validator: closure', () async {
      final projectPath = await _createProject('''
class TextFormField {
  TextFormField({String? Function(String?)? validator});
}

void useWidgets() {
  TextFormField(
    validator: (v) =>
        v == null || v.isEmpty ? 'Enter your email address.' : null,
  );
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final findings = await extractor.findPossibleHardcodedTexts(projectPath);

      expect(findings, hasLength(1));
      expect(findings.single.text, 'Enter your email address.');
      expect(
        findings.single.category,
        PossibleHardcodedTextCategory.validatorClosure,
      );
    });

    test(
        'flags elements of a multi-string const list but not a '
        'single-string list', () async {
      final projectPath = await _createProject('''
const List<String> kDaysOfWeek = ['Monday', 'Tuesday', 'Wednesday'];
final singleName = ['OnlyOne'];
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final findings = await extractor.findPossibleHardcodedTexts(projectPath);
      final texts = findings.map((f) => f.text).toSet();

      expect(texts, {'Monday', 'Tuesday', 'Wednesday'});
      expect(
        findings.every(
          (f) => f.category == PossibleHardcodedTextCategory.constStringList,
        ),
        isTrue,
      );
    });
  });

  group('BuildContext scope resolution', () {
    test(
        'does not auto-extract text in a method with no BuildContext of its '
        'own and no lexical relationship to build() (fl_chart-style '
        'getTitlesWidget callback implemented as a separate method)',
        () async {
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

      final extractor = TextExtractor();
      final skipped = <PossibleHardcodedText>[];
      final texts = await extractor.extractTextFromProject(
        projectPath,
        skipped: skipped,
      );

      expect(texts, isEmpty);
      expect(skipped, hasLength(1));
      expect(
        skipped.single.category,
        PossibleHardcodedTextCategory.noBuildContextInScope,
      );
    });

    test(
        'still auto-extracts a closure literal defined inline inside '
        'build(BuildContext context), even though the closure itself has '
        'no context parameter, because Dart closures capture the '
        'enclosing scope', () async {
      final projectPath = await _createProject('''
class AxisTitles {
  AxisTitles({Text? Function(double, double)? getTitlesWidget});
}

class MyChart {
  Widget build(BuildContext context) {
    return AxisTitles(
      getTitlesWidget: (value, meta) {
        return Text('\${value}/\${meta}');
      },
    );
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final skipped = <PossibleHardcodedText>[];
      final texts = await extractor.extractTextFromProject(
        projectPath,
        skipped: skipped,
      );

      expect(skipped, isEmpty);
      expect(texts, hasLength(1));
      expect(texts.single.contextExpression, 'context');
    });

    test(
        'uses the actual name of the resolvable BuildContext parameter, '
        'not a hardcoded "context" (including a `!` suffix when it was '
        'declared nullable)', () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext ctx) {
    return Text('Hello');
  }
}

class MyNullableCtxWidget {
  Widget build(BuildContext? ctx) {
    return Text('World');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);
      final byText = {for (final t in texts) t.text: t.contextExpression};

      expect(byText['Hello'], 'ctx');
      expect(byText['World'], 'ctx!');
    });
  });

  group('extraWidgets / extraTextParams', () {
    test('extend normal extraction to team-configured sinks', () async {
      final projectPath = await _createProject('''
class MyStatCard {
  MyStatCard({String? label, String? placeholder});
}

void useWidgets(BuildContext context) {
  MyStatCard(label: 'Bookings', placeholder: 'Search bookings');
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(
        projectPath,
        extraWidgets: {
          'MyStatCard': ['label'],
        },
        extraTextParams: {'placeholder'},
      );
      final values = texts.map((t) => t.text).toSet();

      expect(values, {'Bookings', 'Search bookings'});
    });
  });

  group('nullable interpolation handling', () {
    const nullableFixture = '''
class Cooldown {
  int? data;
}

class MyWidget {
  Widget build(BuildContext context, Cooldown cooldown) {
    return Text('Resend in \${cooldown.data}s');
  }
}
''';

    test('coerces a nullable interpolation to a non-null Object by default',
        () async {
      final projectPath = await _createProject(nullableFixture);
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final texts = await extractor.extractTextFromProject(projectPath);

      expect(texts, hasLength(1));
      expect(texts.single.text, 'Resend in {value1}s');
      expect(texts.single.placeholders, ["(cooldown.data)?.toString() ?? ''"]);
    });

    test(
        '--strict-null-handling skips a nullable interpolation instead of '
        'guessing at a fallback', () async {
      final projectPath = await _createProject(nullableFixture);
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();
      final skipped = <PossibleHardcodedText>[];
      final texts = await extractor.extractTextFromProject(
        projectPath,
        strictNullHandling: true,
        skipped: skipped,
      );

      expect(texts, isEmpty);
      expect(skipped, hasLength(1));
      expect(
        skipped.single.category,
        PossibleHardcodedTextCategory.nullableExpressionStrict,
      );
    });

    test('leaves a non-nullable interpolation unaffected in both modes',
        () async {
      final projectPath = await _createProject('''
class MyWidget {
  Widget build(BuildContext context) {
    final int count = 5;
    return Text('Total: \${count}');
  }
}
''');
      addTearDown(() => Directory(projectPath).delete(recursive: true));

      final extractor = TextExtractor();

      final defaultTexts = await extractor.extractTextFromProject(projectPath);
      expect(defaultTexts, hasLength(1));
      expect(defaultTexts.single.placeholders, ['count']);

      final strictTexts = await extractor.extractTextFromProject(
        projectPath,
        strictNullHandling: true,
      );
      expect(strictTexts, hasLength(1));
      expect(strictTexts.single.placeholders, ['count']);
    });
  });
}
