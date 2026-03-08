import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/word_bank_service.dart';

class DailyWordService {
  static final DailyWordService _instance = DailyWordService._internal();
  factory DailyWordService() => _instance;
  DailyWordService._internal();

  static const String _selectedLanguagesKey = 'daily_word_selected_languages';
  static const String _selectedListsKey = 'daily_word_selected_lists';
  static const String _wordCountKey = 'daily_word_count';
  static const String _lastRefreshDateKey = 'daily_word_last_refresh_date';
  static const String _cachedWordsKey = 'daily_word_cached_words';

  final WordBankService _wordBankService = WordBankService();

  int _wordCount = 5;

  int get wordCount => _wordCount;

  Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }

  Future<void> setWordCount(int count) async {
    _wordCount = count;
    final prefs = await _prefs;
    await prefs.setInt(_wordCountKey, count);
  }

  Future<int> getWordCount() async {
    final prefs = await _prefs;
    _wordCount = prefs.getInt(_wordCountKey) ?? 5;
    return _wordCount;
  }

  Future<void> setSelectedLanguages(List<String> languages) async {
    final prefs = await _prefs;
    await prefs.setStringList(_selectedLanguagesKey, languages);
  }

  Future<List<String>> getSelectedLanguages() async {
    final prefs = await _prefs;
    return prefs.getStringList(_selectedLanguagesKey) ?? [];
  }

  Future<void> setSelectedLists(Map<String, List<String>> lists) async {
    final prefs = await _prefs;
    final flattened = <String>[];
    lists.forEach((lang, listNames) {
      for (final name in listNames) {
        flattened.add('$lang:$name');
      }
    });
    await prefs.setStringList(_selectedListsKey, flattened);
  }

  Future<Map<String, List<String>>> getSelectedLists() async {
    final prefs = await _prefs;
    final flattened = prefs.getStringList(_selectedListsKey) ?? [];
    final result = <String, List<String>>{};
    for (final item in flattened) {
      final parts = item.split(':');
      if (parts.length == 2) {
        final lang = parts[0];
        final listName = parts[1];
        result.putIfAbsent(lang, () => []);
        result[lang]!.add(listName);
      }
    }
    return result;
  }

  int _getDailySeed() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<List<String>> getDailyWords() async {
    final prefs = await _prefs;
    final languages = await getSelectedLanguages();
    final listsMap = await getSelectedLists();
    final count = await getWordCount();

    if (languages.isEmpty) {
      return [];
    }

    final todayDate = _getTodayDateString();
    final lastRefreshDate = prefs.getString(_lastRefreshDateKey);
    final cachedWords = prefs.getStringList(_cachedWordsKey) ?? [];

    if (lastRefreshDate == todayDate && cachedWords.isNotEmpty) {
      return cachedWords;
    }

    final allWords = <Map<String, dynamic>>[];

    for (final language in languages) {
      final listNames = listsMap[language];
      if (listNames != null && listNames.isNotEmpty) {
        for (final listName in listNames) {
          final words = await _wordBankService.getWordsByList(
            language,
            listName,
          );
          for (final w in words) {
            final wordWithLang = Map<String, dynamic>.from(w);
            wordWithLang['language'] = language;
            allWords.add(wordWithLang);
          }
        }
      } else {
        final words = await _wordBankService.getWordsByLanguage(language);
        for (final w in words) {
          final wordWithLang = Map<String, dynamic>.from(w);
          wordWithLang['language'] = language;
          allWords.add(wordWithLang);
        }
      }
    }

    if (allWords.isEmpty) {
      return [];
    }

    final words = allWords.map((w) => Map<String, dynamic>.from(w)).toList();
    final currentSeed = _getDailySeed();
    final random = Random(currentSeed);
    words.shuffle(random);

    final selectedWords = words
        .take(count)
        .map((w) => w['word'] as String)
        .toList();

    await prefs.setString(_lastRefreshDateKey, todayDate);
    await prefs.setStringList(_cachedWordsKey, selectedWords);

    return selectedWords;
  }

  Future<List<String>> refreshDailyWords() async {
    final prefs = await _prefs;
    final count = await getWordCount();
    final languages = await getSelectedLanguages();
    final listsMap = await getSelectedLists();

    if (languages.isEmpty) {
      return [];
    }

    final allWords = <Map<String, dynamic>>[];

    for (final language in languages) {
      final listNames = listsMap[language];
      if (listNames != null && listNames.isNotEmpty) {
        for (final listName in listNames) {
          final words = await _wordBankService.getWordsByList(
            language,
            listName,
          );
          for (final w in words) {
            final wordWithLang = Map<String, dynamic>.from(w);
            wordWithLang['language'] = language;
            allWords.add(wordWithLang);
          }
        }
      } else {
        final words = await _wordBankService.getWordsByLanguage(language);
        for (final w in words) {
          final wordWithLang = Map<String, dynamic>.from(w);
          wordWithLang['language'] = language;
          allWords.add(wordWithLang);
        }
      }
    }

    if (allWords.isEmpty) {
      return [];
    }

    final random = Random(DateTime.now().millisecondsSinceEpoch);
    allWords.shuffle(random);

    final selectedWords = allWords
        .take(count)
        .map((w) => w['word'] as String)
        .toList();

    final todayDate = _getTodayDateString();
    await prefs.setString(_lastRefreshDateKey, todayDate);
    await prefs.setStringList(_cachedWordsKey, selectedWords);

    return selectedWords;
  }

  Future<List<String>> getAvailableLanguages() async {
    final languages = <String>[];
    final prefs = await _prefs;
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('word_list_columns_')) {
        final lang = key.substring('word_list_columns_'.length);
        languages.add(lang);
      }
    }

    if (languages.isEmpty) {
      try {
        final allLanguages = await _wordBankService.getSupportedLanguages();
        languages.addAll(allLanguages);
      } catch (_) {}
    }

    return languages;
  }

  Future<List<WordListInfo>> getAvailableLists(String language) async {
    return await _wordBankService.getWordLists(language);
  }

  Future<String> getWordLanguage(String word) async {
    final listsMap = await getSelectedLists();
    final languages = await getSelectedLanguages();

    for (final language in languages) {
      final listNames = listsMap[language];
      if (listNames != null && listNames.isNotEmpty) {
        for (final listName in listNames) {
          final words = await _wordBankService.getWordsByList(
            language,
            listName,
          );
          for (final w in words) {
            if (w['word'] == word) {
              return language;
            }
          }
        }
      } else {
        final words = await _wordBankService.getWordsByLanguage(language);
        for (final w in words) {
          if (w['word'] == word) {
            return language;
          }
        }
      }
    }

    return languages.isNotEmpty ? languages.first : 'en';
  }
}
