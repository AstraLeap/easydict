import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/remote_dictionary.dart';
import 'dictionary_manager.dart';
import '../logger.dart';

/// 词典商店服务
/// 用于从服务器获取词典列表、下载词典等
class DictionaryStoreService {
  final String baseUrl;
  final http.Client _client = http.Client();

  DictionaryStoreService({required this.baseUrl});

  String _buildUrl(String path) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBaseUrl/$cleanPath';
  }

  /// 获取服务器上的词典列表
  Future<List<RemoteDictionary>> fetchDictionaryList() async {
    try {
      final url = Uri.parse(_buildUrl('dictionaries'));
      Logger.i('获取词典列表: $url', tag: 'DictionaryStore');

      final response = await _client
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'EasyDict/1.0.0',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        final list = jsonData['dictionaries'] as List<dynamic>? ?? [];

        final dictionaries = list
            .map(
              (item) =>
                  RemoteDictionary.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();

        Logger.i('获取到 ${dictionaries.length} 个词典', tag: 'DictionaryStore');
        return dictionaries;
      } else {
        throw Exception('获取词典列表失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('获取词典列表超时，请检查网络连接');
    } catch (e) {
      Logger.e('获取词典列表失败: $e', tag: 'DictionaryStore');
      rethrow;
    }
  }

  /// 获取单个词典详情
  Future<RemoteDictionary> fetchDictionaryDetail(String dictId) async {
    try {
      final url = Uri.parse(_buildUrl(dictId));
      Logger.i('获取词典详情: $dictId', tag: 'DictionaryStore');

      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        return RemoteDictionary.fromJson(jsonData);
      } else {
        throw Exception('获取词典详情失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      Logger.e('获取词典详情失败: $e', tag: 'DictionaryStore');
      rethrow;
    }
  }

  /// 下载词典 Logo
  Future<File?> downloadLogo(String dictId, String savePath) async {
    try {
      final url = Uri.parse(_buildUrl('download/$dictId/logo'));
      Logger.i('下载 Logo: $dictId', tag: 'DictionaryStore');

      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        Logger.w(
          'Logo 下载失败: HTTP ${response.statusCode}',
          tag: 'DictionaryStore',
        );
        return null;
      }
    } catch (e) {
      Logger.w('Logo 下载失败: $e', tag: 'DictionaryStore');
      return null;
    }
  }

  /// 下载词典
  ///
  /// [dict] - 要下载的词典
  /// [options] - 下载选项
  /// [onProgress] - 进度回调 (当前字节数, 总字节数, 状态信息)
  /// [onComplete] - 完成回调
  /// [onError] - 错误回调
  Future<void> downloadDictionary({
    required RemoteDictionary dict,
    required DownloadOptions options,
    required Function(int current, int total, String status) onProgress,
    required Function() onComplete,
    required Function(String error) onError,
  }) async {
    try {
      final dictManager = DictionaryManager();
      final dictDir = await dictManager.getDictionaryDirectory(dict.id);

      Logger.i('开始下载词典: ${dict.name}', tag: 'DictionaryStore');
      onProgress(0, 0, '准备下载...');

      int totalSteps = 0;
      int currentStep = 0;

      if (options.includeDatabase) totalSteps++;
      if ((dict.hasAudios || dict.hasImages) && options.includeMedia)
        totalSteps++;

      if (totalSteps == 0) {
        onError('没有选择要下载的内容');
        return;
      }

      if (dict.hasDatabase && options.includeDatabase) {
        currentStep++;
        onProgress(0, 0, '[$currentStep/$totalSteps] 下载数据库...');

        final url = Uri.parse(_buildUrl('download/${dict.id}/database'));
        Logger.i('下载数据库: $url', tag: 'DictionaryStore');

        final request = http.Request('GET', url);
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw Exception('下载数据库失败: HTTP ${response.statusCode}');
        }

        final dbFile = File(path.join(dictDir, 'dictionary.db'));
        final sink = dbFile.openWrite();
        var receivedBytes = 0;
        final totalBytes = response.contentLength ?? 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          if (totalBytes > 0) {
            final progress = (receivedBytes / totalBytes * 100).toInt();
            onProgress(
              receivedBytes,
              totalBytes,
              '[$currentStep/$totalSteps] 下载数据库... $progress%',
            );
          }
        }
        await sink.close();
        Logger.i('数据库下载完成', tag: 'DictionaryStore');
      }

      if ((dict.hasAudios || dict.hasImages) && options.includeMedia) {
        currentStep++;
        onProgress(0, 0, '[$currentStep/$totalSteps] 下载媒体数据库...');

        final url = Uri.parse(_buildUrl('download/${dict.id}/media'));
        final request = http.Request('GET', url);
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw Exception('下载媒体数据库失败: HTTP ${response.statusCode}');
        }

        final mediaDbFile = File(path.join(dictDir, 'media.db'));
        final sink = mediaDbFile.openWrite();
        var receivedBytes = 0;
        final totalBytes = response.contentLength ?? 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          if (totalBytes > 0) {
            final progress = (receivedBytes / totalBytes * 100).toInt();
            onProgress(
              receivedBytes,
              totalBytes,
              '[$currentStep/$totalSteps] 下载媒体数据库... $progress%',
            );
          }
        }
        await sink.close();
        Logger.i('媒体数据库下载完成', tag: 'DictionaryStore');
      }

      Logger.i('词典安装完成: ${dict.name}', tag: 'DictionaryStore');
      onComplete();
    } catch (e) {
      Logger.e('下载词典失败: $e', tag: 'DictionaryStore');
      onError(e.toString());
    }
  }

  /// 检查词典是否已下载
  Future<bool> isDictionaryDownloaded(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      final metadata = await dictManager.getDictionaryMetadata(dictId);
      return metadata != null;
    } catch (e) {
      return false;
    }
  }

  /// 删除已下载的词典
  Future<void> deleteDictionary(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      await dictManager.deleteDictionary(dictId);
      Logger.i('删除词典: $dictId', tag: 'DictionaryStore');
    } catch (e) {
      Logger.e('删除词典失败: $e', tag: 'DictionaryStore');
      rethrow;
    }
  }

  /// 获取已下载的词典列表
  Future<List<String>> getDownloadedDictionaryIds() async {
    try {
      final dictManager = DictionaryManager();
      return await dictManager.getAvailableDictionaries();
    } catch (e) {
      Logger.e('获取已下载词典列表失败: $e', tag: 'DictionaryStore');
      return [];
    }
  }

  /// 分别下载词典的各个文件（Stream 版本）
  ///
  /// [dict] - 要下载的词典
  /// [options] - 下载选项（包含metadata、logo、db、audios、images的选择）
  Stream<Map<String, dynamic>> downloadDictionaryFilesStream({
    required RemoteDictionary dict,
    required dynamic options, // DownloadOptionsResult
  }) async* {
    try {
      final dictManager = DictionaryManager();
      final dictDir = await dictManager.getDictionaryDirectory(dict.id);

      // 确保目录存在
      final dir = Directory(dictDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      int totalSteps = 0;
      int currentStep = 0;

      // 计算总步骤数
      if (options.includeMetadata) totalSteps++;
      if (options.includeLogo && dict.hasLogo) totalSteps++;
      if (options.includeDb && dict.hasDatabase) totalSteps++;
      if (options.includeMedia && (dict.hasAudios || dict.hasImages)) {
        totalSteps++;
      }

      if (totalSteps == 0) {
        yield {'type': 'error', 'error': '没有选择要下载的内容'};
        return;
      }

      Logger.i(
        '开始下载词典文件: ${dict.name}, 共 $totalSteps 个文件',
        tag: 'DictionaryStore',
      );

      // 1. 下载 metadata.json
      if (options.includeMetadata) {
        currentStep++;
        yield {
          'type': 'progress',
          'progress': (currentStep - 1) / totalSteps,
          'status': '[$currentStep/$totalSteps] 下载元数据...',
        };

        final url = Uri.parse(_buildUrl('download/${dict.id}/metadata'));
        Logger.i('正在下载元数据: $url', tag: 'DictionaryStore');
        final response = await _client
            .get(url)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final metadataFile = File(path.join(dictDir, 'metadata.json'));
          // 更新元数据中的 ID
          // 处理 UTF-8 编码
          final body = utf8.decode(response.bodyBytes);
          final metadata = jsonDecode(body) as Map<String, dynamic>;
          metadata['id'] = dict.id;
          await metadataFile.writeAsString(jsonEncode(metadata));
          Logger.i('元数据下载完成', tag: 'DictionaryStore');
        } else {
          Logger.e(
            '下载元数据失败: $url, HTTP ${response.statusCode}',
            tag: 'DictionaryStore',
          );
          throw Exception('下载元数据失败: $url, HTTP ${response.statusCode}');
        }
      }

      // 2. 下载 logo.png
      if (options.includeLogo && dict.hasLogo) {
        currentStep++;
        yield {
          'type': 'progress',
          'progress': (currentStep - 1) / totalSteps,
          'status': '[$currentStep/$totalSteps] 下载图标...',
        };

        final url = Uri.parse(_buildUrl('download/${dict.id}/logo'));
        final response = await _client
            .get(url)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final logoFile = File(path.join(dictDir, 'logo.png'));
          await logoFile.writeAsBytes(response.bodyBytes);
          Logger.i('图标下载完成', tag: 'DictionaryStore');
        } else {
          Logger.w(
            '图标下载失败: HTTP ${response.statusCode}',
            tag: 'DictionaryStore',
          );
        }
      }

      // 3. 下载 database.db
      if (options.includeDb && dict.hasDatabase) {
        currentStep++;
        yield {
          'type': 'progress',
          'fileName': 'dictionary.db',
          'fileIndex': currentStep,
          'totalFiles': totalSteps,
          'progress': 0.0,
          'receivedBytes': 0,
          'totalBytes': 0,
          'status': '[$currentStep/$totalSteps] 下载数据库...',
        };

        final dbPath = path.join(dictDir, 'dictionary.db');
        final existingSize = await _getExistingFileSize(dbPath);
        final url = _buildUrl('download/${dict.id}/database');

        http.BaseRequest request;
        if (existingSize > 0) {
          request = http.Request('GET', Uri.parse(url));
          request.headers['Range'] = 'bytes=$existingSize-';
        } else {
          request = http.Request('GET', Uri.parse(url));
        }

        final response = await _client.send(request);

        if (response.statusCode == 200 || response.statusCode == 206) {
          final dbFile = File(dbPath);
          final sink = dbFile.openWrite(mode: FileMode.append);
          var receivedBytes = 0;
          final contentLength = response.contentLength ?? 0;
          final totalBytes = existingSize + contentLength;
          final startBytes = existingSize;

          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;

            final currentProgress = startBytes + receivedBytes;
            yield {
              'type': 'progress',
              'fileName': 'dictionary.db',
              'fileIndex': currentStep,
              'totalFiles': totalSteps,
              'progress': totalBytes > 0 ? currentProgress / totalBytes : 0.0,
              'receivedBytes': currentProgress,
              'totalBytes': totalBytes,
              'status':
                  '[$currentStep/$totalSteps] 下载数据库... ${totalBytes > 0 ? '${(currentProgress / totalBytes * 100).toInt()}%' : formatBytes(currentProgress)}',
            };
          }
          await sink.close();

          Logger.i(
            '数据库下载完成: ${formatBytes(totalBytes)}',
            tag: 'DictionaryStore',
          );
        } else {
          throw Exception('下载数据库失败: HTTP ${response.statusCode}');
        }
      }

      // 4. 下载媒体数据库
      if (options.includeMedia && (dict.hasAudios || dict.hasImages)) {
        currentStep++;
        yield {
          'type': 'progress',
          'fileName': 'media.db',
          'fileIndex': currentStep,
          'totalFiles': totalSteps,
          'progress': 0.0,
          'receivedBytes': 0,
          'totalBytes': 0,
          'status': '[$currentStep/$totalSteps] 下载媒体数据库...',
        };

        final mediaDbPath = path.join(dictDir, 'media.db');
        final existingSize = await _getExistingFileSize(mediaDbPath);
        final url = _buildUrl('download/${dict.id}/media');

        http.BaseRequest request;
        if (existingSize > 0) {
          request = http.Request('GET', Uri.parse(url));
          request.headers['Range'] = 'bytes=$existingSize-';
        } else {
          request = http.Request('GET', Uri.parse(url));
        }

        final response = await _client.send(request);

        if (response.statusCode == 200 || response.statusCode == 206) {
          final mediaDbFile = File(mediaDbPath);
          final sink = mediaDbFile.openWrite(mode: FileMode.append);
          var receivedBytes = 0;
          final contentLength = response.contentLength ?? 0;
          final totalBytes = existingSize + contentLength;
          final startBytes = existingSize;

          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;

            final currentProgress = startBytes + receivedBytes;
            yield {
              'type': 'progress',
              'fileName': 'media.db',
              'fileIndex': currentStep,
              'totalFiles': totalSteps,
              'progress': totalBytes > 0 ? currentProgress / totalBytes : 0.0,
              'receivedBytes': currentProgress,
              'totalBytes': totalBytes,
              'status':
                  '[$currentStep/$totalSteps] 下载媒体数据库... ${totalBytes > 0 ? '${(currentProgress / totalBytes * 100).toInt()}%' : formatBytes(currentProgress)}',
            };
          }
          await sink.close();

          Logger.i(
            '媒体数据库下载完成: ${formatBytes(totalBytes)}',
            tag: 'DictionaryStore',
          );
        } else {
          throw Exception('下载媒体数据库失败: HTTP ${response.statusCode}');
        }
      }

      Logger.i('词典安装完成: ${dict.name}', tag: 'DictionaryStore');
      yield {'type': 'complete'};
    } catch (e) {
      Logger.e('下载词典失败: $e', tag: 'DictionaryStore');
      yield {'type': 'error', 'error': e.toString()};
    }
  }

  Future<int> _getExistingFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      Logger.w('检查已存在文件大小时出错: $filePath, $e', tag: 'DictionaryStore');
    }
    return 0;
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  void dispose() {
    _client.close();
  }
}
