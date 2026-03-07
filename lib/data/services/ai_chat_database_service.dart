import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/logger.dart';
import 'database_initializer.dart';

/// AI聊天记录模型
class AiChatRecordModel {
  final String id;

  /// 所属会话ID，同一会话的多条消息共享此ID（默认等于首条消息的 id）
  final String conversationId;
  final String word;
  final String question;
  final String answer;
  final DateTime timestamp;
  final String? path;
  final String? elementJson;

  /// 发起聊天时所在的词典ID（元素询问和总结时有值，自由聊天为null）
  final String? dictionaryId;

  AiChatRecordModel({
    required this.id,
    String? conversationId,
    required this.word,
    required this.question,
    required this.answer,
    required this.timestamp,
    this.path,
    this.elementJson,
    this.dictionaryId,
  }) : conversationId = conversationId ?? id;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'word': word,
      'question': question,
      'answer': answer,
      'timestamp': timestamp.toIso8601String(),
      'path': path,
      'elementJson': elementJson,
      'dictionaryId': dictionaryId,
    };
  }

  factory AiChatRecordModel.fromJson(Map<String, dynamic> json) {
    return AiChatRecordModel(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String?,
      word: json['word'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      path: json['path'] as String?,
      elementJson: json['elementJson'] as String?,
      dictionaryId: json['dictionaryId'] as String?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'word': word,
      'question': question,
      'answer': answer,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'path': path,
      'elementJson': elementJson,
      'dictionaryId': dictionaryId,
    };
  }

  factory AiChatRecordModel.fromDbMap(Map<String, dynamic> map) {
    return AiChatRecordModel(
      id: map['id'] as String,
      conversationId: map['conversationId'] as String?,
      word: map['word'] as String,
      question: map['question'] as String,
      answer: map['answer'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      path: map['path'] as String?,
      elementJson: map['elementJson'] as String?,
      dictionaryId: map['dictionaryId'] as String?,
    );
  }
}

/// AI聊天记录数据库服务
class AiChatDatabaseService {
  static final AiChatDatabaseService _instance =
      AiChatDatabaseService._internal();
  factory AiChatDatabaseService() => _instance;
  AiChatDatabaseService._internal();

  Database? _database;
  String? _dbPath;

  static const String _tableName = 'ai_chat_history';
  static const String _autoCleanupKey = 'ai_chat_auto_cleanup_days';

  /// 获取数据库路径
  Future<String> get _databasePath async {
    if (_dbPath == null) {
      final appDir = await getApplicationSupportDirectory();
      _dbPath = join(appDir.path, 'ai_chat_history.db');
    }
    return _dbPath!;
  }

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final String dbPath = await _databasePath;
    Logger.i('AI聊天记录数据库路径: $dbPath', tag: 'AiChatDatabase');

    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_tableName (
            id TEXT PRIMARY KEY,
            conversationId TEXT NOT NULL,
            word TEXT NOT NULL,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            path TEXT,
            elementJson TEXT,
            dictionaryId TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_timestamp ON $_tableName(timestamp)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_word ON $_tableName(word)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_conversation ON $_tableName(conversationId)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 添加 conversationId 列，历史记录以自身 id 作为会话ID
          await db.execute('''
            ALTER TABLE $_tableName ADD COLUMN conversationId TEXT
          ''');
          await db.execute('''
            UPDATE $_tableName SET conversationId = id WHERE conversationId IS NULL
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_conversation ON $_tableName(conversationId)
          ''');
        }
        if (oldVersion < 3) {
          // 添加 dictionaryId 列，记录发起聊天时所在的词典
          await db.execute('''
            ALTER TABLE $_tableName ADD COLUMN dictionaryId TEXT
          ''');
        }
      },
    );
  }

  /// 获取所有聊天记录
  Future<List<AiChatRecordModel>> getAllRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => AiChatRecordModel.fromDbMap(map)).toList();
  }

  /// 获取指定单词的聊天记录
  Future<List<AiChatRecordModel>> getRecordsByWord(String word) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'word = ?',
      whereArgs: [word],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => AiChatRecordModel.fromDbMap(map)).toList();
  }

  /// 添加聊天记录
  Future<void> addRecord(AiChatRecordModel record) async {
    final db = await database;
    await db.insert(
      _tableName,
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 检查并执行自动清理
    await _autoCleanupIfNeeded();
  }

  /// 更新聊天记录
  Future<void> updateRecord(AiChatRecordModel record) async {
    final db = await database;
    await db.update(
      _tableName,
      record.toDbMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  /// 删除单条聊天记录
  Future<void> deleteRecord(String id) async {
    final db = await database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// 清空所有聊天记录
  Future<void> clearAllRecords() async {
    final db = await database;
    await db.delete(_tableName);
    Logger.i('已清空所有AI聊天记录', tag: 'AiChatDatabase');
  }

  /// 清除指定天数前的聊天记录
  Future<int> clearRecordsBeforeDays(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;

    final count = await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );

    Logger.i('已清除 $days 天前的 $count 条AI聊天记录', tag: 'AiChatDatabase');
    return count;
  }

  /// 获取聊天记录总数
  Future<int> getRecordCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $_tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 设置自动清理天数（0表示不自动清理）
  Future<void> setAutoCleanupDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoCleanupKey, days);
  }

  /// 获取自动清理天数
  Future<int> getAutoCleanupDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoCleanupKey) ?? 0;
  }

  /// 执行自动清理
  Future<void> _autoCleanupIfNeeded() async {
    final days = await getAutoCleanupDays();
    if (days > 0) {
      await clearRecordsBeforeDays(days);
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
