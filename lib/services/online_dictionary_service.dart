import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/dictionary_metadata.dart';
import 'dictionary_manager.dart';
import '../logger.dart';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  final i = (bytes.bitLength / 10).floor();
  if (i >= suffixes.length)
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} TB';
  return '${(bytes / (1 << (i * 10))).toStringAsFixed(i > 0 ? 1 : 0)} ${suffixes[i]}';
}

class DictionaryDownloadProgress {
  final String fileName;
  final int downloadedBytes;
  final int totalBytes;

  DictionaryDownloadProgress({
    required this.fileName,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  double get progress {
    if (totalBytes == 0) return 0;
    return downloadedBytes / totalBytes;
  }

  String get progressText {
    return '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
  }
}

class OnlineDictionaryService {
  final String baseUrl;

  OnlineDictionaryService({required this.baseUrl});

  Future<List<OnlineDictionaryInfo>> fetchAvailableDictionaries() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/dictionaries'));
      if (response.statusCode != 200) {
        throw Exception('无法获取词典列表: HTTP ${response.statusCode}');
      }

      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => OnlineDictionaryInfo.fromJson(item)).toList();
    } catch (e) {
      Logger.e('获取词典列表失败: $e', tag: 'OnlineDictionaryService');
      rethrow;
    }
  }

  Future<DictionaryMetadata?> downloadMetadata(String dictId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/$dictId/metadata'));
      if (response.statusCode != 200) {
        Logger.e(
          '下载元数据失败: HTTP ${response.statusCode}',
          tag: 'OnlineDictionaryService',
        );
        return null;
      }

      final data = json.decode(response.body);
      return DictionaryMetadata.fromJson(data);
    } catch (e) {
      Logger.e('下载元数据失败: $e', tag: 'OnlineDictionaryService');
      return null;
    }
  }

  Future<Uint8List?> downloadLogo(String dictId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/$dictId/logo'));
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      Logger.e('下载 Logo 失败: $e', tag: 'OnlineDictionaryService');
      return null;
    }
  }

  Future<void> downloadDictionary(
    String dictId,
    void Function(String, int, int) onProgress, {
    bool downloadAudios = false,
    bool downloadImages = false,
  }) async {
    try {
      final dictManager = DictionaryManager();

      final metadata = await downloadMetadata(dictId);
      if (metadata == null) {
        throw Exception('无法下载词典元数据');
      }

      await dictManager.createDictionaryStructure(dictId, metadata);

      final logoBytes = await downloadLogo(dictId);
      if (logoBytes != null && logoBytes.isNotEmpty) {
        final logoPath = await dictManager.getLogoPath(dictId);
        if (logoPath != null) {
          final logoFile = File(logoPath);
          await logoFile.writeAsBytes(logoBytes);
        }
      }

      final dbPath = await dictManager.getDictionaryDbPath(dictId);
      await _downloadFile(
        '$baseUrl/$dictId/database',
        dbPath,
        (current, total) => onProgress('数据库文件', current, total),
      );

      if (downloadAudios || downloadImages) {
        await _downloadMedia(
          dictId,
          await dictManager
              .getDictionaryDbPath(dictId)
              .then((p) => File(p).parent.path),
          onProgress,
        );
      }

      Logger.d('词典下载完成: $dictId', tag: 'OnlineDictionaryService');
    } catch (e) {
      Logger.e('下载词典失败: $e', tag: 'OnlineDictionaryService');
      rethrow;
    }
  }

  Future<void> _downloadMedia(
    String dictId,
    String targetDir,
    void Function(String, int, int) onProgress,
  ) async {
    try {
      final url = '$baseUrl/$dictId/media';
      final mediaDbPath = '$targetDir/media.db';

      await _downloadFile(url, mediaDbPath, (current, total) {
        onProgress('媒体数据库', current, total);
      });

      Logger.d('媒体数据库下载完成', tag: 'OnlineDictionaryService');
    } catch (e) {
      Logger.e('下载媒体数据库失败: $e', tag: 'OnlineDictionaryService');
      rethrow;
    }
  }

  Future<void> _downloadFile(
    String url,
    String savePath,
    void Function(int, int) onProgress,
  ) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('下载失败: HTTP ${response.statusCode}');
      }

      final file = File(savePath);
      await file.writeAsBytes(response.bodyBytes);

      onProgress(response.bodyBytes.length, response.bodyBytes.length);
      Logger.d(
        '文件下载完成: ${response.bodyBytes.length} bytes',
        tag: 'OnlineDictionaryService',
      );
    } catch (e) {
      Logger.e('下载文件失败: $e', tag: 'OnlineDictionaryService');
      rethrow;
    }
  }
}

class OnlineDictionaryInfo {
  final String id;
  final String name;
  final String version;
  final String description;
  final String language;
  final int wordCount;
  final int fileSize;
  final String sourceUrl;
  final bool hasImages;
  final bool hasAudios;

  OnlineDictionaryInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.language,
    required this.wordCount,
    required this.fileSize,
    required this.sourceUrl,
    this.hasImages = false,
    this.hasAudios = false,
  });

  factory OnlineDictionaryInfo.fromJson(Map<String, dynamic> json) {
    return OnlineDictionaryInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      version: json['version'] ?? '',
      description: json['description'] ?? '',
      language: json['language'] ?? '',
      wordCount: json['wordCount'] ?? 0,
      fileSize: json['fileSize'] ?? 0,
      sourceUrl: json['sourceUrl'] ?? '',
      hasImages: json['hasImages'] ?? false,
      hasAudios: json['hasAudios'] ?? false,
    );
  }

  String buildLogoUrl(String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/download/$id/logo';
  }

  String get formattedFileSize {
    return _formatBytes(fileSize);
  }
}
