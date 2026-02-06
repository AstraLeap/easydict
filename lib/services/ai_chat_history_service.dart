import 'ai_chat_database_service.dart';
export 'ai_chat_database_service.dart' show AiChatRecordModel;

/// AI聊天记录服务（兼容层，使用新的数据库服务）
class AiChatHistoryService {
  static final AiChatHistoryService _instance = AiChatHistoryService._internal();
  factory AiChatHistoryService() => _instance;
  AiChatHistoryService._internal();

  final _databaseService = AiChatDatabaseService();

  /// 获取所有聊天记录
  Future<List<AiChatRecordModel>> getAllRecords() async {
    return await _databaseService.getAllRecords();
  }

  /// 获取指定单词的聊天记录
  Future<List<AiChatRecordModel>> getRecordsByWord(String word) async {
    return await _databaseService.getRecordsByWord(word);
  }

  /// 添加聊天记录
  Future<void> addRecord(AiChatRecordModel record) async {
    await _databaseService.addRecord(record);
  }

  /// 更新聊天记录
  Future<void> updateRecord(AiChatRecordModel record) async {
    await _databaseService.updateRecord(record);
  }

  /// 删除单条聊天记录
  Future<void> deleteRecord(String id) async {
    await _databaseService.deleteRecord(id);
  }

  /// 清空所有聊天记录
  Future<void> clearAllRecords() async {
    await _databaseService.clearAllRecords();
  }

  /// 清除指定天数前的聊天记录
  Future<int> clearRecordsBeforeDays(int days) async {
    return await _databaseService.clearRecordsBeforeDays(days);
  }

  /// 获取聊天记录总数
  Future<int> getRecordCount() async {
    return await _databaseService.getRecordCount();
  }

  /// 设置自动清理天数（0表示不自动清理）
  Future<void> setAutoCleanupDays(int days) async {
    await _databaseService.setAutoCleanupDays(days);
  }

  /// 获取自动清理天数
  Future<int> getAutoCleanupDays() async {
    return await _databaseService.getAutoCleanupDays();
  }
}
