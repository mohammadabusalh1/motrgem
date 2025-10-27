# Motrgem - Flutter L10n Text Extractor

[![pub package](https://img.shields.io/pub/v/motrgem.svg)](https://pub.dev/packages/motrgem)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful command-line tool that automatically extracts hardcoded text strings from Flutter widgets and converts them to l10n (localization) format.

## Installation

### Global Installation (Recommended)

Install globally to use `motrgem` command anywhere:

```bash
dart pub global activate motrgem
```

### As Dev Dependency

Add to your Flutter project's `pubspec.yaml`:

```yaml
dev_dependencies:
  motrgem: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Features

This project includes a powerful **L10n Text Extractor** library that automatically:

- 🔍 **Analyzes your Flutter code** using the Dart analyzer to find hardcoded text strings in widgets
- 🏷️ **Generates unique IDs** for each text string in camelCase format
- 📝 **Updates ARB files** with extracted texts and metadata
- 🔄 **Replaces hardcoded strings** with `AppLocalizations` calls
- 📦 **Automatically adds imports** for localization files
- 🌍 **Supports multiple locales** with easy locale file generation

## Supported Widgets

The library extracts text from these common Flutter widgets:

- `Text`
- `AppBar`
- `TextButton`, `ElevatedButton`, `OutlinedButton`
- `FloatingActionButton`
- `Tooltip`
- `SnackBar`, `AlertDialog`
- `ListTile`, `Chip`
- `InputDecoration` (with parameters like `hintText`, `labelText`, etc.)

## Usage

### Initialize Project (First Time Setup)

Initialize a Flutter project with l10n support:

**If installed globally:**

```bash
motrgem start
```

**If installed as dev dependency:**

```bash
dart run motrgem start
```

This command will:

- Add necessary dependencies to `pubspec.yaml` (flutter_localizations, intl, analyzer, path, args)
- Create `l10n.yaml` configuration file
- Create `lib/l10n` directory
- Create initial `app_en.arb` file
- Enable `generate: true` in pubspec.yaml

### Extract texts (Dry Run)

See what would be extracted without making any changes:

```bash
motrgem --dry-run
```

### Extract texts only

Add extracted texts to the ARB file without modifying your code:

```bash
motrgem
```

### Extract and replace

Extract texts, update ARB file, and replace hardcoded strings in your code:

```bash
motrgem --replace
```

### Add a new locale

Create a new locale file (e.g., Spanish, French, Arabic):

```bash
motrgem --add-locale es
motrgem --add-locale fr
motrgem --add-locale ar
```

### Process a specific project

```bash
motrgem --project /path/to/project --replace
```

> **Note**: If using as a dev dependency, prefix all commands with `dart run`, e.g., `dart run motrgem start`

## Getting Started

### Quick Start (New Project)

1. Create or navigate to your Flutter project
2. Initialize l10n support:

```bash
motrgem start
```

3. Install dependencies:

```bash
flutter pub get
```

4. Extract and replace texts:

```bash
motrgem --replace
```

### Prerequisites

- Flutter SDK installed

### Setup Localization

1. The project already includes `l10n.yaml` configuration:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

2. In your `pubspec.yaml`, ensure you have:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true
```

3. After running the extractor with `--replace`, add localization delegates to your `MaterialApp`:

```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // ... other properties
)
```

## How It Works

### 1. Text Extraction

The library uses the Dart `analyzer` package to parse your Flutter code's Abstract Syntax Tree (AST). It identifies:

- Direct string literals in Text widgets
- Named parameters containing text (like `title:`, `tooltip:`, `label:`)
- Strings in various widget constructors

### 2. ID Generation

Text strings are converted to camelCase IDs:

- "Hello World" → `helloWorld`
- "You have pushed the button" → `youHavePushedTheButton`
- "Sign In" → `signIn`

The generator:

- Removes special characters
- Handles duplicates by appending numbers
- Ensures valid Dart identifiers

### 3. ARB File Management

Extracted texts are added to `lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "youHavePushedTheButton": "You have pushed the button this many times:",
  "@youHavePushedTheButton": {
    "description": "Text from Text in main.dart"
  }
}
```

### 4. Code Replacement

Original code:

```dart
Text('You have pushed the button this many times:')
```

Becomes:

```dart
Text(AppLocalizations.of(context)!.youHavePushedTheButton)
```

## Project Structure

```
lib/
├── main.dart                          # Main app file
├── l10n/
│   └── app_en.arb                     # English translations
└── src/
    └── utils/
        ├── Text_extractor.dart        # Core analyzer and extractor
        ├── arb_manager.dart          # ARB file operations
        └── l10n_manager.dart         # Workflow orchestration

bin/
└── l10n_extractor.dart               # CLI tool

l10n.yaml                             # L10n configuration
```

## Library Components

### TextExtractor

Analyzes Dart files using the analyzer package to find hardcoded strings.

```dart
final extractor = TextExtractor();
final texts = await extractor.extractTextFromProject(projectPath);
```

### ArbManager

Manages ARB file operations (reading, writing, adding locales).

```dart
final arbManager = ArbManager(projectPath: projectPath);
await arbManager.addTextsToArb(texts);
```

### L10nManager

Orchestrates the complete workflow.

```dart
final manager = L10nManager(projectPath);
final result = await manager.processProject(replaceInCode: true);
```

## Example Output

### Initialize Command

```
🚀 Initializing Flutter L10n in project...

📋 Setup Results:
  ✅ Updated pubspec.yaml with dependencies
  ✅ Created l10n.yaml configuration
  ✅ Created lib/l10n directory
  ✅ Created initial ARB file (app_en.arb)

✅ Project initialized successfully!

📝 Next steps:
  1. Run: flutter pub get
  2. Run: dart run bin/l10n_extractor.dart --dry-run
  3. Run: dart run bin/l10n_extractor.dart --replace
```

### Extract Command

```
🚀 Flutter L10n Text Extractor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Extracting texts from project: .
📝 Found 2 hardcoded text(s)

📋 Extracted texts:
  lib/main.dart:107:24 - [Text] "You have pushed the button..." -> youHavePushedTheButton
  lib/main.dart:117:18 - [FloatingActionButton.tooltip] "Increment" -> increment

📄 Updating ARB file...
ARB file updated: lib/l10n/app_en.arb
Added 2 text entries

🔄 Replacing texts in code...
  ✅ Replaced in main.dart: "You have pushed the button..."
  ✅ Replaced in main.dart: "Increment"
  📦 Added import to main.dart

✨ Summary:
  - Texts extracted: 2
  - Texts replaced: 2

📊 ARB Statistics:
  - Total entries: 2
  - With metadata: 2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Process completed successfully!
```

## Advanced Usage

### Filtering Technical Strings

The library automatically skips:

- URLs (`http://`, `https://`, `www.`)
- File paths
- Numbers-only strings
- ALL_CAPS constants
- Format strings (`%s`, `%d`)
- Template strings with `${}`

### Handling Duplicates

When the same base ID would be generated multiple times, the library automatically appends numbers:

- First occurrence: `buttonText`
- Second occurrence: `buttonText2`
- Third occurrence: `buttonText3`

## Development

### Running Tests

```bash
flutter test
```

### Adding New Widget Support

Edit `lib/src/utils/Text_extractor.dart` and add to the `textWidgets` set:

```dart
static const textWidgets = {
  'Text',
  'YourCustomWidget',
  // ... more widgets
};
```

### Adding New Text Parameters

Add to the `textParams` set in `_isTextParameter()`:

```dart
const textParams = {
  'title',
  'yourCustomParam',
  // ... more parameters
};
```

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with the Dart `analyzer` package
- Uses Flutter's official `intl` package for localization
- Follows Flutter localization best practices
