import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'english_db_service.dart';
import '../data/services/database_initializer.dart';
import '../core/logger.dart';

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

  SearchRelation({
    required this.originalWord,
    required this.mappedWord,
    required this.relationType,
    this.description,
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

  Future<Database> _initDatabase() async {
    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    final path = await EnglishDbService().getDbPath();
    final exists = await File(path).exists();

    if (!exists) {
      return Future.error('英语词典数据库不存在，请先下载。');
    }

    // 以只读方式打开，禁用WAL模式
    final db = await openDatabase(path, readOnly: true, singleInstance: true);

    // 确保使用DELETE日志模式（禁用WAL）
    await db.execute('PRAGMA journal_mode=DELETE');

    return db;
  }

  Future<List<String>> searchSimpleTables(String word) async {
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
      // Error handling without debug output
    }
    return results;
  }

  Future<String?> searchNominalizationBase(String word) async {
    try {
      final db = await database;
      final maps = await db.query(
        'nominalization',
        columns: ['base'],
        where: 'nominal = ?',
        whereArgs: [word],
      );
      if (maps.isNotEmpty) {
        return maps.first['base'] as String?;
      }
    } catch (e) {
      // Error handling without debug output
    }
    return null;
  }

  Future<List<String>> searchInflection(String word) async {
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
      // Error handling without debug output
    }

    return results.toList();
  }

  /// 搜索并返回关系信息
  /// 返回 Map<映射词, List<关系信息>>
  Future<Map<String, List<SearchRelation>>> searchWithRelations(
    String word,
  ) async {
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
        results.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    }

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
          results
              .putIfAbsent(val2, () => [])
              .add(
                SearchRelation(
                  originalWord: word,
                  mappedWord: val2,
                  relationType: table,
                  description: relationDesc,
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
                ),
              );
        }
      }
    } catch (e) {
      // Error handling without debug output
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
      final maps = await db.query(
        'inflection',
        columns: [
          'base',
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
                    ),
                  );
            }
          }
        }
      }
    } catch (e) {
      // Error handling without debug output
    }
    return results;
  }
}
