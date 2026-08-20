# Motrgem - Flutter L10n Text Extractor

[![pub package](https://img.shields.io/pub/v/motrgem.svg)](https://pub.dev/packages/motrgem)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful command-line tool that automatically extracts hardcoded text strings from Flutter widgets and converts them to l10n (localization) format.

## Installation

### Option 1: Quick Install (Recommended for Dev Dependency)

Run this command in your Flutter project:

```bash
flutter pub add dev:motrgem
```

This automatically adds `motrgem` to your `dev_dependencies` and runs `flutter pub get`.

### Option 2: Global Installation (Recommended for CLI Tool)

Install globally to use the `motrgem` command anywhere:

```bash
dart pub global activate motrgem
```

**Verify installation:**

```bash
motrgem --help
```

### Option 3: Manual Installation

Add to your `pubspec.yaml`:

```yaml
dev_dependencies:
  motrgem: ^1.1.1
```

Then run:

```bash
flutter pub get
```

---

**Command Usage:**

- **Global install**: `motrgem start`, `motrgem --replace`
- **Dev dependency**: `dart run motrgem start`, `dart run motrgem --replace`

## 🤖 AI Prompt

Using an AI coding assistant (Claude Code, Cursor, Copilot Chat, etc.) in your Flutter project? Paste this prompt in and it will drive `motrgem` for you correctly, including the manual review steps the CLI can't do on its own:

```
This Flutter project should use the `motrgem` package to extract hardcoded
text into Flutter's l10n system. Please:

1. Add it as a dev dependency: `flutter pub add dev:motrgem`
2. If the project has no `l10n.yaml` / `lib/l10n` yet, run:
   `dart run motrgem start`
3. Run `dart run motrgem --dry-run` and show me what would be extracted
   before changing anything.
4. If I approve, run `dart run motrgem --replace` to extract the strings,
   update `lib/l10n/app_en.arb`, and rewrite the call sites.
5. After that finishes, run `flutter analyze` and fix anything it flags,
   in particular:
   - any remaining `const` on a widget that now calls
     `AppLocalizations.of(context)!.xxx` (remove the `const`)
   - any file missing the
     `import 'package:<package_name>/l10n/app_localizations.dart';` import
   - any ARB entry with `{value1}`/`{value2}`-style placeholders that needs
     its generated method call reviewed for correct argument order
6. Run `flutter gen-l10n` (or `flutter pub get`) to regenerate
   `AppLocalizations`, and confirm the app still builds.
7. Check `lib/l10n/possible_hardcoded_texts.txt` (motrgem writes it whenever
   it finds text it couldn't safely auto-fix: custom-widget/exception
   constructor args, `validator:` closures, const string lists). For each
   entry, either localize it by hand or add it to `motrgem.yaml`'s
   `extra_widgets`/`extra_text_params` so future runs handle it
   automatically, then re-run `dart run motrgem --replace`.
8. Ask me which locales to add, then run
   `dart run motrgem --add-locale <code>` for each one and tell me to
   review the machine translations in `lib/l10n/app_<code>.arb` before
   shipping.

Do not hand-write translations yourself — only use motrgem's ARB output.
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

## Beyond SDK Widgets: Possible Hardcoded Text & Custom Sinks

Auto-extraction only ever touches the SDK widgets/parameters above — it never rewrites your own
reusable widgets, since it can't safely assume every call site has the same `BuildContext`
availability an SDK widget does. Real apps route a lot of copy through those custom widgets
anyway (e.g. `MyStatCard(label: 'Bookings')` that internally does `Text(label)`), so instead of
staying silent about it, every `--dry-run`/`--replace` run also **scans and reports** (without
auto-fixing) these patterns:

- String arguments passed to a **locally-declared class constructor** motrgem doesn't recognize
  (covers custom widgets *and* custom exception/error classes, e.g. `throw AuthError(message:
  'Your session has expired.')`) — arguments named like non-display data (`key`, `id`, `value`,
  `color`, `url`, `icon`, `route`, `type`, `code`, `tag`, `asset`, `path`) are skipped
- String literals inside a **`validator:` closure** (form-field validators)
- Elements of a **`const`/plain `List<String>`** variable (e.g. `const kDaysOfWeek = ['Monday',
  ...]`)
- Text that *does* match a recognized widget+parameter, but has **no `BuildContext` resolvable in
  its lexical scope** (e.g. inside a callback like `getTitlesWidget: (value, meta) { ... }`, or a
  helper method that isn't `build(BuildContext context)`) — auto-replacing this would emit
  `Undefined name 'context'`, so it's reported instead of silently leaving broken code. Note that
  a closure defined *inline inside* `build(BuildContext context)` still gets auto-replaced even
  without its own `context` parameter, since Dart closures capture the enclosing scope; only
  genuinely BuildContext-less scopes are reported. When a different-named context parameter (e.g.
  `ctx`) is what's actually in scope, the generated call site correctly uses that name instead of
  a hardcoded `context`.

If anything is found, you'll see a console summary and a full list written to
`lib/l10n/possible_hardcoded_texts.txt` — review it and either localize those spots by hand, or
configure motrgem to auto-handle them (next section).

### Configuring extra sinks (`motrgem.yaml`)

To make motrgem treat your own design-system components exactly like `Text`/`AppBar` (full
extraction *and* auto-replacement, not just a report), add an optional `motrgem.yaml` at your
project root:

```yaml
extra_widgets:
  MyStatCard:
    - label
    - subtitle
extra_text_params:
  - placeholder
```

- `extra_widgets` maps a class name to the parameter names on it that hold display text.
- `extra_text_params` adds parameter names recognized on *any* widget (built-in or custom).

Widgets configured this way are also excluded from the possible-hardcoded-text report, since
they're now fully handled instead of merely flagged.

## Nullable Interpolations

When an interpolated expression has a nullable static type (e.g. `Text('Error: ${snapshot.error}')`
where `snapshot.error` is `Object?`), `flutter gen-l10n` always types the generated ARB placeholder
as a non-nullable `Object`, so a bare nullable argument would fail `flutter analyze`. By default
motrgem coerces it at the call site instead of guessing at your app's copy:

```dart
AppLocalizations.of(context)!.errorMessage(snapshot.error?.toString() ?? '')
```

If you'd rather be alerted than have motrgem silently fall back to an empty string for a null
value, pass `--strict-null-handling`: any nullable interpolation is skipped (reported the same way
as other possible-hardcoded-text findings) and the run exits non-zero instead of applying the
default coercion.

## Usage

### Initialize Project (First Time Setup)

Initialize a Flutter project with l10n support:

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
dart run motrgem --dry-run
```

### Extract and replace

Extract texts, update ARB file, and replace hardcoded strings in your code:

```bash
dart run motrgem --replace
flutter clean
flutter pub get
```

### Const Keyword remove

You should delete all `const` widgets which use AppLocalizations:

**Before:**

```dart
const Text(AppLocalizations.of(context)!.helloWorld)
```

**Should be After:**

```dart
Text(AppLocalizations.of(context)!.helloWorld)
```

### Add a new locale

Create a new locale file (e.g., Spanish, French, Arabic):

```bash
dart run motrgem --add-locale es
dart run motrgem --add-locale fr
dart run motrgem --add-locale ar
flutter clean
flutter pub get
```

> **Note**: If using as a dev dependency, prefix all commands with `dart run`, e.g., `dart run motrgem start`

### Changing Language at Runtime

After setting up localization, you can allow users to change the app language dynamically:

#### 1. Make your app stateful with locale management:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:your_app/l10n/app_localizations.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();

  // Static method to change locale from anywhere in the app
  static void setLocale(BuildContext context, Locale newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}
```

#### 2. Change language from anywhere in your app:

```dart
// Switch to Spanish
MyApp.setLocale(context, const Locale('es'));

// Switch to Arabic
MyApp.setLocale(context, const Locale('ar'));

// Switch to English
MyApp.setLocale(context, const Locale('en'));
```

#### 3. Example: Language selector dropdown:

```dart
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: Localizations.localeOf(context).languageCode,
      items: const [
        DropdownMenuItem(value: 'en', child: Text('English')),
        DropdownMenuItem(value: 'es', child: Text('Español')),
        DropdownMenuItem(value: 'ar', child: Text('العربية')),
        DropdownMenuItem(value: 'fr', child: Text('Français')),
      ],
      onChanged: (String? languageCode) {
        if (languageCode != null) {
          MyApp.setLocale(context, Locale(languageCode));
        }
      },
    );
  }
}
```

## Getting Started

### Quick Start (New Project)

1. Create or navigate to your Flutter project
2. Initialize l10n support:

```bash
dart run motrgem start
```

3. Install dependencies:

```bash
flutter pub get
```

4. Extract and replace texts:

```bash
dart run motrgem --replace
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
└── motrgem.dart                       # CLI tool

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
  2. Run: dart run motrgem --dry-run
  3. Run: dart run motrgem --replace
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
dart test
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
