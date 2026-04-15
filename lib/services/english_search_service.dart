import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'english_db_service.dart';
import '../data/services/database_initializer.dart';
import '../core/logger.dart';
import '../i18n/strings.g.dart';

/// 三张关系表中命中的完整行数据
class WordRelationRow {
  /// 表名: 'spelling_variant', 'nominalization', 'inflection'
  final String tableName;

  /// 该行所有字段 (列名 -> 值)
  final Map<String, String?> fields;

  WordRelationRow({required this.tableName, required this.fields});
}

/// 搜索结果与原始搜索词的关系信息

class SearchRelation {
  /// 原始搜索词
  final String originalWord;

  /// 映射到的词
  final String mappedWord;

  /// 关系类型：spelling_variant, abbreviation, acronym, nominalization, inflection
  final String relationType;

  /// 描述：例如 "复数形式"、"缩写" 等
  final String? description;

  /// 词性，例如 'noun', 'verb', 'adj', 'adv' 等（来自表的 pos 字段）
  final String? pos;

  SearchRelation({
    required this.originalWord,
    required this.mappedWord,
    required this.relationType,
    this.description,
    this.pos,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchRelation &&
          runtimeType == other.runtimeType &&
          originalWord == other.originalWord &&
          mappedWord == other.mappedWord &&
          relationType == other.relationType;

  @override
  int get hashCode =>
      originalWord.hashCode ^ mappedWord.hashCode ^ relationType.hashCode;
}

class EnglishSearchService {
  static final EnglishSearchService _instance =
      EnglishSearchService._internal();
  factory EnglishSearchService() => _instance;
  EnglishSearchService._internal();

  Database? _database;
  Future<Database>? _databaseFuture;

  // 热路径缓存：同一词在短时间内会被重复查询（顶部关系横幅/词典关系提示）。
  static const int _maxWordRelationsCacheSize = 200;
  static const int _maxSearchWithRelationsCacheSize = 200;
  final Map<String, List<WordRelationRow>> _wordRelationsCache = {};
  final Map<String, Map<String, List<SearchRelation>>>
  _searchWithRelationsCache = {};
  final Map<String, Future<List<WordRelationRow>>> _wordRelationsInFlight = {};
  final Map<String, Future<Map<String, List<SearchRelation>>>>
  _searchWithRelationsInFlight = {};

  Future<Database> get database async {
    if (_database != null) return _database!;
    final inFlight = _databaseFuture;
    if (inFlight != null) {
      return await inFlight;
    }

    final initFuture = _initDatabase();
    _databaseFuture = initFuture;
    try {
      final db = await initFuture;
      _database = db;
      return db;
    } finally {
      _databaseFuture = null;
    }
  }

  /// 关闭并释放数据库连接，删除数据库文件后需要调用此方法以使单例重置
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _databaseFuture = null;
      _wordRelationsCache.clear();
      _searchWithRelationsCache.clear();
      _wordRelationsInFlight.clear();
      _searchWithRelationsInFlight.clear();
      Logger.i('EnglishSearchService: 数据库已关闭并重置', tag: 'EnglishDB');
    }
  }

  void _putWordRelationsCache(String key, List<WordRelationRow> value) {
    if (_wordRelationsCache.length >= _maxWordRelationsCacheSize) {
      _wordRelationsCache.remove(_wordRelationsCache.keys.first);
    }
    _wordRelationsCache[key] = value;
  }

  /// 同步读取关系缓存（仅用于 UI 热路径快速渲染，不触发查询）。
  List<WordRelationRow>? getCachedWordRelations(String word) {
    final query = word.trim();
    if (query.isEmpty) return null;
    return _wordRelationsCache[query.toLowerCase()];
  }

  void _putSearchWithRelationsCache(
    String key,
    Map<String, List<SearchRelation>> value,
  ) {
    if (_searchWithRelationsCache.length >= _maxSearchWithRelationsCacheSize) {
      _searchWithRelationsCache.remove(_searchWithRelationsCache.keys.first);
    }
    _searchWithRelationsCache[key] = value;
  }

  Future<Database> _initDatabase() async {
    Logger.d('EnglishSearchService: 初始化数据库...', tag: 'EnglishDB');
    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    final path = await EnglishDbService().getDbPath();
    Logger.d('EnglishSearchService: 数据库路径: $path', tag: 'EnglishDB');

    final exists = await File(path).exists();
    Logger.d('EnglishSearchService: 数据库是否存在: $exists', tag: 'EnglishDB');

    if (!exists) {
      Logger.w('EnglishSearchService: 英语词典数据库不存在，请先下载。', tag: 'EnglishDB');
      return Future.error(t.dict.dbNotExists);
    }

    // 以只读方式打开
    final db = await openDatabase(path, readOnly: true, singleInstance: true);
    Logger.i('EnglishSearchService: 数据库打开成功', tag: 'EnglishDB');

    return db;
  }

  /// 在三张关系表中搜索词，返回每一个命中的完整行。
  /// 表: spelling_variant(word1,word2), nominalization(base,nominal),
  ///     inflection(base,plural,past,past_part,pres_part,third_sing,comp,superl)
  Future<List<WordRelationRow>> searchWordRelations(String word) async {
    if (word.isEmpty) return [];
    final query = word.trim();
    if (query.isEmpty) return [];
    final cacheKey = query.toLowerCase();
    final cached = _wordRelationsCache[cacheKey];
    if (cached != null) {
      Logger.d(
        'WordRelations cache hit: word=$cacheKey, rows=${cached.length}',
        tag: 'RelationPerf',
      );
      return cached;
    }
    final inFlight = _wordRelationsInFlight[cacheKey];
    if (inFlight != null) {
      Logger.d(
        'WordRelations in-flight reuse: word=$cacheKey',
        tag: 'RelationPerf',
      );
      return inFlight;
    }

    Logger.d(
      'WordRelations query dispatch: word=$cacheKey',
      tag: 'RelationPerf',
    );

    final task = _searchWordRelationsInternal(query, cacheKey);
    _wordRelationsInFlight[cacheKey] = task;

    try {
      return await task;
    } finally {
      _wordRelationsInFlight.remove(cacheKey);
    }
  }

  Future<List<WordRelationRow>> _searchWordRelationsInternal(
    String query,
    String cacheKey,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final db = await database;
      final futureRows = Future.wait([
        db.query(
          'spelling_variant',
          where: 'word1 = ? OR word2 = ?',
          whereArgs: [query, query],
        ),
        db.query(
          'nominalization',
          where: 'base = ? OR nominal = ?',
          whereArgs: [query, query],
        ),
        db.query(
          'inflection',
          columns: [
            'base',
            'pos',
            'plural',
            'past',
            'past_part',
            'pres_part',
            'third_sing',
            'comp',
            'superl',
          ],
          where:
              'base = ? OR plural = ? OR past = ? OR past_part = ? OR pres_part = ? OR third_sing = ? OR comp = ? OR superl = ?',
          whereArgs: [query, query, query, query, query, query, query, query],
        ),
      ]);

      final [svRows, nomRows, inflRows] = await futureRows;
      final results = <WordRelationRow>[];
      for (final row in svRows) {
        results.add(
          WordRelationRow(
            tableName: 'spelling_variant',
            fields: row.map((k, v) => MapEntry(k, v?.toString())),
          ),
        );
      }
      for (final row in nomRows) {
        results.add(
          WordRelationRow(
            tableName: 'nominalization',
            fields: row.map((k, v) => MapEntry(k, v?.toString())),
          ),
        );
      }
      for (final row in inflRows) {
        results.add(
          WordRelationRow(
            tableName: 'inflection',
            fields: row.map((k, v) => MapEntry(k, v?.toString())),
          ),
        );
      }

      _putWordRelationsCache(cacheKey, results);
      Logger.d(
        'WordRelations query finished: word=$cacheKey, rows=${results.length}, elapsed=${sw.elapsedMilliseconds}ms',
        tag: 'RelationPerf',
      );
      return results;
    } catch (e) {
      Logger.w(
        'WordRelations query failed: word=$cacheKey, elapsed=${sw.elapsedMilliseconds}ms, error=$e',
        tag: 'RelationPerf',
      );
      return [];
    }
  }

  Future<List<String>> searchSimpleTables(String word) async {
    Logger.d(
      'EnglishSearchService: searchSimpleTables 搜索词: $word',
      tag: 'EnglishDB',
    );
    final db = await database;
    final results = <String>{};

    final futures = [
      _searchTwoColumnTable(db, 'spelling_variant', 'word1', 'word2', word),
      _searchTwoColumnTable(db, 'abbreviation', 'base', 'full_form', word),
      _searchTwoColumnTable(db, 'acronym', 'base', 'full_form', word),
      _searchTwoColumnTable(db, 'nominalization', 'base', 'nominal', word),
    ];

    final allResults = await Future.wait(futures);
    for (final list in allResults) {
      results.addAll(list);
    }
    Logger.d(
      'EnglishSearchService: searchSimpleTables 结果: ${results.toList()}',
      tag: 'EnglishDB',
    );

    return results.toList();
  }

  Future<List<String>> _searchTwoColumnTable(
    Database db,
    String table,
    String col1,
    String col2,
    String word,
  ) async {
    final results = <String>[];
    try {
      final maps = await db.query(
        table,
        columns: [col1, col2],
        where: '$col1 = ? OR $col2 = ?',
        whereArgs: [word, word],
      );
      for (final map in maps) {
        final val1 = map[col1] as String?;
        final val2 = map[col2] as String?;
        if (val1 == word && val2 != null) {
          results.add(val2);
        } else if (val2 == word && val1 != null) {
          results.add(val1);
        }
      }
    } catch (e) {
      Logger.w(
        'EnglishSearchService: _searchTwoColumnTable 表 $table 查询失败: $e',
        tag: 'EnglishDB',
      );
    }
    return results;
  }

  Future<String?> searchNominalizationBase(String word) async {
    Logger.d(
      'EnglishSearchService: searchNominalizationBase 搜索词: $word',
      tag: 'EnglishDB',
    );
    try {
      final db = await database;
      final maps = await db.query(
        'nominalization',
        columns: ['base'],
        where: 'nominal = ?',
        whereArgs: [word],
      );
      if (maps.isNotEmpty) {
        final result = maps.first['base'] as String?;
        Logger.d(
          'EnglishSearchService: searchNominalizationBase 结果: $result',
          tag: 'EnglishDB',
        );
        return result;
      }
    } catch (e) {
      Logger.e(
        'EnglishSearchService: searchNominalizationBase 错误: $e',
        tag: 'EnglishDB',
      );
    }
    Logger.d(
      'EnglishSearchService: searchNominalizationBase 结果: null',
      tag: 'EnglishDB',
    );
    return null;
  }

  Future<List<String>> searchInflection(String word) async {
    Logger.d(
      'EnglishSearchService: searchInflection 搜索词: $word',
      tag: 'EnglishDB',
    );
    final db = await database;
    final results = <String>{};

    try {
      final maps = await db.query(
        'inflection',
        columns: ['base'],
        where:
            'plural = ? OR past = ? OR past_part = ? OR pres_part = ? OR third_sing = ? OR comp = ? OR superl = ?',
        whereArgs: [word, word, word, word, word, word, word],
      );
      for (final map in maps) {
        if (map['base'] != null) {
          results.add(map['base'] as String);
        }
      }
    } catch (e) {
      Logger.e(
        'EnglishSearchService: searchInflection 错误: $e',
        tag: 'EnglishDB',
      );
    }
    Logger.d(
      'EnglishSearchService: searchInflection 结果: ${results.toList()}',
      tag: 'EnglishDB',
    );
    return results.toList();
  }

  /// 搜索并返回关系信息
  /// 返回 Map<映射词, List<关系信息>>
  ///
  /// [maxRelatedWords] 限制返回的最大关联词数量，默认 10
  /// [maxRelationsPerWord] 限制每个词的最大关系数量，默认 3
  Future<Map<String, List<SearchRelation>>> searchWithRelations(
    String word, {
    int maxRelatedWords = 10,
    int maxRelationsPerWord = 3,
  }) async {
    if (word.isEmpty) return {};
    final query = word.trim();
    if (query.isEmpty) return {};
    final cacheKey =
        '${query.toLowerCase()}|$maxRelatedWords|$maxRelationsPerWord';
    final cached = _searchWithRelationsCache[cacheKey];
    if (cached != null) {
      Logger.d(
        'SearchWithRelations cache hit: key=$cacheKey, relatedWords=${cached.length}',
        tag: 'RelationPerf',
      );
      return cached;
    }
    final inFlight = _searchWithRelationsInFlight[cacheKey];
    if (inFlight != null) {
      Logger.d(
        'SearchWithRelations in-flight reuse: key=$cacheKey',
        tag: 'RelationPerf',
      );
      return inFlight;
    }

    Logger.d(
      'SearchWithRelations dispatch: key=$cacheKey',
      tag: 'RelationPerf',
    );

    final task = _searchWithRelationsInternal(
      query,
      cacheKey,
      maxRelatedWords: maxRelatedWords,
      maxRelationsPerWord: maxRelationsPerWord,
    );
    _searchWithRelationsInFlight[cacheKey] = task;

    try {
      return await task;
    } finally {
      _searchWithRelationsInFlight.remove(cacheKey);
    }
  }

  Future<Map<String, List<SearchRelation>>> _searchWithRelationsInternal(
    String query,
    String cacheKey, {
    required int maxRelatedWords,
    required int maxRelationsPerWord,
  }) async {
    final sw = Stopwatch()..start();
    // 预热顶部关系横幅所需数据，避免进入详情页后再次冷查询。
    unawaited(searchWordRelations(query));

    Logger.d(
      'EnglishSearchService: searchWithRelations 搜索词: $query',
      tag: 'EnglishDB',
    );
    final db = await database;
    final results = <String, List<SearchRelation>>{};

    final futures = [
      _searchTwoColumnTableWithRelations(
        db,
        'spelling_variant',
        'word1',
        'word2',
        query,
        t.entry.spellingVariantLabel,
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'abbreviation',
        'base',
        'full_form',
        query,
        t.entry.abbreviationLabel,
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'acronym',
        'base',
        'full_form',
        query,
        t.entry.acronymLabel,
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'nominalization',
        'base',
        'nominal',
        query,
        t.entry.morphNominalization,
      ),
      _searchInflectionWithRelations(db, query),
    ];

    final allResults = await Future.wait(futures);
    for (final map in allResults) {
      for (final entry in map.entries) {
        if (results.length >= maxRelatedWords) break;
        final relations = entry.value.take(maxRelationsPerWord).toList();
        results.putIfAbsent(entry.key, () => []).addAll(relations);
      }
      if (results.length >= maxRelatedWords) break;
    }

    _putSearchWithRelationsCache(cacheKey, results);
    return results;
  }

  Future<Map<String, List<SearchRelation>>> _searchTwoColumnTableWithRelations(
    Database db,
    String table,
    String col1,
    String col2,
    String word,
    String relationDesc,
  ) async {
    final results = <String, List<SearchRelation>>{};
    try {
      // 不限定 columns，让每个表返回全部字段（nominalization 有 pos 字段）
      final maps = await db.query(
        table,
        where: '$col1 = ? OR $col2 = ?',
        whereArgs: [word, word],
      );

      for (final map in maps) {
        final val1 = map[col1] as String?;
        final val2 = map[col2] as String?;
        final pos = map['pos'] as String?;
        if (val1 == word && val2 != null) {
          results
              .putIfAbsent(val2, () => [])
              .add(
                SearchRelation(
                  originalWord: word,
                  mappedWord: val2,
                  relationType: table,
                  description: relationDesc,
                  pos: pos,
                ),
              );
        } else if (val2 == word && val1 != null) {
          results
              .putIfAbsent(val1, () => [])
              .add(
                SearchRelation(
                  originalWord: word,
                  mappedWord: val1,
                  relationType: table,
                  description: relationDesc,
                  pos: pos,
                ),
              );
        }
      }
    } catch (e) {
      Logger.w(
        'EnglishSearchService: _searchTwoColumnTableWithRelations 表 $table 查询失败: $e',
        tag: 'EnglishDB',
      );
    }
    return results;
  }

  Future<Map<String, List<SearchRelation>>> _searchInflectionWithRelations(
    Database db,
    String word,
  ) async {
    final results = <String, List<SearchRelation>>{};
    final inflectionCols = {
      'plural': t.entry.morphPluralForm,
      'past': t.entry.morphPast,
      'past_part': t.entry.morphPastPart,
      'pres_part': t.entry.morphPresPart,
      'third_sing': t.entry.morphThirdSingFull,
      'comp': t.entry.morphComp,
      'superl': t.entry.morphSuperl,
    };

    try {
      // 包含 pos 字段，用于显示词性
      final maps = await db.query(
        'inflection',
        columns: [
          'base',
          'pos',
          'plural',
          'past',
          'past_part',
          'pres_part',
          'third_sing',
          'comp',
          'superl',
        ],
        where:
            'plural = ? OR past = ? OR past_part = ? OR pres_part = ? OR third_sing = ? OR comp = ? OR superl = ?',
        whereArgs: [word, word, word, word, word, word, word],
      );

      for (final map in maps) {
        final baseWord = map['base'] as String?;
        final pos = map['pos'] as String?;
        if (baseWord != null) {
          for (final entry in inflectionCols.entries) {
            final col = entry.key;
            final desc = entry.value;
            if (map[col] == word) {
              results
                  .putIfAbsent(baseWord, () => [])
                  .add(
                    SearchRelation(
                      originalWord: word,
                      mappedWord: baseWord,
                      relationType: 'inflection',
                      description: desc,
                      pos: pos,
                    ),
                  );
            }
          }
        }
      }
    } catch (e) {
      Logger.w(
        'EnglishSearchService: _searchInflectionWithRelations 查询失败: $e',
        tag: 'EnglishDB',
      );
    }
    return results;
  }
}
