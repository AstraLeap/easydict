import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dictionary_manager.dart';
import 'english_search_service.dart';
import 'preferences_service.dart';
import '../core/logger.dart';

class EnglishDbService {
  static final EnglishDbService _instance = EnglishDbService._internal();
  factory EnglishDbService() => _instance;
  EnglishDbService._internal();

  static const String _kNeverAskAgain = 'english_db_never_ask_again';

  Future<String> getDbPath() async {
    Logger.d('EnglishDbService: 获取数据库路径...', tag: 'EnglishDB');
    final appDir = await getApplicationSupportDirectory();
    final dbPath = path.join(appDir.path, 'en.db');
    Logger.d('EnglishDbService: 数据库路径: $dbPath', tag: 'EnglishDB');
    return dbPath;
  }

  Future<bool> dbExists() async {
    final dbPath = await getDbPath();
    final exists = File(dbPath).existsSync();
    Logger.d('EnglishDbService: 数据库是否存在: $exists', tag: 'EnglishDB');
    return exists;
  }

  Future<bool> shouldShowDownloadDialog() async {
    final prefs = await PreferencesService().prefs;
    final neverAskAgain = prefs.getBool(_kNeverAskAgain) ?? false;
    return !neverAskAgain;
  }

  Future<void> setNeverAskAgain(bool value) async {
    final prefs = await PreferencesService().prefs;
    await prefs.setBool(_kNeverAskAgain, value);
  }

  Future<void> resetNeverAskAgain() async {
    final prefs = await PreferencesService().prefs;
    await prefs.setBool(_kNeverAskAgain, false);
  }

  Future<bool> getNeverAskAgain() async {
    final prefs = await PreferencesService().prefs;
    return prefs.getBool(_kNeverAskAgain) ?? false;
  }

  Future<bool> downloadDb({
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
    String? downloadUrl,
  }) async {
    Logger.i('EnglishDbService: 开始下载数据库...', tag: 'EnglishDB');
    final dbPath = await getDbPath();
    Logger.d('EnglishDbService: 下载目标路径: $dbPath', tag: 'EnglishDB');
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      Logger.d('EnglishDbService: 存在旧数据库，删除...', tag: 'EnglishDB');
      await dbFile.delete();
    }

    await dbFile.parent.create(recursive: true);

    try {
      final url = downloadUrl ?? await _getDefaultDownloadUrl();
      Logger.d('EnglishDbService: 下载URL: $url', tag: 'EnglishDB');
      if (url.isEmpty) {
        Logger.e('EnglishDbService: 下载失败 - 无效的URL', tag: 'EnglishDB');
        onError('Download failed: Invalid download URL');
        return false;
      }

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        Logger.e(
          'EnglishDbService: 下载失败 - HTTP ${response.statusCode}',
          tag: 'EnglishDB',
        );
        onError('下载失败: HTTP ${response.statusCode}');
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      Logger.d(
        'EnglishDbService: 文件大小: $contentLength bytes',
        tag: 'EnglishDB',
      );
      final sink = dbFile.openWrite();

      int downloadedBytes = 0;

      await response.stream
          .listen(
            (chunk) {
              sink.add(chunk);
              downloadedBytes += chunk.length;
              if (contentLength > 0) {
                onProgress(downloadedBytes / contentLength);
              }
            },
            onDone: () async {
              await sink.close();
            },
            onError: (error) {
              sink.close();
              throw error;
            },
            cancelOnError: true,
          )
          .asFuture();

      onProgress(1.0);
      Logger.i('EnglishDbService: 数据库下载完成!', tag: 'EnglishDB');
      return true;
    } catch (e) {
      Logger.e('EnglishDbService: 下载失败: $e', tag: 'EnglishDB');
      onError('下载失败: $e');
      return false;
    }
  }

  Future<String> getDefaultDownloadUrl() async {
    final dictManager = DictionaryManager();
    final subscriptionUrl = await dictManager.onlineSubscriptionUrl;

    final cleanUrl = subscriptionUrl.trim().replaceAll(RegExp(r'/$'), '');
    return '$cleanUrl/auxi/en.db';
  }

  Future<String> _getDefaultDownloadUrl() async {
    return getDefaultDownloadUrl();
  }

  Future<bool> deleteDb() async {
    // 先关闭存在的内存中数据库连接，否则尽管文件删除了查词依然可用
    await EnglishSearchService().closeDatabase();
    final dbPath = await getDbPath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
      Logger.i('EnglishDbService: 数据库已删除', tag: 'EnglishDB');
      return true;
    }
    return false;
  }
}
