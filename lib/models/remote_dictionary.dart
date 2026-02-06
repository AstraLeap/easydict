/// 远程词典信息模型
class RemoteDictionary {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String language;
  final int entryCount;
  final bool hasDatabase;
  final bool hasAudios;
  final bool hasImages;
  final bool hasLogo;
  final bool hasMetadata;
  final int audioCount;
  final int imageCount;
  final int databaseSize;
  final int dictSize;
  final int mediaSize;
  final int? audioSize;
  final int? imageSize;
  final int? logoSize;
  final int? metadataSize;
  final DateTime? createdAt;
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
    this.hasDatabase = false,
    this.hasAudios = false,
    this.hasImages = false,
    this.hasLogo = false,
    this.hasMetadata = false,
    this.audioCount = 0,
    this.imageCount = 0,
    this.databaseSize = 0,
    this.dictSize = 0,
    this.mediaSize = 0,
    this.audioSize,
    this.imageSize,
    this.logoSize,
    this.metadataSize,
    this.createdAt,
    this.updatedAt,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.downloadStatus,
    this.isLinked = true, // 默认开启链接
  });

  factory RemoteDictionary.fromJson(Map<String, dynamic> json) {
    return RemoteDictionary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? '',
      language: json['language'] as String? ?? '',
      entryCount: json['entry_count'] as int? ?? 0,
      hasDatabase: json['has_database'] as bool? ?? false,
      hasAudios: json['has_audios'] as bool? ?? false,
      hasImages: json['has_images'] as bool? ?? false,
      hasLogo: json['has_logo'] as bool? ?? false,
      hasMetadata: json['has_metadata'] as bool? ?? false,
      audioCount: json['audio_count'] as int? ?? 0,
      imageCount: json['image_count'] as int? ?? 0,
      databaseSize: json['database_size'] as int? ?? 0,
      dictSize: json['dict_size'] as int? ?? 0,
      mediaSize: json['media_size'] as int? ?? 0,
      audioSize: json['audio_size'] as int?,
      imageSize: json['image_size'] as int?,
      logoSize: json['logo_size'] as int?,
      metadataSize: json['metadata_size'] as int?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'version': version,
      'author': author,
      'language': language,
      'entry_count': entryCount,
      'has_database': hasDatabase,
      'has_audios': hasAudios,
      'has_images': hasImages,
      'has_logo': hasLogo,
      'has_metadata': hasMetadata,
      'audio_count': audioCount,
      'image_count': imageCount,
      'database_size': databaseSize,
      'dict_size': dictSize,
      'media_size': mediaSize,
      'audio_size': audioSize,
      'image_size': imageSize,
      'logo_size': logoSize,
      'metadata_size': metadataSize,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
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

  /// 获取格式化的数据库大小
  String get formattedDatabaseSize {
    return _formatSize(databaseSize);
  }

  /// 获取格式化的音频大小
  String get formattedAudioSize {
    return audioSize != null ? _formatSize(audioSize!) : '';
  }

  /// 获取格式化的图片大小
  String get formattedImageSize {
    return imageSize != null ? _formatSize(imageSize!) : '';
  }

  /// 获取格式化的 Logo 大小
  String get formattedLogoSize {
    return logoSize != null ? _formatSize(logoSize!) : '';
  }

  /// 获取格式化的 Metadata 大小
  String get formattedMetadataSize {
    return metadataSize != null ? _formatSize(metadataSize!) : '';
  }

  /// 获取格式化的词典数据库大小
  String get formattedDictSize {
    return dictSize > 0 ? _formatSize(dictSize) : '';
  }

  /// 获取格式化的媒体数据库大小
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

  /// 获取 Logo URL
  String getLogoUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/logo';
  }

  /// 获取 Metadata URL
  String getMetadataUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/metadata';
  }

  /// 获取 Database URL
  String getDatabaseUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/database';
  }

  /// 获取 Audios URL
  String getAudiosUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/media';
  }

  /// 获取 Images URL
  String getImagesUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/media';
  }

  RemoteDictionary copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? author,
    String? language,
    int? entryCount,
    bool? hasDatabase,
    bool? hasAudios,
    bool? hasImages,
    bool? hasLogo,
    bool? hasMetadata,
    int? audioCount,
    int? imageCount,
    int? databaseSize,
    int? dictSize,
    int? mediaSize,
    int? audioSize,
    int? imageSize,
    int? logoSize,
    int? metadataSize,
    DateTime? createdAt,
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
      hasDatabase: hasDatabase ?? this.hasDatabase,
      hasAudios: hasAudios ?? this.hasAudios,
      hasImages: hasImages ?? this.hasImages,
      hasLogo: hasLogo ?? this.hasLogo,
      hasMetadata: hasMetadata ?? this.hasMetadata,
      audioCount: audioCount ?? this.audioCount,
      imageCount: imageCount ?? this.imageCount,
      databaseSize: databaseSize ?? this.databaseSize,
      dictSize: dictSize ?? this.dictSize,
      mediaSize: mediaSize ?? this.mediaSize,
      audioSize: audioSize ?? this.audioSize,
      imageSize: imageSize ?? this.imageSize,
      logoSize: logoSize ?? this.logoSize,
      metadataSize: metadataSize ?? this.metadataSize,
      createdAt: createdAt ?? this.createdAt,
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
