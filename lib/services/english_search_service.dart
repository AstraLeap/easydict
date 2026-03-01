import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'english_db_service.dart';
import '../data/services/database_initializer.dart';
import '../core/logger.dart';

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

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 关闭并释放数据库连接，删除数据库文件后需要调用此方法以使单例重置
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      Logger.i('EnglishSearchService: 数据库已关闭并重置', tag: 'EnglishDB');
    }
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
      return Future.error('英语词典数据库不存在，请先下载。');
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
    try {
      final db = await database;
      final results = <WordRelationRow>[];

      // spelling_variant
      final svRows = await db.query(
        'spelling_variant',
        where: 'word1 = ? OR word2 = ?',
        whereArgs: [word, word],
      );
      for (final row in svRows) {
        results.add(WordRelationRow(
          tableName: 'spelling_variant',
          fields: row.map((k, v) => MapEntry(k, v?.toString())),
        ));
      }

      // nominalization
      final nomRows = await db.query(
        'nominalization',
        where: 'base = ? OR nominal = ?',
        whereArgs: [word, word],
      );
      for (final row in nomRows) {
        results.add(WordRelationRow(
          tableName: 'nominalization',
          fields: row.map((k, v) => MapEntry(k, v?.toString())),
        ));
      }

      // inflection — pos 列无索引，不放入 WHERE，只在 SELECT 中取用
      final inflRows = await db.query(
        'inflection',
        columns: ['base', 'pos', 'plural', 'past', 'past_part', 'pres_part', 'third_sing', 'comp', 'superl'],
        where:
            'base = ? OR plural = ? OR past = ? OR past_part = ? OR pres_part = ? OR third_sing = ? OR comp = ? OR superl = ?',
        whereArgs: [word, word, word, word, word, word, word, word],
      );
      for (final row in inflRows) {
        results.add(WordRelationRow(
          tableName: 'inflection',
          fields: row.map((k, v) => MapEntry(k, v?.toString())),
        ));
      }

      return results;
    } catch (e) {
      Logger.w(
        'EnglishSearchService: searchWordRelations 错误: $e',
        tag: 'EnglishDB',
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
    Logger.d(
      'EnglishSearchService: searchWithRelations 搜索词: $word',
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
        word,
        '拼写变体',
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'abbreviation',
        'base',
        'full_form',
        word,
        '缩写',
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'acronym',
        'base',
        'full_form',
        word,
        '首字母缩写',
      ),
      _searchTwoColumnTableWithRelations(
        db,
        'nominalization',
        'base',
        'nominal',
        word,
        '名词化',
      ),
      _searchInflectionWithRelations(db, word),
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

    Logger.d(
      'EnglishSearchService: searchWithRelations 结果: $results',
      tag: 'EnglishDB',
    );
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
      'plural': '复数形式',
      'past': '过去式',
      'past_part': '过去分词',
      'pres_part': '现在分词',
      'third_sing': '第三人称单数',
      'comp': '比较级',
      'superl': '最高级',
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
