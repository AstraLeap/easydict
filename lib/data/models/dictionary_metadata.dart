class DictionaryMetadata {
  final String id;
  final String name;
  final int version;
  final String description;
  final String sourceLanguage;
  final List<String> targetLanguages;
  final String publisher;
  final String maintainer;
  final String? contactMaintainer;
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
      'updated_at': updatedAt.toUtc().toIso8601String().replaceFirst('Z', '+00:00'),
    };
  }

  factory DictionaryMetadata.fromJson(Map<String, dynamic> json) {
    List<String> parseTargetLanguage(dynamic value) {
      if (value == null) return ['en'];
      if (value is String) return [value];
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return ['en'];
    }

    int parseVersion(dynamic value) {
      if (value == null) return 1;
      if (value is int) return value;
      if (value is String) {
        return int.tryParse(value) ?? 1;
      }
      return 1;
    }

    return DictionaryMetadata(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: parseVersion(json['version']),
      description: json['description'] as String? ?? '',
      sourceLanguage: json['source_language'] as String? ?? 'en',
      targetLanguages: parseTargetLanguage(json['target_language']),
      publisher: json['publisher'] as String? ?? '',
      maintainer: json['maintainer'] as String? ?? '',
      contactMaintainer: json['contact_maintainer'] as String?,
      updatedAt: _parseDateTime(json['updated_at'] ?? json['updatedAt']),
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
    int? version,
    String? description,
    String? sourceLanguage,
    List<String>? targetLanguages,
    String? publisher,
    String? maintainer,
    String? contactMaintainer,
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
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
