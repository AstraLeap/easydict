import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:easydict/core/logger.dart';

/// TTS 音频缓存服务
/// 用于缓存 TTS 生成的音频文件，避免重复请求
class TtsCacheService {
  static final TtsCacheService _instance = TtsCacheService._internal();
  factory TtsCacheService() => _instance;
  TtsCacheService._internal();

  /// 缓存目录名称
  static const String _cacheDirName = 'tts_cache';

  /// 缓存元数据文件名
  static const String _metadataFileName = 'metadata.json';

  /// 获取缓存目录
  Future<Directory> _getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(path.join(tempDir.path, _cacheDirName));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 获取系统临时目录
  Future<Directory> getTemporaryDirectory() async {
    // 使用系统临时目录
    return Directory.systemTemp;
  }

  /// 生成缓存键（基于文本、语言代码和音色的 MD5）
  String _generateCacheKey(String text, String? languageCode, String? voice) {
    final content = '$text|$languageCode|$voice';
    return md5.convert(utf8.encode(content)).toString();
  }

  /// 获取缓存文件路径
  Future<File> _getCacheFile(String cacheKey) async {
    final cacheDir = await _getCacheDirectory();
    return File(path.join(cacheDir.path, '$cacheKey.mp3'));
  }

  /// 获取元数据文件路径
  Future<File> _getMetadataFile() async {
    final cacheDir = await _getCacheDirectory();
    return File(path.join(cacheDir.path, _metadataFileName));
  }

  /// 读取元数据
  Future<Map<String, int>> _readMetadata() async {
    try {
      final metadataFile = await _getMetadataFile();
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        return json.map((key, value) => MapEntry(key, value as int));
      }
    } catch (e) {
      Logger.w('读取 TTS 缓存元数据失败: $e', tag: 'TtsCacheService');
    }
    return {};
  }

  /// 保存元数据
  Future<void> _saveMetadata(Map<String, int> metadata) async {
    try {
      final metadataFile = await _getMetadataFile();
      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      Logger.w('保存 TTS 缓存元数据失败: $e', tag: 'TtsCacheService');
    }
  }

  /// 检查缓存是否存在
  Future<bool> hasCache(String text, String? languageCode, String? voice) async {
    final cacheKey = _generateCacheKey(text, languageCode, voice);
    final cacheFile = await _getCacheFile(cacheKey);
    return await cacheFile.exists();
  }

  /// 获取缓存的音频数据
  Future<List<int>?> getCache(
    String text,
    String? languageCode,
    String? voice,
  ) async {
    try {
      final cacheKey = _generateCacheKey(text, languageCode, voice);
      final cacheFile = await _getCacheFile(cacheKey);

      if (await cacheFile.exists()) {
        Logger.d('TTS 缓存命中: $cacheKey', tag: 'TtsCacheService');
        return await cacheFile.readAsBytes();
      }
    } catch (e) {
      Logger.w('读取 TTS 缓存失败: $e', tag: 'TtsCacheService');
    }
    return null;
  }

  /// 保存音频数据到缓存
  Future<File> saveCache(
    String text,
    String? languageCode,
    String? voice,
    List<int> audioData,
  ) async {
    final cacheKey = _generateCacheKey(text, languageCode, voice);
    final cacheFile = await _getCacheFile(cacheKey);

    await cacheFile.writeAsBytes(audioData);
    Logger.d('TTS 缓存已保存: $cacheKey', tag: 'TtsCacheService');

    // 更新元数据（记录创建时间戳）
    final metadata = await _readMetadata();
    metadata[cacheKey] = DateTime.now().millisecondsSinceEpoch;
    await _saveMetadata(metadata);

    return cacheFile;
  }

  /// 清理超过指定天数的缓存
  Future<int> cleanOldCache({int maxAgeDays = 1}) async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return 0;

      final metadata = await _readMetadata();
      final now = DateTime.now();
      final maxAge = Duration(days: maxAgeDays);
      int cleanedCount = 0;

      final List<String> keysToRemove = [];

      for (final entry in metadata.entries) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(entry.value);
        if (now.difference(cacheTime) > maxAge) {
          final cacheFile = File(path.join(cacheDir.path, '${entry.key}.mp3'));
          if (await cacheFile.exists()) {
            await cacheFile.delete();
            cleanedCount++;
            Logger.d('已清理过期 TTS 缓存: ${entry.key}', tag: 'TtsCacheService');
          }
          keysToRemove.add(entry.key);
        }
      }

      // 更新元数据
      for (final key in keysToRemove) {
        metadata.remove(key);
      }
      if (keysToRemove.isNotEmpty) {
        await _saveMetadata(metadata);
      }

      if (cleanedCount > 0) {
        Logger.i('已清理 $cleanedCount 个过期 TTS 缓存文件', tag: 'TtsCacheService');
      }

      return cleanedCount;
    } catch (e) {
      Logger.e('清理 TTS 缓存失败: $e', tag: 'TtsCacheService');
      return 0;
    }
  }

  /// 清理所有缓存
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        Logger.i('已清理所有 TTS 缓存', tag: 'TtsCacheService');
      }
    } catch (e) {
      Logger.e('清理所有 TTS 缓存失败: $e', tag: 'TtsCacheService');
    }
  }
}
