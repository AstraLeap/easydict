import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class WordBankService {
  static final WordBankService _instance = WordBankService._internal();
  factory WordBankService() => _instance;
  WordBankService._internal();

  Database? _database;
  String? _userDataPath;

  Future<String> get userDataPath async {
    if (_userDataPath == null) {
      final appDir = await getApplicationSupportDirectory();
      _userDataPath = join(appDir.path, 'word_list.db');
    }
    return _userDataPath!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String dbPath = await userDataPath;

    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS word_bank (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headword TEXT NOT NULL UNIQUE,
            added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_word_bank_headword ON word_bank(headword)
        ''');
      },
    );
    return _database!;
  }

  Future<bool> addFavorite(String headword) async {
    final db = await database;
    final headwordLower = headword.toLowerCase();

    try {
      await db.insert('word_bank', {'headword': headwordLower});
      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> isFavorite(String headword) async {
    final db = await database;
    final headwordLower = headword.toLowerCase();

    final result = await db.query(
      'word_bank',
      where: 'LOWER(headword) = ?',
      whereArgs: [headwordLower],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> removeFavorite(String headword) async {
    final db = await database;
    final headwordLower = headword.toLowerCase();

    await db.delete(
      'word_bank',
      where: 'LOWER(headword) = ?',
      whereArgs: [headwordLower],
    );
  }

  Future<void> removeFavoriteById(int id) async {
    final db = await database;
    await db.delete('word_bank', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    final db = await database;
    return db.query('word_bank', orderBy: 'added_at DESC');
  }

  Future<List<Map<String, dynamic>>> searchFavorites(String query) async {
    final db = await database;
    final queryLower = query.toLowerCase();
    return db.query(
      'word_bank',
      where: 'LOWER(headword) LIKE ?',
      whereArgs: ['%$queryLower%'],
      orderBy: 'added_at DESC',
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

class FavoriteWord {
  final int id;
  final String headword;
  final int addedAt;

  FavoriteWord({
    required this.id,
    required this.headword,
    required this.addedAt,
  });

  factory FavoriteWord.fromJson(Map<String, dynamic> json) {
    return FavoriteWord(
      id: json['id'] as int,
      headword: json['headword'] as String,
      addedAt: json['added_at'] as int,
    );
  }
}
