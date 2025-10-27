import 'dart:io';
import 'package:path/path.dart' as path;
import 'Text_extractor.dart';
import 'arb_manager.dart';

class L10nManager {
  final String projectPath;
  final TextExtractor extractor;
  final ArbManager arbManager;

  L10nManager(this.projectPath)
      : extractor = TextExtractor(),
        arbManager = ArbManager(projectPath: projectPath);

  /// Main workflow: Extract texts, generate IDs, update ARB, and optionally replace in code
  Future<L10nResult> processProject({
    bool replaceInCode = false,
    bool dryRun = false,
  }) async {
    print('🔍 Extracting texts from project: $projectPath');
    
    // Step 1: Extract all texts
    final extractedTexts = await extractor.extractTextFromProject(projectPath);
    
    if (extractedTexts.isEmpty) {
      print('✅ No hardcoded texts found!');
      return L10nResult(
        extractedCount: 0,
        replacedCount: 0,
        errors: [],
      );
    }

    print('📝 Found ${extractedTexts.length} hardcoded text(s)');

    // Step 2: Generate IDs and handle duplicates
    final existingIds = await arbManager.getExistingIds();
    final textsWithIds = await _generateUniqueIds(extractedTexts, existingIds);

    // Print found texts
    print('\n📋 Extracted texts:');
    for (final text in textsWithIds) {
      print('  ${text.toString()}');
    }

    if (dryRun) {
      print('\n🔍 Dry run mode - no changes will be made');
      return L10nResult(
        extractedCount: textsWithIds.length,
        replacedCount: 0,
        errors: [],
      );
    }

    // Step 3: Update ARB file
    print('\n📄 Updating ARB file...');
    await arbManager.addTextsToArb(textsWithIds);

    int replacedCount = 0;
    List<String> errors = [];

    // Step 4: Replace in code if requested
    if (replaceInCode) {
      print('\n🔄 Replacing texts in code...');
      
      for (final text in textsWithIds) {
        try {
          final success = await extractor.replaceTextByName(
            text.filePath,
            text,
          );
          
          if (success) {
            replacedCount++;
            print('  ✅ Replaced in ${path.basename(text.filePath)}: "${text.text}"');
          } else {
            final error = 'Failed to replace in ${text.filePath}: "${text.text}"';
            errors.add(error);
            print('  ❌ $error');
          }
        } catch (e) {
          final error = 'Error replacing in ${text.filePath}: $e';
          errors.add(error);
          print('  ❌ $error');
        }
      }

      // Add import statement to files that were modified
      if (replacedCount > 0) {
        await _addImportsToModifiedFiles(textsWithIds);
      }
    }

    // Step 5: Print summary
    print('\n✨ Summary:');
    print('  - Texts extracted: ${textsWithIds.length}');
    print('  - Texts replaced: $replacedCount');
    if (errors.isNotEmpty) {
      print('  - Errors: ${errors.length}');
    }

    final stats = await arbManager.getStatistics();
    print('\n📊 ARB Statistics:');
    print('  - Total entries: ${stats['total']}');
    print('  - With metadata: ${stats['withMetadata']}');

    return L10nResult(
      extractedCount: textsWithIds.length,
      replacedCount: replacedCount,
      errors: errors,
    );
  }

  /// Generates unique IDs for texts, handling duplicates
  Future<List<ExtractedText>> _generateUniqueIds(
    List<ExtractedText> texts,
    Set<String> existingIds,
  ) async {
    final result = <ExtractedText>[];
    final usedIds = <String>{...existingIds};
    final idCounts = <String, int>{};

    for (final text in texts) {
      String baseId = await extractor.generateTextId(text.text);
      String uniqueId = baseId;

      // Handle duplicates by appending numbers
      if (usedIds.contains(uniqueId)) {
        int count = idCounts[baseId] ?? 1;
        do {
          count++;
          uniqueId = '$baseId$count';
        } while (usedIds.contains(uniqueId));
        idCounts[baseId] = count;
      }

      usedIds.add(uniqueId);
      
      result.add(ExtractedText(
        text: text.text,
        filePath: text.filePath,
        offset: text.offset,
        line: text.line,
        column: text.column,
        widgetType: text.widgetType,
        generatedId: uniqueId,
      ));
    }

    return result;
  }

  /// Adds necessary imports to modified files
  Future<void> _addImportsToModifiedFiles(List<ExtractedText> texts) async {
    final modifiedFiles = texts.map((t) => t.filePath).toSet();

    for (final filePath in modifiedFiles) {
      try {
        final file = File(filePath);
        String content = await file.readAsString();

        // Check if import already exists
        if (!content.contains('flutter_gen/gen_l10n/app_localizations.dart')) {
          // Find the position after the last import
          final importRegex = RegExp(r"import '[^']+';");
          final matches = importRegex.allMatches(content).toList();
          
          if (matches.isNotEmpty) {
            final lastImport = matches.last;
            final insertPosition = lastImport.end;
            
            content = content.substring(0, insertPosition) +
                "\nimport 'package:flutter_gen/gen_l10n/app_localizations.dart';" +
                content.substring(insertPosition);
          } else {
            // No imports found, add at the beginning
            content = "import 'package:flutter_gen/gen_l10n/app_localizations.dart';\n" + content;
          }

          await file.writeAsString(content);
          print('  📦 Added import to ${path.basename(filePath)}');
        }
      } catch (e) {
        print('  ⚠️  Could not add import to $filePath: $e');
      }
    }
  }

  /// Creates additional locale files
  Future<void> addLocale(String locale) async {
    await arbManager.createLocaleFile(locale);
  }
}

class L10nResult {
  final int extractedCount;
  final int replacedCount;
  final List<String> errors;

  L10nResult({
    required this.extractedCount,
    required this.replacedCount,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => !hasErrors && extractedCount > 0;
}

