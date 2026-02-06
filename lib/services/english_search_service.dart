import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';
import 'english_db_service.dart';

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
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await EnglishDbService().getDbPath();
    final exists = await File(path).exists();

    if (!exists) {
      return Future.error('英语词典数据库不存在，请先下载。');
    }

    return await openDatabase(path, readOnly: true);
  }

  /// 搜索简单表，返回映射词列表
  Future<List<String>> searchSimpleTables(String word) async {
    final db = await database;
    final results = <String>{};

    // spelling_variant: (word1, word2) - 两个互为变体
    await _searchTwoColumnTable(
      db,
      'spelling_variant',
      'word1',
      'word2',
      word,
      results,
    );

    // abbreviation: (base, full_form)
    await _searchTwoColumnTable(
      db,
      'abbreviation',
      'base',
      'full_form',
      word,
      results,
    );

    // acronym: (base, full_form)
    await _searchTwoColumnTable(
      db,
      'acronym',
      'base',
      'full_form',
      word,
      results,
    );

    // nominalization: (base, nominal)
    await _searchTwoColumnTable(
      db,
      'nominalization',
      'base',
      'nominal',
      word,
      results,
    );

    return results.toList();
  }

  Future<void> _searchTwoColumnTable(
    Database db,
    String table,
    String col1,
    String col2,
    String word,
    Set<String> results,
  ) async {
    try {
      // 正向查询：col1 -> col2
      final maps = await db.query(
        table,
        columns: [col2],
        where: '$col1 = ?',
        whereArgs: [word],
      );
      for (final map in maps) {
        if (map[col2] != null) {
          results.add(map[col2] as String);
        }
      }

      // 反向查询：col2 -> col1
      final reverseMaps = await db.query(
        table,
        columns: [col1],
        where: '$col2 = ?',
        whereArgs: [word],
      );
      for (final map in reverseMaps) {
        if (map[col1] != null) {
          results.add(map[col1] as String);
        }
      }
    } catch (e) {
      print('Error searching table $table: $e');
    }
  }

  /// 查找nominalization还原词
  /// 如果word是nominal（名词化形式），则返回对应的base词
  /// 返回 null 表示不是名词化形式
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
      print('Error searching nominalization: $e');
    }
    return null;
  }

  /// 搜索 inflection 表，返回映射词列表
  Future<List<String>> searchInflection(String word) async {
    final db = await database;
    final results = <String>{};

    // inflection: (base, plural, past, past_part, pres_part, third_sing, comp, superl)
    final cols = [
      'plural',
      'past',
      'past_part',
      'pres_part',
      'third_sing',
      'comp',
      'superl',
    ];

    for (final col in cols) {
      try {
        final maps = await db.query(
          'inflection',
          columns: ['base'],
          where: '$col = ?',
          whereArgs: [word],
        );
        for (final map in maps) {
          if (map['base'] != null) {
            results.add(map['base'] as String);
          }
        }
      } catch (e) {
        print('Error searching inflection ($col): $e');
      }
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

    // spelling_variant: (word1, word2) - 两个互为变体
    await _searchTwoColumnTableWithRelations(
      db,
      'spelling_variant',
      'word1',
      'word2',
      word,
      results,
      '拼写变体',
    );

    // abbreviation: (base, full_form)
    await _searchTwoColumnTableWithRelations(
      db,
      'abbreviation',
      'base',
      'full_form',
      word,
      results,
      '缩写',
    );

    // acronym: (base, full_form)
    await _searchTwoColumnTableWithRelations(
      db,
      'acronym',
      'base',
      'full_form',
      word,
      results,
      '首字母缩写',
    );

    // nominalization: (base, nominal)
    await _searchTwoColumnTableWithRelations(
      db,
      'nominalization',
      'base',
      'nominal',
      word,
      results,
      '名词化',
    );

    // inflection: (base, plural, past, past_part, pres_part, third_sing, comp, superl)
    final inflectionCols = {
      'plural': '复数形式',
      'past': '过去式',
      'past_part': '过去分词',
      'pres_part': '现在分词',
      'third_sing': '第三人称单数',
      'comp': '比较级',
      'superl': '最高级',
    };

    for (final entry in inflectionCols.entries) {
      final col = entry.key;
      final desc = entry.value;

      try {
        final maps = await db.query(
          'inflection',
          columns: ['base'],
          where: '$col = ?',
          whereArgs: [word],
        );

        for (final map in maps) {
          final baseWord = map['base'] as String?;
          if (baseWord != null) {
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
      } catch (e) {
        print('Error searching inflection ($col): $e');
      }
    }

    return results;
  }

  Future<void> _searchTwoColumnTableWithRelations(
    Database db,
    String table,
    String col1,
    String col2,
    String word,
    Map<String, List<SearchRelation>> results,
    String relationDesc,
  ) async {
    try {
      // 正向查询：col1 -> col2
      final maps = await db.query(
        table,
        columns: [col2],
        where: '$col1 = ?',
        whereArgs: [word],
      );

      for (final map in maps) {
        final mappedWord = map[col2] as String?;
        if (mappedWord != null) {
          results
              .putIfAbsent(mappedWord, () => [])
              .add(
                SearchRelation(
                  originalWord: word,
                  mappedWord: mappedWord,
                  relationType: table,
                  description: relationDesc,
                ),
              );
        }
      }

      // 反向查询：col2 -> col1
      final reverseMaps = await db.query(
        table,
        columns: [col1],
        where: '$col2 = ?',
        whereArgs: [word],
      );

      for (final map in reverseMaps) {
        final mappedWord = map[col1] as String?;
        if (mappedWord != null) {
          results
              .putIfAbsent(mappedWord, () => [])
              .add(
                SearchRelation(
                  originalWord: word,
                  mappedWord: mappedWord,
                  relationType: table,
                  description: relationDesc,
                ),
              );
        }
      }
    } catch (e) {
      print('Error searching table $table: $e');
    }
  }
}
