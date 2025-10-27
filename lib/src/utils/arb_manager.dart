import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'Text_extractor.dart';

class ArbManager {
  final String projectPath;
  final String arbDirectory;
  final String templateFileName;

  ArbManager({
    required this.projectPath,
    this.arbDirectory = 'lib/l10n',
    this.templateFileName = 'app_en.arb',
  });

  /// Adds extracted texts to the ARB file
  Future<void> addTextsToArb(List<ExtractedText> texts) async {
    final arbPath = path.join(projectPath, arbDirectory, templateFileName);
    final file = File(arbPath);

    // Read existing ARB content
    Map<String, dynamic> arbContent = {};
    if (file.existsSync()) {
      final content = await file.readAsString();
      arbContent = json.decode(content) as Map<String, dynamic>;
    } else {
      arbContent = {'@@locale': 'en'};
    }

    // Add new texts
    for (final text in texts) {
      if (!arbContent.containsKey(text.generatedId)) {
        arbContent[text.generatedId] = text.text;
        
        // Add metadata
        arbContent['@${text.generatedId}'] = {
          'description': 'Text from ${text.widgetType} in ${path.basename(text.filePath)}',
        };
      }
    }

    // Write back to file with pretty formatting
    final encoder = JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(arbContent);
    await file.writeAsString(prettyJson);

    print('ARB file updated: $arbPath');
    print('Added ${texts.length} text entries');
  }

  /// Reads all existing IDs from the ARB file
  Future<Set<String>> getExistingIds() async {
    final arbPath = path.join(projectPath, arbDirectory, templateFileName);
    final file = File(arbPath);

    if (!file.existsSync()) {
      return {};
    }

    final content = await file.readAsString();
    final arbContent = json.decode(content) as Map<String, dynamic>;

    // Filter out metadata keys (those starting with @ or @@)
    return arbContent.keys
        .where((key) => !key.startsWith('@'))
        .toSet();
  }

  /// Creates additional locale ARB files
  Future<void> createLocaleFile(String locale) async {
    final arbPath = path.join(projectPath, arbDirectory, 'app_$locale.arb');
    final file = File(arbPath);

    if (file.existsSync()) {
      print('Locale file already exists: $arbPath');
      return;
    }

    // Read the template file to get all keys
    final templatePath = path.join(projectPath, arbDirectory, templateFileName);
    final templateFile = File(templatePath);
    
    if (!templateFile.existsSync()) {
      print('Template file not found: $templatePath');
      return;
    }

    final content = await templateFile.readAsString();
    final arbContent = json.decode(content) as Map<String, dynamic>;

    // Create new locale file with empty translations
    final newContent = <String, dynamic>{
      '@@locale': locale,
    };

    // Add all keys from template but with placeholder values
    for (final key in arbContent.keys) {
      if (!key.startsWith('@')) {
        newContent[key] = arbContent[key]; // Copy original as placeholder
      }
    }

    // Write new locale file
    final encoder = JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(newContent);
    await file.writeAsString(prettyJson);

    print('Created locale file: $arbPath');
  }

  /// Gets statistics about the ARB file
  Future<Map<String, int>> getStatistics() async {
    final arbPath = path.join(projectPath, arbDirectory, templateFileName);
    final file = File(arbPath);

    if (!file.existsSync()) {
      return {'total': 0, 'withMetadata': 0};
    }

    final content = await file.readAsString();
    final arbContent = json.decode(content) as Map<String, dynamic>;

    final total = arbContent.keys.where((key) => !key.startsWith('@')).length;
    final withMetadata = arbContent.keys.where((key) => key.startsWith('@') && !key.startsWith('@@')).length;

    return {
      'total': total,
      'withMetadata': withMetadata,
    };
  }
}

