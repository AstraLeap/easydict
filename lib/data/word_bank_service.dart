import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 词表信息
class WordListInfo {
  final String name;

  WordListInfo({required this.name});

  /// 显示名称直接使用列名
  String get displayName => name;

  Map<String, dynamic> toJson() => {'name': name};

  factory WordListInfo.fromJson(Map<String, dynamic> json) =>
      WordListInfo(name: json['name'] as String);
}

/// 单词在词表中的归属信息
class WordListMembership {
  final String word;
  final String language;
  final Map<String, int> lists; // 词表名 -> 是否属于 (1/0)

  WordListMembership({
    required this.word,
    required this.language,
    required this.lists,
  });
}

class WordBankService {
  static final WordBankService _instance = WordBankService._internal();
  factory WordBankService() => _instance;
  WordBankService._internal();

  Database? _database;
  String? _dbPath;
  SharedPreferences? _prefs;

  /// 缓存的词表列（从数据库读取）
  final Map<String, List<WordListInfo>> _cachedWordLists = {};

  /// 用户自定义的词表配置
  Map<String, List<WordListInfo>> _customLists = {};

  static const String _customListsKey = 'custom_word_lists';
  static const String _lastLanguageKey = 'last_selected_language';

  /// 获取 SharedPreferences
  Future<SharedPreferences> get prefs async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      await _loadCustomLists();
    }
    return _prefs!;
  }

  /// 加载用户自定义词表
  Future<void> _loadCustomLists() async {
    final p = await SharedPreferences.getInstance();
    final customListsJson = p.getString(_customListsKey);
    if (customListsJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(customListsJson);
        _customLists = decoded.map((key, value) {
          final lists = (value as List<dynamic>)
              .map((e) => WordListInfo.fromJson(e as Map<String, dynamic>))
              .toList();
          return MapEntry(key, lists);
        });
      } catch (e) {
        _customLists = {};
      }
    }
  }

  /// 保存用户自定义词表
  Future<void> _saveCustomLists() async {
    final p = await prefs;
    final encoded = _customLists.map((key, value) {
      final lists = value.map((e) => e.toJson()).toList();
      return MapEntry(key, lists);
    });
    await p.setString(_customListsKey, jsonEncode(encoded));
  }

  /// 保存最后选择的语言
  Future<void> saveLastSelectedLanguage(String language) async {
    final p = await prefs;
    await p.setString(_lastLanguageKey, language);
  }

  /// 获取最后选择的语言
  Future<String?> getLastSelectedLanguage() async {
    final p = await prefs;
    return p.getString(_lastLanguageKey);
  }

  /// 获取数据库路径
  Future<String> get dbPath async {
    if (_dbPath == null) {
      final appDir = await getApplicationSupportDirectory();
      _dbPath = join(appDir.path, 'word_list.db');
    }
    return _dbPath!;
  }

  /// 获取数据库
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final String dbPath = await this.dbPath;

    // 检查数据库是否存在，不存在则从 assets 复制
    if (!File(dbPath).existsSync()) {
      await _copyDatabaseFromAssets(dbPath);
    }

    _database = await openDatabase(
      dbPath,
      version: 1,
      onOpen: (db) async {
        // 数据库打开时的初始化
        await _ensureCustomListsInDatabase(db);
      },
    );
    return _database!;
  }

  /// 确保自定义词表在数据库中存在
  Future<void> _ensureCustomListsInDatabase(Database db) async {
    for (final entry in _customLists.entries) {
      final language = entry.key;
      final lists = entry.value;

      // 检查表是否存在
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [language],
      );

      if (tables.isNotEmpty) {
        // 检查列是否存在
        final columns = await db.rawQuery('PRAGMA table_info($language)');
        final existingColumns = columns.map((c) => c['name'] as String).toSet();

        for (final list in lists) {
          if (!existingColumns.contains(list.name)) {
            // 添加新列
            await db.execute(
              'ALTER TABLE $language ADD COLUMN ${list.name} INTEGER DEFAULT 0',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_${language}_${list.name} ON $language(${list.name})',
            );
          }
        }
      }
    }
  }

  /// 从 assets 复制数据库到用户目录
  Future<void> _copyDatabaseFromAssets(String targetPath) async {
    try {
      // 从 assets 加载数据库
      final ByteData data = await rootBundle.load('assets/word_list.db');
      final List<int> bytes = data.buffer.asUint8List();

      // 确保目标目录存在
      final dir = Directory(dirname(targetPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 写入文件
      await File(targetPath).writeAsBytes(bytes);
    } catch (e) {
      // 如果 assets 中没有，则创建新的数据库
      await _createNewDatabase(targetPath);
    }
  }

  /// 创建新的数据库
  Future<void> _createNewDatabase(String path) async {
    final db = await openDatabase(path, version: 1);

    // 创建默认的英语词表表
    await _createLanguageTable(db, 'en');

    await db.close();
  }

  /// 系统保留列（非词表列）
  static const Set<String> _reservedColumns = {'word', 'created_at'};

  /// 创建语言表
  Future<void> _createLanguageTable(Database db, String language) async {
    // 新表只包含基础列，词表列通过 ALTER TABLE 动态添加
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $language (
        word TEXT PRIMARY KEY,
        created_at INTEGER DEFAULT 0
      )
    ''');
  }

  /// 添加新词表
  Future<bool> addWordList(String language, String listName) async {
    final db = await database;
    final langLower = language.toLowerCase();
    // 移除强制大写，保留用户输入的大小写
    final listNameClean = listName.trim();

    try {
      // 确保语言表存在
      await _ensureLanguageTableExists(db, langLower);

      // 检查列是否已存在（不区分大小写比较）
      final columns = await db.rawQuery('PRAGMA table_info($langLower)');
      final existingColumns = columns.map((c) => c['name'] as String).toSet();

      // 检查是否存在同名列（不区分大小写）
      if (existingColumns.any(
        (c) => c.toLowerCase() == listNameClean.toLowerCase(),
      )) {
        // 如果已存在但大小写不同，可能需要更新显示名称（这里简化处理，认为已存在）
        return true;
      }

      // 添加新列，使用双引号包裹以保留大小写（虽然SQLite列名通常不区分大小写，但为了显示一致性）
      // 注意：SQLite列名不区分大小写，但为了避免关键字冲突和特殊字符，建议用双引号
      await db.execute(
        'ALTER TABLE $langLower ADD COLUMN "$listNameClean" INTEGER DEFAULT 0',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS "idx_${langLower}_$listNameClean" ON $langLower("$listNameClean")',
      );

      // 保存到自定义词表配置
      _customLists[langLower] ??= [];
      final existingIndex = _customLists[langLower]!.indexWhere(
        (l) => l.name.toLowerCase() == listNameClean.toLowerCase(),
      );
      if (existingIndex < 0) {
        _customLists[langLower]!.add(WordListInfo(name: listNameClean));
      }

      await _saveCustomLists();

      // 清除缓存，下次读取时重新加载
      _clearWordListsCache(langLower);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 删除词表（删除列并清理孤立单词）
  Future<bool> removeWordList(String language, String listName) async {
    final db = await database;
    final langLower = language.toLowerCase();
    final listNameClean = listName.trim();

    try {
      // 获取当前所有词表
      final allLists = await getWordLists(langLower);
      final remainingLists = allLists
          .where((l) => l.name != listNameClean)
          .toList();

      // 获取表的所有列
      final columns = await db.rawQuery('PRAGMA table_info($langLower)');
      final allColumns = columns.map((c) => c['name'] as String).toList();

      // 构建新表的列（保留系统列和要保留的词表列）
      final newColumns = <String>[
        'word',
        'created_at',
        ...remainingLists.map((l) => l.name),
      ];

      // 开始事务
      await db.transaction((txn) async {
        // 创建新表
        final columnDefs = newColumns
            .map((col) {
              if (col == 'word') {
                return '$col TEXT PRIMARY KEY';
              } else if (col == 'created_at') {
                return '$col INTEGER DEFAULT 0';
              } else {
                // 使用双引号包裹列名
                return '"$col" INTEGER DEFAULT 0';
              }
            })
            .join(', ');

        await txn.execute('''
          CREATE TABLE ${langLower}_new ($columnDefs)
        ''');

        // 复制数据（只复制要保留的列）
        // 列名需要用双引号包裹
        final selectColumns = newColumns
            .map((c) => c == 'word' || c == 'created_at' ? c : '"$c"')
            .join(', ');
        await txn.execute('''
          INSERT INTO ${langLower}_new ($selectColumns)
          SELECT $selectColumns FROM $langLower
        ''');

        // 删除旧表
        await txn.execute('DROP TABLE $langLower');

        // 重命名新表
        await txn.execute('ALTER TABLE ${langLower}_new RENAME TO $langLower');

        // 重建索引
        for (final list in remainingLists) {
          await txn.execute(
            'CREATE INDEX IF NOT EXISTS "idx_${langLower}_${list.name}" ON $langLower("${list.name}")',
          );
        }

        // 删除不属于任何词表的单词（所有词表列都为0的行）
        if (remainingLists.isNotEmpty) {
          final allListColumns = remainingLists
              .map((l) => '"${l.name}"')
              .join(' + ');
          await txn.execute('''
            DELETE FROM $langLower
            WHERE ($allListColumns) = 0
          ''');
        } else {
          // 如果没有任何词表，删除所有单词
          await txn.execute('DELETE FROM $langLower');
        }
      });

      // 从自定义配置中移除
      if (_customLists.containsKey(langLower)) {
        _customLists[langLower]!.removeWhere((l) => l.name == listNameClean);
        await _saveCustomLists();
      }

      // 清除缓存
      _clearWordListsCache(langLower);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 重命名词表
  Future<bool> renameWordList(
    String language,
    String oldName,
    String newName,
  ) async {
    final db = await database;
    final langLower = language.toLowerCase();
    final oldNameClean = oldName.trim();
    final newNameClean = newName.trim();

    // 检查新名称是否已存在
    if (await listNameExists(langLower, newNameClean)) {
      throw Exception('词表 "$newNameClean" 已存在');
    }

    try {
      // 获取当前所有词表
      final allLists = await getWordLists(langLower);
      final renamedLists = allLists.map((l) {
        if (l.name == oldNameClean) {
          return WordListInfo(name: newNameClean);
        }
        return l;
      }).toList();

      // 获取表的所有列
      final columns = await db.rawQuery('PRAGMA table_info($langLower)');

      // 构建新表的列（替换旧列名为新列名）
      final newColumns = <String>['word', 'created_at'];
      for (final list in renamedLists) {
        newColumns.add(list.name);
      }

      // 开始事务
      await db.transaction((txn) async {
        // 创建新表
        final columnDefs = newColumns
            .map((col) {
              if (col == 'word') {
                return '$col TEXT PRIMARY KEY';
              } else if (col == 'created_at') {
                return '$col INTEGER DEFAULT 0';
              } else {
                return '"$col" INTEGER DEFAULT 0';
              }
            })
            .join(', ');

        await txn.execute('''
          CREATE TABLE ${langLower}_new ($columnDefs)
        ''');

        // 复制数据（将旧列名映射到新列名）
        final oldColumns = [
          'word',
          'created_at',
          ...allLists.map((l) => l.name),
        ];
        final selectParts = <String>[];
        for (int i = 0; i < newColumns.length; i++) {
          if (oldColumns[i] == oldNameClean) {
            selectParts.add('"$oldNameClean" AS "$newNameClean"');
          } else {
            final col = oldColumns[i];
            if (col == 'word' || col == 'created_at') {
              selectParts.add('$col AS ${newColumns[i]}');
            } else {
              selectParts.add('"$col" AS "${newColumns[i]}"');
            }
          }
        }
        final selectClause = selectParts.join(', ');

        await txn.execute('''
          INSERT INTO ${langLower}_new
          SELECT $selectClause FROM $langLower
        ''');

        // 删除旧表
        await txn.execute('DROP TABLE $langLower');

        // 重命名新表
        await txn.execute('ALTER TABLE ${langLower}_new RENAME TO $langLower');

        // 重建索引
        for (final list in renamedLists) {
          await txn.execute(
            'CREATE INDEX IF NOT EXISTS "idx_${langLower}_${list.name}" ON $langLower("${list.name}")',
          );
        }
      });

      // 更新自定义配置
      if (_customLists.containsKey(langLower)) {
        final index = _customLists[langLower]!.indexWhere(
          (l) => l.name == oldNameClean,
        );
        if (index >= 0) {
          _customLists[langLower]![index] = WordListInfo(name: newNameClean);
          await _saveCustomLists();
        }
      }

      // 清除缓存
      _clearWordListsCache(langLower);

      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// 重新排序词表（通过重建表来调整列顺序）
  Future<bool> reorderWordLists(String language, List<String> newOrder) async {
    final db = await database;
    final langLower = language.toLowerCase();

    try {
      // 获取当前所有词表
      final currentLists = await getWordLists(langLower);
      final currentNames = currentLists.map((l) => l.name).toSet();

      // 构建新表的列顺序
      final newColumns = <String>['word', 'created_at'];
      for (final name in newOrder) {
        // 确保该列确实存在
        if (currentNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
          // 找到原始名称（保持大小写一致）
          final originalName = currentNames.firstWhere(
            (n) => n.toLowerCase() == name.toLowerCase(),
          );
          newColumns.add(originalName);
        }
      }

      // 如果有遗漏的列，追加到后面（防止数据丢失）
      for (final name in currentNames) {
        if (!newColumns.any((c) => c.toLowerCase() == name.toLowerCase())) {
          newColumns.add(name);
        }
      }

      // 开始事务
      await db.transaction((txn) async {
        // 创建新表
        final columnDefs = newColumns
            .map((col) {
              if (col == 'word') {
                return '$col TEXT PRIMARY KEY';
              } else if (col == 'created_at') {
                return '$col INTEGER DEFAULT 0';
              } else {
                return '"$col" INTEGER DEFAULT 0';
              }
            })
            .join(', ');

        await txn.execute('''
          CREATE TABLE ${langLower}_new ($columnDefs)
        ''');

        // 复制数据
        final selectColumns = newColumns
            .map((c) => c == 'word' || c == 'created_at' ? c : '"$c"')
            .join(', ');
        await txn.execute('''
          INSERT INTO ${langLower}_new ($selectColumns)
          SELECT $selectColumns FROM $langLower
        ''');

        // 删除旧表
        await txn.execute('DROP TABLE $langLower');

        // 重命名新表
        await txn.execute('ALTER TABLE ${langLower}_new RENAME TO $langLower');

        // 重建索引
        for (final col in newColumns) {
          if (col != 'word' && col != 'created_at') {
            await txn.execute(
              'CREATE INDEX IF NOT EXISTS "idx_${langLower}_$col" ON $langLower("$col")',
            );
          }
        }
      });

      // 更新自定义配置中的顺序
      if (_customLists.containsKey(langLower)) {
        final customListMap = {
          for (var l in _customLists[langLower]!) l.name: l,
        };
        final newCustomLists = <WordListInfo>[];
        for (final name in newOrder) {
          final matchedKey = customListMap.keys.firstWhere(
            (k) => k.toLowerCase() == name.toLowerCase(),
            orElse: () => '',
          );
          if (matchedKey.isNotEmpty) {
            newCustomLists.add(customListMap[matchedKey]!);
          }
        }
        // 添加遗漏的
        for (final l in _customLists[langLower]!) {
          if (!newCustomLists.contains(l)) {
            newCustomLists.add(l);
          }
        }
        _customLists[langLower] = newCustomLists;
        await _saveCustomLists();
      }

      // 清除缓存
      _clearWordListsCache(langLower);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取某个语言的所有词表（从数据库读取）- 异步版本
  Future<List<WordListInfo>> getWordLists(String language) async {
    final langLower = language.toLowerCase();

    // 检查缓存
    if (_cachedWordLists.containsKey(langLower)) {
      return _cachedWordLists[langLower]!;
    }

    // 从数据库获取词表列（顺序即为数据库列顺序）
    final columns = await getWordListColumnsFromDb(language);
    final dbLists = columns.map((name) => WordListInfo(name: name)).toList();

    // 合并自定义词表（仅用于补充可能不在数据库中的信息，如果有的话，但目前主要依赖数据库列）
    // 注意：getWordListColumnsFromDb 返回的已经是按数据库列顺序排列的

    // 缓存结果
    _cachedWordLists[langLower] = dbLists;
    return dbLists;
  }

  /// 获取某个语言的所有词表（从缓存读取）- 同步版本，仅用于UI渲染
  /// 如果缓存不存在，返回空列表
  List<WordListInfo> getWordListsSync(String language) {
    final langLower = language.toLowerCase();
    return _cachedWordLists[langLower] ?? [];
  }

  /// 清除词表缓存（在添加新词表后调用）
  void _clearWordListsCache(String language) {
    _cachedWordLists.remove(language.toLowerCase());
  }

  /// 从数据库获取某个语言的所有词表列（排除系统保留列）
  Future<List<String>> getWordListColumnsFromDb(String language) async {
    final db = await database;
    final langLower = language.toLowerCase();

    try {
      final columns = await db.rawQuery('PRAGMA table_info($langLower)');
      return columns
          .map((c) => c['name'] as String)
          .where((name) => !_reservedColumns.contains(name))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取所有支持的语言
  Future<List<String>> getSupportedLanguages() async {
    final db = await database;
    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ''');
    return tables.map((t) => t['name'] as String).toList();
  }

  /// 添加单词到单词本
  /// [word] 单词
  /// [language] 语言代码（如 'en'）
  /// [lists] 要添加到的词表列表，空列表则添加到默认词表
  Future<bool> addWord(
    String word,
    String language, {
    List<String>? lists,
  }) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();

    // 确保语言表存在
    await _ensureLanguageTableExists(db, langLower);

    // 获取该语言的所有词表
    final allLists = await getWordLists(langLower);
    final defaultList = allLists.isNotEmpty ? allLists.first.name : 'DEFAULT';

    // 确定要添加到的词表
    final targetLists = lists?.isNotEmpty == true ? lists! : [defaultList];

    try {
      // 检查单词是否已存在
      final existing = await db.query(
        langLower,
        where: 'word = ?',
        whereArgs: [wordLower],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // 已存在，更新词表归属
        final updates = <String, int>{};
        for (final listName in targetLists) {
          // 查找匹配的词表名（不区分大小写）
          final matchedList = allLists.firstWhere(
            (l) => l.name.toLowerCase() == listName.toLowerCase(),
            orElse: () => WordListInfo(name: listName),
          );
          // 使用双引号包裹列名以支持特殊字符
          updates['"${matchedList.name}"'] = 1;
        }

        // 使用 rawUpdate 以确保列名被正确引用
        final setClause = updates.keys.map((k) => '$k = ?').join(', ');
        final args = [...updates.values, wordLower];

        await db.rawUpdate(
          'UPDATE $langLower SET $setClause WHERE word = ?',
          args,
        );
      } else {
        // 不存在，插入新记录
        final values = <String, dynamic>{
          'word': wordLower,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        };
        for (final list in allLists) {
          final isTarget = targetLists.any(
            (e) => e.toLowerCase() == list.name.toLowerCase(),
          );
          values['"${list.name}"'] = isTarget ? 1 : 0;
        }

        final columns = values.keys.join(', ');
        final placeholders = List.filled(values.length, '?').join(', ');
        final args = values.values.toList();

        await db.rawInsert(
          'INSERT INTO $langLower ($columns) VALUES ($placeholders)',
          args,
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 确保语言表存在
  Future<void> _ensureLanguageTableExists(Database db, String language) async {
    final tables = await db.rawQuery(
      '''
      SELECT name FROM sqlite_master 
      WHERE type='table' AND name = ?
    ''',
      [language],
    );

    if (tables.isEmpty) {
      await _createLanguageTable(db, language);
    }
  }

  /// 从单词本删除单词
  /// [word] 单词
  /// [language] 语言代码
  Future<bool> removeWord(String word, String language) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();

    try {
      final count = await db.delete(
        langLower,
        where: 'word = ?',
        whereArgs: [wordLower],
      );
      return count > 0;
    } catch (e) {
      return false;
    }
  }

  /// 从指定词表中移除单词（将对应列设为0）
  Future<bool> removeWordFromList(
    String word,
    String language,
    String listName,
  ) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();
    final listNameClean = listName.trim();

    try {
      await db.rawUpdate(
        'UPDATE $langLower SET "$listNameClean" = 0 WHERE word = ?',
        [wordLower],
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 调整单词的词表归属
  /// [word] 单词
  /// [language] 语言代码
  /// [listChanges] 词表变更映射（词表名 -> 是否属于）
  Future<bool> updateWordLists(
    String word,
    String language,
    Map<String, int> listChanges,
  ) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();

    try {
      // 检查单词是否存在
      final existing = await db.query(
        langLower,
        where: 'word = ?',
        whereArgs: [wordLower],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // 更新现有记录
        final updates = <String>[];
        final args = <dynamic>[];
        listChanges.forEach((key, value) {
          updates.add('"$key" = ?');
          args.add(value);
        });
        args.add(wordLower);

        await db.rawUpdate(
          'UPDATE $langLower SET ${updates.join(', ')} WHERE word = ?',
          args,
        );
      } else {
        // 插入新记录
        final values = <String, dynamic>{
          'word': wordLower,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        };
        final allLists = await getWordLists(langLower);
        for (final list in allLists) {
          values[list.name] = listChanges[list.name] ?? 0;
        }

        final columns = values.keys
            .map((k) => k == 'word' || k == 'created_at' ? k : '"$k"')
            .join(', ');
        final placeholders = List.filled(values.length, '?').join(', ');
        final args = values.values.toList();

        await db.rawInsert(
          'INSERT INTO $langLower ($columns) VALUES ($placeholders)',
          args,
        );
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检查单词是否在单词本中
  Future<bool> isInWordBank(String word, String language) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();

    try {
      final result = await db.query(
        langLower,
        where: 'word = ?',
        whereArgs: [wordLower],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 获取单词的词表归属信息
  Future<WordListMembership?> getWordMembership(
    String word,
    String language,
  ) async {
    final db = await database;
    final wordLower = word.toLowerCase();
    final langLower = language.toLowerCase();

    try {
      final result = await db.query(
        langLower,
        where: 'word = ?',
        whereArgs: [wordLower],
        limit: 1,
      );

      if (result.isEmpty) return null;

      final row = result.first;
      final lists = <String, int>{};

      // 获取所有词表列
      final allLists = await getWordLists(langLower);
      for (final list in allLists) {
        lists[list.name] = row[list.name] as int? ?? 0;
      }

      return WordListMembership(
        word: wordLower,
        language: langLower,
        lists: lists,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取某个语言的所有单词
  /// [sortBy] 排序方式: 'word' 字母顺序, 'created_at' 添加时间, 'random' 随机
  /// [ascending] 是否升序，默认true
  /// [offset] 偏移量，用于分页
  /// [limit] 限制数量，用于分页
  Future<List<Map<String, dynamic>>> getWordsByLanguage(
    String language, {
    String sortBy = 'word',
    bool ascending = true,
    int offset = 0,
    int? limit,
  }) async {
    final db = await database;
    final langLower = language.toLowerCase();

    String orderBy;
    if (sortBy == 'random') {
      // SQLite 的随机排序
      orderBy = 'RANDOM()';
    } else {
      final direction = ascending ? 'ASC' : 'DESC';
      orderBy = '$sortBy $direction';
    }

    try {
      String? limitClause;
      List<dynamic>? limitArgs;

      if (limit != null) {
        limitClause = 'LIMIT ? OFFSET ?';
        limitArgs = [limit, offset];
      } else {
        limitClause = 'LIMIT ? OFFSET ?';
        limitArgs = [2147483647, offset];
      }

      final query = 'SELECT * FROM $langLower ORDER BY $orderBy $limitClause';
      return await db.rawQuery(query, limitArgs);
    } catch (e) {
      return [];
    }
  }

  /// 获取某个词表的所有单词
  Future<List<Map<String, dynamic>>> getWordsByList(
    String language,
    String listName,
  ) async {
    final db = await database;
    final langLower = language.toLowerCase();
    final listNameClean = listName.trim();

    try {
      return await db.query(
        langLower,
        where: '"$listNameClean" = ?',
        whereArgs: [1],
        orderBy: 'word ASC',
      );
    } catch (e) {
      return [];
    }
  }

  /// 搜索单词
  Future<List<Map<String, dynamic>>> searchWords(
    String query,
    String language,
  ) async {
    final db = await database;
    final queryLower = query.toLowerCase();
    final langLower = language.toLowerCase();

    try {
      return await db.query(
        langLower,
        where: 'word LIKE ?',
        whereArgs: ['%$queryLower%'],
        orderBy: 'word ASC',
      );
    } catch (e) {
      return [];
    }
  }

  /// 获取某个语言的单词数量
  Future<int> getWordCount(String language) async {
    final db = await database;
    final langLower = language.toLowerCase();

    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $langLower',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 获取某个词表的单词数量
  Future<int> getListWordCount(String language, String listName) async {
    final db = await database;
    final langLower = language.toLowerCase();
    final listNameClean = listName.trim();

    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $langLower WHERE "$listNameClean" = ?',
        [1],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 批量导入单词到词表
  /// [language] 语言代码
  /// [listName] 词表名称
  /// [words] 要导入的单词列表
  /// 返回成功导入的单词数量
  Future<int> importWordsToList(
    String language,
    String listName,
    List<String> words,
  ) async {
    final db = await database;
    final langLower = language.toLowerCase();
    final listNameClean = listName.trim();

    // 1. 检查词表名是否已存在（不区分大小写）
    final wordLists = await getWordLists(langLower);
    if (wordLists.any(
      (l) => l.name.toLowerCase() == listNameClean.toLowerCase(),
    )) {
      throw Exception('词表 "$listNameClean" 已存在');
    }

    // 2. 创建新词表列
    await addWordList(langLower, listNameClean);

    int importedCount = 0;

    // 3. 批量导入单词
    for (final word in words) {
      final wordLower = word.toLowerCase().trim();
      if (wordLower.isEmpty) continue;

      try {
        // 检查单词是否已存在
        final existing = await db.query(
          langLower,
          where: 'word = ?',
          whereArgs: [wordLower],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          // 已存在，更新词表归属
          await db.update(
            langLower,
            {'"$listNameClean"': 1},
            where: 'word = ?',
            whereArgs: [wordLower],
          );
        } else {
          // 不存在，插入新记录
          final values = <String, dynamic>{
            'word': wordLower,
            'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            '"$listNameClean"': 1,
          };

          // 初始化其他词表列为0
          for (final list in wordLists) {
            if (list.name.toLowerCase() != listNameClean.toLowerCase()) {
              values['"${list.name}"'] = 0;
            }
          }

          final columns = values.keys.join(', ');
          final placeholders = List.filled(values.length, '?').join(', ');
          final args = values.values.toList();

          await db.rawInsert(
            'INSERT INTO $langLower ($columns) VALUES ($placeholders)',
            args,
          );
        }
        importedCount++;
      } catch (e) {
        // 忽略单个单词导入错误
        continue;
      }
    }

    return importedCount;
  }

  /// 检查词表名是否已存在
  Future<bool> listNameExists(String language, String listName) async {
    final wordLists = await getWordLists(language);
    final listNameClean = listName.trim();
    return wordLists.any(
      (l) => l.name.toLowerCase() == listNameClean.toLowerCase(),
    );
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
