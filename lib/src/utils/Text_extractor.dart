import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
    };
  }
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

  /// Extracts all hardcoded text strings from Flutter widget files in the project
  Future<List<ExtractedText>> extractTextFromProject(String projectPath) async {
    final List<ExtractedText> extractedTexts = [];
    final libPath = path.normalize(
      path.absolute(path.join(projectPath, 'lib')),
    );

    if (!Directory(libPath).existsSync()) {
      throw Exception('lib directory not found at: $libPath');
    }

    // Create analysis context
    final collection = AnalysisContextCollection(includedPaths: [libPath]);

    // Get all Dart files in lib directory
    final dartFiles = Directory(libPath)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    for (final file in dartFiles) {
      final texts = await _extractTextFromFile(file.path, collection);
      extractedTexts.addAll(texts);
    }

    return extractedTexts;
  }

  /// Extracts text from a single Dart file
  Future<List<ExtractedText>> _extractTextFromFile(
    String filePath,
    AnalysisContextCollection collection,
  ) async {
    final extractedTexts = <ExtractedText>[];

    try {
      final context = collection.contextFor(filePath);
      final result = await context.currentSession.getResolvedUnit(filePath);

      if (result is ResolvedUnitResult) {
        final visitor = _TextVisitor(filePath, result.lineInfo);
        result.unit.visitChildren(visitor);
        extractedTexts.addAll(visitor.extractedTexts);
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
      final replacement = args.isNotEmpty
          ? 'AppLocalizations.of(context)!.${extractedText.generatedId}(${args.join(', ')})'
          : 'AppLocalizations.of(context)!.${extractedText.generatedId}';
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

  // Common Flutter widgets that contain text
  static const textWidgets = {
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

  _TextVisitor(this.filePath, this.lineInfo);

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

    final textWithArgs = _expressionToTextWithPlaceholders(expression);
    if (textWithArgs == null) {
      return;
    }

    _addExtractedText(
      textWithArgs.text,
      expression.offset,
      expression.length,
      widgetType,
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
          args.add(element.expression.toSource());
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
    String widgetType, {
    List<String> placeholders = const [],
  }) {
    if (text.isEmpty || text.length < 2) return;
    if (_isTechnicalString(text)) return;

    final lineLocation = lineInfo.getLocation(offset);

    final extractedText = ExtractedText(
      text: text,
      filePath: filePath,
      offset: offset,
      length: length,
      line: lineLocation?.lineNumber ?? 0,
      column: lineLocation?.columnNumber ?? 0,
      widgetType: widgetType,
      generatedId: '',
      placeholders: placeholders,
    );

    extractedTexts.add(extractedText);
  }

  bool _isTextParameter(String paramName) {
    const textParams = {
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
    return textParams.contains(paramName);
  }

  bool _isTechnicalString(String text) {
    // Skip URLs, paths, IDs, format strings, etc.
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
