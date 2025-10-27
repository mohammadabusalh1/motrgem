# Publishing Motrgem to pub.dev

This guide explains how to publish the Motrgem package to pub.dev.

## Prerequisites

1. **Create a pub.dev account**

   - Go to https://pub.dev
   - Sign in with your Google account

2. **Install/Update Dart SDK**

   ```bash
   # Check your Dart version
   dart --version
   ```

3. **Update Package URLs**
   - Replace `yourusername` in `pubspec.yaml` with your actual GitHub username or organization
   - Update the repository URLs if needed

## Pre-Publishing Checklist

### 1. Update pubspec.yaml

Make sure these fields are filled correctly:

```yaml
name: motrgem
description: A Flutter localization tool that automatically extracts hardcoded texts from widgets and converts them to l10n format.
version: 1.0.0
homepage: https://github.com/yourusername/motrgem
repository: https://github.com/yourusername/motrgem
issue_tracker: https://github.com/yourusername/motrgem/issues
```

### 2. Verify Package Structure

Ensure you have these files:

- ✅ `pubspec.yaml` - Package metadata
- ✅ `README.md` - Package documentation
- ✅ `CHANGELOG.md` - Version history
- ✅ `LICENSE` - License file (MIT)
- ✅ `lib/` - Library code
- ✅ `bin/motrgem.dart` - Executable entry point
- ✅ `example/` - Usage examples

### 3. Clean Up Flutter App Files (Optional)

Remove these directories if not needed for the package:

```bash
# These are Flutter app files, not needed for a CLI package
# You can remove them or keep them for testing
# - android/
# - ios/
# - linux/
# - macos/
# - windows/
# - web/
# - test/ (unless you add proper tests)
# - lib/main.dart (sample app)
```

### 4. Run Package Analysis

```bash
# Analyze your package
dart analyze

# Check for publishing issues
dart pub publish --dry-run
```

Fix any errors or warnings that appear.

### 5. Format Code

```bash
# Format all Dart files
dart format .
```

### 6. Test the Package Locally

Test the package before publishing:

```bash
# Run the executable
dart run bin/motrgem.dart --help
dart run bin/motrgem.dart start --help
```

## Publishing Steps

### 1. Dry Run

First, do a dry run to see what would be published:

```bash
dart pub publish --dry-run
```

This will show you:

- Which files will be included
- Package size
- Any warnings or errors

### 2. Publish to pub.dev

When ready, publish the package:

```bash
dart pub publish
```

You'll be asked to:

1. Review the files that will be published
2. Confirm publishing
3. Authenticate via browser (first time only)

### 3. Verify Publication

After publishing:

1. Visit https://pub.dev/packages/motrgem
2. Check that all information is correct
3. Test installation in a new project

## Using the Published Package

Once published, users can install it globally:

```bash
# Install globally
dart pub global activate motrgem

# Use anywhere
motrgem start
motrgem --help
```

Or add to `pubspec.yaml`:

```yaml
dev_dependencies:
  motrgem: ^1.0.0
```

Then run:

```bash
dart run motrgem start
```

## Updating the Package

### 1. Make Changes

Update your code as needed.

### 2. Update Version

Update the version in `pubspec.yaml` following [semantic versioning](https://semver.org/):

- `1.0.0` → `1.0.1` for bug fixes
- `1.0.0` → `1.1.0` for new features (backwards compatible)
- `1.0.0` → `2.0.0` for breaking changes

### 3. Update CHANGELOG.md

Add your changes to `CHANGELOG.md`:

```markdown
## 1.0.1

- Fixed bug in text extraction
- Improved error messages

## 1.0.0

- Initial release
```

### 4. Publish Update

```bash
dart pub publish --dry-run
dart pub publish
```

## Important Notes

### Package Score

pub.dev gives packages a score based on:

- **Documentation** - Good README, API docs, examples
- **Platform Support** - Works on multiple platforms
- **Maintenance** - Regular updates, responsive to issues
- **Dependencies** - Up-to-date, minimal dependencies

### Best Practices

1. **Keep README Updated** - Clear installation and usage instructions
2. **Add Examples** - Show real-world usage
3. **Write Tests** - Ensure code quality
4. **Respond to Issues** - Be active on GitHub
5. **Follow Semantic Versioning** - Don't break backwards compatibility in minor updates
6. **Add API Documentation** - Use `///` comments for public APIs

### Common Issues

**Issue**: Package name already taken

- **Solution**: Choose a different name in `pubspec.yaml`

**Issue**: Validation errors

- **Solution**: Run `dart pub publish --dry-run` and fix issues

**Issue**: Authentication fails

- **Solution**: Make sure you're logged into Google and pub.dev

**Issue**: Files too large

- **Solution**: Add unnecessary files to `.gitignore`

## Resources

- [Publishing Packages (dart.dev)](https://dart.dev/tools/pub/publishing)
- [Package Layout Conventions](https://dart.dev/tools/pub/package-layout)
- [Semantic Versioning](https://semver.org/)
- [Writing Package Documentation](https://dart.dev/guides/libraries/writing-package-pages)
