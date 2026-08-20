import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
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

    final config = await _loadMotrgemConfig();

    // Step 0: report text that sits outside what auto-extraction covers
    // (custom widgets, validator closures, const string lists) *before* the
    // empty-extraction early return below, so a project with zero SDK-widget
    // hits doesn't get a false "fully localized" signal.
    await _reportPossibleHardcodedTexts(config.extraWidgets);

    // Step 1: Extract all texts
    final extractedTexts = await extractor.extractTextFromProject(
      projectPath,
      extraWidgets: config.extraWidgets,
      extraTextParams: config.extraTextParams,
    );

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
      await stdout.flush();
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
    int constRemovedCount = 0;
    List<String> errors = [];
    final modifiedFiles = <String>{};

    // Step 4: Replace in code if requested
    if (replaceInCode) {
      print('\n🔄 Replacing texts in code...');

      // Group texts by file, and replace in reverse offset order per file
      final textsByFile = <String, List<ExtractedText>>{};
      for (final t in textsWithIds) {
        textsByFile.putIfAbsent(t.filePath, () => []).add(t);
      }

      for (final entry in textsByFile.entries) {
        final filePath = entry.key;
        final items = entry.value..sort((a, b) => b.offset.compareTo(a.offset));
        for (final text in items) {
          try {
            final success = await extractor.replaceTextByName(
              text.filePath,
              text,
            );
            if (success) {
              replacedCount++;
              modifiedFiles.add(text.filePath);
              print(
                  '  ✅ Replaced in ${path.basename(text.filePath)}: "${text.text}"');
            } else {
              final error =
                  'Failed to replace in ${text.filePath}: "${text.text}"';
              errors.add(error);
              print('  ❌ $error');
            }
          } catch (e) {
            final error = 'Error replacing in $filePath: $e';
            errors.add(error);
            print('  ❌ $error');
          }
          await stdout.flush();
        }
      }

      // Step 4.5: Remove const keywords from modified files
      if (modifiedFiles.isNotEmpty) {
        print(
            '\n🔧 Removing const keywords from widgets with AppLocalizations...');
        for (final filePath in modifiedFiles) {
          try {
            final removedCount = await extractor.removeConstKeywords(filePath);
            if (removedCount > 0) {
              constRemovedCount += removedCount;
              print(
                  '  ✅ Removed $removedCount const keyword(s) from ${path.basename(filePath)}');
            }
          } catch (e) {
            print('  ⚠️  Could not remove const keywords from $filePath: $e');
          }
          await stdout.flush();
        }
      }

      // Add import statement to files that were modified
      if (replacedCount > 0) {
        await _addImportsToModifiedFiles(modifiedFiles);

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
    if (constRemovedCount > 0) {
      print('  - Const keywords removed: $constRemovedCount');
    }
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
    final textToIdMap = <String, String>{}; // Map to track text -> ID for reuse

    // First, load existing text-to-ID mappings from ARB file
    final existingMappings = await _getExistingTextMappings();
    textToIdMap.addAll(existingMappings);

    for (final text in texts) {
      String uniqueId;

      // Check if we've already seen this exact text
      if (textToIdMap.containsKey(text.text)) {
        // Reuse the existing ID for the same text
        uniqueId = textToIdMap[text.text]!;
        print('  ♻️  Reusing ID "$uniqueId" for: "${text.text}"');
      } else {
        // Generate new ID for new text
        String baseId = await extractor.generateTextId(text.text);
        uniqueId = baseId;

        // Handle ID collisions (different text, same generated ID)
        if (usedIds.contains(uniqueId)) {
          int count = idCounts[baseId] ?? 1;
          do {
            count++;
            uniqueId = '$baseId$count';
          } while (usedIds.contains(uniqueId));
          idCounts[baseId] = count;
        }

        usedIds.add(uniqueId);
        textToIdMap[text.text] = uniqueId; // Store mapping for future reuse
      }

      result.add(ExtractedText(
        text: text.text,
        filePath: text.filePath,
        offset: text.offset,
        length: text.length,
        line: text.line,
        column: text.column,
        widgetType: text.widgetType,
        generatedId: uniqueId,
        placeholders: text.placeholders,
      ));
    }

    return result;
  }

  /// Gets existing text-to-ID mappings from ARB file
  Future<Map<String, String>> _getExistingTextMappings() async {
    final mappings = <String, String>{};

    try {
      final arbPath = path.join(projectPath, 'lib', 'l10n', 'app_en.arb');
      final file = File(arbPath);

      if (!file.existsSync()) {
        return mappings;
      }

      final content = await file.readAsString();
      final arbContent = json.decode(content) as Map<String, dynamic>;

      // Build text -> ID map from existing ARB
      for (final entry in arbContent.entries) {
        if (!entry.key.startsWith('@')) {
          mappings[entry.value as String] = entry.key;
        }
      }
    } catch (e) {
      // If we can't read the ARB file, just return empty map
    }

    return mappings;
  }

  /// Adds necessary imports to modified files
  Future<void> _addImportsToModifiedFiles(Set<String> modifiedFiles) async {
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
          // Find the position after the last import. Matches both quote
          // styles and combinator clauses (as/show/hide) so imports like
          // `import 'package:app/models.dart' as models;` are not skipped,
          // which would otherwise misplace the insertion point.
          final importRegex = RegExp(
            r'''import\s+['"][^'"]+['"](?:\s+(?:as\s+\w+|show\s+[\w,\s]+|hide\s+[\w,\s]+))*\s*;''',
          );
          final matches = importRegex.allMatches(content).toList();

          if (matches.isNotEmpty) {
            final lastImport = matches.last;
            final insertPosition = lastImport.end;

            content = content.substring(0, insertPosition) +
                "\n$importStatement" +
                content.substring(insertPosition);
          } else {
            // No imports found. Insert after any leading library/part-of
            // directive (which must appear before imports) instead of
            // unconditionally at the very start of the file.
            final directiveRegex = RegExp(
              r'^\s*(?:library\s+[^;]*;|part\s+of\s+[^;]*;)\s*',
            );
            final directiveMatch = directiveRegex.matchAsPrefix(content);
            final insertPosition = directiveMatch?.end ?? 0;

            content = content.substring(0, insertPosition) +
                "$importStatement\n" +
                content.substring(insertPosition);
          }

          await file.writeAsString(content);
          print('  📦 Added import to ${path.basename(filePath)}');
        }
      } catch (e) {
        print('  ⚠️  Could not add import to $filePath: $e');
      }
      await stdout.flush();
    }
  }

  /// Loads the optional `motrgem.yaml` config from the project root. Its
  /// `extra_widgets` map lets a team opt their own design-system components
  /// into full extraction + replacement (treated just like `Text`/`AppBar`
  /// etc.); `extra_text_params` adds parameter names recognized on any
  /// widget. Missing or unparseable config behaves exactly like no config at
  /// all (empty defaults) — fully backward compatible.
  Future<({Map<String, List<String>> extraWidgets, Set<String> extraTextParams})>
      _loadMotrgemConfig() async {
    const empty = (
      extraWidgets: <String, List<String>>{},
      extraTextParams: <String>{},
    );

    final file = File(path.join(projectPath, 'motrgem.yaml'));
    if (!file.existsSync()) {
      return empty;
    }

    try {
      final yamlDoc = loadYaml(await file.readAsString());
      if (yamlDoc is! YamlMap) return empty;

      final extraWidgets = <String, List<String>>{};
      final rawWidgets = yamlDoc['extra_widgets'];
      if (rawWidgets is YamlMap) {
        for (final entry in rawWidgets.entries) {
          final params = entry.value;
          if (params is YamlList) {
            extraWidgets[entry.key.toString()] =
                params.map((p) => p.toString()).toList();
          }
        }
      }

      final extraTextParams = <String>{};
      final rawParams = yamlDoc['extra_text_params'];
      if (rawParams is YamlList) {
        extraTextParams.addAll(rawParams.map((p) => p.toString()));
      }

      return (extraWidgets: extraWidgets, extraTextParams: extraTextParams);
    } catch (e) {
      print('  ⚠️  Could not parse motrgem.yaml: $e');
      return empty;
    }
  }

  /// Scans for user-visible-looking text that auto-extraction can't safely
  /// reach (custom widget/exception constructor args, `validator:` closures,
  /// const string lists — see TextExtractor.findPossibleHardcodedTexts) and
  /// reports it: a console summary plus the full list written to
  /// lib/l10n/possible_hardcoded_texts.txt, so it's never silently skipped.
  Future<void> _reportPossibleHardcodedTexts(
    Map<String, List<String>> extraWidgets,
  ) async {
    final findings = await extractor.findPossibleHardcodedTexts(
      projectPath,
      extraWidgets: extraWidgets,
    );

    if (findings.isEmpty) return;

    print(
      '\n⚠️  ${findings.length} possible additional hardcoded text(s) found '
      'in custom widgets/validators/lists — not auto-fixed.',
    );
    const previewLimit = 15;
    for (final finding in findings.take(previewLimit)) {
      print('  $finding');
    }
    if (findings.length > previewLimit) {
      print('  ... and ${findings.length - previewLimit} more');
    }
    await stdout.flush();

    final reportFile = File(
      path.join(projectPath, 'lib', 'l10n', 'possible_hardcoded_texts.txt'),
    );
    await reportFile.parent.create(recursive: true);

    final buffer = StringBuffer()
      ..writeln('Possible additional hardcoded text (not auto-fixed by motrgem)')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln();

    for (final category in PossibleHardcodedTextCategory.values) {
      final inCategory =
          findings.where((f) => f.category == category).toList();
      if (inCategory.isEmpty) continue;

      buffer.writeln('## ${category.name} (${inCategory.length})');
      for (final finding in inCategory) {
        buffer.writeln('  $finding');
      }
      buffer.writeln();
    }

    await reportFile.writeAsString(buffer.toString());
    print('  📄 Full list written to lib/l10n/possible_hardcoded_texts.txt');
    await stdout.flush();
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
