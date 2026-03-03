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

/// 解析 pronunciation 字段，兼容 List / Map / String 三种形式
List<Map<String, dynamic>> _parsePronunciations(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    return value
        .map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          // 字符串形式：当作 phonetic 字段
          if (e is String) return <String, dynamic>{'phonetic': e};
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }
  if (value is Map) {
    return [Map<String, dynamic>.from(value)];
  }
  if (value is String) {
    return [<String, dynamic>{'phonetic': value}];
  }
  return [];
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
        frequency: json['frequency'] is Map<String, dynamic>
            ? json['frequency'] as Map<String, dynamic>
            : {},
        etymology: json['etymology'],
        pronunciations: _parsePronunciations(json['pronunciation']),
        sense: json['sense'] != null
            ? (json['sense'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        phrase: () {
          // 只支持 'phrases' 字段（唯一正确形式）
          final p = json['phrases'];
          if (p == null || p == '' || p is! List) return <String>[];
          return (p as List<dynamic>)
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }(),
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

  /// 原始 JSON 中的 pronunciation 字段是否为单个对象（而非列表）
  bool get pronunciationIsSingleObject {
    final raw = _rawJson['pronunciation'];
    return raw != null && raw is Map;
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

/// 查询操作符模式：根据用户输入文本自动检测
enum _QueryMode { normal, like, glob }

/// 根据查询文本自动检测操作符模式：
/// - 含 % 或 _ → LIKE
/// - 含 * ? [ ] ^ → GLOB
/// - 否则 → 普通精确/前缀匹配
_QueryMode _detectQueryMode(String query) {
  if (query.contains('%') || query.contains('_')) return _QueryMode.like;
  if (query.contains('*') || query.contains('?') ||
      query.contains('[') || query.contains(']') || query.contains('^')) {
    return _QueryMode.glob;
  }
  return _QueryMode.normal;
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

  // 缓存各词典是否为表音（biaoyi）模式（有 phonetic 列，无 headword_normalized 列）
  final Map<String, bool> _dictHasPhoneticsCache = {};

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

  /// 规范化搜索词：小写化、去除音调符号、去除空格
  String _normalizeSearchWord(String word) {
    // 小写化
    String normalized = word.toLowerCase();
    // 去除音调符号（Unicode组合字符）
    normalized = normalized.replaceAll(_diacriticsRegExp, '');
    // 去除空格（与数据库构建时的 normalize_text 保持一致）
    normalized = normalized.replaceAll(' ', '');
    return normalized;
  }

  /// 自动模式下检测输入文本可能属于的语言列表。
  /// 返回 null 表示未检测到特定表意文字脚本，应搜索所有表音文字词典。
  List<String>? _detectPossibleLanguages(String text) {
    final hasKana = _japaneseRegExp.hasMatch(text);
    final hasCJK = _chineseRegExp.hasMatch(text);
    final hasHangul = _koreanRegExp.hasMatch(text);

    if (hasHangul) return ['ko'];
    if (hasKana) return ['ja']; // 有假名（含汉字）→ 日语
    if (hasCJK) return ['zh', 'ja']; // 纯汉字 → 中文或日文均可
    return null; // 拉丁字母等表音文字 → 搜索所有非表意词典
  }

  Future<SearchResult> getAllEntries(
    String word, {
    bool exactMatch = false,
    bool usePhoneticSearch = false,
    String? sourceLanguage,
  }) async {
    var entries = <DictionaryEntry>[];
    var relations = <String, List<SearchRelation>>{};

    entries = await _searchEntriesInternal(
      word,
      exactMatch: exactMatch,
      usePhoneticSearch: usePhoneticSearch,
      sourceLanguage: sourceLanguage,
    );

    if (entries.isEmpty && _detectQueryMode(word) == _QueryMode.normal && !usePhoneticSearch) {
      // 判断是否需要调用英语关系词搜索
      bool shouldSearchEnglish;
      if (sourceLanguage == 'auto') {
        final possibleLangs = _detectPossibleLanguages(word);
        // possibleLangs == null 表示表音文字（可能含英语）；包含 'en' 则明确含英语
        shouldSearchEnglish = possibleLangs == null;
      } else {
        shouldSearchEnglish = sourceLanguage == 'en' || sourceLanguage == null;
      }

      if (shouldSearchEnglish) {
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
              exactMatch: exactMatch,
              usePhoneticSearch: false,
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
    required bool exactMatch,
    bool usePhoneticSearch = false,
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
    List<String>? possibleLangs;

    if (targetLang == 'auto') {
      possibleLangs = _detectPossibleLanguages(word);
      Logger.i(
        '自动模式检测到可能语言: ${possibleLangs ?? "(表音文字，搜索所有非表意词典)"}',
        tag: 'DatabaseService',
      );
    } else {
      Logger.i('指定语言: $targetLang', tag: 'DatabaseService');
    }

    final filteredDicts = enabledDicts.where((metadata) {
      if (targetLang == 'auto') {
        final lang = metadata.sourceLanguage;
        if (possibleLangs != null) {
          // 检测到表意文字：只搜索匹配的语言
          final match = possibleLangs.contains(lang);
          if (!match) {
            Logger.i(
              '  过滤掉词典 ${metadata.name}: 语言 $lang 不在候选列表 $possibleLangs',
              tag: 'DatabaseService',
            );
          }
          return match;
        } else {
          // 表音文字：搜索所有非表意文字词典
          const logographic = {'zh', 'ja', 'ko'};
          final match = !logographic.contains(lang);
          if (!match) {
            Logger.i(
              '  过滤掉词典 ${metadata.name}: 表音文字模式下跳过表意词典 $lang',
              tag: 'DatabaseService',
            );
          }
          return match;
        }
      } else if (targetLang != null && targetLang != metadata.sourceLanguage) {
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
        exactMatch: exactMatch,
        usePhoneticSearch: usePhoneticSearch,
      );
    }).toList();

    final results = await Future.wait(futures);
    final allEntries = results.expand((list) => list).toList();
    Logger.i('搜索完成，找到 ${allEntries.length} 条结果', tag: 'DatabaseService');
    return allEntries;
  }

  /// 检查词典是否为表音（biaoyi）模式：有 phonetic 列，无 headword_normalized 列
  Future<bool> _isBiaoyiDict(String dictId, Database db) async {
    if (_dictHasPhoneticsCache.containsKey(dictId)) {
      return _dictHasPhoneticsCache[dictId]!;
    }
    try {
      final columns = await db.rawQuery('PRAGMA table_info(entries)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      final isbiaoyi = columnNames.contains('phonetic') &&
          !columnNames.contains('headword_normalized');
      _dictHasPhoneticsCache[dictId] = isbiaoyi;
      return isbiaoyi;
    } catch (e) {
      _dictHasPhoneticsCache[dictId] = false;
      return false;
    }
  }

  Future<List<DictionaryEntry>> _searchInDictionary(
    String dictId,
    String word, {
    required bool exactMatch,
    bool usePhoneticSearch = false,
  }) async {
    final entries = <DictionaryEntry>[];

    try {
      Logger.i('正在搜索词典: $dictId', tag: 'DatabaseService');
      final db = await _dictManager.openDictionaryDatabase(dictId);
      Logger.i('成功打开词典数据库: $dictId', tag: 'DatabaseService');

      // 获取该词典的 zstd 字典用于解压
      final zstdDict = await _dictManager.getZstdDictionary(dictId);

      final isbiaoyi = await _isBiaoyiDict(dictId, db);

      String whereClause;
      List<dynamic> whereArgs;

      final qMode = _detectQueryMode(word);
      final normWord = _normalizeSearchWord(word);

      if (isbiaoyi) {
        // 表意文字词典：支持 headword 字段搜索及 phonetic 读音搜索
        if (usePhoneticSearch) {
          if (qMode == _QueryMode.like) {
            whereClause = 'phonetic LIKE ?';
            whereArgs = [normWord];
          } else if (qMode == _QueryMode.glob) {
            whereClause = 'phonetic GLOB ?';
            whereArgs = [normWord];
          } else {
            whereClause = 'phonetic = ?';
            whereArgs = [normWord];
          }
        } else {
          if (qMode == _QueryMode.like) {
            whereClause = 'headword LIKE ?';
            whereArgs = [word];
          } else if (qMode == _QueryMode.glob) {
            whereClause = 'headword GLOB ?';
            whereArgs = [word];
          } else {
            whereClause = 'headword = ?';
            whereArgs = [word];
          }
        }
      } else {
        if (qMode == _QueryMode.like) {
          whereClause = 'headword_normalized LIKE ?';
          whereArgs = [normWord];
        } else if (qMode == _QueryMode.glob) {
          whereClause = 'headword_normalized GLOB ?';
          whereArgs = [normWord];
        } else {
          whereClause = 'headword_normalized = ?';
          whereArgs = [normWord];
        }
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
            Logger.w('compute 解析失败，回退到主线程解析: $e', tag: 'DatabaseService');
            try {
              final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (exactMatch) {
                final headword = jsonData['headword'] as String? ?? '';
                if (headword != word) continue;
              }
              _ensureEntryId(jsonData, row, dictId);
              entry = DictionaryEntry.fromJson(jsonData);
            } catch (e2) {
              Logger.e('回退解析也失败，跳过此条目: $e2', tag: 'DatabaseService');
              continue;
            }
          }
        }

        if (entry != null) {
          entries.add(entry);
        }
      }
    } catch (e) {
      Logger.e('_searchInDictionary 整体失败: $e', tag: 'DatabaseService');
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

  // ─────────────────────────────────────────────────────────────────
  // 边打边搜候选词
  // ─────────────────────────────────────────────────────────────────

  /// 统一的边打边搜候选词入口。
  ///
  /// [sourceLanguage] 可以是具体语言代码或 'auto'。
  /// 返回已排序、去重、不超过 [limit] 条的候选 headword 列表。
  Future<List<String>> getPreSearchCandidates(
    String query, {
    required String sourceLanguage,
    bool exactMatch = false,
    bool usePhoneticSearch = false,
    int limit = 8,
  }) async {
    if (query.isEmpty) return [];

    final normalizedQuery = _normalizeSearchWord(query);
    final enabledDicts = await _dictManager.getEnabledDictionariesMetadata();

    // ── 过滤要搜索的词典 ────────────────────────────────────────────
    List<String>? possibleLangs;
    if (sourceLanguage == 'auto') {
      possibleLangs = _detectPossibleLanguages(query);
    }

    final filteredDicts = enabledDicts.where((m) {
      if (sourceLanguage == 'auto') {
        final lang = m.sourceLanguage;
        if (possibleLangs != null) return possibleLangs.contains(lang);
        const logographic = {'zh', 'ja', 'ko'};
        return !logographic.contains(lang); // 表音输入只搜非表意词典
      }
      return m.sourceLanguage == sourceLanguage;
    }).toList();

    if (filteredDicts.isEmpty) return [];

    // ── 并行搜索各词典 ──────────────────────────────────────────────
    final futures = filteredDicts.map((metadata) async {
      try {
        final db = await _dictManager.openDictionaryDatabase(metadata.id);
        final isbiaoyi = await _isBiaoyiDict(metadata.id, db);

        if (isbiaoyi) {
          return _prefixFromBiaoyiDict(
            db, query, normalizedQuery,
            usePhoneticSearch: usePhoneticSearch,
            limit: limit,
          );
        } else if (sourceLanguage == 'auto') {
          // auto 模式：简单前缀匹配，不做排名分级
          return _prefixFromPhoneticDictAuto(db, normalizedQuery, limit: limit);
        } else {
          return _prefixFromPhoneticDict(
            db, query, normalizedQuery,
            exactMatch: exactMatch,
            limit: limit,
          );
        }
      } catch (e) {
        return <MapEntry<String, int>>[];
      }
    }).toList();

    final allCandidates = await Future.wait(futures);

    // ── 合并、去重、排序 ────────────────────────────────────────────
    final seen = <String>{};
    final merged = <MapEntry<String, int>>[];
    for (final candidates in allCandidates) {
      for (final c in candidates) {
        if (seen.add(c.key)) {
          merged.add(c);
        }
      }
    }

    merged.sort((a, b) {
      final rankCmp = a.value.compareTo(b.value);
      if (rankCmp != 0) return rankCmp;
      final lenCmp = a.key.length.compareTo(b.key.length);
      if (lenCmp != 0) return lenCmp;
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });

    return merged.take(limit).map((e) => e.key).toList();
  }

  /// 表意文字词典（biaoyi）的前缀候选词搜索。
  /// 自动从查询文本检测通配符模式（LIKE / GLOB / 前缀匹配）。
  Future<List<MapEntry<String, int>>> _prefixFromBiaoyiDict(
    Database db,
    String query,
    String normalizedQuery, {
    bool usePhoneticSearch = false,
    required int limit,
  }) async {
    final qMode = _detectQueryMode(query);
    String whereClause;
    List<dynamic> whereArgs;

    if (usePhoneticSearch) {
      // 读音搜索：在 phonetic 字段上搜索
      if (qMode == _QueryMode.like) {
        whereClause = 'phonetic LIKE ?';
        whereArgs = [normalizedQuery];
      } else if (qMode == _QueryMode.glob) {
        whereClause = 'phonetic GLOB ?';
        whereArgs = [normalizedQuery];
      } else {
        // 默认前缀匹配
        whereClause = 'phonetic LIKE ?';
        whereArgs = ['$normalizedQuery%'];
      }
    } else {
      // headword 字段搜索
      if (qMode == _QueryMode.like) {
        whereClause = 'headword LIKE ?';
        whereArgs = [query];
      } else if (qMode == _QueryMode.glob) {
        whereClause = 'headword GLOB ?';
        whereArgs = [query];
      } else {
        // 默认前缀匹配
        whereClause = 'headword LIKE ?';
        whereArgs = ['$query%'];
      }
    }

    // 读音搜索时按 phonetic 排序，否则按 headword 排序
    final orderBy = usePhoneticSearch ? 'phonetic ASC' : 'headword ASC';

    final results = await db.query(
      'entries',
      columns: ['headword'],
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );

    return results
        .map((r) => r['headword'] as String?)
        .where((h) => h != null && h.isNotEmpty)
        .cast<String>()
        .map((h) => MapEntry(h, 1))
        .toList();
  }

  /// Auto 模式下的表音词典前缀候选词搜索（简单前缀，无分级排名）。
  /// 自动从查询文本检测通配符模式。
  Future<List<MapEntry<String, int>>> _prefixFromPhoneticDictAuto(
    Database db,
    String normalizedQuery, {
    required int limit,
  }) async {
    final qMode = _detectQueryMode(normalizedQuery);
    final String whereStr;
    final List<dynamic> whereArgsList;
    if (qMode == _QueryMode.like) {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = [normalizedQuery];
    } else if (qMode == _QueryMode.glob) {
      whereStr = 'headword_normalized GLOB ?';
      whereArgsList = [normalizedQuery];
    } else {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = ['$normalizedQuery%'];
    }
    final results = await db.query(
      'entries',
      columns: ['headword'],
      where: whereStr,
      whereArgs: whereArgsList,
      orderBy: 'headword_normalized ASC',
      limit: limit,
    );

    return results
        .map((r) => r['headword'] as String?)
        .where((h) => h != null && h.isNotEmpty)
        .cast<String>()
        .map((h) => MapEntry(h, 3)) // 统一 rank=3，后续按长度/字母排序
        .toList();
  }

  /// 表音字母文字词典的前缀候选词搜索，支持精确匹配和自动通配符检测。
  ///
  /// LIKE/GLOB 通配符（输入含 % _ * ? [ ] ^）：直接用对应操作符搜索 headword_normalized。
  /// 仅精确：前缀取 limit*2 条，过滤 headword.startsWith(query)（区分大小写前缀匹配）。
  /// 默认：前缀搜索，Dart 侧按 rank(精确/空格前缀/纯前缀) 分级。
  Future<List<MapEntry<String, int>>> _prefixFromPhoneticDict(
    Database db,
    String query,
    String normalizedQuery, {
    bool exactMatch = false,
    required int limit,
  }) async {
    final qMode = _detectQueryMode(query);
    List<String> headwords;

    if (qMode == _QueryMode.like || qMode == _QueryMode.glob) {
      // 通配符模式：直接使用用户模式匹配 headword_normalized
      final fetchLimit = exactMatch ? limit * 2 : limit;
      final results = await db.query(
        'entries',
        columns: ['headword'],
        where: qMode == _QueryMode.like
            ? 'headword_normalized LIKE ?'
            : 'headword_normalized GLOB ?',
        whereArgs: [normalizedQuery],
        orderBy: 'headword_normalized ASC',
        limit: fetchLimit,
      );
      headwords = results
          .map((r) => r['headword'] as String?)
          .where((h) => h != null && h.isNotEmpty)
          .cast<String>()
          .toList();
    } else {
      // 默认：带分级排名的前缀搜索，多取一些，Dart 侧排序
      final fetchLimit = limit * 2;
      final results = await db.query(
        'entries',
        columns: ['headword'],
        where: 'headword_normalized LIKE ?',
        whereArgs: ['$normalizedQuery%'],
        orderBy: 'headword_normalized ASC',
        limit: fetchLimit,
      );
      headwords = results
          .map((r) => r['headword'] as String?)
          .where((h) => h != null && h.isNotEmpty)
          .cast<String>()
          .toList();
    }

    // 精确前缀过滤：候选词的前 X 个字符（X = query长度）必须与原始查询完全匹配（区分大小写）
    if (exactMatch) {
      headwords = headwords.where((h) => h.startsWith(query)).take(limit).toList();
    }

    if (qMode != _QueryMode.normal || exactMatch) {
      // 通配符 / 精确模式：已按 headword_normalized ASC 排序，rank 统一为 1
      return headwords.take(limit).map((h) => MapEntry(h, 1)).toList();
    }

    // 默认分级排名
    final queryLower = query.toLowerCase();
    final queryLowerSpace = '$queryLower ';
    return headwords.map((h) {
      final hl = h.toLowerCase();
      final rank = hl == queryLower ? 1 : (hl.startsWith(queryLowerSpace) ? 2 : 3);
      return MapEntry(h, rank);
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────



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
        update_time INTEGER NOT NULL,
        delete INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 在 commits 表中记录更新操作
  Future<void> _recordUpdate(
    Database db,
    String entryId,
    String headword, {
    bool isDelete = false,
  }) async {
    try {
      await _createCommitsTableIfNotExists(db);
      await db.insert('commits', {
        'id': entryId,
        'headword': headword,
        'update_time': DateTime.now().millisecondsSinceEpoch,
        'delete': isDelete ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      Logger.e('记录更新操作失败: $e', tag: 'DatabaseService', error: e);
    }
  }

  /// 更新词典条目
  Future<bool> updateEntry(
    DictionaryEntry entry, {
    bool skipCommit = false,
  }) async {
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
      if (result > 0 && !skipCommit) {
        await _recordUpdate(db, entry.id, entry.headword);
      }

      return result > 0;
    } catch (e) {
      Logger.e('更新词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 插入或更新词典条目
  Future<bool> insertOrUpdateEntry(
    DictionaryEntry entry, {
    bool skipCommit = false,
  }) async {
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

      if (!skipCommit) {
        await _recordUpdate(db, entry.id, entry.headword);
      }

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
        columns: ['id', 'headword', 'update_time', 'delete'],
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

  /// 删除 commits 表中指定条目的记录
  Future<bool> deleteUpdateRecord(String dictId, String entryId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return true;
      }

      await db.delete('commits', where: 'id = ?', whereArgs: [entryId]);
      return true;
    } catch (e) {
      Logger.e('删除更新记录失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 删除词典条目（同时在 commits 表中记录删除操作）
  Future<bool> deleteEntryById(String dictId, String entryId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      int? entryIdInt = int.tryParse(entryId);
      if (entryIdInt == null && entryId.contains('_')) {
        final parts = entryId.split('_');
        if (parts.length >= 2) {
          entryIdInt = int.tryParse(parts.last);
        }
      }

      if (entryIdInt == null) {
        Logger.e('无效 entry_id: $entryId', tag: 'DatabaseService');
        return false;
      }

      // 先获取 headword，用于 commit 记录
      final rows = await db.query(
        'entries',
        columns: ['headword'],
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
      );

      if (rows.isEmpty) {
        Logger.e('未找到 entry_id=$entryId 的条目', tag: 'DatabaseService');
        return false;
      }

      final headword = rows.first['headword'] as String? ?? '';

      // 删除条目
      await db.delete(
        'entries',
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
      );

      // 在 commits 表中记录删除操作
      await _recordUpdate(db, entryId, headword, isDelete: true);

      return true;
    } catch (e) {
      Logger.e('删除词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
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
