import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

class ProjectInitializer {
  final String projectPath;

  ProjectInitializer(this.projectPath);

  /// Initializes the project with l10n support
  Future<InitializationResult> initialize() async {
    print('🚀 Initializing Flutter L10n in project...\n');

    final results = <String>[];
    final errors = <String>[];

    // 1. Update pubspec.yaml
    try {
      await _updatePubspec();
      results.add('✅ Updated pubspec.yaml with dependencies');
    } catch (e) {
      errors.add('❌ Failed to update pubspec.yaml: $e');
    }

    // 2. Create l10n.yaml
    try {
      await _createL10nConfig();
      results.add('✅ Created l10n.yaml configuration');
    } catch (e) {
      errors.add('❌ Failed to create l10n.yaml: $e');
    }

    // 3. Create l10n directory
    try {
      await _createL10nDirectory();
      results.add('✅ Created lib/l10n directory');
    } catch (e) {
      errors.add('❌ Failed to create l10n directory: $e');
    }

    // 4. Create initial ARB file
    try {
      await _createInitialArbFile();
      results.add('✅ Created initial ARB file (app_en.arb)');
    } catch (e) {
      errors.add('❌ Failed to create ARB file: $e');
    }

    // Print results
    print('\n📋 Setup Results:');
    for (final result in results) {
      print('  $result');
    }

    if (errors.isNotEmpty) {
      print('\n⚠️  Errors:');
      for (final error in errors) {
        print('  $error');
      }
    }

    return InitializationResult(
      success: errors.isEmpty,
      results: results,
      errors: errors,
    );
  }

  /// Updates pubspec.yaml with necessary dependencies
  Future<void> _updatePubspec() async {
    final pubspecPath = path.join(projectPath, 'pubspec.yaml');
    final file = File(pubspecPath);

    if (!file.existsSync()) {
      throw Exception('pubspec.yaml not found at $pubspecPath');
    }

    String content = await file.readAsString();
    final yaml = loadYaml(content);

    // Check if dependencies already exist
    final dependencies = yaml['dependencies'] as YamlMap?;
    final devDependencies = yaml['dev_dependencies'] as YamlMap?;

    bool modified = false;

    // Add flutter_localizations if not present
    if (dependencies == null ||
        !dependencies.containsKey('flutter_localizations')) {
      content = _addDependency(
        content,
        'flutter_localizations',
        'sdk: flutter',
        section: 'dependencies',
      );
      modified = true;
    }

    // Add intl if not present
    if (dependencies == null || !dependencies.containsKey('intl')) {
      content = _addDependency(
        content,
        'intl',
        'any',
        section: 'dependencies',
      );
      modified = true;
    }

    // Add dev dependencies
    final devDepsToAdd = {
      'analyzer': 'any',
      'path': 'any',
      'args': 'any',
      'yaml': 'any',
    };

    for (final entry in devDepsToAdd.entries) {
      if (devDependencies == null || !devDependencies.containsKey(entry.key)) {
        content = _addDependency(
          content,
          entry.key,
          entry.value,
          section: 'dev_dependencies',
        );
        modified = true;
      }
    }

    // Add flutter.generate if not present
    if (!content.contains('generate: true')) {
      // Find the flutter section
      final flutterRegex = RegExp(r'^flutter:\s*$', multiLine: true);
      final flutterMatch = flutterRegex.firstMatch(content);

      if (flutterMatch != null) {
        // Insert generate: true after flutter:
        final insertPos = flutterMatch.end + 1; // +1 for newline
        content = content.substring(0, insertPos) +
            '  generate: true\n' +
            content.substring(insertPos);
      } else {
        // Add flutter section at the end
        content += '\nflutter:\n  generate: true\n';
      }
      modified = true;
    }

    if (modified) {
      await file.writeAsString(content);
    }
  }

  String _addDependency(
    String content,
    String name,
    String value, {
    required String section,
  }) {
    // Check if dependency already exists in content (to avoid duplicates)
    final depCheckRegex =
        RegExp(r'^\s+' + RegExp.escape(name) + r':', multiLine: true);
    if (depCheckRegex.hasMatch(content)) {
      // Dependency already exists, don't add again
      return content;
    }

    // Find the section
    final sectionRegex = RegExp('^$section:\\s*\$', multiLine: true);
    final sectionMatch = sectionRegex.firstMatch(content);

    if (sectionMatch != null) {
      // Section exists, find where to insert (after section line)
      final sectionEnd = sectionMatch.end;

      // Find the next line after the section header
      int insertPosition = sectionEnd;

      // Skip the newline after section header
      if (insertPosition < content.length && content[insertPosition] == '\n') {
        insertPosition++;
      }

      // Build the dependency string
      String dependencyString;
      if (value.startsWith('sdk:')) {
        dependencyString = '  $name:\n    $value\n';
      } else {
        dependencyString = '  $name: $value\n';
      }

      // Insert the dependency
      return content.substring(0, insertPosition) +
          dependencyString +
          content.substring(insertPosition);
    } else {
      // Section doesn't exist, create it at the end
      String dependencyString;
      if (value.startsWith('sdk:')) {
        dependencyString = '\n$section:\n  $name:\n    $value\n';
      } else {
        dependencyString = '\n$section:\n  $name: $value\n';
      }
      return content + dependencyString;
    }
  }

  /// Creates l10n.yaml configuration file
  Future<void> _createL10nConfig() async {
    final l10nConfigPath = path.join(projectPath, 'l10n.yaml');
    final file = File(l10nConfigPath);

    if (file.existsSync()) {
      print('  ℹ️  l10n.yaml already exists, skipping...');
      return;
    }

    const config = '''arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''';

    await file.writeAsString(config);
  }

  /// Creates lib/l10n directory
  Future<void> _createL10nDirectory() async {
    final l10nDir = Directory(path.join(projectPath, 'lib', 'l10n'));

    if (l10nDir.existsSync()) {
      print('  ℹ️  lib/l10n directory already exists, skipping...');
      return;
    }

    await l10nDir.create(recursive: true);
  }

  /// Creates initial ARB file
  Future<void> _createInitialArbFile() async {
    final arbPath = path.join(projectPath, 'lib', 'l10n', 'app_en.arb');
    final file = File(arbPath);

    if (file.existsSync()) {
      print('  ℹ️  app_en.arb already exists, skipping...');
      return;
    }

    const arbContent = '''{
  "@@locale": "en"
}
''';

    await file.writeAsString(arbContent);
  }
}

class InitializationResult {
  final bool success;
  final List<String> results;
  final List<String> errors;

  InitializationResult({
    required this.success,
    required this.results,
    required this.errors,
  });
}
