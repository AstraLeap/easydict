/// AI聊天记录（UI层模型，用于页面内展示流式聊天历史）
class AiChatRecord {
  final String id;

  /// 所属会话ID，同一会话的多条消息共享此ID（默认等于首条消息的 id）
  final String conversationId;
  final String word;
  final String question;
  String answer;

  /// 深度思考内容（流式时实时更新）
  String? thinkingContent;
  final DateTime timestamp;
  final String? path;
  final String? elementJson; // 存储查询的JSON内容

  /// 发起聊天时所在的词典ID（元素询问和总结时有值，自由聊天为null）
  final String? dictionaryId;

  AiChatRecord({
    required this.id,
    String? conversationId,
    required this.word,
    required this.question,
    required this.answer,
    required this.timestamp,
    this.thinkingContent,
    this.path,
    this.elementJson,
    this.dictionaryId,
  }) : conversationId = conversationId ?? id;
}
