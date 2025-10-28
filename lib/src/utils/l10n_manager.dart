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
            print(
                '  ✅ Replaced in ${path.basename(text.filePath)}: "${text.text}"');
          } else {
            final error =
                'Failed to replace in ${text.filePath}: "${text.text}"';
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

        // Configure MaterialApp for localization
        await _configureMaterialApp();

        // Run Flutter commands to generate localization files
        print('\n🔧 Running Flutter commands...');
        await _runFlutterCommands();
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

    // Get the package name from the project's pubspec.yaml
    final packageName = await _getPackageName();
    if (packageName == null) {
      print('  ⚠️  Could not determine package name from pubspec.yaml');
      return;
    }

    final importStatement =
        "import 'package:$packageName/l10n/app_localizations.dart';";

    for (final filePath in modifiedFiles) {
      try {
        final file = File(filePath);
        String content = await file.readAsString();

        // Check if import already exists
        if (!content.contains('/l10n/app_localizations.dart')) {
          // Find the position after the last import
          final importRegex = RegExp(r"import '[^']+';");
          final matches = importRegex.allMatches(content).toList();

          if (matches.isNotEmpty) {
            final lastImport = matches.last;
            final insertPosition = lastImport.end;

            content = content.substring(0, insertPosition) +
                "\n$importStatement" +
                content.substring(insertPosition);
          } else {
            // No imports found, add at the beginning
            content = "$importStatement\n" + content;
          }

          await file.writeAsString(content);
          print('  📦 Added import to ${path.basename(filePath)}');
        }
      } catch (e) {
        print('  ⚠️  Could not add import to $filePath: $e');
      }
    }
  }

  /// Gets the package name from pubspec.yaml
  Future<String?> _getPackageName() async {
    try {
      final pubspecPath = path.join(projectPath, 'pubspec.yaml');
      final file = File(pubspecPath);

      if (!file.existsSync()) {
        return null;
      }

      final content = await file.readAsString();
      final nameRegex = RegExp(r'^name:\s*(.+)$', multiLine: true);
      final match = nameRegex.firstMatch(content);

      if (match != null) {
        return match.group(1)?.trim();
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Runs Flutter commands to generate localization files and clean build
  Future<void> _runFlutterCommands() async {
    try {
      // Run flutter clean
      print('  🧹 Running flutter clean...');
      final cleanResult = await Process.run(
        'flutter',
        ['clean'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      if (cleanResult.exitCode == 0) {
        print('  ✅ flutter clean completed');
      } else {
        print('  ⚠️  flutter clean warning: ${cleanResult.stderr}');
      }

      // Run flutter pub get
      print('  📦 Running flutter pub get...');
      final pubGetResult = await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      if (pubGetResult.exitCode == 0) {
        print('  ✅ flutter pub get completed');
      } else {
        print('  ⚠️  flutter pub get warning: ${pubGetResult.stderr}');
      }

      // Run flutter gen-l10n
      print('  🌍 Running flutter gen-l10n...');
      final genL10nResult = await Process.run(
        'flutter',
        ['gen-l10n'],
        workingDirectory: projectPath,
        runInShell: true,
      );

      if (genL10nResult.exitCode == 0) {
        print('  ✅ flutter gen-l10n completed');
        print('  📝 Localization files generated successfully!');
      } else {
        print('  ⚠️  flutter gen-l10n warning: ${genL10nResult.stderr}');
        print(
            '  💡 Note: Localization files will be generated automatically on next flutter pub get');
      }
    } catch (e) {
      print('  ⚠️  Could not run Flutter commands: $e');
      print('  💡 Please run manually: flutter clean && flutter pub get');
    }
  }

  /// Configures MaterialApp widget with localization delegates
  Future<void> _configureMaterialApp() async {
    print('\n📱 Configuring MaterialApp...');

    try {
      // Find main.dart or any file with MaterialApp
      final libPath = path.join(projectPath, 'lib');
      final dartFiles = Directory(libPath)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      for (final file in dartFiles) {
        String content = await file.readAsString();

        // Check if file contains MaterialApp
        if (!content.contains('MaterialApp')) {
          continue;
        }

        bool modified = false;

        // Check if localizationsDelegates is already configured
        if (!content.contains('localizationsDelegates')) {
          // Find MaterialApp( and add localization config
          final materialAppRegex = RegExp(
            r'MaterialApp\s*\(',
            multiLine: true,
          );

          final match = materialAppRegex.firstMatch(content);
          if (match != null) {
            // Find the position after MaterialApp(
            int insertPos = match.end;

            // Skip whitespace and newlines
            while (insertPos < content.length &&
                (content[insertPos] == ' ' ||
                    content[insertPos] == '\n' ||
                    content[insertPos] == '\r')) {
              insertPos++;
            }

            // Insert localization configuration
            final localizationConfig = '''
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
''';

            content = content.substring(0, insertPos) +
                localizationConfig +
                content.substring(insertPos);

            modified = true;
            print(
                '  ✅ Added localization configuration to ${path.basename(file.path)}');
          }
        } else {
          print(
              '  ℹ️  ${path.basename(file.path)} already has localization configuration');
        }

        if (modified) {
          await file.writeAsString(content);
        }
      }
    } catch (e) {
      print('  ⚠️  Could not configure MaterialApp: $e');
      print('  💡 Please add localization configuration manually');
    }
  }

  /// Creates additional locale files
  Future<void> addLocale(String locale) async {
    await arbManager.createLocaleFile(locale);

    // Update MaterialApp configuration after adding locale
    print('\n📱 Updating MaterialApp configuration...');
    await _configureMaterialApp();

    print(
        '\n💡 Note: The new locale will be automatically included in supportedLocales');
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
