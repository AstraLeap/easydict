import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'services/dictionary_manager.dart';
import 'services/english_search_service.dart';
import 'services/database_initializer.dart';
import 'logger.dart';

/// 搜索结果，包含 entries 和关系信息
class SearchResult {
  final List<DictionaryEntry> entries;
  final String originalWord;
  final Map<String, List<SearchRelation>> relations;

  SearchResult({
    required this.entries,
    required this.originalWord,
    this.relations = const {},
  });

  bool get hasRelations => relations.isNotEmpty;
}

class DictionaryEntry {
  final String id;
  final String? dictId;
  final String? version;
  final String headword;
  final String entryType;
  final String? page;
  final String? section;
  final List<String> tags;
  final List<String> certifications;
  final Map<String, dynamic> frequency;
  final dynamic etymology;
  final List<Map<String, dynamic>> inflections;
  final List<Map<String, dynamic>> pronunciations;
  final List<Map<String, dynamic>> senses;
  final List<Map<String, dynamic>> boards;
  final Map<String, dynamic>? collocations;
  final Map<String, dynamic>? phrases;
  final Map<String, dynamic>? theasaruses;
  final List<Map<String, dynamic>> senseGroups;
  final List<String> hiddenLanguages;

  DictionaryEntry({
    required this.id,
    this.dictId,
    this.version,
    required this.headword,
    required this.entryType,
    this.page,
    this.section,
    required this.tags,
    required this.certifications,
    required this.frequency,
    this.etymology,
    required this.inflections,
    required this.pronunciations,
    required this.senses,
    required this.boards,
    this.collocations,
    this.phrases,
    this.theasaruses,
    this.senseGroups = const [],
    this.hiddenLanguages = const [],
  });

  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    try {
      return DictionaryEntry(
        id: json['entry_id']?.toString() ?? json['id']?.toString() ?? '',
        dictId: json['dict_id']?.toString(),
        version: json['version']?.toString(),
        headword:
            json['headword']?.toString() ?? json['word']?.toString() ?? '',
        entryType: json['entry_type'] as String? ?? 'word',
        page: json['page']?.toString(),
        section: json['section']?.toString(),
        tags: json['tags'] != null
            ? (json['tags'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        certifications: json['certifications'] != null
            ? (json['certifications'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        frequency: json['frequency'] as Map<String, dynamic>? ?? {},
        etymology: json['etymology'],
        inflections: json['inflections'] != null
            ? (json['inflections'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        pronunciations:
            (json['pronunciation'] ?? json['pronunciations']) != null
            ? ((json['pronunciation'] ?? json['pronunciations'])
                      as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        senses: json['senses'] != null
            ? (json['senses'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        boards: json['boards'] != null
            ? (json['boards'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        collocations: (json['collocations'] is Map<String, dynamic>)
            ? json['collocations'] as Map<String, dynamic>?
            : null,
        phrases: (json['phrases'] is Map<String, dynamic>)
            ? json['phrases'] as Map<String, dynamic>?
            : null,
        theasaruses: (json['theasaruses'] is Map<String, dynamic>)
            ? json['theasaruses'] as Map<String, dynamic>?
            : null,
        senseGroups: json['sense_groups'] != null
            ? (json['sense_groups'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        hiddenLanguages: json['hidden_languages'] != null
            ? (json['hidden_languages'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
      );
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'entry_id': id,
      if (dictId != null) 'dict_id': dictId,
      if (version != null) 'version': version,
      'headword': headword,
      'entry_type': entryType,
      'page': page,
      'section': section,
      'tags': tags,
      'certifications': certifications,
      'frequency': frequency,
      'etymology': etymology,
      'inflections': inflections,
      'pronunciation': pronunciations,
      'senses': senses,
      'boards': boards,
      if (collocations != null) 'collocations': collocations,
      if (phrases != null) 'phrases': phrases,
      if (theasaruses != null) 'theasaruses': theasaruses,
      'sense_groups': senseGroups,
      'hidden_languages': hiddenLanguages,
    };
  }
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final DictionaryManager _dictManager = DictionaryManager();
  Database? _database;
  String? _currentDictionaryId;
  String? _cachedDatabasePath;

  Future<String> get currentDictionaryId async {
    if (_currentDictionaryId != null) return _currentDictionaryId!;

    final installedDicts = await _dictManager.getInstalledDictionaries();
    if (installedDicts.isEmpty) {
      _currentDictionaryId = 'default';
    } else {
      _currentDictionaryId = installedDicts.first;
    }

    return _currentDictionaryId!;
  }

  Future<void> setCurrentDictionary(String dictionaryId) async {
    if (_currentDictionaryId == dictionaryId) return;

    await close();
    _currentDictionaryId = dictionaryId;
    _cachedDatabasePath = null;
  }

  Future<String> get databasePath async {
    if (_cachedDatabasePath != null) return _cachedDatabasePath!;

    final dictId = await currentDictionaryId;
    final dbPath = await _dictManager.getDictionaryDbPath(dictId);

    if (!await File(dbPath).exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    _cachedDatabasePath = dbPath;
    return _cachedDatabasePath!;
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase(readOnly: true);
    return _database!;
  }

  /// 获取可写的数据库实例（用于编辑）
  Future<Database> get writableDatabase async {
    final String dbPath = await databasePath;
    final File dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    Logger.d('writableDatabase: 打开可写数据库: $dbPath', tag: 'DatabaseService');

    return await openDatabase(
      dbPath,
      version: 1,
      readOnly: false,
      onCreate: (db, version) {
        Logger.d('Creating database schema...', tag: 'DatabaseService');
      },
    );
  }

  Future<Database> _initDatabase({bool readOnly = true}) async {
    final String dbPath = await databasePath;
    final File dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    Logger.d(
      '_initDatabase: 打开数据库 (readOnly=$readOnly): $dbPath',
      tag: 'DatabaseService',
    );

    // 只读模式下不设置 version 和 onCreate，避免触发写入操作
    if (readOnly) {
      return await openDatabase(dbPath, readOnly: true);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      readOnly: readOnly,
      onCreate: (db, version) {
        Logger.d('Creating database schema...', tag: 'DatabaseService');
      },
    );
  }

  Future<DictionaryEntry?> searchWord(String word) async {
    return getEntry(word);
  }

  /// 规范化搜索词：小写化并去除音调符号
  String _normalizeSearchWord(String word) {
    // 小写化
    String normalized = word.toLowerCase();
    // 去除音调符号（Unicode组合字符）
    normalized = normalized.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
    return normalized;
  }

  /// 简单的语言检测
  String _detectLanguage(String text) {
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    return 'en';
  }

  Future<SearchResult> getAllEntries(
    String word, {
    bool useFuzzySearch = false,
    bool exactMatch = false, // 对应"区分大小写"
    String? sourceLanguage,
  }) async {
    var entries = <DictionaryEntry>[];
    var relations = <String, List<SearchRelation>>{};

    // 1. 尝试直接搜索
    entries = await _searchEntriesInternal(
      word,
      useFuzzySearch: useFuzzySearch,
      exactMatch: exactMatch,
      sourceLanguage: sourceLanguage,
    );

    // 2. 如果没有结果，且未开启模糊搜索，且是英语环境，尝试辅助搜索
    if (entries.isEmpty && !useFuzzySearch) {
      // 检查语言环境
      String? targetLang = sourceLanguage;
      if (targetLang == 'auto') {
        targetLang = _detectLanguage(word);
      }

      if (targetLang == 'en' || targetLang == 'auto') {
        final englishService = EnglishSearchService();

        try {
          relations = await englishService.searchWithRelations(word);

          for (final relatedWord in relations.keys) {
            final relatedEntries = await _searchEntriesInternal(
              relatedWord,
              useFuzzySearch: false,
              exactMatch: exactMatch,
              sourceLanguage: sourceLanguage,
            );
            entries.addAll(relatedEntries);
          }
        } catch (e) {
          // Error handling without debug output
        }
      }
    }

    return SearchResult(
      entries: entries,
      originalWord: word,
      relations: relations,
    );
  }

  /// 内部搜索方法：针对特定单词在所有启用词典中搜索
  Future<List<DictionaryEntry>> _searchEntriesInternal(
    String word, {
    required bool useFuzzySearch,
    required bool exactMatch,
    String? sourceLanguage,
  }) async {
    final entries = <DictionaryEntry>[];
    final dictManager = DictionaryManager();
    final enabledDicts = await dictManager.getEnabledDictionariesMetadata();

    // 处理自动分组
    String? targetLang = sourceLanguage;
    if (targetLang == 'auto') {
      targetLang = _detectLanguage(word);
    }

    for (final metadata in enabledDicts) {
      // 过滤语言
      if (targetLang != null && targetLang != metadata.sourceLanguage) {
        continue;
      }

      try {
        final db = await dictManager.openDictionaryDatabase(metadata.id);

        // Step 1: 基础检索 (headword_normalized)
        // 无论是否模糊搜索，都将搜索词小写化后匹配 headword_normalized
        String whereClause;
        List<dynamic> whereArgs;

        if (useFuzzySearch) {
          // 模糊搜索
          whereClause = 'headword_normalized LIKE ?';
          whereArgs = ['%${_normalizeSearchWord(word)}%'];
        } else {
          // 直接搜索 (精确匹配 normalized 字段)
          whereClause = 'headword_normalized = ?';
          whereArgs = [_normalizeSearchWord(word)];
        }

        final results = await db.query(
          'entries',
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: 'entry_id ASC',
        );

        for (final row in results) {
          final jsonStr = row['json_data'] as String;
          final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

          // Step 2: 区分大小写过滤
          if (exactMatch) {
            final headword = jsonData['headword'] as String? ?? '';
            // 如果开启区分大小写，则要求 headword 与原始搜索词完全一致
            if (headword != word) continue;
          }

          _ensureEntryId(jsonData, row, metadata.id);
          entries.add(DictionaryEntry.fromJson(jsonData));
        }

        await db.close();
      } catch (e) {
        // Error handling without debug output
      }
    }

    return entries;
  }

  /// 确保条目ID包含词典ID前缀
  void _ensureEntryId(
    Map<String, dynamic> jsonData,
    Map<String, dynamic> row,
    String dictId,
  ) {
    String entryId = jsonData['id']?.toString() ?? '';
    if (entryId.isEmpty) {
      // entry_id 现在是整型，需要转换为字符串
      final rawEntryId = row['entry_id'];
      final entryIdStr = rawEntryId?.toString() ?? '';
      entryId = '${dictId}_$entryIdStr';
      jsonData['id'] = entryId;
    } else if (!entryId.startsWith('${dictId}_')) {
      entryId = '${dictId}_$entryId';
      jsonData['id'] = entryId;
    }
  }

  Future<DictionaryEntry?> getEntry(String word) async {
    try {
      final db = await database;

      // 默认使用headword_normalized进行搜索（规范化匹配）
      final String whereClause = 'headword_normalized = ?';

      final List<Map<String, dynamic>> results = await db.query(
        'entries',
        where: whereClause,
        whereArgs: [_normalizeSearchWord(word)],
        limit: 1,
      );

      if (results.isEmpty) {
        return null;
      }

      final jsonStr = results.first['json_data'] as String;
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      return DictionaryEntry.fromJson(jsonData);
    } catch (e) {
      return null;
    }
  }

  /// 前缀搜索 - 用于边打边搜功能
  /// 返回匹配前缀的单词列表（去重，限制数量）
  Future<List<String>> searchByPrefix(
    String prefix, {
    int limit = 10,
    String? sourceLanguage,
  }) async {
    if (prefix.isEmpty) return [];

    final results = <String>{};
    final dictManager = DictionaryManager();
    final enabledDicts = await dictManager.getEnabledDictionariesMetadata();

    // 处理自动分组
    String? targetLang = sourceLanguage;
    if (targetLang == 'auto') {
      targetLang = _detectLanguage(prefix);
    }

    for (final metadata in enabledDicts) {
      // 过滤语言
      if (targetLang != null && targetLang != metadata.sourceLanguage) {
        continue;
      }

      try {
        final db = await dictManager.openDictionaryDatabase(metadata.id);

        // 前缀搜索始终使用 headword_normalized
        const whereClause = 'headword_normalized LIKE ?';
        final whereArgs = ['${_normalizeSearchWord(prefix)}%'];

        final queryResults = await db.query(
          'entries',
          columns: ['headword'],
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: 'headword ASC',
          limit: limit,
        );

        for (final row in queryResults) {
          final headword = row['headword'] as String?;
          if (headword != null && headword.isNotEmpty) {
            results.add(headword);
            if (results.length >= limit) break;
          }
        }

        await db.close();
        if (results.length >= limit) break;
      } catch (e) {
        // Error handling without debug output
      }
    }

    return results.toList()..sort();
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// 更新词典条目
  Future<bool> updateEntry(DictionaryEntry entry) async {
    try {
      final dictId = entry.dictId;
      if (dictId == null) {
        return false;
      }

      final dictManager = DictionaryManager();
      final dbPath = await dictManager.getDictionaryDbPath(dictId);

      if (!await File(dbPath).exists()) {
        return false;
      }

      // 使用统一的数据库初始化器
      DatabaseInitializer().initialize();

      final db = await openDatabase(dbPath, readOnly: false);

      try {
        final jsonStr = jsonEncode(entry.toJson());

        // 从 entry.id 中提取纯数字的 entry_id
        // entry.id 格式可能是 "dictId_entryId" 或直接是 "entryId"
        final String idStr = entry.id;
        int? entryId;

        // 尝试直接解析
        entryId = int.tryParse(idStr);

        // 如果失败，尝试从 "dictId_entryId" 格式中提取
        if (entryId == null && idStr.contains('_')) {
          final parts = idStr.split('_');
          if (parts.length >= 2) {
            entryId = int.tryParse(parts.last);
          }
        }

        if (entryId == null) {
          return false;
        }

        final result = await db.update(
          'entries',
          {'json_data': jsonStr},
          where: 'entry_id = ?',
          whereArgs: [entryId],
        );

        return result > 0;
      } finally {
        await db.close();
      }
    } catch (e) {
      return false;
    }
  }
}
