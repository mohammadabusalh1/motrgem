import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

class ExtractedText {
  final String text;
  final String filePath;
  final int offset;
  final int line;
  final int column;
  final String widgetType;
  final String generatedId;

  ExtractedText({
    required this.text,
    required this.filePath,
    required this.offset,
    required this.line,
    required this.column,
    required this.widgetType,
    required this.generatedId,
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
      'line': line,
      'column': column,
      'widgetType': widgetType,
      'generatedId': generatedId,
    };
  }
}

class TextExtractor {
  TextExtractor();

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
      final originalText = "'${extractedText.text}'";
      final doubleQuoteText = '"${extractedText.text}"';
      final replacement =
          'AppLocalizations.of(context)!.${extractedText.generatedId}';

      // Try single quotes first, then double quotes
      if (content.contains(originalText)) {
        content = content.replaceFirst(originalText, replacement);
      } else if (content.contains(doubleQuoteText)) {
        content = content.replaceFirst(doubleQuoteText, replacement);
      } else {
        return false;
      }

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
    String cleaned = text
        .replaceAll(RegExp(r'[^\w\s]'), '')
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

    return id;
  }
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

  void _extractTextFromArguments(ArgumentList argumentList, String widgetType) {
    for (final argument in argumentList.arguments) {
      if (argument is SimpleStringLiteral) {
        final text = argument.value;

        // Skip empty strings and very short strings
        if (text.isEmpty || text.length < 2) continue;

        // Skip strings that look like technical values (URLs, IDs, etc.)
        if (_isTechnicalString(text)) continue;

        final location = argument.offset;
        final lineLocation = lineInfo.getLocation(location);

        final extractedText = ExtractedText(
          text: text,
          filePath: filePath,
          offset: location,
          line: lineLocation?.lineNumber ?? 0,
          column: lineLocation?.columnNumber ?? 0,
          widgetType: widgetType,
          generatedId: '', // Will be generated later
        );

        extractedTexts.add(extractedText);
      } else if (argument is NamedExpression) {
        // Check named arguments like title:, label:, tooltip:, etc.
        final argumentName = argument.name.label.name;
        if (_isTextParameter(argumentName)) {
          if (argument.expression is SimpleStringLiteral) {
            final stringLiteral = argument.expression as SimpleStringLiteral;
            final text = stringLiteral.value;

            if (text.isEmpty || text.length < 2) continue;
            if (_isTechnicalString(text)) continue;

            final location = stringLiteral.offset;
            final lineLocation = lineInfo.getLocation(location);

            final extractedText = ExtractedText(
              text: text,
              filePath: filePath,
              offset: location,
              line: lineLocation?.lineNumber ?? 0,
              column: lineLocation?.columnNumber ?? 0,
              widgetType: '$widgetType.$argumentName',
              generatedId: '',
            );

            extractedTexts.add(extractedText);
          }
        }
      }
    }
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
