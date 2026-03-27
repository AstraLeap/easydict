# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EasyDict is a cross-platform Flutter dictionary application supporting Windows, macOS, Linux, Android, and iOS. It uses a custom SQLite-based dictionary format with zstd compression for efficient storage and fast lookups.

## Commands

```bash
flutter pub get           # Install dependencies
flutter run               # Run the application
flutter build windows     # Build for Windows
flutter build apk         # Build for Android
flutter build macos       # Build for macOS
flutter build linux       # Build for Linux
flutter test              # Run tests
flutter analyze           # Run static analysis
```

### Build Flags

```bash
--dart-define=ENABLE_LOG=true    # Enable logging (disabled by default)
--dart-define=LOG_TO_FILE=true   # Write logs to file (for Release debugging)
```

## Architecture

```
lib/
├── main.dart                    # Entry point with global error handling
├── pages/                       # UI screens (search, settings, detail pages)
├── services/                    # Business logic (dictionary, database, download, AI)
├── models/                      # Data models
├── components/                  # Reusable UI widgets
│   └── rendering/               # Component rendering engine
├── core/                        # Utilities (theme, logger, locale)
├── data/                        # Data layer (database services, models)
└── i18n/                        # Internationalization (slang package)
```

- **State Management**: Provider pattern
- **Database**: SQLite via sqflite package
- **i18n**: slang package with JSON translation files in `lib/i18n/`

## Dictionary Format

Dictionaries are stored in SQLite databases with zstd compression:

- `dictionary.db` - Main dictionary with entries and indices tables
- `media.db` - Audio and image resources
- `metadata.json` - Dictionary metadata (id, languages, version, etc.)

The `entries` table stores compressed JSON data; the `indices` table enables fast lookups on normalized headwords and phonetics.

## Dictionary Building

Use `auxi_tools/build_dictionary.py` to generate dictionary databases from JSONL source files:

```bash
python auxi_tools/build_dictionary.py data/entries.jsonl ja \
    --audio-dir data/audio \
    --image-dir data/image \
    --groups data/groups.jsonl \
    -o output/my_dict
```

See README.md for the complete dictionary JSON schema and text formatting syntax.

## Key Services

- `DictionaryManager` - Manages loaded dictionaries and lookups
- `DatabaseService` - SQLite operations
- `DownloadManager` - Dictionary downloads
- `PreferencesService` - User settings
- `AIService` - AI-powered features
