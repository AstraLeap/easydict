import 'package:sqflite/sqflite.dart';
import '../data/word_bank_service.dart';

/// 笔记模型
class Note {
  final String word;
  final String language;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.word,
    required this.language,
    this.content = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => content.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toDbMap() => {
        'word': word.toLowerCase(),
        'language': language.toLowerCase(),
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromDbMap(Map<String, dynamic> map) => Note(
        word: map['word'] as String,
        language: map['language'] as String,
        content: map['content'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int? ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          map['updated_at'] as int? ?? 0,
        ),
      );

  Note copyWith({
    String? content,
    DateTime? updatedAt,
  }) =>
      Note(
        word: word,
        language: language,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}

/// 笔记服务
class NoteService {
  static final NoteService _instance = NoteService._internal();
  factory NoteService() => _instance;
  NoteService._internal();

  static const String _tableName = 'notes';

  Future<Database> get _database async => (await WordBankService().database);

  /// 获取笔记
  Future<Note?> getNote(String word, String language) async {
    final db = await _database;
    final results = await db.query(
      _tableName,
      where: 'word = ? AND language = ?',
      whereArgs: [word.toLowerCase(), language.toLowerCase()],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Note.fromDbMap(results.first);
  }

  /// 保存笔记（插入或更新）
  Future<void> saveNote(Note note) async {
    final db = await _database;
    final existing = await getNote(note.word, note.language);

    if (existing != null) {
      await db.update(
        _tableName,
        note.toDbMap(),
        where: 'word = ? AND language = ?',
        whereArgs: [note.word.toLowerCase(), note.language.toLowerCase()],
      );
    } else {
      await db.insert(
        _tableName,
        note.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 追加内容到笔记
  Future<void> appendToNote(
    String word,
    String language,
    String content,
  ) async {
    final existing = await getNote(word, language);
    if (existing == null) {
      await saveNote(Note(
        word: word,
        language: language,
        content: content,
      ));
    } else {
      final newContent = existing.content.isNotEmpty
          ? '${existing.content}  \n$content'
          : content;
      await saveNote(existing.copyWith(content: newContent));
    }
  }

  /// 删除笔记
  Future<void> deleteNote(String word, String language) async {
    final db = await _database;
    await db.delete(
      _tableName,
      where: 'word = ? AND language = ?',
      whereArgs: [word.toLowerCase(), language.toLowerCase()],
    );
  }

  /// 检查笔记是否存在且非空
  Future<bool> hasNote(String word, String language) async {
    final note = await getNote(word, language);
    return note != null && note.isNotEmpty;
  }
}
