import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:translator/translator.dart';
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
    await file.parent.create(recursive: true);

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
          'description':
              'Text from ${text.widgetType} in ${path.basename(text.filePath)}',
          if (text.placeholders.isNotEmpty)
            'placeholders': {
              for (var i = 0; i < text.placeholders.length; i++)
                'value${i + 1}': {},
            },
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
    return arbContent.keys.where((key) => !key.startsWith('@')).toSet();
  }

  /// Creates additional locale ARB files with automatic translation
  Future<void> createLocaleFile(String locale, {bool translate = true}) async {
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

    // Create new locale file
    final newContent = <String, dynamic>{
      '@@locale': locale,
    };

    if (translate) {
      print('🌍 Translating texts to ${_getLanguageName(locale)}...');
      final translator = GoogleTranslator();

      int translatedCount = 0;
      int totalCount = 0;

      // Translate all keys from template
      for (final key in arbContent.keys) {
        if (!key.startsWith('@')) {
          totalCount++;
          final originalText = arbContent[key] as String;

          try {
            // Show progress (flush so it's visible immediately even when
            // stdout is redirected to a file/pipe rather than a TTY)
            print(
                '  Translating ($translatedCount/$totalCount): "$originalText"');
            await stdout.flush();

            // Mask ICU placeholders before translation to avoid being altered
            final masked = _maskIcuPlaceholders(originalText);

            final translation = await translator.translate(
              masked.$1,
              from: 'en',
              to: locale,
            );

            // Restore placeholders after translation
            final restored =
                _restoreIcuPlaceholders(translation.text, masked.$2);

            newContent[key] = restored;
            translatedCount++;

            // Add a small delay to avoid rate limiting
            await Future.delayed(Duration(milliseconds: 100));
          } catch (e) {
            print('  ⚠️  Could not translate "$originalText": $e');
            newContent[key] = originalText; // Fallback to original
          }
        }
      }

      print('✅ Translated $translatedCount out of $totalCount texts');
    } else {
      // Add all keys from template without translation
      for (final key in arbContent.keys) {
        if (!key.startsWith('@')) {
          newContent[key] = arbContent[key]; // Copy original as placeholder
        }
      }
    }

    // Write new locale file
    final encoder = JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(newContent);
    await file.writeAsString(prettyJson);

    print('📄 Created locale file: $arbPath');
  }

  /// Replaces all ICU-like brace sections `{...}` with stable tokens to protect them during translation.
  /// Returns a record of (maskedText, placeholders).
  (String, List<String>) _maskIcuPlaceholders(String text) {
    final placeholderPattern = RegExp(r'\{[^}]+\}');
    final matches = placeholderPattern.allMatches(text).toList();
    if (matches.isEmpty) return (text, const []);

    // Collect originals in forward order
    final originals = <String>[
      for (final m in matches) text.substring(m.start, m.end)
    ];

    // Replace from last to first to keep indices valid
    var masked = text;
    for (var i = matches.length - 1; i >= 0; i--) {
      final m = matches[i];
      final token = '__PH_${i}__';
      masked = masked.replaceRange(m.start, m.end, token);
    }
    return (masked, originals);
  }

  /// Restores previously masked placeholders back into the translated text.
  String _restoreIcuPlaceholders(String translated, List<String> placeholders) {
    var restored = translated;
    for (var i = 0; i < placeholders.length; i++) {
      final token = '__PH_${i}__';
      restored = restored.replaceAll(token, placeholders[i]);
    }
    return restored;
  }

  /// Gets a human-readable language name for a locale code
  String _getLanguageName(String locale) {
    const languageNames = {
      'ar': 'Arabic',
      'de': 'German',
      'es': 'Spanish',
      'fr': 'French',
      'hi': 'Hindi',
      'it': 'Italian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'nl': 'Dutch',
      'tr': 'Turkish',
      'pl': 'Polish',
      'vi': 'Vietnamese',
      'th': 'Thai',
      'id': 'Indonesian',
      'sv': 'Swedish',
      'da': 'Danish',
      'fi': 'Finnish',
      'no': 'Norwegian',
      'cs': 'Czech',
      'ro': 'Romanian',
      'el': 'Greek',
      'he': 'Hebrew',
      'uk': 'Ukrainian',
      'bn': 'Bengali',
      'ta': 'Tamil',
      'te': 'Telugu',
      'fa': 'Persian',
      'ur': 'Urdu',
    };

    return languageNames[locale] ?? locale.toUpperCase();
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
    final withMetadata = arbContent.keys
        .where((key) => key.startsWith('@') && !key.startsWith('@@'))
        .length;

    return {
      'total': total,
      'withMetadata': withMetadata,
    };
  }
}
