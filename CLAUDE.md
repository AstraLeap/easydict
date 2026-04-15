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
│   ├── component_renderer.dart  # Dictionary entry rendering engine
│   └── rendering/               # Text formatting, ruby layout, decorations
├── core/                        # Utilities (theme, logger, locale)
├── data/                        # Data layer (database services, models)
└── i18n/                        # Internationalization (slang package)
```

### Key Architectural Patterns

- **State Management**: Provider pattern with `ChangeNotifier` providers registered in `main.dart`
- **Singleton Services**: Most services use factory constructor singleton pattern (e.g., `DictionaryManager`, `PreferencesService`)
- **Database**: SQLite via sqflite package with connection pooling in `DictionaryManager`
- **i18n**: slang package with JSON translation files in `lib/i18n/` (en.i18n.json, zh.i18n.json)

### Entry Rendering System

Dictionary entries are rendered declaratively from JSON:

1. `ComponentRenderer` widget recursively renders entry JSON structures
2. `formatted_text_parser.dart` handles text formatting syntax like `[text](bold)`, `[text](->headword)` for cross-references
3. Supports special rendering: ruby text (Japanese furigana), labels, inline images, audio playback

## Dictionary Format

Dictionaries are stored in SQLite databases with zstd compression:

- `dictionary.db` - Main dictionary with entries, indices, and groups tables
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

| Service | Purpose |
|---------|---------|
| `DictionaryManager` | Manages loaded dictionaries, database connections, and lookups |
| `PreferencesService` | User settings persistence via SharedPreferences |
| `DownloadManager` | Dictionary download progress and state |
| `AIService` | AI-powered features using LLM |
| `FontLoaderService` | Custom font loading and UI scaling |
| `ZstdService` | Zstd compression/decompression for dictionary entries |
| `ClipboardWatcherService` | Clipboard monitoring for quick lookups (desktop) |
| `SystemTrayService` | System tray integration (desktop) |

## Adding New Translations

1. Add keys to `lib/i18n/en.i18n.json` and `lib/i18n/zh.i18n.json`
2. Run `flutter pub run slang` to regenerate `strings.g.dart`
