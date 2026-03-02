/// AI聊天记录（UI层模型，用于页面内展示流式聊天历史）
class AiChatRecord {
  final String id;
  final String word;
  final String question;
  String answer;

  /// 深度思考内容（流式时实时更新）
  String? thinkingContent;
  final DateTime timestamp;
  final String? path;
  final String? elementJson; // 存储查询的JSON内容

  AiChatRecord({
    required this.id,
    required this.word,
    required this.question,
    required this.answer,
    required this.timestamp,
    this.thinkingContent,
    this.path,
    this.elementJson,
  });
}
