# Motrgem Example

This example shows how to use Motrgem to add localization to your Flutter project.

## Installation

Add this to your `pubspec.yaml` dev_dependencies:

```yaml
dev_dependencies:
  motrgem: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Usage

### 1. Initialize Your Project

```bash
dart run motrgem start
```

This will:

- Add necessary dependencies to your `pubspec.yaml`
- Create `l10n.yaml` configuration
- Create `lib/l10n` directory
- Create initial `app_en.arb` file

### 2. Run Flutter Pub Get

```bash
flutter pub get
```

### 3. Extract Texts (Dry Run)

See what texts will be extracted:

```bash
dart run motrgem --dry-run
```

### 4. Extract and Replace Texts

```bash
dart run motrgem --replace
```

### 5. Add Localization Support to Your App

Update your `main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePage(),
    );
  }
}
```

### 6. Generate Localization Files

```bash
flutter gen-l10n
```

Or simply run:

```bash
flutter pub get
```

### 7. Add More Locales

```bash
dart run motrgem --add-locale es
dart run motrgem --add-locale fr
dart run motrgem --add-locale ar
```

## Before and After

### Before

```dart
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('My App'),
    ),
    body: Center(
      child: Text('Hello World'),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {},
      tooltip: 'Add',
      child: Icon(Icons.add),
    ),
  );
}
```

### After

```dart
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context)!.myApp),
    ),
    body: Center(
      child: Text(AppLocalizations.of(context)!.helloWorld),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {},
      tooltip: AppLocalizations.of(context)!.add,
      child: Icon(Icons.add),
    ),
  );
}
```

### Generated ARB File

```json
{
  "@@locale": "en",
  "myApp": "My App",
  "@myApp": {
    "description": "Text from Text in main.dart"
  },
  "helloWorld": "Hello World",
  "@helloWorld": {
    "description": "Text from Text in main.dart"
  },
  "add": "Add",
  "@add": {
    "description": "Text from FloatingActionButton.tooltip in main.dart"
  }
}
```
