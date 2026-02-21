/// 用户上传的词典模型
class UserDictionary {
  final String dictId;
  final String name;
  final bool hasMedia;
  final DateTime createdAt;
  final DateTime updatedAt;

  // 从 metadata.json 解析的额外信息（可选）
  final String? sourceLanguage;
  final String? targetLanguage;

  UserDictionary({
    required this.dictId,
    required this.name,
    required this.hasMedia,
    required this.createdAt,
    required this.updatedAt,
    this.sourceLanguage,
    this.targetLanguage,
  });

  factory UserDictionary.fromJson(Map<String, dynamic> json) {
    return UserDictionary(
      dictId: json['dict_id'] as String,
      name: json['name'] as String,
      hasMedia: json['has_media'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sourceLanguage: json['source_language'] as String?,
      targetLanguage: json['target_language'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dict_id': dictId,
      'name': name,
      'has_media': hasMedia,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
    };
  }
}

/// 上传词典结果
class UploadResult {
  final bool success;
  final String? error;
  final String? dictId;
  final String? name;

  UploadResult({required this.success, this.error, this.dictId, this.name});
}

/// 条目更新结果
class EntryUpdateResult {
  final bool success;
  final String? error;
  final String? action;
  final String? entryId;

  EntryUpdateResult({
    required this.success,
    this.error,
    this.action,
    this.entryId,
  });
}

/// 词典条目模型
class DictionaryEntry {
  final String entryId;
  final String headword;
  final String entryType;
  final String definition;
  final int version;

  DictionaryEntry({
    required this.entryId,
    required this.headword,
    required this.entryType,
    required this.definition,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      'entry_id': entryId,
      'headword': headword,
      'entry_type': entryType,
      'definition': definition,
      'version': version,
    };
  }

  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    return DictionaryEntry(
      entryId: json['entry_id'] as String,
      headword: json['headword'] as String,
      entryType: json['entry_type'] as String,
      definition: json['definition'] as String,
      version: json['version'] as int,
    );
  }
}

/// 推送更新结果
class PushUpdateResult {
  final bool success;
  final String? error;
  final int count;
  final List<PushUpdateItem>? results;

  PushUpdateResult({
    required this.success,
    this.error,
    this.count = 0,
    this.results,
  });
}

/// 推送更新单项结果
class PushUpdateItem {
  final String file;
  final String action;
  final String entryId;

  PushUpdateItem({
    required this.file,
    required this.action,
    required this.entryId,
  });

  factory PushUpdateItem.fromJson(Map<String, dynamic> json) {
    return PushUpdateItem(
      file: json['file'] as String,
      action: json['action'] as String,
      entryId: json['entry_id'] as String,
    );
  }
}
