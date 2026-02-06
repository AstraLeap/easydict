class DictionaryMetadata {
  final String id;
  final String name;
  final String version;
  final String description;
  final String sourceLanguage;
  final List<String> targetLanguages;
  final String publisher;
  final String maintainer;
  final String? contactMaintainer;
  final String? repository;
  final DateTime createdAt;
  final DateTime updatedAt;

  DictionaryMetadata({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.sourceLanguage,
    required this.targetLanguages,
    required this.publisher,
    required this.maintainer,
    this.contactMaintainer,
    this.repository,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'source_language': sourceLanguage,
      'target_language': targetLanguages,
      'publisher': publisher,
      'maintainer': maintainer,
      if (contactMaintainer != null) 'contact_maintainer': contactMaintainer,
      if (repository != null) 'repository': repository,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DictionaryMetadata.fromJson(Map<String, dynamic> json) {
    // 处理 target_language 可能是字符串或列表的情况
    List<String> parseTargetLanguage(dynamic value) {
      if (value == null) return ['en'];
      if (value is String) return [value];
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return ['en'];
    }

    return DictionaryMetadata(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      sourceLanguage: json['source_language'] as String? ?? 'en',
      targetLanguages: parseTargetLanguage(json['target_language']),
      publisher: json['publisher'] as String? ?? '',
      maintainer: json['maintainer'] as String? ?? '',
      contactMaintainer: json['contact_maintainer'] as String?,
      repository: json['repository'] as String?,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  DictionaryMetadata copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    String? sourceLanguage,
    List<String>? targetLanguages,
    String? publisher,
    String? maintainer,
    String? contactMaintainer,
    String? repository,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DictionaryMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguages: targetLanguages ?? this.targetLanguages,
      publisher: publisher ?? this.publisher,
      maintainer: maintainer ?? this.maintainer,
      contactMaintainer: contactMaintainer ?? this.contactMaintainer,
      repository: repository ?? this.repository,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
