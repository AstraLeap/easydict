import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'preferences_service.dart';

/// 搜索记录模型
class SearchRecord {
  final String word;
  final DateTime timestamp;
  final bool exactMatch;
  final bool biaoyiExactMatch;
  final String? group;

  SearchRecord({
    required this.word,
    required this.timestamp,
    this.exactMatch = false,
    this.biaoyiExactMatch = false,
    this.group,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'timestamp': timestamp.toIso8601String(),
    'exactMatch': exactMatch,
    'biaoyiExactMatch': biaoyiExactMatch,
    if (group != null) 'group': group,
  };

  factory SearchRecord.fromJson(Map<String, dynamic> json) => SearchRecord(
    word: json['word'] ?? '',
    timestamp: DateTime.parse(
      json['timestamp'] ?? DateTime.now().toIso8601String(),
    ),
    exactMatch: json['exactMatch'] ?? json['caseSensitive'] ?? false,
    biaoyiExactMatch: json['biaoyiExactMatch'] ?? false,
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
    final prefs = await PreferencesService().prefs;
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
    bool exactMatch = false,
    bool biaoyiExactMatch = false,
    String? group,
  }) async {
    if (word.trim().isEmpty) return;

    final prefs = await PreferencesService().prefs;
    List<SearchRecord> records = await getSearchRecords();

    final trimmedWord = word.trim();

    // 移除重复记录，但保留已成功搜索时记录的语言信息
    final existingIdx = records.indexWhere((r) => r.word == trimmedWord);
    final existingGroup = existingIdx >= 0 ? records[existingIdx].group : null;
    records.removeWhere((r) => r.word == trimmedWord);

    // 添加新记录到开头
    // 若未传入 group（语言），则保留该词已记录的语言，避免覆盖
    records.insert(
      0,
      SearchRecord(
        word: trimmedWord,
        timestamp: DateTime.now(),
        exactMatch: exactMatch,
        biaoyiExactMatch: biaoyiExactMatch,
        group: group ?? existingGroup,
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
    final prefs = await PreferencesService().prefs;
    await prefs.remove(_prefKeySearchHistory);
  }

  Future<void> removeSearchRecord(String word) async {
    final prefs = await PreferencesService().prefs;
    List<SearchRecord> records = await getSearchRecords();

    records.removeWhere((r) => r.word == word);

    final jsonList = records.map((r) => r.toJson()).toList();
    await prefs.setString(_prefKeySearchHistory, jsonEncode(jsonList));
  }
}
