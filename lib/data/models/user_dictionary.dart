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
  final int? version;
  final List<PushUpdateItem>? results;

  PushUpdateResult({
    required this.success,
    this.error,
    this.count = 0,
    this.version,
    this.results,
  });
}

/// 推送更新单项结果
class PushUpdateItem {
  final String? file;
  final String action;
  final String entryId;

  PushUpdateItem({this.file, required this.action, required this.entryId});

  factory PushUpdateItem.fromJson(Map<String, dynamic> json) {
    return PushUpdateItem(
      file: json['file'] as String?,
      action: (json['action'] as String?) ?? '',
      entryId: json['entry_id']?.toString() ?? '',
    );
  }
}

/// 词典更新信息
class DictUpdateInfo {
  final String dictId;
  final int from;
  final int to;
  final List<DictUpdateHistory> history;
  final DictUpdateRequired required;

  DictUpdateInfo({
    required this.dictId,
    required this.from,
    required this.to,
    required this.history,
    required this.required,
  });

  factory DictUpdateInfo.fromJson(Map<String, dynamic> json) {
    return DictUpdateInfo(
      dictId: json['dict_id'] as String? ?? '',
      from: json['from'] as int? ?? 0,
      to: json['to'] as int? ?? 0,
      history:
          (json['history'] as List<dynamic>?)
              ?.map(
                (e) => DictUpdateHistory.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      required: DictUpdateRequired.fromJson(
        json['required'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// 词典更新历史
class DictUpdateHistory {
  final int v;
  final String m;

  DictUpdateHistory({required this.v, required this.m});

  factory DictUpdateHistory.fromJson(Map<String, dynamic> json) {
    return DictUpdateHistory(
      v: json['v'] as int? ?? 0,
      m: json['m'] as String? ?? '',
    );
  }
}

/// 词典更新所需内容
class DictUpdateRequired {
  final List<String> files;
  final List<int> entries;

  DictUpdateRequired({required this.files, required this.entries});

  factory DictUpdateRequired.fromJson(Map<String, dynamic> json) {
    return DictUpdateRequired(
      files:
          (json['files'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      entries:
          (json['entries'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [],
    );
  }
}
