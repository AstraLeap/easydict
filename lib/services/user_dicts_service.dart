import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../data/models/user_dictionary.dart';
import '../core/logger.dart';
import 'auth_service.dart';

class UserDictsService {
  static final UserDictsService _instance = UserDictsService._internal();
  factory UserDictsService() => _instance;
  UserDictsService._internal();

  final http.Client _client = http.Client();
  final AuthService _authService = AuthService();

  String? _baseUrl;
  String? _uploadBaseUrl;

  void setBaseUrl(String? url) {
    _baseUrl = url;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (uri.host.startsWith('dict.')) {
        final newHost = uri.host.replaceFirst('dict.', 'upload.dict.');
        _uploadBaseUrl = uri.replace(host: newHost).toString();
      } else {
        _uploadBaseUrl = url;
      }
    } else {
      _uploadBaseUrl = null;
    }
  }

  void setUploadBaseUrl(String? url) {
    _uploadBaseUrl = url;
  }

  String _buildUrl(String path) {
    final authBaseUrl = _baseUrl;
    if (authBaseUrl == null || authBaseUrl.isEmpty) {
      throw Exception('服务器地址未设置');
    }
    final cleanBaseUrl = authBaseUrl.endsWith('/')
        ? authBaseUrl.substring(0, authBaseUrl.length - 1)
        : authBaseUrl;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBaseUrl/$cleanPath';
  }

  String _buildUploadUrl(String path) {
    final uploadBaseUrl = _uploadBaseUrl;
    if (uploadBaseUrl == null || uploadBaseUrl.isEmpty) {
      throw Exception('上传服务器地址未设置');
    }
    final cleanBaseUrl = uploadBaseUrl.endsWith('/')
        ? uploadBaseUrl.substring(0, uploadBaseUrl.length - 1)
        : uploadBaseUrl;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBaseUrl/$cleanPath';
  }

  Map<String, String> _getHeaders({bool withAuth = true}) {
    final headers = {
      'Accept': 'application/json',
      'User-Agent': 'EasyDict/1.0.0',
    };
    if (withAuth) {
      final token = _authService.token;
      Logger.d(
        '获取token: ${token != null ? '存在(${token.substring(0, token.length > 10 ? 10 : token.length)}...)' : 'null'}',
        tag: 'UserDictsService',
      );
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// 获取用户词典列表
  Future<List<UserDictionary>> fetchUserDicts() async {
    try {
      final url = Uri.parse(_buildUrl('user/dicts'));
      Logger.i('获取用户词典列表: $url', tag: 'UserDictsService');

      final response = await _client
          .get(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 30));

      Logger.i('获取词典列表响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data.map((item) => UserDictionary.fromJson(item)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('登录已过期，请重新登录');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '获取词典列表失败';
        throw Exception(errorMsg);
      }
    } on FormatException catch (e) {
      Logger.e('解析响应失败: $e', tag: 'UserDictsService');
      throw Exception('服务器返回数据格式错误');
    } catch (e) {
      Logger.e('获取词典列表异常: $e', tag: 'UserDictsService');
      throw Exception('获取词典列表失败: $e');
    }
  }

  String _generateMultipartBoundary() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return 'EasyDictBoundary$random';
  }

  Future<UploadResult> _uploadWithProgress({
    required String endpoint,
    required String method,
    required Map<String, String> fields,
    required List<(String fieldName, File file, String filename)> files,
    void Function(
      String fileName,
      int current,
      int total,
      int sent,
      int totalBytes,
    )?
    onProgress,
  }) async {
    HttpClient? httpClient;
    try {
      final url = Uri.parse(_buildUploadUrl(endpoint));
      Logger.i('$method 上传: $url', tag: 'UserDictsService');

      final boundary = _generateMultipartBoundary();
      httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(minutes: 5);
      httpClient.idleTimeout = const Duration(minutes: 5);

      Logger.d('开始建立连接...', tag: 'UserDictsService');
      final httpRequest = await httpClient.openUrl(method, url);
      Logger.d('连接已建立', tag: 'UserDictsService');

      final headers = _getHeaders();
      Logger.d('设置请求头: $headers', tag: 'UserDictsService');
      headers.forEach((key, value) {
        httpRequest.headers.set(key, value);
      });
      httpRequest.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      Logger.d(
        'Content-Type: ${httpRequest.headers.contentType}',
        tag: 'UserDictsService',
      );

      final bodyParts = <Uint8List>[];
      final utf8Encoder = utf8.encoder;

      for (final entry in fields.entries) {
        final part =
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
            '${entry.value}\r\n';
        bodyParts.add(utf8Encoder.convert(part));
      }

      final fileInfos =
          <
            (
              String fieldName,
              File file,
              String filename,
              int length,
              Uint8List header,
            )
          >[];
      var totalBytes = 0;

      for (final (fieldName, file, filename) in files) {
        final length = await file.length();
        final header =
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n'
            'Content-Type: application/octet-stream\r\n\r\n';
        final headerBytes = utf8Encoder.convert(header);
        fileInfos.add((fieldName, file, filename, length, headerBytes));
        totalBytes += length + headerBytes.length;
        Logger.d(
          '文件 $filename: ${(length / 1024 / 1024).toStringAsFixed(2)} MB',
          tag: 'UserDictsService',
        );
      }

      var headerBytes = 0;
      for (final part in bodyParts) {
        headerBytes += part.length;
      }
      // 添加文件之间的 \r\n 分隔符 (每个文件后添加，最后一个除外)
      final separatorBytes = (files.length > 1) ? (files.length - 1) * 2 : 0;
      // 添加最后的 footer: \r\n--boundary--\r\n
      final footerBytes = '\r\n--$boundary--\r\n'.length;
      totalBytes += headerBytes + separatorBytes + footerBytes;

      final totalContentLength = totalBytes;
      httpRequest.headers.contentLength = totalContentLength;
      Logger.d(
        '总上传大小: ${(totalContentLength / 1024 / 1024).toStringAsFixed(2)} MB',
        tag: 'UserDictsService',
      );

      var totalSent = 0;
      var currentFileIndex = 0;
      final totalFiles = files.length;

      // 发送 fields 部分
      Logger.d('发送请求头和字段...', tag: 'UserDictsService');
      for (final part in bodyParts) {
        httpRequest.add(part);
        totalSent += part.length;
      }
      await httpRequest.flush();
      Logger.d('字段已发送', tag: 'UserDictsService');

      var lastLogTime = DateTime.now();
      for (final (_, file, filename, _, fileHeader) in fileInfos) {
        currentFileIndex++;
        Logger.d(
          '开始发送文件 $currentFileIndex/$totalFiles: $filename',
          tag: 'UserDictsService',
        );

        // 发送该文件的 header
        httpRequest.add(fileHeader);
        await httpRequest.flush();
        totalSent += fileHeader.length;

        // 发送文件内容
        final stream = file.openRead();
        var fileBytesSent = 0;
        await for (final chunk in stream) {
          httpRequest.add(chunk);
          await httpRequest.flush();
          totalSent += chunk.length;
          fileBytesSent += chunk.length;

          final now = DateTime.now();
          if (now.difference(lastLogTime).inSeconds >= 5) {
            final progress = (totalSent / totalContentLength * 100)
                .toStringAsFixed(1);
            Logger.d(
              '上传进度: $progress% (${(totalSent / 1024 / 1024).toStringAsFixed(1)} MB / ${(totalContentLength / 1024 / 1024).toStringAsFixed(1)} MB)',
              tag: 'UserDictsService',
            );
            lastLogTime = now;
          }

          if (onProgress != null) {
            onProgress(
              filename,
              currentFileIndex,
              totalFiles,
              totalSent,
              totalContentLength,
            );
          }
        }
        // 文件内容发送完成后，添加 \r\n 作为分隔（除了最后一个文件）
        // 注意：下一个文件的 boundary 已经包含在 header 中了
        if (currentFileIndex < totalFiles) {
          httpRequest.add(utf8Encoder.convert('\r\n'));
          await httpRequest.flush();
          totalSent += 2;
        }
        Logger.d(
          '文件 $filename 发送完成 ($fileBytesSent bytes)',
          tag: 'UserDictsService',
        );
      }

      // 发送最后的 footer
      final footer = '\r\n--$boundary--\r\n';
      httpRequest.add(utf8Encoder.convert(footer));
      await httpRequest.flush();
      totalSent += footer.length;

      Logger.d('等待服务器响应...', tag: 'UserDictsService');
      final httpResponse = await httpRequest.close();
      Logger.d('收到响应: ${httpResponse.statusCode}', tag: 'UserDictsService');
      final responseBytes = await httpResponse.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      );

      final statusCode = httpResponse.statusCode;
      final responseBody = utf8.decode(responseBytes);

      Logger.i('$method 上传响应: $statusCode', tag: 'UserDictsService');

      httpClient.close();

      if (statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        return UploadResult(
          success: true,
          dictId: data['dict_id'] as String?,
          name: data['name'] as String?,
          version: data['version'] as int?,
          updatedFiles: (data['updated_files'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
        );
      } else if (statusCode == 401) {
        return UploadResult(success: false, error: '登录已过期，请重新登录');
      } else {
        final errorData = jsonDecode(responseBody) as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '上传失败';
        return UploadResult(success: false, error: errorMsg);
      }
    } catch (e, stackTrace) {
      Logger.e('$method 上传异常: $e', tag: 'UserDictsService');
      Logger.d('堆栈: $stackTrace', tag: 'UserDictsService');
      return UploadResult(success: false, error: '上传失败: $e');
    } finally {
      httpClient?.close();
    }
  }

  /// 上传新词典
  Future<UploadResult> uploadDictionary({
    required File metadataFile,
    required File dictionaryFile,
    required File logoFile,
    File? mediaFile,
    String message = '初始上传',
    void Function(
      String fileName,
      int current,
      int total,
      int sent,
      int totalBytes,
    )?
    onProgress,
  }) async {
    final files = <(String, File, String)>[
      ('metadata_file', metadataFile, 'metadata.json'),
      ('dictionary_file', dictionaryFile, 'dictionary.db'),
      ('logo_file', logoFile, 'logo.png'),
    ];

    if (mediaFile != null) {
      files.add(('media_file', mediaFile, 'media.db'));
    }

    return _uploadWithProgress(
      endpoint: '',
      method: 'POST',
      fields: {},
      files: files,
      onProgress: onProgress,
    );
  }

  /// 删除词典
  Future<bool> deleteDictionary(String dictId) async {
    try {
      final url = Uri.parse(_buildUrl('user/dicts/$dictId'));
      Logger.i('删除词典: $url', tag: 'UserDictsService');

      final response = await _client
          .delete(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 30));

      Logger.i('删除词典响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 401) {
        throw Exception('登录已过期，请重新登录');
      } else if (response.statusCode == 404) {
        throw Exception('词典不存在');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '删除失败';
        throw Exception(errorMsg);
      }
    } catch (e) {
      Logger.e('删除词典异常: $e', tag: 'UserDictsService');
      throw Exception('删除失败: $e');
    }
  }

  /// 更新/插入词典条目
  Future<EntryUpdateResult> updateEntry(
    String dictId, {
    required String entryId,
    required String headword,
    required String entryType,
    required String definition,
    required int version,
    String message = '更新条目',
  }) async {
    try {
      final url = Uri.parse(
        _buildUrl('user/dicts/$dictId/entries?message=$message'),
      );
      Logger.i('更新条目: $url', tag: 'UserDictsService');

      final body = {
        'entry_id': entryId,
        'headword': headword,
        'entry_type': entryType,
        'definition': definition,
        'version': version,
      };

      final response = await _client
          .post(
            url,
            headers: {..._getHeaders(), 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      Logger.i('更新条目响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return EntryUpdateResult(
          success: true,
          action: data['action'] as String?,
          entryId: data['entry_id'] as String?,
        );
      } else if (response.statusCode == 401) {
        return EntryUpdateResult(success: false, error: '登录已过期，请重新登录');
      } else if (response.statusCode == 404) {
        return EntryUpdateResult(success: false, error: '词典不存在');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '更新失败';
        return EntryUpdateResult(success: false, error: errorMsg);
      }
    } catch (e) {
      Logger.e('更新条目异常: $e', tag: 'UserDictsService');
      return EntryUpdateResult(success: false, error: '更新失败: $e');
    }
  }

  /// 更新词典文件
  Future<UploadResult> updateDictionary(
    String dictId, {
    required String message,
    File? metadataFile,
    File? dictionaryFile,
    File? logoFile,
    File? mediaFile,
    void Function(
      String fileName,
      int current,
      int total,
      int sent,
      int totalBytes,
    )?
    onProgress,
  }) async {
    final files = <(String, File, String)>[];

    if (metadataFile != null) {
      files.add(('metadata_file', metadataFile, 'metadata.json'));
    }

    if (dictionaryFile != null) {
      files.add(('dictionary_file', dictionaryFile, 'dictionary.db'));
    }

    if (logoFile != null) {
      files.add(('logo_file', logoFile, 'logo.png'));
    }

    if (mediaFile != null) {
      files.add(('media_file', mediaFile, 'media.db'));
    }

    if (files.isEmpty) {
      return UploadResult(success: false, error: '请至少选择一个文件进行更新');
    }

    return _uploadWithProgress(
      endpoint: dictId,
      method: 'POST',
      fields: {'message': message},
      files: files,
      onProgress: onProgress,
    );
  }

  /// 推送条目更新
  /// [dictId] - 词典ID
  /// [zstFile] - entries.zst 文件
  /// [message] - 更新消息
  Future<PushUpdateResult> pushEntryUpdates(
    String dictId, {
    required File zstFile,
    String message = '更新条目',
  }) async {
    try {
      final url = Uri.parse(_buildUrl('user/dicts/$dictId/entries'));
      Logger.i('推送条目更新: $url', tag: 'UserDictsService');

      // 读取文件内容
      final fileBytes = await zstFile.readAsBytes();
      Logger.d(
        'ZST file size: ${fileBytes.length} bytes',
        tag: 'UserDictsService',
      );

      // 使用 http.Client 发送 multipart 请求
      final request = http.MultipartRequest('POST', url);

      // 添加认证头
      final token = _authService.token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // 添加消息字段
      request.fields['message'] = message;
      Logger.d('Request fields: ${request.fields}', tag: 'UserDictsService');

      // 添加 zst 文件（从内存中）
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: 'entries.zst',
      );
      request.files.add(multipartFile);
      Logger.d(
        'Request files count: ${request.files.length}',
        tag: 'UserDictsService',
      );

      // 手动构建 multipart body 来查看 Content-Type
      final boundary =
          'dart-http-boundary-${DateTime.now().millisecondsSinceEpoch}';
      request.headers['Content-Type'] =
          'multipart/form-data; boundary=$boundary';
      Logger.d(
        'Content-Type: ${request.headers['Content-Type']}',
        tag: 'UserDictsService',
      );

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 100),
      );

      final response = await http.Response.fromStream(streamedResponse);

      Logger.i('推送条目更新响应: ${response.statusCode}', tag: 'UserDictsService');
      Logger.d('Response body: ${response.body}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return PushUpdateResult(
          success: true,
          count: data['count'] as int? ?? 0,
          version: data['version'] as int?,
          results: (data['results'] as List<dynamic>?)
              ?.map((e) => PushUpdateItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      } else if (response.statusCode == 401) {
        return PushUpdateResult(success: false, error: '登录已过期，请重新登录');
      } else if (response.statusCode == 404) {
        return PushUpdateResult(success: false, error: '词典不存在');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '推送更新失败';
        return PushUpdateResult(success: false, error: errorMsg);
      }
    } catch (e, stackTrace) {
      Logger.e('推送条目更新异常: $e\n堆栈: $stackTrace', tag: 'UserDictsService');
      return PushUpdateResult(success: false, error: '推送更新失败: $e');
    }
  }

  /// 获取单个词典更新信息
  /// [dictId] - 词典ID
  /// [fromVer] - 当前版本
  /// [toVer] - 目标版本（可选，不传则获取到最新版本）
  Future<DictUpdateInfo?> getDictUpdateInfo(
    String dictId,
    int fromVer, [
    int? toVer,
  ]) async {
    final result = await getDictsUpdateInfo({dictId: (fromVer, toVer)});
    return result[dictId];
  }

  /// 批量获取词典更新信息
  /// [dictVersions] - 字典，key为词典ID，value为(fromVer, toVer?)元组
  /// toVer为null时表示获取到最新版本
  Future<Map<String, DictUpdateInfo>> getDictsUpdateInfo(
    Map<String, (int, int?)> dictVersions,
  ) async {
    try {
      final queryParams = <String>[];
      dictVersions.forEach((dictId, versions) {
        final (fromVer, toVer) = versions;
        if (toVer != null) {
          queryParams.add('$dictId=$fromVer:$toVer');
        } else {
          queryParams.add('$dictId=$fromVer');
        }
      });

      final url = Uri.parse(_buildUrl('update?${queryParams.join('&')}'));
      Logger.i('批量获取词典更新信息: $url', tag: 'UserDictsService');

      final response = await _client
          .get(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 30));

      Logger.i('获取更新信息响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final result = <String, DictUpdateInfo>{};

        Logger.d('更新信息响应数据类型: ${data.runtimeType}', tag: 'UserDictsService');

        if (data is List) {
          Logger.d('解析数组格式，长度: ${data.length}', tag: 'UserDictsService');
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final dictId = item['dict_id'] as String?;
              Logger.d(
                '解析词典: $dictId, from: ${item['from']}, to: ${item['to']}',
                tag: 'UserDictsService',
              );
              if (dictId != null) {
                result[dictId] = DictUpdateInfo.fromJson(item);
              }
            }
          }
        } else if (data is Map<String, dynamic>) {
          Logger.d('解析对象格式', tag: 'UserDictsService');
          data.forEach((key, value) {
            if (value != null) {
              result[key] = DictUpdateInfo.fromJson(
                value as Map<String, dynamic>,
              );
            }
          });
        }

        Logger.d('解析结果: ${result.keys.toList()}', tag: 'UserDictsService');
        return result;
      } else {
        return {};
      }
    } catch (e) {
      Logger.e('批量获取更新信息异常: $e', tag: 'UserDictsService');
      return {};
    }
  }

  /// 下载词典条目更新
  Future<Uint8List?> downloadEntryUpdates(
    String dictId,
    List<int> entries,
  ) async {
    try {
      final url = Uri.parse(_buildUrl('download/$dictId/entries'));
      Logger.i('下载条目更新: $url', tag: 'UserDictsService');

      final body = jsonEncode({'entries': entries});
      Logger.d('请求体: $body', tag: 'UserDictsService');

      final response = await _client
          .post(
            url,
            headers: {..._getHeaders(), 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        Logger.w(
          '条目下载失败: HTTP ${response.statusCode}, 响应: ${utf8.decode(response.bodyBytes)}',
          tag: 'UserDictsService',
        );
        return null;
      }
    } catch (e) {
      Logger.e('条目下载异常: $e', tag: 'UserDictsService');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchEntry(
    String dictId,
    String entryId,
  ) async {
    try {
      final url = Uri.parse(_buildUrl('entry/$dictId/$entryId'));
      Logger.i('获取词条: $url', tag: 'UserDictsService');

      final response = await _client
          .get(url, headers: _getHeaders())
          .timeout(const Duration(seconds: 30));

      Logger.i('获取词条响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 404) {
        Logger.w('词条不存在: $dictId/$entryId', tag: 'UserDictsService');
        return null;
      } else {
        Logger.w(
          '获取词条失败: HTTP ${response.statusCode}',
          tag: 'UserDictsService',
        );
        return null;
      }
    } catch (e) {
      Logger.e('获取词条异常: $e', tag: 'UserDictsService');
      return null;
    }
  }

  void dispose() {
    // 不关闭 client，因为它是单例共享的
    // _client.close();
  }
}
