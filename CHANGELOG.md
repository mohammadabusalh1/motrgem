## 1.3.0

- Fixed: `--replace` no longer emits `AppLocalizations.of(context)!...` inside a callback/method with no `BuildContext` actually resolvable in scope (e.g. an `fl_chart`-style `getTitlesWidget` callback, or a helper method that isn't `build(BuildContext context)`), which previously produced `Undefined name 'context'`. The call site now uses whichever BuildContext-typed identifier is genuinely in lexical scope (respecting closure capture — an inline closure inside `build` still resolves correctly — and using the parameter's real name, e.g. `ctx`, not a hardcoded `context`). Text with no BuildContext resolvable is reported instead of silently dropped or turned into broken code.
- Added: string interpolations with a nullable static type (e.g. `Text('Error: ${snapshot.error}')`) are now coerced to a non-null `Object` at the call site by default (`expr?.toString() ?? ''`), fixing `flutter analyze` failures like `The argument type 'X?' can't be assigned to the parameter type 'Object'`. Pass `--strict-null-handling` to skip-and-report these instead of applying the default coercion.
- Improved: the possible-hardcoded-text scan now skips named arguments that look like non-display data (`key`, `id`, `value`, `color`, `url`, `icon`, `route`, `type`, `code`, `tag`, `asset`, `path`) instead of flagging every string literal regardless of parameter name
- Fixed: two remaining `--replace` progress lines (`Added import to X.dart`, `Removed N const keyword(s)...`) are now flushed immediately like the rest, so long runs redirected to a file don't appear to hang between them

## 1.2.0

- Added: motrgem now scans for hardcoded-looking text it can't safely auto-fix — string args passed to your own custom widget/exception classes (e.g. `MyStatCard(label: ...)`, `throw AuthError(message: ...)`), strings inside `validator:` closures, and elements of `const`/plain `List<String>` variables — and reports them (console summary + `lib/l10n/possible_hardcoded_texts.txt`) on every `--dry-run`/`--replace` run instead of silently skipping them. Fixes the "clean run but the app isn't actually fully localized" false-completion problem.
- Added: optional `motrgem.yaml` config (`extra_widgets`, `extra_text_params`) lets a team opt their own design-system components into full auto-extraction + replacement, the same way built-in widgets like `Text` work

## 1.1.2

- Fixed: generated ARB/AppLocalizations ids that collided with Dart reserved words (e.g. `continue`, `new`, `default`) now get a safe suffix (`continueLabel`) instead of producing invalid Dart
- Fixed: strings with multiple `${...}` interpolations now get uniquely-named placeholders (`value1`, `value2`, ...) instead of all colliding on the same name, and the ARB entry now includes a matching `placeholders` metadata block
- Fixed: interpolated expressions spread across adjacent string-literal parts (e.g. multi-line concatenated strings) are no longer dropped — every argument is now collected and passed at the call site
- Fixed: `--replace` now creates `lib/l10n/` automatically if it doesn't exist yet, instead of crashing when the project hasn't been initialized with `start` first
- Improved: the `AppLocalizations` import inserter now recognizes imports with `as`/`show`/`hide` combinators and both quote styles, and correctly respects the actually-modified file set
- Improved: `const` keyword removal now also covers `const [...]` and `const {...}` collection literals (e.g. `items: const [DropdownMenuItem(...)]`), not just widget constructors
- Improved: progress output during `--replace` and `--add-locale` is now flushed immediately so long runs don't appear to hang when output is redirected to a file or pipe
- Added a `test/` suite covering the extraction, ARB, orchestration, and project-init code paths

## 1.0.6

- Fixed duplicate text entries in ARB files
- Now reuses existing IDs for the same text instead of creating duplicates
- Improved text-to-ID mapping for better deduplication
- Added visual feedback when reusing IDs

## 1.0.4

- Updated README with improved installation instructions
- Added comprehensive guide for changing language at runtime
- Improved documentation for const keyword handling
- Enhanced examples and usage documentation

## 1.0.3

- Documentation improvements and bug fixes
- Updated example code

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
