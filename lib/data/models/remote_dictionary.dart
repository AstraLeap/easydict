/// 远程词典信息模型
class RemoteDictionary {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String language;
  final int entryCount;
  final int audioCount;
  final int imageCount;
  final int dictSize;
  final int mediaSize;
  final DateTime? updatedAt;

  // 下载状态（本地使用）
  bool isDownloaded;
  bool isDownloading;
  double downloadProgress;
  String? downloadStatus;

  // 链接状态（是否获取更新）
  bool isLinked;

  RemoteDictionary({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.author = '',
    this.language = '',
    this.entryCount = 0,
    this.audioCount = 0,
    this.imageCount = 0,
    this.dictSize = 0,
    this.mediaSize = 0,
    this.updatedAt,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.downloadStatus,
    this.isLinked = true,
  });

  factory RemoteDictionary.fromJson(Map<String, dynamic> json) {
    final versionValue = json['version'];
    final versionStr = versionValue is int
        ? versionValue.toString()
        : (versionValue as String? ?? '1.0.0');

    return RemoteDictionary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: versionStr,
      author: json['author'] as String? ?? '',
      language: json['language'] as String? ?? '',
      entryCount: json['entry_count'] as int? ?? 0,
      audioCount: json['audio_count'] as int? ?? 0,
      imageCount: json['image_count'] as int? ?? 0,
      dictSize: json['dict_size'] as int? ?? 0,
      mediaSize: json['media_size'] as int? ?? 0,
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  bool get hasDatabase => dictSize > 0;
  bool get hasAudios => audioCount > 0;
  bool get hasImages => imageCount > 0;
  bool get hasLogo => true;
  bool get hasMetadata => true;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'version': version,
      'author': author,
      'language': language,
      'entry_count': entryCount,
      'audio_count': audioCount,
      'image_count': imageCount,
      'dict_size': dictSize,
      'media_size': mediaSize,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    return null;
  }

  String get formattedDictSize {
    return dictSize > 0 ? _formatSize(dictSize) : '';
  }

  String get formattedMediaSize {
    return mediaSize > 0 ? _formatSize(mediaSize) : '';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  RemoteDictionary copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? author,
    String? language,
    int? entryCount,
    int? audioCount,
    int? imageCount,
    int? dictSize,
    int? mediaSize,
    DateTime? updatedAt,
    bool? isDownloaded,
    bool? isDownloading,
    double? downloadProgress,
    String? downloadStatus,
    bool? isLinked,
  }) {
    return RemoteDictionary(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      language: language ?? this.language,
      entryCount: entryCount ?? this.entryCount,
      audioCount: audioCount ?? this.audioCount,
      imageCount: imageCount ?? this.imageCount,
      dictSize: dictSize ?? this.dictSize,
      mediaSize: mediaSize ?? this.mediaSize,
      updatedAt: updatedAt ?? this.updatedAt,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      isLinked: isLinked ?? this.isLinked,
    );
  }
}

/// 下载选项
class DownloadOptions {
  final bool includeDatabase;
  final bool includeMedia;

  DownloadOptions({this.includeDatabase = true, this.includeMedia = false});

  Map<String, dynamic> toJson() {
    return {'include_database': includeDatabase, 'include_media': includeMedia};
  }
}
