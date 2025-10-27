#!/usr/bin/env dart

import 'dart:io';
import 'package:args/args.dart';
import 'package:motrgem/src/utils/l10n_manager.dart';
import 'package:motrgem/src/utils/project_initializer.dart';

void main(List<String> arguments) async {
  // Check for commands
  if (arguments.isNotEmpty && arguments[0] == 'start') {
    await _handleStartCommand(arguments.sublist(1));
    return;
  }

  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Flutter project',
      defaultsTo: '.',
    )
    ..addFlag(
      'replace',
      abbr: 'r',
      help: 'Replace hardcoded texts with l10n calls',
      defaultsTo: false,
    )
    ..addFlag(
      'dry-run',
      abbr: 'd',
      help: 'Perform a dry run without making changes',
      defaultsTo: false,
    )
    ..addOption(
      'add-locale',
      abbr: 'l',
      help: 'Add a new locale file (e.g., es, fr, ar)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _printUsage(parser);
      exit(0);
    }

    final projectPath = results['project'] as String;
    final replace = results['replace'] as bool;
    final dryRun = results['dry-run'] as bool;
    final addLocale = results['add-locale'] as String?;

    // Validate project path
    final projectDir = Directory(projectPath);
    if (!projectDir.existsSync()) {
      print('❌ Error: Project directory not found: $projectPath');
      exit(1);
    }

    final manager = L10nManager(projectDir.absolute.path);

    // Handle add locale command
    if (addLocale != null) {
      print('📦 Adding locale: $addLocale');
      print('');
      print(
          'This will automatically translate all texts using Google Translate.');
      print('Translations may need manual review for accuracy.');
      print('');
      await manager.addLocale(addLocale);
      print('');
      print('✅ Locale added successfully!');
      print(
          '💡 Tip: Review translations in lib/l10n/app_$addLocale.arb for accuracy');
      exit(0);
    }

    // Run the main extraction and replacement workflow
    print('🚀 Flutter L10n Text Extractor');
    print('━' * 50);

    final result = await manager.processProject(
      replaceInCode: replace,
      dryRun: dryRun,
    );

    print('\n━' * 50);

    if (result.hasErrors) {
      print('⚠️  Completed with errors');
      exit(1);
    } else if (result.extractedCount == 0) {
      print('✅ No hardcoded texts found - your project is already localized!');
    } else {
      print('✅ Process completed successfully!');

      if (!replace && !dryRun) {
        print(
          '\n💡 Tip: Run with --replace flag to automatically replace texts in your code',
        );
      }

      if (replace && !dryRun) {
        print('\n📝 Next steps:');
        print(
            '   1. Add localization delegates to your MaterialApp (if not already added)');
        print('   2. Review the changes and test your app');
        print('   3. Translate texts in other locale ARB files if needed');
      }
    }
  } on FormatException catch (e) {
    print('❌ Error: ${e.message}');
    print('');
    _printUsage(parser);
    exit(1);
  } catch (e) {
    print('❌ Unexpected error: $e');
    exit(1);
  }
}

Future<void> _handleStartCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the Flutter project',
      defaultsTo: '.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show help for start command',
      negatable: false,
    );

  try {
    final results = parser.parse(args);

    if (results['help'] as bool) {
      _printStartUsage();
      exit(0);
    }

    final projectPath = results['project'] as String;
    final projectDir = Directory(projectPath);

    if (!projectDir.existsSync()) {
      print('❌ Error: Project directory not found: $projectPath');
      exit(1);
    }

    final initializer = ProjectInitializer(projectDir.absolute.path);
    final result = await initializer.initialize();

    if (result.success) {
      print('\n✅ Project initialized successfully!');
      print('\n📝 Next steps:');
      print('  1. Run: flutter pub get');
      print('  2. Run: motrgem --dry-run');
      print('  3. Run: motrgem --replace');
      exit(0);
    } else {
      print('\n⚠️  Initialization completed with errors');
      exit(1);
    }
  } on FormatException catch (e) {
    print('❌ Error: ${e.message}');
    print('');
    _printStartUsage();
    exit(1);
  } catch (e) {
    print('❌ Unexpected error: $e');
    exit(1);
  }
}

void _printStartUsage() {
  print('Motrgem - Flutter L10n Text Extractor - Start Command');
  print('');
  print('Initializes a Flutter project with l10n support.');
  print('');
  print('Usage: motrgem start [options]');
  print('');
  print('Options:');
  print('  -p, --project    Path to the Flutter project (default: ".")');
  print('  -h, --help       Show this help message');
  print('');
  print('Example:');
  print('  motrgem start');
}

void _printUsage(ArgParser parser) {
  print('Motrgem - Flutter L10n Text Extractor');
  print('');
  print('A tool to extract hardcoded texts from Flutter widgets and');
  print('convert them to l10n (localization) format.');
  print('');
  print('Usage: motrgem [command] [options]');
  print('');
  print('Commands:');
  print('  start            Initialize project with l10n support');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('');
  print('  # Initialize project with l10n support');
  print('  motrgem start');
  print('');
  print('  # Analyze project and show what would be extracted (dry run)');
  print('  motrgem --dry-run');
  print('');
  print('  # Extract texts and add to ARB file (no code changes)');
  print('  motrgem');
  print('');
  print('  # Extract texts and replace in code');
  print('  motrgem --replace');
  print('');
  print('  # Add a new locale (Spanish)');
  print('  motrgem --add-locale es');
  print('');
  print('  # Process a specific project');
  print('  motrgem --project /path/to/project --replace');
}
