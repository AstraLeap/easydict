import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import '../core/logger.dart';
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
  }) : createdAt = createdAt ?? DateTime.now(),
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

  Note copyWith({String? content, DateTime? updatedAt}) => Note(
    word: word,
    language: language,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

/// 笔记服务
class NoteService {
  static const String _logTag = 'NoteMedia';
  static final NoteService _instance = NoteService._internal();
  factory NoteService() => _instance;
  NoteService._internal();

  static const String _tableName = 'notes';
  static const String _mediaTableName = 'medias';
  static final RegExp _mediaLinkPattern = RegExp(
    r'!\[[^\]]*\]\(media://([^\)\s]+)\)',
    caseSensitive: false,
  );
  static final RegExp _mediaImagePattern = RegExp(
    r'!\[([^\]]*)\]\(media://([^\)\s]+)\)',
    caseSensitive: false,
  );
  // 匹配网络图片：http:// 或 https:// 开头的图片链接
  static final RegExp _networkImagePattern = RegExp(
    r'!\[([^\]]*)\]\((https?://[^\)\s]+)\)',
    caseSensitive: false,
  );

  static String upsertMediaWidthPercentInMarkdown({
    required String markdown,
    required String mediaName,
    required int widthPercent,
  }) {
    if (markdown.isEmpty || mediaName.isEmpty) {
      return markdown;
    }

    final clampedPercent = widthPercent.clamp(1, 100);

    // 先尝试匹配 media:// 图片
    var result = markdown.replaceAllMapped(_mediaImagePattern, (match) {
      final alt = match.group(1) ?? '';
      final rawName = match.group(2) ?? '';
      final decodedName = Uri.decodeComponent(rawName);
      if (decodedName.toLowerCase() != mediaName.toLowerCase()) {
        return match.group(0)!;
      }
      final nextAlt = _upsertWidthInAlt(alt, clampedPercent);
      return '![$nextAlt](media://$rawName)';
    });

    // 再尝试匹配网络图片 URL
    result = result.replaceAllMapped(_networkImagePattern, (match) {
      final alt = match.group(1) ?? '';
      final url = match.group(2) ?? '';
      if (url.toLowerCase() != mediaName.toLowerCase()) {
        return match.group(0)!;
      }
      final nextAlt = _upsertWidthInAlt(alt, clampedPercent);
      return '![$nextAlt]($url)';
    });

    return result;
  }

  static String _upsertWidthInAlt(String alt, int widthPercent) {
    final rawParts = alt.split('|');
    final cleanedParts = <String>[];
    for (final part in rawParts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex <= 0) {
        cleanedParts.add(trimmed);
        continue;
      }
      final key = trimmed.substring(0, eqIndex).trim().toLowerCase();
      if (key == 'w' || key == 'width') {
        continue;
      }
      cleanedParts.add(trimmed);
    }

    cleanedParts.add('w=$widthPercent%');
    return cleanedParts.join('|');
  }

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
    final oldRefs = _extractMediaRefs(existing?.content ?? '');
    final newRefs = _extractMediaRefs(note.content);

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

    final removedRefs = oldRefs.difference(newRefs);
    if (removedRefs.isNotEmpty) {
      await _cleanupUnreferencedMedias(candidates: removedRefs);
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
      await saveNote(Note(word: word, language: language, content: content));
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
    final existing = await getNote(word, language);
    final removedRefs = _extractMediaRefs(existing?.content ?? '');
    await db.delete(
      _tableName,
      where: 'word = ? AND language = ?',
      whereArgs: [word.toLowerCase(), language.toLowerCase()],
    );
    if (removedRefs.isNotEmpty) {
      await _cleanupUnreferencedMedias(candidates: removedRefs);
    }
  }

  /// 检查笔记是否存在且非空
  Future<bool> hasNote(String word, String language) async {
    final note = await getNote(word, language);
    return note != null && note.isNotEmpty;
  }

  /// 保存媒体（若重名则自动追加序号）
  Future<String> saveMedia({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final db = await _database;
    Logger.d(
      'saveMedia start: fileName=$fileName bytes=${bytes.length}',
      tag: _logTag,
    );
    final resolvedName = await _resolveMediaName(db, fileName);
    await db.insert(_mediaTableName, {
      'name': resolvedName,
      'blob': bytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    Logger.i('saveMedia success: resolvedName=$resolvedName', tag: _logTag);
    return resolvedName;
  }

  /// 读取媒体二进制
  Future<Uint8List?> getMedia(String name) async {
    final db = await _database;
    var rows = await db.query(
      _mediaTableName,
      columns: ['blob'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    // 部分平台会把 media:// 的 host 规范化为小写，导致大小写敏感匹配失败。
    if (rows.isEmpty) {
      rows = await db.query(
        _mediaTableName,
        columns: ['blob'],
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [name],
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    final blob = rows.first['blob'];
    if (blob is Uint8List) {
      return blob;
    }
    if (blob is List<int>) {
      return Uint8List.fromList(blob);
    }
    return null;
  }

  Future<String> _resolveMediaName(Database db, String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    final hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1;
    final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
    final extension = hasExtension ? fileName.substring(dotIndex) : '';

    var candidate = fileName;
    var suffix = 1;
    while (await _mediaExists(db, candidate)) {
      candidate = '${baseName}_$suffix$extension';
      suffix++;
    }
    return candidate;
  }

  Future<bool> _mediaExists(Database db, String name) async {
    final result = await db.query(
      _mediaTableName,
      columns: ['name'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Set<String> _extractMediaRefs(String markdown) {
    if (markdown.isEmpty || !markdown.contains('media://')) {
      return <String>{};
    }
    final refs = <String>{};
    for (final match in _mediaLinkPattern.allMatches(markdown)) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) {
        continue;
      }
      refs.add(Uri.decodeComponent(raw));
    }
    return refs;
  }

  Future<void> _cleanupUnreferencedMedias({Set<String>? candidates}) async {
    final db = await _database;
    final noteRows = await db.query(
      _tableName,
      columns: ['content'],
      where: 'content LIKE ?',
      whereArgs: ['%media://%'],
    );

    final referenced = <String>{};
    for (final row in noteRows) {
      final content = row['content'] as String? ?? '';
      referenced.addAll(_extractMediaRefs(content));
    }

    Set<String> targetSet;
    if (candidates != null) {
      targetSet = candidates.difference(referenced);
    } else {
      final allMediaRows = await db.query(_mediaTableName, columns: ['name']);
      final allMediaNames = allMediaRows
          .map((row) => row['name'] as String)
          .toSet();
      targetSet = allMediaNames.difference(referenced);
    }

    if (targetSet.isEmpty) {
      return;
    }

    final batch = db.batch();
    for (final name in targetSet) {
      batch.delete(_mediaTableName, where: 'name = ?', whereArgs: [name]);
    }
    await batch.commit(noResult: true);
  }
}
