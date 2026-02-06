import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dictionary_manager.dart';

class EnglishDbService {
  static final EnglishDbService _instance = EnglishDbService._internal();
  factory EnglishDbService() => _instance;
  EnglishDbService._internal();

  static const String _kNeverAskAgain = 'english_db_never_ask_again';

  Future<String> getDbPath() async {
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, 'en.db');
  }

  Future<bool> dbExists() async {
    final dbPath = await getDbPath();
    return File(dbPath).exists();
  }

  Future<bool> shouldShowDownloadDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final neverAskAgain = prefs.getBool(_kNeverAskAgain) ?? false;
    return !neverAskAgain;
  }

  Future<void> setNeverAskAgain(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNeverAskAgain, value);
  }

  Future<void> resetNeverAskAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNeverAskAgain, false);
  }

  Future<bool> getNeverAskAgain() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNeverAskAgain) ?? false;
  }

  Future<bool> downloadDb({
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
    String? downloadUrl,
  }) async {
    final dbPath = await getDbPath();
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    await dbFile.parent.create(recursive: true);

    try {
      final url = downloadUrl ?? await _getDefaultDownloadUrl();
      if (url.isEmpty) {
        onError('Download failed: Invalid download URL');
        return false;
      }

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        onError('下载失败: HTTP ${response.statusCode}');
        return false;
      }

      final contentLength = response.contentLength ?? 0;
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
      return true;
    } catch (e) {
      onError('下载失败: $e');
      return false;
    }
  }

  Future<String> _getDefaultDownloadUrl() async {
    try {
      final dictManager = DictionaryManager();
      final subscriptionUrl = await dictManager.onlineSubscriptionUrl;

      if (subscriptionUrl.isNotEmpty) {
        final cleanUrl = subscriptionUrl.trim().replaceAll(RegExp(r'/$'), '');
        return '$cleanUrl/auxi/en.db';
      }
    } catch (e) {
      // 忽略错误，使用默认 URL
    }

    return 'https://github.com/tisfeng/Easydict/releases/download/v1.0.0/en.db';
  }
}
