import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索记录模型
class SearchRecord {
  final String word;
  final DateTime timestamp;
  final bool useFuzzySearch;
  final bool exactMatch;
  final String? group;

  SearchRecord({
    required this.word,
    required this.timestamp,
    this.useFuzzySearch = false,
    this.exactMatch = false,
    this.group,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'timestamp': timestamp.toIso8601String(),
    'useFuzzySearch': useFuzzySearch,
    'exactMatch': exactMatch,
    if (group != null) 'group': group,
  };

  factory SearchRecord.fromJson(Map<String, dynamic> json) => SearchRecord(
    word: json['word'] ?? '',
    timestamp: DateTime.parse(
      json['timestamp'] ?? DateTime.now().toIso8601String(),
    ),
    useFuzzySearch: json['useFuzzySearch'] ?? false,
    exactMatch: json['exactMatch'] ?? json['caseSensitive'] ?? false,
    group: json['group'],
  );
}

class SearchHistoryService {
  static const String _prefKeySearchHistory = 'search_history_v2';
  static const int _maxHistorySize = 50;

  static final SearchHistoryService _instance =
      SearchHistoryService._internal();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._internal();

  /// 获取搜索历史（兼容旧版本，只返回单词列表）
  Future<List<String>> getSearchHistory() async {
    final records = await getSearchRecords();
    return records.map((r) => r.word).toList();
  }

  /// 获取完整的搜索记录
  Future<List<SearchRecord>> getSearchRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefKeySearchHistory);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => SearchRecord.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加搜索记录（带高级搜索选项）
  Future<void> addSearchRecord(
    String word, {
    bool useFuzzySearch = false,
    bool exactMatch = false,
    String? group,
  }) async {
    if (word.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    List<SearchRecord> records = await getSearchRecords();

    final trimmedWord = word.trim();

    // 移除重复的记录
    records.removeWhere((r) => r.word == trimmedWord);

    // 添加新记录到开头
    records.insert(
      0,
      SearchRecord(
        word: trimmedWord,
        timestamp: DateTime.now(),
        useFuzzySearch: useFuzzySearch,
        exactMatch: exactMatch,
        group: group,
      ),
    );

    // 限制历史记录数量
    if (records.length > _maxHistorySize) {
      records = records.sublist(0, _maxHistorySize);
    }

    // 保存
    final jsonList = records.map((r) => r.toJson()).toList();
    await prefs.setString(_prefKeySearchHistory, jsonEncode(jsonList));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeySearchHistory);
  }

  Future<void> removeSearchRecord(String word) async {
    final prefs = await SharedPreferences.getInstance();
    List<SearchRecord> records = await getSearchRecords();

    records.removeWhere((r) => r.word == word);

    final jsonList = records.map((r) => r.toJson()).toList();
    await prefs.setString(_prefKeySearchHistory, jsonEncode(jsonList));
  }
}
