import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:path/path.dart' as path;

class ExtractedText {
  final String text;
  final String filePath;
  final int offset;
  final int length;
  final int line;
  final int column;
  final String widgetType;
  final String generatedId;
  final List<String> placeholders;

  /// The expression to pass to `AppLocalizations.of(...)` at the call site —
  /// almost always `'context'`, but can be a differently-named parameter
  /// (e.g. `'ctx'`, or `'ctx!'` if it was declared nullable) when that's the
  /// actual BuildContext-typed identifier resolvable in scope at [offset].
  final String contextExpression;

  ExtractedText({
    required this.text,
    required this.filePath,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.widgetType,
    required this.generatedId,
    this.placeholders = const [],
    this.contextExpression = 'context',
  });

  @override
  String toString() {
    return '$filePath:$line:$column - [$widgetType] "$text" -> $generatedId';
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'filePath': filePath,
      'offset': offset,
      'length': length,
      'line': line,
      'column': column,
      'widgetType': widgetType,
      'generatedId': generatedId,
      'placeholders': placeholders,
      'contextExpression': contextExpression,
    };
  }
}

/// Categories of text findPossibleHardcodedTexts can report.
enum PossibleHardcodedTextCategory {
  /// A string literal passed to a locally-declared (non-SDK) class
  /// constructor — covers custom widgets and custom exception/error classes.
  customConstructorArg,

  /// A string literal inside a closure passed as a `validator:` argument.
  validatorClosure,

  /// A string literal element of a `const`/plain `List<String>` variable.
  constStringList,

  /// Text that matched a recognized widget+parameter, but no BuildContext
  /// was resolvable in lexical scope at that point, so it was never
  /// auto-replaced (that would produce `Undefined name 'context'`).
  noBuildContextInScope,

  /// A string interpolation with a nullable static type, skipped because
  /// --strict-null-handling was passed instead of applying the default
  /// null-coercion fallback.
  nullableExpressionStrict,
}

/// A string literal that looks like user-visible copy but sits outside the
/// widgets/parameters motrgem auto-extracts, so it is reported rather than
/// silently skipped or auto-rewritten.
class PossibleHardcodedText {
  final String text;
  final String filePath;
  final int line;
  final int column;
  final String source;
  final PossibleHardcodedTextCategory category;

  PossibleHardcodedText({
    required this.text,
    required this.filePath,
    required this.line,
    required this.column,
    required this.source,
    required this.category,
  });

  @override
  String toString() => '$filePath:$line:$column - "$text" ($source)';
}

/// Skips URLs, paths, IDs, format strings, etc. Shared by the main extractor
/// and the possible-hardcoded-text scan so both apply the same definition of
/// "looks like real copy".
bool isTechnicalString(String text) {
  final technicalPatterns = [
    RegExp(r'^https?://'),
    RegExp(r'^www\.'),
    RegExp(r'^/'),
    RegExp(r'^\d+$'),
    RegExp(r'^[A-Z_]+$'), // ALL_CAPS constants
    RegExp(r'%[sd]'), // Format strings
    RegExp(r'\$\{'), // Template strings
  ];

  return technicalPatterns.any((pattern) => pattern.hasMatch(text));
}

/// Named-parameter "words" (matched case-insensitively against each
/// camelCase-split word of a parameter name) that indicate the argument is
/// data, not display copy, so findPossibleHardcodedTexts shouldn't flag it —
/// e.g. `key:`, `iconUrl:`, `routeKey:`.
const _nonDisplayParamWords = {
  'key', 'id', 'value', 'color', 'colour', 'url', 'uri', 'icon',
  'route', 'type', 'code', 'tag', 'asset', 'path',
};

/// Whether [paramName] looks like it holds non-display data rather than
/// user-visible copy, based on the words that make up its camelCase name.
bool _looksLikeNonDisplayParamName(String paramName) {
  final spaced = paramName.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  final words = spaced.toLowerCase().split(RegExp(r'[\s_]+'));
  return words.any(_nonDisplayParamWords.contains);
}

/// Walks up from [node] through enclosing FunctionExpression/MethodDeclaration/
/// FunctionDeclaration/ConstructorDeclaration parameter lists looking for a
/// parameter whose declared type is named `BuildContext`. Returns the
/// expression to use at the call site (the parameter's name, `!`-suffixed if
/// its declared type was nullable), or null if none is resolvable.
///
/// This is a pure syntactic scope walk (matches on the parameter's type
/// *annotation* name, not a semantically-resolved type), which also mirrors
/// Dart's real closure-capture semantics: a closure literal defined lexically
/// inside `build(BuildContext context) { ... }` finds `context` by walking
/// past its own (context-less) parameter list up to build's; a standalone
/// method with no BuildContext parameter of its own — and no enclosing
/// function-like scope that has one — correctly finds nothing, since a
/// MethodDeclaration's parent is always a class/mixin/extension body, never
/// another method, so the walk can't "leak" scope between sibling methods.
String? resolveBuildContextExpression(AstNode node) {
  AstNode? current = node.parent;
  while (current != null) {
    FormalParameterList? params;
    if (current is FunctionExpression) {
      params = current.parameters;
    } else if (current is MethodDeclaration) {
      params = current.parameters;
    } else if (current is FunctionDeclaration) {
      params = current.functionExpression.parameters;
    } else if (current is ConstructorDeclaration) {
      params = current.parameters;
    }

    if (params != null) {
      for (final param in params.parameters) {
        final normalParam =
            param is DefaultFormalParameter ? param.parameter : param;
        if (normalParam is SimpleFormalParameter) {
          final type = normalParam.type;
          if (type is NamedType && type.name2.lexeme == 'BuildContext') {
            final name = normalParam.name?.lexeme;
            if (name != null) {
              return type.question != null ? '$name!' : name;
            }
          }
        }
      }
    }

    current = current.parent;
  }
  return null;
}

/// Extracts the literal text of a simple string expression (no placeholder
/// bookkeeping), or null if [expression] isn't a plain/interpolated string
/// literal we can render as a single display string.
String? _plainStringOf(Expression expression) {
  if (expression is SimpleStringLiteral) return expression.value;
  if (expression is AdjacentStrings) {
    final buffer = StringBuffer();
    for (final part in expression.strings) {
      final text = _plainStringOf(part);
      if (text == null) return null;
      buffer.write(text);
    }
    return buffer.toString();
  }
  if (expression is StringInterpolation) {
    final buffer = StringBuffer();
    for (final element in expression.elements) {
      if (element is InterpolationString) {
        buffer.write(element.value);
      } else {
        buffer.write('{value}');
      }
    }
    return buffer.toString();
  }
  if (expression is ParenthesizedExpression) {
    return _plainStringOf(expression.expression);
  }
  return null;
}

class TextExtractor {
  TextExtractor();

  /// Dart words that cannot be used as identifiers. Includes the
  /// unconditionally-reserved words plus the limited-reserved async words
  /// (async/await/yield), which we avoid defensively even though they're
  /// only reserved inside async/generator function bodies.
  static const Set<String> _dartReservedWords = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
    'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
    'async', 'await', 'yield',
  };

  /// Resolves and validates the project's lib/ directory.
  String _resolveLibPath(String projectPath) {
    final libPath = path.normalize(
      path.absolute(path.join(projectPath, 'lib')),
    );

    if (!Directory(libPath).existsSync()) {
      throw Exception('lib directory not found at: $libPath');
    }

    return libPath;
  }

  /// Lists all Dart files under [libPath].
  List<File> _listDartFiles(String libPath) {
    return Directory(libPath)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  }

  /// Extracts all hardcoded text strings from Flutter widget files in the
  /// project. [extraWidgets] and [extraTextParams] extend the built-in
  /// widget/parameter recognition (see `motrgem.yaml`'s `extra_widgets` and
  /// `extra_text_params`), so teams can opt their own design-system
  /// components into full extraction + replacement.
  ///
  /// If [skipped] is provided, candidates that matched a recognized
  /// widget+parameter but couldn't be safely auto-replaced (no BuildContext
  /// resolvable in scope, or a nullable interpolation under
  /// [strictNullHandling]) are appended to it instead of being silently
  /// dropped, so callers can surface them in a report.
  ///
  /// [strictNullHandling] controls what happens to a string interpolation
  /// whose expression has a nullable static type: by default it's coerced
  /// to a non-null `Object` (`expr?.toString() ?? ''`) so the generated
  /// call always compiles; when true, that candidate is skipped and
  /// reported (in [skipped]) instead of guessing at a fallback.
  Future<List<ExtractedText>> extractTextFromProject(
    String projectPath, {
    Map<String, List<String>> extraWidgets = const {},
    Set<String> extraTextParams = const {},
    List<PossibleHardcodedText>? skipped,
    bool strictNullHandling = false,
  }) async {
    final List<ExtractedText> extractedTexts = [];
    final libPath = _resolveLibPath(projectPath);
    final collection = AnalysisContextCollection(includedPaths: [libPath]);
    final dartFiles = _listDartFiles(libPath);

    final mergedExtraParams = {
      ...extraTextParams,
      for (final params in extraWidgets.values) ...params,
    };

    for (final file in dartFiles) {
      final texts = await _extractTextFromFile(
        file.path,
        collection,
        extraWidgets: extraWidgets.keys.toSet(),
        extraTextParams: mergedExtraParams,
        skipped: skipped,
        strictNullHandling: strictNullHandling,
      );
      extractedTexts.addAll(texts);
    }

    return extractedTexts;
  }

  /// Extracts text from a single Dart file
  Future<List<ExtractedText>> _extractTextFromFile(
    String filePath,
    AnalysisContextCollection collection, {
    Set<String> extraWidgets = const {},
    Set<String> extraTextParams = const {},
    List<PossibleHardcodedText>? skipped,
    bool strictNullHandling = false,
  }) async {
    final extractedTexts = <ExtractedText>[];

    try {
      final context = collection.contextFor(filePath);
      final result = await context.currentSession.getResolvedUnit(filePath);

      if (result is ResolvedUnitResult) {
        final visitor = _TextVisitor(
          filePath,
          result.lineInfo,
          extraWidgets: extraWidgets,
          extraTextParams: extraTextParams,
          strictNullHandling: strictNullHandling,
        );
        result.unit.visitChildren(visitor);
        extractedTexts.addAll(visitor.extractedTexts);
        skipped?.addAll(visitor.skippedTexts);
      }
    } catch (e) {
      print('Error analyzing file $filePath: $e');
    }

    return extractedTexts;
  }

  /// Replaces hardcoded text with l10n call in a file
  Future<bool> replaceTextByName(
    String filePath,
    ExtractedText extractedText,
  ) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return false;
      }

      String content = await file.readAsString();
      final args = extractedText.placeholders;
      final ctx = extractedText.contextExpression;
      final replacement = args.isNotEmpty
          ? 'AppLocalizations.of($ctx)!.${extractedText.generatedId}(${args.join(', ')})'
          : 'AppLocalizations.of($ctx)!.${extractedText.generatedId}';
      final start = extractedText.offset;
      final end = start + extractedText.length;

      if (start < 0 || end > content.length) {
        return false;
      }

      content = content.replaceRange(start, end, replacement);

      await file.writeAsString(content);
      return true;
    } catch (e) {
      print('Error replacing text in file $filePath: $e');
      return false;
    }
  }

  /// Generates a unique ID for the text string
  Future<String> generateTextId(String text) async {
    // Convert text to camelCase ID
    // Remove special characters and convert to lowercase
    // Normalize any interpolation placeholders {...} to the word "value"
    String normalizedPlaceholders =
        text.replaceAll(RegExp(r'\{[^}]*\}'), ' value ');
    // Turn underscores into spaces to avoid leaking them into IDs
    normalizedPlaceholders =
        normalizedPlaceholders.replaceAll(RegExp(r'_+'), ' ');
    String cleaned = normalizedPlaceholders
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .trim()
        .toLowerCase();

    // Split by whitespace
    List<String> words = cleaned.split(RegExp(r'\s+'));

    if (words.isEmpty) {
      return 'text${DateTime.now().millisecondsSinceEpoch}';
    }

    // First word lowercase, rest capitalized
    String id = words.first;
    for (int i = 1; i < words.length && i < 5; i++) {
      if (words[i].isNotEmpty) {
        id += words[i][0].toUpperCase() + words[i].substring(1);
      }
    }

    // Ensure ID is not empty and doesn't start with number
    if (id.isEmpty || RegExp(r'^\d').hasMatch(id)) {
      id = 'text$id';
    }

    // Avoid Dart reserved words (e.g. "continue" -> "continueLabel")
    if (_dartReservedWords.contains(id)) {
      id = '${id}Label';
    }

    return id;
  }

  /// Removes const keywords from widgets that contain AppLocalizations.of(context)
  Future<int> removeConstKeywords(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return 0;
      }

      // Create analysis context - need directory path, not file path
      final fileDir = path.dirname(filePath);
      final collection = AnalysisContextCollection(includedPaths: [fileDir]);
      final context = collection.contextFor(filePath);
      final result = await context.currentSession.getResolvedUnit(filePath);

      if (result is! ResolvedUnitResult) {
        return 0;
      }

      // Use visitor to find widgets with AppLocalizations and const keywords
      final visitor = _ConstRemovalVisitor(result.lineInfo, this);
      result.unit.visitChildren(visitor);

      if (visitor.constRemovalRanges.isEmpty) {
        return 0;
      }

      // Read file content
      String content = await file.readAsString();

      // Sort ranges by offset in reverse order to avoid offset shifting issues
      final sortedRanges = visitor.constRemovalRanges.toList()
        ..sort((a, b) => b.start.compareTo(a.start));

      // Apply edits in reverse order
      for (final range in sortedRanges) {
        // Calculate the end position, including all trailing whitespace after "const"
        int endPos = range.end;

        // Remove all whitespace after "const" (spaces, tabs, but preserve newlines for formatting)
        while (endPos < content.length) {
          final char = content[endPos];
          if (char == ' ' || char == '\t') {
            endPos++;
          } else if (char == '\n' || char == '\r') {
            // Preserve newlines - they're part of the formatting
            break;
          } else {
            // Non-whitespace character - stop here
            break;
          }
        }

        // Remove const keyword and trailing whitespace
        final beforeConst = content.substring(0, range.start);
        final afterConst = content.substring(endPos);
        content = beforeConst + afterConst;
      }

      // Write updated content
      await file.writeAsString(content);

      return visitor.constRemovalRanges.length;
    } catch (e) {
      print('Error removing const keywords in file $filePath: $e');
      return 0;
    }
  }

  /// Checks if an expression contains AppLocalizations.of(context) pattern
  bool containsAppLocalizations(Expression? expression) {
    if (expression == null) return false;

    // Check for MethodInvocation: AppLocalizations.of(context)
    if (expression is MethodInvocation) {
      // Check if it's AppLocalizations.of(context)
      if (isAppLocalizationsCall(expression)) {
        return true;
      }
      // Check arguments recursively
      for (final arg in expression.argumentList.arguments) {
        if (arg is NamedExpression) {
          if (containsAppLocalizations(arg.expression)) return true;
        } else {
          // Positional arguments are Expression
          if (containsAppLocalizations(arg)) return true;
        }
      }
    }

    // Check for PostfixExpression: AppLocalizations.of(context)!
    if (expression is PostfixExpression &&
        containsAppLocalizations(expression.operand)) {
      return true;
    }

    // Check for PropertyAccess: AppLocalizations.of(context)!.someProperty
    if (expression is PropertyAccess &&
        containsAppLocalizations(expression.target)) {
      return true;
    }

    // Check InstanceCreationExpression arguments
    if (expression is InstanceCreationExpression) {
      for (final arg in expression.argumentList.arguments) {
        if (arg is NamedExpression) {
          if (containsAppLocalizations(arg.expression)) return true;
        } else {
          // Positional arguments are Expression
          if (containsAppLocalizations(arg)) return true;
        }
      }
    }

    // Check ListLiteral elements
    if (expression is ListLiteral) {
      for (final element in expression.elements) {
        if (element is Expression) {
          if (containsAppLocalizations(element)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Checks if a MethodInvocation is AppLocalizations.of(context)
  bool isAppLocalizationsCall(MethodInvocation node) {
    // Check method name is "of"
    if (node.methodName.name != 'of') return false;

    // Check target is AppLocalizations
    Expression? target = node.target;

    if (target is PrefixedIdentifier) {
      return target.identifier.name == 'AppLocalizations';
    } else if (target is SimpleIdentifier) {
      return target.name == 'AppLocalizations';
    }

    // If target is null, check if the node is part of a property access
    // like: AppLocalizations.of(context)!.someProperty
    if (target == null) {
      final parent = node.parent;
      if (parent is PropertyAccess) {
        final parentTarget = parent.target;
        if (parentTarget is MethodInvocation) {
          // This might be the case, but we're already checking this node
          // So check if parent's target is AppLocalizations
          return isAppLocalizationsCall(parentTarget);
        }
      }
    }

    // Fallback: check the source code representation
    // This handles cases where AST structure might be different
    try {
      final source = node.toString();
      if (source.contains('AppLocalizations.of')) {
        return true;
      }
    } catch (e) {
      // If toString fails, continue with other checks
    }

    return false;
  }

  /// Scans the project for user-visible-looking string literals that sit
  /// outside what [extractTextFromProject] auto-extracts: string arguments
  /// passed to locally-declared (non-SDK) class constructors — which covers
  /// both custom widgets and custom exception/error classes — strings
  /// inside `validator:` closures, and elements of `const`/plain
  /// `List<String>` variables. These are reported only, never rewritten,
  /// since we can't safely assume every call site has the same
  /// `BuildContext` availability an SDK widget does.
  ///
  /// [extraWidgets]' keys are treated as already handled (matching
  /// [extractTextFromProject]) and excluded from the report.
  Future<List<PossibleHardcodedText>> findPossibleHardcodedTexts(
    String projectPath, {
    Map<String, List<String>> extraWidgets = const {},
  }) async {
    final libPath = _resolveLibPath(projectPath);
    final collection = AnalysisContextCollection(includedPaths: [libPath]);
    final dartFiles = _listDartFiles(libPath);

    // Pass 1: collect every class the project itself declares, so we can
    // tell "custom widget/class we don't recognize" apart from an SDK type
    // we simply don't special-case.
    final localClassNames = <String>{};
    for (final file in dartFiles) {
      try {
        final context = collection.contextFor(file.path);
        final result = await context.currentSession.getResolvedUnit(file.path);
        if (result is ResolvedUnitResult) {
          final collector = _ClassNameCollector();
          result.unit.visitChildren(collector);
          localClassNames.addAll(collector.classNames);
        }
      } catch (e) {
        // Best-effort: a file that fails to resolve here will also have
        // failed in extractTextFromProject, which already reports it.
      }
    }

    final excludedTypeNames = {
      ..._TextVisitor._builtinTextWidgets,
      ...extraWidgets.keys,
    };

    // Pass 2: find the actual possible-hardcoded-text findings.
    final findings = <PossibleHardcodedText>[];
    for (final file in dartFiles) {
      try {
        final context = collection.contextFor(file.path);
        final result = await context.currentSession.getResolvedUnit(file.path);
        if (result is ResolvedUnitResult) {
          final visitor = _PossibleHardcodedTextVisitor(
            file.path,
            result.lineInfo,
            localClassNames: localClassNames,
            excludedTypeNames: excludedTypeNames,
          );
          result.unit.visitChildren(visitor);
          findings.addAll(visitor.findings);
        }
      } catch (e) {
        // Best-effort scan; skip files that fail to resolve.
      }
    }

    return findings;
  }
}

class _TextWithPlaceholders {
  final String text;
  final List<String> placeholders;
  const _TextWithPlaceholders(this.text, this.placeholders);
}

/// AST Visitor to find text strings in Flutter widgets
class _TextVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final lineInfo;
  final List<ExtractedText> extractedTexts = [];

  /// Candidates that matched a recognized widget+parameter but couldn't be
  /// safely auto-replaced (no BuildContext resolvable in scope), reported
  /// separately instead of being silently dropped or emitting broken code.
  final List<PossibleHardcodedText> skippedTexts = [];

  final Set<String> textWidgets;
  final Set<String> textParams;

  /// When true, a string interpolation whose expression has a nullable
  /// static type is never auto-coerced — the whole candidate is skipped and
  /// reported (category nullableExpressionStrict) instead.
  final bool strictNullHandling;

  /// Set by _extractTextAndArgs when it bails out specifically because of
  /// --strict-null-handling, so _extractTextFromExpression can tell that
  /// apart from an expression that just isn't a string at all (which is
  /// normal and shouldn't be reported).
  bool _strictNullSkipped = false;

  // Common Flutter widgets that contain text
  static const _builtinTextWidgets = {
    'Text',
    'AppBar',
    'TextButton',
    'ElevatedButton',
    'OutlinedButton',
    'IconButton',
    'FloatingActionButton',
    'SnackBar',
    'AlertDialog',
    'ListTile',
    'Tooltip',
    'Chip',
    'InputDecoration',
  };

  static const _builtinTextParams = {
    'title',
    'label',
    'tooltip',
    'text',
    'data',
    'message',
    'hintText',
    'labelText',
    'helperText',
    'errorText',
    'counterText',
    'prefixText',
    'suffixText',
    'semanticLabel',
  };

  _TextVisitor(
    this.filePath,
    this.lineInfo, {
    Set<String> extraWidgets = const {},
    Set<String> extraTextParams = const {},
    this.strictNullHandling = false,
  })  : textWidgets = {..._builtinTextWidgets, ...extraWidgets},
        textParams = {..._builtinTextParams, ...extraTextParams};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.toString();

    if (textWidgets.contains(typeName)) {
      _extractTextFromArguments(node.argumentList, typeName);
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Check if this is a builder method (like _buildActionButton, buildButton, etc.)
    final methodName = node.methodName.name;

    // Check if method name suggests it's a widget builder method
    if (_isBuilderMethod(methodName)) {
      // Extract text from method arguments
      _extractTextFromArguments(node.argumentList, methodName);
    }

    super.visitMethodInvocation(node);
  }

  bool _isBuilderMethod(String methodName) {
    // Common patterns for builder methods
    final builderPatterns = [
      RegExp(r'^_?build[A-Z]'), // _buildActionButton, buildButton, etc.
      RegExp(r'^_?create[A-Z]'), // _createButton, createWidget, etc.
      RegExp(r'^_?make[A-Z]'), // _makeButton, makeWidget, etc.
      RegExp(r'^_?get[A-Z].*Widget$'), // _getActionWidget, etc.
    ];

    return builderPatterns.any((pattern) => pattern.hasMatch(methodName));
  }

  void _extractTextFromArguments(ArgumentList argumentList, String widgetType) {
    for (final argument in argumentList.arguments) {
      if (argument is NamedExpression) {
        // Check named arguments like title:, label:, tooltip:, etc.
        final argumentName = argument.name.label.name;
        if (_isTextParameter(argumentName)) {
          _extractTextFromExpression(
            argument.expression,
            '$widgetType.$argumentName',
          );
        }
      } else {
        _extractTextFromExpression(argument, widgetType);
      }
    }
  }

  void _extractTextFromExpression(Expression expression, String widgetType) {
    if (expression is ParenthesizedExpression) {
      _extractTextFromExpression(expression.expression, widgetType);
      return;
    }

    if (expression is ConditionalExpression) {
      _extractTextFromExpression(expression.thenExpression, widgetType);
      _extractTextFromExpression(expression.elseExpression, widgetType);
      return;
    }

    _strictNullSkipped = false;
    final textWithArgs = _expressionToTextWithPlaceholders(expression);
    if (textWithArgs == null) {
      if (_strictNullSkipped) {
        final lineLocation = lineInfo.getLocation(expression.offset);
        skippedTexts.add(PossibleHardcodedText(
          text: expression.toSource(),
          filePath: filePath,
          line: lineLocation?.lineNumber ?? 0,
          column: lineLocation?.columnNumber ?? 0,
          source: widgetType,
          category: PossibleHardcodedTextCategory.nullableExpressionStrict,
        ));
      }
      return;
    }

    _addExtractedText(
      textWithArgs.text,
      expression.offset,
      expression.length,
      widgetType,
      expression,
      placeholders: textWithArgs.placeholders,
    );
  }

  _TextWithPlaceholders? _expressionToTextWithPlaceholders(
      Expression expression) {
    final args = <String>[];
    final text = _extractTextAndArgs(expression, args);
    if (text == null) return null;
    return _TextWithPlaceholders(text, args);
  }

  /// Recursively extracts the literal text of [expression], collecting every
  /// distinct interpolated expression's source (in left-to-right order) into
  /// [args] and emitting a uniquely-numbered `{valueN}` placeholder for each
  /// one. The same [args] accumulator is threaded through nested
  /// AdjacentStrings/BinaryExpression parts so numbering stays consistent
  /// (and no interpolated expression is ever dropped) across multi-part
  /// string literals such as `'${a} – ' '${b} (${c}h)'`.
  String? _extractTextAndArgs(Expression expression, List<String> args) {
    if (expression is SimpleStringLiteral) {
      return expression.value;
    }

    if (expression is AdjacentStrings) {
      final buffer = StringBuffer();
      for (final stringLiteral in expression.strings) {
        final part = _extractTextAndArgs(stringLiteral, args);
        if (part == null) {
          return null;
        }
        buffer.write(part);
      }
      return buffer.toString();
    }

    if (expression is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in expression.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else if (element is InterpolationExpression) {
          final source = element.expression.toSource();
          final type = element.expression.staticType;
          final isNullable =
              type != null && type.nullabilitySuffix == NullabilitySuffix.question;

          if (isNullable && strictNullHandling) {
            // Can't prove this won't be null, and the caller asked us not
            // to guess — bail out of the whole candidate so it gets
            // reported instead of silently coerced.
            _strictNullSkipped = true;
            return null;
          }

          // ARB placeholders are always typed as non-nullable Object, so a
          // nullable interpolation must be coerced to a non-null value or
          // `flutter analyze` fails with "argument type 'X?' can't be
          // assigned to the parameter type 'Object'".
          args.add(isNullable ? "($source)?.toString() ?? ''" : source);
          buffer.write('{value${args.length}}');
        }
      }
      return buffer.toString();
    }

    if (expression is BinaryExpression &&
        expression.operator.type == TokenType.PLUS) {
      final left = _extractTextAndArgs(expression.leftOperand, args);
      final right = _extractTextAndArgs(expression.rightOperand, args);
      if (left == null || right == null) {
        return null;
      }
      return left + right;
    }

    if (expression is ParenthesizedExpression) {
      return _extractTextAndArgs(expression.expression, args);
    }

    if (expression is StringLiteral) {
      // Covers other string literal types if introduced in future.
      return expression.stringValue;
    }

    return null;
  }

  void _addExtractedText(
    String text,
    int offset,
    int length,
    String widgetType,
    AstNode node, {
    List<String> placeholders = const [],
  }) {
    if (text.isEmpty || text.length < 2) return;
    if (isTechnicalString(text)) return;

    final lineLocation = lineInfo.getLocation(offset);
    final line = lineLocation?.lineNumber ?? 0;
    final column = lineLocation?.columnNumber ?? 0;

    final contextExpression = resolveBuildContextExpression(node);
    if (contextExpression == null) {
      // A recognized widget/parameter, but no BuildContext is resolvable in
      // scope here — auto-replacing would emit `Undefined name 'context'`.
      // Report it instead of silently dropping it or emitting broken code.
      skippedTexts.add(PossibleHardcodedText(
        text: text,
        filePath: filePath,
        line: line,
        column: column,
        source: widgetType,
        category: PossibleHardcodedTextCategory.noBuildContextInScope,
      ));
      return;
    }

    final extractedText = ExtractedText(
      text: text,
      filePath: filePath,
      offset: offset,
      length: length,
      line: line,
      column: column,
      widgetType: widgetType,
      generatedId: '',
      placeholders: placeholders,
      contextExpression: contextExpression,
    );

    extractedTexts.add(extractedText);
  }

  bool _isTextParameter(String paramName) => textParams.contains(paramName);
}

/// AST Visitor to find and remove const keywords from widgets with AppLocalizations
class _ConstRemovalVisitor extends RecursiveAstVisitor<void> {
  final lineInfo;
  final TextExtractor extractor;
  final Set<_ConstRemovalRange> constRemovalRanges = {};
  final List<InstanceCreationExpression> widgetStack = [];

  _ConstRemovalVisitor(this.lineInfo, this.extractor);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Track widget hierarchy
    widgetStack.add(node);

    // Check if this widget has const keyword
    final hasConst = node.keyword?.lexeme == 'const';

    // Visit children first
    super.visitInstanceCreationExpression(node);

    // After visiting children, check if this widget or its subtree contains AppLocalizations
    if (hasConst && _widgetOrSubtreeContainsAppLocalizations(node)) {
      _markConstForRemoval(node);
    }

    widgetStack.removeLast();
  }

  @override
  void visitListLiteral(ListLiteral node) {
    final hasConst = node.constKeyword?.lexeme == 'const';

    super.visitListLiteral(node);

    if (hasConst && _subtreeContainsAppLocalizations(node)) {
      _markConstTokenForRemoval(node.constKeyword);
    }
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    final hasConst = node.constKeyword?.lexeme == 'const';

    super.visitSetOrMapLiteral(node);

    if (hasConst && _subtreeContainsAppLocalizations(node)) {
      _markConstTokenForRemoval(node.constKeyword);
    }
  }

  /// Checks if a widget or any node in its subtree contains AppLocalizations
  bool _widgetOrSubtreeContainsAppLocalizations(
      InstanceCreationExpression node) {
    return _subtreeContainsAppLocalizations(node);
  }

  /// Checks if any node in [node]'s subtree contains AppLocalizations
  bool _subtreeContainsAppLocalizations(AstNode node) {
    // Use a checker visitor to scan the entire subtree
    final checker = _AppLocalizationsChecker(extractor);
    node.accept(checker);
    return checker.found;
  }

  /// Marks a const keyword for removal
  void _markConstForRemoval(InstanceCreationExpression node) {
    _markConstTokenForRemoval(node.keyword);
  }

  /// Marks the given const [keyword] token for removal
  void _markConstTokenForRemoval(Token? keyword) {
    if (keyword == null) return;

    // Get the range of the const keyword
    final offset = keyword.offset;
    final length = keyword.length;
    final endOffset = offset + length;

    constRemovalRanges.add(_ConstRemovalRange(offset, endOffset));
  }
}

/// Visitor to check if a subtree contains AppLocalizations
class _AppLocalizationsChecker extends RecursiveAstVisitor<void> {
  final TextExtractor extractor;
  bool found = false;

  _AppLocalizationsChecker(this.extractor);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (found) return; // Early exit if already found
    if (extractor.isAppLocalizationsCall(node)) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (found) return;
    // Check if target is AppLocalizations.of(context)!
    final target = node.target;
    if (target is MethodInvocation &&
        extractor.isAppLocalizationsCall(target)) {
      found = true;
      return;
    }
    if (target is PostfixExpression) {
      final operand = target.operand;
      if (operand is MethodInvocation &&
          extractor.isAppLocalizationsCall(operand)) {
        found = true;
        return;
      }
    }
    super.visitPropertyAccess(node);
  }
}

/// Represents a range in source code where const keyword should be removed
class _ConstRemovalRange {
  final int start;
  final int end;

  _ConstRemovalRange(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ConstRemovalRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

/// Collects the names of every class declared in the visited compilation
/// unit(s), used to tell a locally-defined ("custom") widget/class apart
/// from an SDK type findPossibleHardcodedTexts simply doesn't recognize.
class _ClassNameCollector extends RecursiveAstVisitor<void> {
  final Set<String> classNames = {};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classNames.add(node.name.lexeme);
    super.visitClassDeclaration(node);
  }
}

/// Collects string literals inside a `validator:` closure body. Kept
/// deliberately simple (plain literals only, not interpolations/adjacent
/// strings) since this is a best-effort report, not a rewrite.
class _ClosureStringCollector extends RecursiveAstVisitor<void> {
  final List<SimpleStringLiteral> stringLiterals = [];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    stringLiterals.add(node);
    super.visitSimpleStringLiteral(node);
  }
}

/// AST visitor backing [TextExtractor.findPossibleHardcodedTexts]: flags
/// string literals that look like user-visible copy but sit outside the
/// widgets/parameters the main extractor auto-handles.
class _PossibleHardcodedTextVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final lineInfo;
  final Set<String> localClassNames;
  final Set<String> excludedTypeNames;
  final List<PossibleHardcodedText> findings = [];

  _PossibleHardcodedTextVisitor(
    this.filePath,
    this.lineInfo, {
    required this.localClassNames,
    required this.excludedTypeNames,
  });

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.toString();

    if (localClassNames.contains(typeName) &&
        !excludedTypeNames.contains(typeName)) {
      for (final argument in node.argumentList.arguments) {
        if (argument is NamedExpression) {
          final paramName = argument.name.label.name;
          if (_looksLikeNonDisplayParamName(paramName)) continue;
          _checkStringExpression(
            argument.expression,
            '$typeName.$paramName',
            PossibleHardcodedTextCategory.customConstructorArg,
          );
        } else {
          _checkStringExpression(
            argument,
            '$typeName.positional arg',
            PossibleHardcodedTextCategory.customConstructorArg,
          );
        }
      }
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'validator' &&
        node.expression is FunctionExpression) {
      final collector = _ClosureStringCollector();
      (node.expression as FunctionExpression).body.accept(collector);
      for (final literal in collector.stringLiterals) {
        _record(
          literal.value,
          literal.offset,
          'validator closure',
          PossibleHardcodedTextCategory.validatorClosure,
        );
      }
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer is ListLiteral) {
      final stringElements = <Expression>[];
      var allStrings = true;
      for (final element in initializer.elements) {
        if (element is SimpleStringLiteral ||
            element is StringInterpolation ||
            element is AdjacentStrings) {
          stringElements.add(element as Expression);
        } else {
          allStrings = false;
          break;
        }
      }
      // Require 2+ elements so a single-string list (often an id/key, not
      // display data) doesn't get flagged.
      if (allStrings && stringElements.length >= 2) {
        for (final element in stringElements) {
          _checkStringExpression(
            element,
            'const list ${node.name.lexeme}',
            PossibleHardcodedTextCategory.constStringList,
          );
        }
      }
    }
    super.visitVariableDeclaration(node);
  }

  void _checkStringExpression(
    Expression expression,
    String source,
    PossibleHardcodedTextCategory category,
  ) {
    final text = _plainStringOf(expression);
    if (text == null) return;
    _record(text, expression.offset, source, category);
  }

  void _record(
    String text,
    int offset,
    String source,
    PossibleHardcodedTextCategory category,
  ) {
    if (text.isEmpty || text.length < 2) return;
    if (isTechnicalString(text)) return;

    final loc = lineInfo.getLocation(offset);
    findings.add(PossibleHardcodedText(
      text: text,
      filePath: filePath,
      line: loc?.lineNumber ?? 0,
      column: loc?.columnNumber ?? 0,
      source: source,
      category: category,
    ));
  }
}
