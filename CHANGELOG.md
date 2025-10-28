## 1.0.2

- Added automatic MaterialApp configuration with localization delegates
- Automatically configures `localizationsDelegates` and `supportedLocales` in MaterialApp
- Added automatic translation when creating new locale files using `--add-locale`
- Automatically translates all texts using Google Translate
- Fixed import statement to use correct package name format: `package:[PackageName]/l10n/app_localizations.dart`
- Added automatic execution of Flutter commands after code replacement
- Automatically runs `flutter clean`, `flutter pub get`, and `flutter gen-l10n` after replacing texts
- Improved user experience with automatic localization file generation

## 1.0.1

- Fixed bug in `start` command that was malforming pubspec.yaml when adding dependencies
- Improved dependency insertion to properly format YAML structure
- Added duplicate dependency check to prevent adding same dependency twice

## 1.0.0

- Initial release
- Extract hardcoded text strings from Flutter widgets
- Generate unique IDs in camelCase format
- Update ARB files with extracted texts
- Replace hardcoded strings with AppLocalizations calls
- Support for multiple locales
- Initialize projects with `start` command
- Support for common Flutter widgets (Text, Button, AppBar, etc.)
