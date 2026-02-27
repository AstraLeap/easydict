import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../services/dictionary_manager.dart';
import '../services/english_search_service.dart';
import '../services/zstd_service.dart';
import 'services/database_initializer.dart';
import '../core/logger.dart';

Map<String, dynamic> _parseJsonInIsolate(String jsonStr) {
  return Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
}

class JsonParseParams {
  final String jsonStr;
  final String dictId;
  final Map<String, dynamic> row;
  final bool exactMatch;
  final String originalWord;

  JsonParseParams({
    required this.jsonStr,
    required this.dictId,
    required this.row,
    required this.exactMatch,
    required this.originalWord,
  });
}

DictionaryEntry? _parseEntryInIsolate(JsonParseParams params) {
  final jsonData = jsonDecode(params.jsonStr) as Map<String, dynamic>;

  if (params.exactMatch) {
    final headword = jsonData['headword'] as String? ?? '';
    if (headword != params.originalWord) return null;
  }

  String entryId = jsonData['id']?.toString() ?? '';
  if (entryId.isEmpty) {
    final rawEntryId = params.row['entry_id'];
    final entryIdStr = rawEntryId?.toString() ?? '';
    entryId = '${params.dictId}_$entryIdStr';
    jsonData['id'] = entryId;
    jsonData['entry_id'] = entryId;
  } else if (!entryId.startsWith('${params.dictId}_')) {
    entryId = '${params.dictId}_$entryId';
    jsonData['id'] = entryId;
    jsonData['entry_id'] = entryId;
  }

  return DictionaryEntry.fromJson(jsonData);
}

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
  final List<Map<String, dynamic>> pronunciations;
  final List<Map<String, dynamic>> sense;
  final List<String> phrase;
  final List<Map<String, dynamic>> senseGroup;
  final List<String> hiddenLanguages;
  final Map<String, dynamic> _rawJson;

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
    required this.pronunciations,
    required this.sense,
    this.phrase = const [],
    this.senseGroup = const [],
    this.hiddenLanguages = const [],
    Map<String, dynamic>? rawJson,
  }) : _rawJson = rawJson ?? {};

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
        pronunciations: json['pronunciation'] != null
            ? (json['pronunciation'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        sense: json['sense'] != null
            ? (json['sense'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        phrase: json['phrase'] != null
            ? (json['phrase'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        senseGroup: json['sense_group'] != null
            ? (json['sense_group'] as List<dynamic>)
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
        rawJson: json,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 从复合ID中提取纯数字entry_id（去掉dict_id前缀）
  String get _pureEntryId {
    if (id.contains('_')) {
      final parts = id.split('_');
      if (parts.length >= 2) {
        final lastPart = parts.last;
        if (int.tryParse(lastPart) != null) {
          return lastPart;
        }
      }
    }
    return id;
  }

  /// 从复合ID中提取纯数字entry_id作为整型（去掉dict_id前缀）
  int get _pureEntryIdAsInt {
    final pureId = _pureEntryId;
    return int.tryParse(pureId) ?? 0;
  }

  Map<String, dynamic> toJson() {
    if (_rawJson.isNotEmpty) {
      final result = Map<String, dynamic>.from(_rawJson);
      // 保存时使用纯数字的entry_id，去掉dict_id前缀，并转换为整型
      result['entry_id'] = _pureEntryIdAsInt;
      return result;
    }
    return {
      'entry_id': _pureEntryIdAsInt,
      if (dictId != null) 'dict_id': dictId,
      'headword': headword,
      'entry_type': entryType,
      'page': page,
      'section': section,
      'tags': tags,
      'certifications': certifications,
      'frequency': frequency,
      'etymology': etymology,
      'pronunciation': pronunciations,
      'sense': sense,
      'phrase': phrase,
      'sense_group': senseGroup,
    };
  }
}

/// 从数据库字段中提取JSON字符串（不使用字典）
/// 支持普通字符串和zstd压缩的blob数据
String? extractJsonFromField(dynamic fieldValue) {
  if (fieldValue == null) {
    return null;
  }

  // 如果已经是字符串，直接返回
  if (fieldValue is String) {
    return fieldValue;
  }

  // 如果是字节数组（blob），尝试zstd解压
  if (fieldValue is Uint8List) {
    try {
      final zstdService = ZstdService();
      final decompressed = zstdService.decompressWithoutDict(fieldValue);
      return utf8.decode(decompressed);
    } catch (e) {
      Logger.e('Zstd解压失败: $e', tag: 'DatabaseService');
      // 如果解压失败，尝试直接作为UTF8解码（可能是未压缩的blob）
      try {
        return utf8.decode(fieldValue);
      } catch (_) {
        return null;
      }
    }
  }

  // 其他类型，尝试转字符串
  try {
    return fieldValue.toString();
  } catch (_) {
    return null;
  }
}

/// 使用指定字典从数据库字段中提取JSON字符串
/// 支持普通字符串和zstd压缩的blob数据
String? extractJsonFromFieldWithDict(dynamic fieldValue, Uint8List? dictBytes) {
  if (fieldValue == null) {
    return null;
  }

  // 如果已经是字符串，直接返回
  if (fieldValue is String) {
    return fieldValue;
  }

  // 如果是字节数组（blob），尝试zstd解压（使用字典）
  if (fieldValue is Uint8List) {
    try {
      final zstdService = ZstdService();
      final decompressed = zstdService.decompress(fieldValue, dictBytes);
      return utf8.decode(decompressed);
    } catch (e) {
      Logger.e('Zstd解压失败: $e', tag: 'DatabaseService');
      // 如果解压失败，尝试直接作为UTF8解码（可能是未压缩的blob）
      try {
        return utf8.decode(fieldValue);
      } catch (_) {
        return null;
      }
    }
  }

  // 其他类型，尝试转字符串
  try {
    return fieldValue.toString();
  } catch (_) {
    return null;
  }
}

/// 将JSON对象压缩为zstd格式的blob数据（不使用字典）
/// 使用压缩级别3，返回Uint8List
Uint8List compressJsonToBlob(Map<String, dynamic> jsonData) {
  // 1. 转换为紧凑JSON字符串（无换行、无多余空格）
  final jsonString = jsonEncode(jsonData);

  // 2. 转换为UTF8字节
  final jsonBytes = utf8.encode(jsonString);

  // 3. 使用zstd压缩，级别3
  final zstdService = ZstdService();
  return zstdService.compressWithoutDict(
    Uint8List.fromList(jsonBytes),
    level: 3,
  );
}

/// 使用指定字典将JSON对象压缩为zstd格式的blob数据
/// 使用压缩级别3，返回Uint8List
Uint8List compressJsonToBlobWithDict(
  Map<String, dynamic> jsonData,
  Uint8List? dictBytes,
) {
  // 1. 转换为紧凑JSON字符串（无换行、无多余空格）
  final jsonString = jsonEncode(jsonData);

  // 2. 转换为UTF8字节
  final jsonBytes = utf8.encode(jsonString);

  // 3. 使用zstd压缩（使用字典），级别3
  final zstdService = ZstdService();
  return zstdService.compress(
    Uint8List.fromList(jsonBytes),
    dictBytes,
    level: 3,
  );
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // 静态 RegExp 常量，避免每次调用时重新创建对象
  static final RegExp _diacriticsRegExp = RegExp(r'[\u0300-\u036f]');
  static final RegExp _chineseRegExp = RegExp(r'[\u4e00-\u9fa5]');
  static final RegExp _japaneseRegExp = RegExp(r'[\u3040-\u309f\u30a0-\u30ff]');
  static final RegExp _koreanRegExp = RegExp(r'[\uac00-\ud7af]');

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
    // DictionaryManager 会在关闭数据库时自动清除 zstd 字典缓存
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
    normalized = normalized.replaceAll(_diacriticsRegExp, '');
    return normalized;
  }

  /// 简单的语言检测
  String _detectLanguage(String text) {
    if (_chineseRegExp.hasMatch(text)) return 'zh';
    if (_japaneseRegExp.hasMatch(text)) return 'ja';
    if (_koreanRegExp.hasMatch(text)) return 'ko';
    return 'en';
  }

  Future<SearchResult> getAllEntries(
    String word, {
    bool useFuzzySearch = false,
    bool exactMatch = false,
    String? sourceLanguage,
  }) async {
    var entries = <DictionaryEntry>[];
    var relations = <String, List<SearchRelation>>{};

    entries = await _searchEntriesInternal(
      word,
      useFuzzySearch: useFuzzySearch,
      exactMatch: exactMatch,
      sourceLanguage: sourceLanguage,
    );

    if (entries.isEmpty && !useFuzzySearch) {
      String? targetLang = sourceLanguage;
      if (targetLang == 'auto') {
        targetLang = _detectLanguage(word);
      }

      if (targetLang == 'en' || targetLang == 'auto') {
        Logger.d(
          'DatabaseService: 检测到英语，调用 EnglishSearchService',
          tag: 'EnglishDB',
        );
        final englishService = EnglishSearchService();

        try {
          Logger.d('DatabaseService: 开始搜索关系: $word', tag: 'EnglishDB');
          relations = await englishService
              .searchWithRelations(
                word,
                maxRelatedWords: 10,
                maxRelationsPerWord: 3,
              )
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () {
                  Logger.w('DatabaseService: 关系词搜索超时', tag: 'EnglishDB');
                  return <String, List<SearchRelation>>{};
                },
              );
          Logger.d('DatabaseService: 搜索结果: $relations', tag: 'EnglishDB');

          final relatedWords = relations.keys.toList();
          final limitedWords = relatedWords.take(10).toList();
          final futures = limitedWords.map((relatedWord) {
            return _searchEntriesInternal(
              relatedWord,
              useFuzzySearch: false,
              exactMatch: exactMatch,
              sourceLanguage: sourceLanguage,
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () => <DictionaryEntry>[],
            );
          }).toList();

          final results = await Future.wait(futures).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              Logger.w('DatabaseService: 关联词查询超时', tag: 'EnglishDB');
              return <List<DictionaryEntry>>[];
            },
          );
          for (final result in results) {
            entries.addAll(result);
          }
        } catch (e) {
          Logger.e(
            'DatabaseService: EnglishSearchService 错误: $e',
            tag: 'EnglishDB',
          );
        }
      }
    }

    return SearchResult(
      entries: entries,
      originalWord: word,
      relations: relations,
    );
  }

  Future<List<DictionaryEntry>> _searchEntriesInternal(
    String word, {
    required bool useFuzzySearch,
    required bool exactMatch,
    String? sourceLanguage,
  }) async {
    final dictManager = DictionaryManager();
    final enabledDicts = await dictManager.getEnabledDictionariesMetadata();

    Logger.i(
      '搜索单词: "$word", 启用的词典数量: ${enabledDicts.length}',
      tag: 'DatabaseService',
    );
    for (final dict in enabledDicts) {
      Logger.i(
        '  - 启用的词典: ${dict.name} (${dict.id}), 语言: ${dict.sourceLanguage}',
        tag: 'DatabaseService',
      );
    }

    String? targetLang = sourceLanguage;
    if (targetLang == 'auto') {
      targetLang = _detectLanguage(word);
    }

    Logger.i('检测到的目标语言: $targetLang', tag: 'DatabaseService');

    final filteredDicts = enabledDicts.where((metadata) {
      if (targetLang != null && targetLang != metadata.sourceLanguage) {
        Logger.i(
          '  过滤掉词典 ${metadata.name}: 语言不匹配 (${metadata.sourceLanguage} != $targetLang)',
          tag: 'DatabaseService',
        );
        return false;
      }
      return true;
    }).toList();

    Logger.i('将要搜索的词典数量: ${filteredDicts.length}', tag: 'DatabaseService');
    for (final dict in filteredDicts) {
      Logger.i('  - 将搜索: ${dict.name} (${dict.id})', tag: 'DatabaseService');
    }

    final futures = filteredDicts.map((metadata) async {
      return await _searchInDictionary(
        metadata.id,
        word,
        useFuzzySearch: useFuzzySearch,
        exactMatch: exactMatch,
      );
    }).toList();

    final results = await Future.wait(futures);
    final allEntries = results.expand((list) => list).toList();
    Logger.i('搜索完成，找到 ${allEntries.length} 条结果', tag: 'DatabaseService');
    return allEntries;
  }

  Future<List<DictionaryEntry>> _searchInDictionary(
    String dictId,
    String word, {
    required bool useFuzzySearch,
    required bool exactMatch,
  }) async {
    final entries = <DictionaryEntry>[];

    try {
      Logger.i('正在搜索词典: $dictId', tag: 'DatabaseService');
      final db = await _dictManager.openDictionaryDatabase(dictId);
      Logger.i('成功打开词典数据库: $dictId', tag: 'DatabaseService');

      // 获取该词典的 zstd 字典用于解压
      final zstdDict = await _dictManager.getZstdDictionary(dictId);

      String whereClause;
      List<dynamic> whereArgs;

      if (useFuzzySearch) {
        whereClause = 'headword_normalized LIKE ?';
        whereArgs = ['%${_normalizeSearchWord(word)}%'];
      } else {
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
        // 使用字典解压
        final jsonStr = extractJsonFromFieldWithDict(
          row['json_data'],
          zstdDict,
        );
        if (jsonStr == null) {
          Logger.w('无法解析行数据的json_data字段', tag: 'DatabaseService');
          continue;
        }

        DictionaryEntry? entry;
        if (kIsWeb) {
          final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (exactMatch) {
            final headword = jsonData['headword'] as String? ?? '';
            if (headword != word) continue;
          }
          _ensureEntryId(jsonData, row, dictId);
          entry = DictionaryEntry.fromJson(jsonData);
        } else {
          try {
            entry = await compute(
              _parseEntryInIsolate,
              JsonParseParams(
                jsonStr: jsonStr,
                dictId: dictId,
                row: row,
                exactMatch: exactMatch,
                originalWord: word,
              ),
            );
          } catch (e) {
            final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (exactMatch) {
              final headword = jsonData['headword'] as String? ?? '';
              if (headword != word) continue;
            }
            _ensureEntryId(jsonData, row, dictId);
            entry = DictionaryEntry.fromJson(jsonData);
          }
        }

        if (entry != null) {
          entries.add(entry);
        }
      }
    } catch (e) {
      // Error handling without debug output
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
      final rawEntryId = row['entry_id'];
      final entryIdStr = rawEntryId?.toString() ?? '';
      entryId = '${dictId}_$entryIdStr';
      jsonData['id'] = entryId;
      jsonData['entry_id'] = entryId;
    } else if (!entryId.startsWith('${dictId}_')) {
      entryId = '${dictId}_$entryId';
      jsonData['id'] = entryId;
      jsonData['entry_id'] = entryId;
    }
  }

  Future<DictionaryEntry?> getEntry(String word) async {
    try {
      final db = await database;
      final dictId = await currentDictionaryId;

      // 获取当前词典的 zstd 字典用于解压
      final zstdDict = await _dictManager.getZstdDictionary(dictId);

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

      // 使用字典解压
      final jsonStr = extractJsonFromFieldWithDict(
        results.first['json_data'],
        zstdDict,
      );
      if (jsonStr == null) {
        Logger.e('无法解析json_data字段', tag: 'DatabaseService');
        return null;
      }
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      return DictionaryEntry.fromJson(jsonData);
    } catch (e) {
      Logger.e('getEntry错误: $e', tag: 'DatabaseService');
      return null;
    }
  }

  Future<List<String>> searchByPrefix(
    String prefix, {
    int limit = 10,
    String? sourceLanguage,
  }) async {
    if (prefix.isEmpty) return [];

    final results = <String>{};
    final enabledDicts = await _dictManager.getEnabledDictionariesMetadata();

    String? targetLang = sourceLanguage;
    if (targetLang == 'auto') {
      targetLang = _detectLanguage(prefix);
    }

    final filteredDicts = enabledDicts.where((metadata) {
      if (targetLang != null && targetLang != metadata.sourceLanguage) {
        return false;
      }
      return true;
    }).toList();

    final futures = filteredDicts.map((metadata) async {
      try {
        final db = await _dictManager.openDictionaryDatabase(metadata.id);

        const whereClause = 'headword_normalized LIKE ?';
        final whereArgs = ['${_normalizeSearchWord(prefix)}%'];

        final queryResults = await db.query(
          'entries',
          columns: ['headword'],
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: 'headword_normalized ASC',
          limit: limit,
        );

        return queryResults
            .map((row) => row['headword'] as String?)
            .where((h) => h != null && h.isNotEmpty)
            .cast<String>()
            .toList();
      } catch (e) {
        return <String>[];
      }
    }).toList();

    final allResults = await Future.wait(futures);
    for (final dictResults in allResults) {
      for (final headword in dictResults) {
        results.add(headword);
      }
    }

    return results.toList();
  }

  Future<List<String>> searchByWildcard(
    String pattern, {
    int limit = 20,
    String? sourceLanguage,
  }) async {
    if (pattern.isEmpty) return [];

    final results = <String>{};
    final enabledDicts = await _dictManager.getEnabledDictionariesMetadata();

    String? targetLang = sourceLanguage;
    if (targetLang == 'auto') {
      targetLang = _detectLanguage(pattern);
    }

    final filteredDicts = enabledDicts.where((metadata) {
      if (targetLang != null && targetLang != metadata.sourceLanguage) {
        return false;
      }
      return true;
    }).toList();

    final futures = filteredDicts.map((metadata) async {
      try {
        final db = await _dictManager.openDictionaryDatabase(metadata.id);

        final whereClause = 'headword_normalized LIKE ?';
        final whereArgs = ['%${_normalizeSearchWord(pattern)}%'];

        final queryResults = await db.query(
          'entries',
          columns: ['headword'],
          where: whereClause,
          whereArgs: whereArgs,
          orderBy: 'headword ASC',
          limit: limit,
        );

        return queryResults
            .map((row) => row['headword'] as String?)
            .where((h) => h != null && h.isNotEmpty)
            .cast<String>()
            .toList();
      } catch (e) {
        return <String>[];
      }
    }).toList();

    final allResults = await Future.wait(futures);
    for (final dictResults in allResults) {
      for (final headword in dictResults) {
        results.add(headword);
        if (results.length >= limit) break;
      }
      if (results.length >= limit) break;
    }

    return results.toList()..sort();
  }

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// 创建 commits 表（如果不存在）
  Future<void> _createCommitsTableIfNotExists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commits (
        id TEXT PRIMARY KEY,
        headword TEXT NOT NULL,
        update_time INTEGER NOT NULL
      )
    ''');
  }

  /// 在 commits 表中记录更新操作
  Future<void> _recordUpdate(
    Database db,
    String entryId,
    String headword,
  ) async {
    try {
      await _createCommitsTableIfNotExists(db);
      await db.insert('commits', {
        'id': entryId,
        'headword': headword,
        'update_time': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      Logger.e('记录更新操作失败: $e', tag: 'DatabaseService', error: e);
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
      final db = await dictManager.openDictionaryDatabase(dictId);

      final json = entry.toJson();
      json.remove('id');

      // 获取该词典的 zstd 字典并使用字典压缩
      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final compressedBlob = compressJsonToBlobWithDict(json, zstdDict);

      final String idStr = entry.id;
      int? entryId;

      entryId = int.tryParse(idStr);

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
        {'json_data': compressedBlob},
        where: 'entry_id = ?',
        whereArgs: [entryId],
      );

      // 如果更新成功，记录到 update 表
      if (result > 0) {
        await _recordUpdate(db, entry.id, entry.headword);
      }

      return result > 0;
    } catch (e) {
      Logger.e('更新词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 插入或更新词典条目
  Future<bool> insertOrUpdateEntry(DictionaryEntry entry) async {
    try {
      final dictId = entry.dictId;
      if (dictId == null) {
        return false;
      }

      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      final json = entry.toJson();
      json.remove('id');

      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final compressedBlob = compressJsonToBlobWithDict(json, zstdDict);

      final String idStr = entry.id;
      int? entryId;

      entryId = int.tryParse(idStr);

      if (entryId == null && idStr.contains('_')) {
        final parts = idStr.split('_');
        if (parts.length >= 2) {
          entryId = int.tryParse(parts.last);
        }
      }

      if (entryId == null) {
        return false;
      }

      final headwordNormalized = _normalizeSearchWord(entry.headword);

      await db.insert('entries', {
        'entry_id': entryId,
        'headword': entry.headword,
        'headword_normalized': headwordNormalized,
        'entry_type': entry.entryType,
        'page': entry.page,
        'section': entry.section,
        'json_data': compressedBlob,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _recordUpdate(db, entry.id, entry.headword);

      return true;
    } catch (e) {
      Logger.e('插入词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 从 commits 表获取所有更新记录
  Future<List<Map<String, dynamic>>> getUpdateRecords(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      // 检查表是否存在
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return [];
      }

      final results = await db.query(
        'commits',
        columns: ['id', 'headword', 'update_time'],
        orderBy: 'update_time DESC',
      );
      return results;
    } catch (e) {
      Logger.e('获取更新记录失败: $e', tag: 'DatabaseService', error: e);
      return [];
    }
  }

  /// 根据 entry_id 获取完整的 entry JSON 数据
  Future<Map<String, dynamic>?> getEntryJsonById(
    String dictId,
    String entryId,
  ) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      int? entryIdInt;
      entryIdInt = int.tryParse(entryId);
      if (entryIdInt == null && entryId.contains('_')) {
        final parts = entryId.split('_');
        if (parts.length >= 2) {
          entryIdInt = int.tryParse(parts.last);
        }
      }

      if (entryIdInt == null) {
        return null;
      }

      final results = await db.query(
        'entries',
        columns: ['json_data'],
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
      );

      if (results.isEmpty) {
        return null;
      }

      final jsonData = results.first['json_data'];
      if (jsonData == null) {
        return null;
      }

      // 获取 zstd 字典并解压
      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final jsonStr = extractJsonFromFieldWithDict(jsonData, zstdDict);
      if (jsonStr == null) {
        return null;
      }

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      Logger.e('获取条目JSON失败: $e', tag: 'DatabaseService', error: e);
      return null;
    }
  }

  /// 清除 commits 表中的所有记录
  Future<bool> clearUpdateRecords(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      // 检查表是否存在
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return true;
      }

      await db.delete('commits');
      return true;
    } catch (e) {
      Logger.e('清除更新记录失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }
}
