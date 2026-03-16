import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../core/logger.dart';
import '../core/utils/crc32_utils.dart';
import '../data/models/remote_dictionary.dart';
import '../i18n/strings.g.dart';
import 'dictionary_manager.dart';

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

  static const List<int> _pngHeader = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  bool _isValidPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _pngHeader[i]) return false;
    }
    return true;
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
        throw Exception(
          t.dict.fetchListFailedHttp(code: response.statusCode.toString()),
        );
      }
    } on TimeoutException {
      throw Exception(t.dict.fetchListTimeout);
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
        throw Exception(
          t.dict.fetchDetailFailedHttp(code: response.statusCode.toString()),
        );
      }
    } catch (e) {
      Logger.e('获取词典详情失败: $e', tag: 'DictionaryStore');
      rethrow;
    }
  }

  /// 下载词典 Logo
  Future<File?> downloadLogo(String dictId, String savePath) async {
    try {
      final url = Uri.parse(_buildUrl('download/$dictId/file/logo.png'));
      Logger.i('下载 Logo: $url', tag: 'DictionaryStore');

      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final bodyBytes = response.bodyBytes;
        if (bodyBytes.isEmpty) {
          Logger.w('Logo 下载失败: 响应内容为空', tag: 'DictionaryStore');
          return null;
        }
        if (!_isValidPng(bodyBytes)) {
          Logger.w('Logo 下载失败: 文件不是有效的 PNG 格式', tag: 'DictionaryStore');
          return null;
        }
        final file = File(savePath);
        await file.writeAsBytes(bodyBytes);
        Logger.i(
          'Logo 下载完成: ${formatBytes(bodyBytes.length)}',
          tag: 'DictionaryStore',
        );
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
      onProgress(0, 0, t.dict.statusPreparing);

      int totalSteps = 0;
      int currentStep = 0;

      if (options.includeDatabase) totalSteps++;
      if ((dict.hasAudios || dict.hasImages) && options.includeMedia) {
        totalSteps++;
      }

      if (totalSteps == 0) {
        onError(t.dict.noContentSelected);
        return;
      }

      if (dict.hasDatabase && options.includeDatabase) {
        currentStep++;
        onProgress(
          0,
          0,
          t.dict.downloadingDatabase(
            step: currentStep.toString(),
            total: totalSteps.toString(),
          ),
        );

        final url = Uri.parse(
          _buildUrl('download/${dict.id}/file/dictionary.db'),
        );
        Logger.i('下载数据库: $url', tag: 'DictionaryStore');

        final request = http.Request('GET', url);
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw Exception(
            t.dict.downloadDbFailedHttp(code: response.statusCode.toString()),
          );
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
              t.dict.downloadingDatabaseProgress(
                step: currentStep.toString(),
                total: totalSteps.toString(),
                progress: progress.toString(),
              ),
            );
          }
        }
        await sink.close();
        Logger.i('数据库下载完成', tag: 'DictionaryStore');
      }

      if ((dict.hasAudios || dict.hasImages) && options.includeMedia) {
        currentStep++;
        onProgress(
          0,
          0,
          t.dict.downloadingMedia(
            step: currentStep.toString(),
            total: totalSteps.toString(),
          ),
        );

        final url = Uri.parse(_buildUrl('download/${dict.id}/file/media.db'));
        final request = http.Request('GET', url);
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw Exception(
            t.dict.downloadMediaFailedHttp(
              code: response.statusCode.toString(),
            ),
          );
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
              t.dict.downloadingMediaProgress(
                step: currentStep.toString(),
                total: totalSteps.toString(),
                progress: progress.toString(),
              ),
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

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 下载词典文件（通用方法）
  ///
  /// [dictId] - 词典ID
  /// [fileName] - 文件名（如 logo.png, metadata.json）
  /// [savePath] - 本地保存路径
  Future<File?> downloadDictFile(
    String dictId,
    String fileName,
    String savePath,
  ) async {
    try {
      final url = Uri.parse(_buildUrl('download/$dictId/file/$fileName'));
      Logger.i('下载词典文件: $url', tag: 'DictionaryStore');

      // Use a streamed request so that only the connection/headers phase is
      // subject to a short timeout.  The body is piped to disk in chunks
      // with no overall timeout, which avoids spurious failures on large
      // files (e.g. media.db) over slow mobile connections.
      // 无断点续传：先删除可能存在的残余文件，从头重新下载
      final file = File(savePath);
      await file.parent.create(recursive: true);
      if (await file.exists()) await file.delete();

      final request = http.Request('GET', Uri.parse(url.toString()));
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        Logger.w('文件下载失败: HTTP ${response.statusCode}', tag: 'DictionaryStore');
        return null;
      }

      final sink = file.openWrite();
      var downloadedBytes = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
        }
      } finally {
        await sink.close();
      }

      final totalBytes = downloadedBytes;
      if (totalBytes == 0) {
        Logger.w('文件下载失败: 响应内容为空 - $fileName', tag: 'DictionaryStore');
        await file.delete().catchError((_) => file);
        return null;
      }

      Logger.i(
        '文件下载完成: $fileName (${formatBytes(totalBytes)})',
        tag: 'DictionaryStore',
      );
      return file;
    } catch (e) {
      Logger.e('文件下载异常: $e', tag: 'DictionaryStore');
      return null;
    }
  }

  /// 下载词典文件（流式版本，实时报告字节进度）
  ///
  /// 事件类型：
  ///   {'type':'progress','receivedBytes':int,'totalBytes':int,'progress':double,'speedBytesPerSecond':int,'fileName':String,'fileIndex':int,'totalFiles':int,'status':String}
  ///   {'type':'complete'}
  ///   {'type':'file_complete','fileName':String}
  /// [startBytes] 用于断点续传，指定从哪个字节开始下载
  /// [fileIndex] 当前文件索引（用于多文件下载进度显示）
  /// [totalFiles] 总文件数（用于多文件下载进度显示）
  /// [status] 状态文本（可选，用于UI显示）
  Stream<Map<String, dynamic>> downloadDictFileStream(
    String dictId,
    String fileName,
    String savePath, {
    int startBytes = 0,
    int fileIndex = 1,
    int totalFiles = 1,
    String? status,
  }) async* {
    try {
      final url = Uri.parse(_buildUrl('download/$dictId/file/$fileName'));
      Logger.i(
        '下载词典文件(流式): $url, startBytes: $startBytes',
        tag: 'DictionaryStore',
      );

      // 使用 .downloading 临时文件
      final tempPath = '$savePath.downloading';
      final tempFile = File(tempPath);
      final finalFile = File(savePath);

      await tempFile.parent.create(recursive: true);

      // 如果是数据库文件，需要先关闭数据库连接
      if (fileName == 'dictionary.db') {
        Logger.d('关闭词典数据库连接以便更新: $dictId', tag: 'DictionaryStore');
        await DictionaryManager().closeDatabase(dictId);
      } else if (fileName == 'media.db') {
        Logger.d('关闭媒体数据库连接以便更新: $dictId', tag: 'DictionaryStore');
        await DictionaryManager().closeMediaDatabase(dictId);
      }

      final request = http.Request('GET', url);

      // 断点续传：添加 Range 头
      if (startBytes > 0) {
        // 检查临时文件是否存在且大小匹配
        if (await tempFile.exists()) {
          final tempSize = await tempFile.length();
          if (tempSize != startBytes) {
            Logger.w(
              '临时文件大小($tempSize)与请求的起始字节($startBytes)不匹配，从头开始下载',
              tag: 'DictionaryStore',
            );
            startBytes = 0;
          }
        } else {
          Logger.w('临时文件不存在，从头开始下载', tag: 'DictionaryStore');
          startBytes = 0;
        }
      }

      if (startBytes > 0) {
        request.headers['Range'] = 'bytes=$startBytes-';
        Logger.i('断点续传: 从 $startBytes 字节开始', tag: 'DictionaryStore');
      }

      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));

      // 206 Partial Content 表示断点续传成功
      // 200 OK 表示服务器不支持 Range 或从头开始
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final isResuming = response.statusCode == 206;
      final totalBytesFromHeader = response.contentLength ?? 0;

      // 计算实际总字节数
      // 对于 206 响应，contentLength 是剩余部分的大小
      final totalBytes = isResuming
          ? startBytes + totalBytesFromHeader
          : totalBytesFromHeader;

      // 获取服务器返回的 CRC32 值（仅 dictionary.db 和 media.db 有）
      final serverCrc32 = response.headers['x-crc32'];
      final shouldVerifyCrc32 = _shouldVerifyCrc32(fileName);

      if (serverCrc32 != null && shouldVerifyCrc32) {
        Logger.d('服务器 CRC32: $serverCrc32', tag: 'DictionaryStore');
      }

      // 以追加模式打开文件（断点续传）或创建新文件
      final sink = tempFile.openWrite(
        mode: isResuming ? FileMode.append : FileMode.write,
      );

      var downloadedBytes = isResuming ? startBytes : 0;
      DateTime? lastSpeedUpdate;
      int speedBytesPerSecond = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          final now = DateTime.now();
          if (lastSpeedUpdate != null) {
            final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;
            if (elapsedMs > 0) {
              speedBytesPerSecond = (chunk.length * 1000 / elapsedMs).round();
            }
          }
          lastSpeedUpdate = now;

          yield {
            'type': 'progress',
            'receivedBytes': downloadedBytes,
            'totalBytes': totalBytes,
            'progress': totalBytes > 0 ? downloadedBytes / totalBytes : 0.0,
            'speedBytesPerSecond': speedBytesPerSecond,
            'fileName': fileName,
            'fileIndex': fileIndex,
            'totalFiles': totalFiles,
            'status': status,
          };
        }
      } finally {
        await sink.close();
      }

      if (downloadedBytes == 0) {
        throw Exception(t.dict.responseEmpty);
      }

      // CRC32 校验（仅对 dictionary.db 和 media.db，且服务器返回了 CRC32）
      if (shouldVerifyCrc32 && serverCrc32 != null && !isResuming) {
        // 只有完整下载时才校验 CRC32（断点续传时临时文件不完整）
        Logger.i('开始 CRC32 校验: $fileName', tag: 'DictionaryStore');
        try {
          final localCrc32 = await Crc32Utils.calculateFileCrc32(tempFile);
          Logger.i(
            'CRC32 校验信息 [$fileName]:\n  - 本地计算: $localCrc32\n  - 服务器返回: $serverCrc32',
            tag: 'DictionaryStore',
          );

          if (!Crc32Utils.compareCrc32(localCrc32, serverCrc32)) {
            // CRC32 校验失败，删除临时文件
            await tempFile.delete();
            Logger.e(
              'CRC32 校验失败 [$fileName]: 本地($localCrc32) != 服务器($serverCrc32)',
              tag: 'DictionaryStore',
            );
            throw Exception(
              t.dict.crc32Mismatch(
                file: fileName,
                expected: serverCrc32,
                actual: localCrc32,
              ),
            );
          }
          Logger.i(
            'CRC32 校验通过 [$fileName]: $localCrc32',
            tag: 'DictionaryStore',
          );
        } catch (e) {
          // 如果是 CRC32 不匹配异常，直接抛出
          if (e.toString().contains('CRC32')) {
            rethrow;
          }
          // 其他错误（如文件读取失败）记录日志但不阻止下载
          Logger.w('CRC32 校验异常: $e', tag: 'DictionaryStore');
        }
      } else if (shouldVerifyCrc32 && serverCrc32 == null) {
        Logger.w('服务器未返回 CRC32 值，跳过校验: $fileName', tag: 'DictionaryStore');
      } else if (shouldVerifyCrc32 && isResuming) {
        Logger.i('断点续传模式，跳过 CRC32 校验: $fileName', tag: 'DictionaryStore');
      }

      // 下载完成，重命名临时文件为正式文件
      await tempFile.rename(savePath);

      Logger.i(
        '文件下载完成: $fileName (${formatBytes(downloadedBytes)})',
        tag: 'DictionaryStore',
      );
      yield {'type': 'file_complete', 'fileName': fileName};
      yield {'type': 'complete'};
    } catch (e) {
      Logger.e('文件下载异常(流式): $e', tag: 'DictionaryStore');
      yield {'type': 'error', 'error': e.toString()};
    }
  }

  /// 判断文件是否需要进行 CRC32 校验
  ///
  /// 仅 dictionary.db 和 media.db 需要校验
  bool _shouldVerifyCrc32(String fileName) {
    return fileName == 'dictionary.db' || fileName == 'media.db';
  }

  void dispose() {
    _client.close();
  }
}

/// 下载选项
class DownloadOptions {
  final bool includeDatabase;
  final bool includeMedia;

  const DownloadOptions({
    required this.includeDatabase,
    this.includeMedia = false,
  });
}
