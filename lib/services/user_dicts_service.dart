import 'dart:convert';
import 'dart:io';
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

  String _buildUrl(String path) {
    // 从 AuthService 获取 baseUrl
    final authBaseUrl = _getBaseUrlFromAuth();
    if (authBaseUrl == null || authBaseUrl.isEmpty) {
      throw Exception('服务器地址未设置');
    }
    final cleanBaseUrl = authBaseUrl.endsWith('/')
        ? authBaseUrl.substring(0, authBaseUrl.length - 1)
        : authBaseUrl;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBaseUrl/$cleanPath';
  }

  String? _getBaseUrlFromAuth() {
    // AuthService 没有直接暴露 baseUrl，我们通过反射或修改 AuthService 来获取
    // 这里使用一个变通方法：从 AuthService 的当前状态推断
    return _authService.currentUser != null ? _getBaseUrl() : null;
  }

  String? _baseUrl;

  void setBaseUrl(String? url) {
    _baseUrl = url;
  }

  String? _getBaseUrl() {
    return _baseUrl;
  }

  Map<String, String> _getHeaders({bool withAuth = true}) {
    final headers = {
      'Accept': 'application/json',
      'User-Agent': 'EasyDict/1.0.0',
    };
    if (withAuth) {
      final token = _authService.token;
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

  /// 上传新词典
  Future<UploadResult> uploadDictionary({
    required File metadataFile,
    required File dictionaryFile,
    required File logoFile,
    File? mediaFile,
    String message = '初始上传',
  }) async {
    try {
      final url = Uri.parse(_buildUrl('user/dicts'));
      Logger.i('上传词典: $url', tag: 'UserDictsService');

      final request = http.MultipartRequest('POST', url);

      // 添加认证头
      final headers = _getHeaders();
      request.headers.addAll(headers);

      // 添加文件
      request.files.add(
        await http.MultipartFile.fromPath('metadata_file', metadataFile.path),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'dictionary_file',
          dictionaryFile.path,
        ),
      );

      request.files.add(
        await http.MultipartFile.fromPath('logo_file', logoFile.path),
      );

      if (mediaFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('media_file', mediaFile.path),
        );
      }

      // 添加消息字段
      request.fields['message'] = message;

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );

      final response = await http.Response.fromStream(streamedResponse);

      Logger.i('上传词典响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return UploadResult(
          success: true,
          dictId: data['dict_id'] as String?,
          name: data['name'] as String?,
        );
      } else if (response.statusCode == 401) {
        return UploadResult(success: false, error: '登录已过期，请重新登录');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '上传失败';
        return UploadResult(success: false, error: errorMsg);
      }
    } catch (e) {
      Logger.e('上传词典异常: $e', tag: 'UserDictsService');
      return UploadResult(success: false, error: '上传失败: $e');
    }
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
  }) async {
    try {
      final url = Uri.parse(_buildUrl('user/dicts/$dictId'));
      Logger.i('更新词典: $url', tag: 'UserDictsService');

      final request = http.MultipartRequest('PUT', url);

      // 添加认证头
      final headers = _getHeaders();
      request.headers.addAll(headers);

      // 添加消息字段（必填）
      request.fields['message'] = message;

      // 添加文件（可选，但至少提供一个）
      if (metadataFile != null) {
        final metadataStream = http.ByteStream(metadataFile.openRead());
        final metadataLength = await metadataFile.length();
        final metadataMultipart = http.MultipartFile(
          'metadata_file',
          metadataStream,
          metadataLength,
          filename: 'metadata.json',
        );
        request.files.add(metadataMultipart);
      }

      if (dictionaryFile != null) {
        final dictStream = http.ByteStream(dictionaryFile.openRead());
        final dictLength = await dictionaryFile.length();
        final dictMultipart = http.MultipartFile(
          'dictionary_file',
          dictStream,
          dictLength,
          filename: 'dictionary.db',
        );
        request.files.add(dictMultipart);
      }

      if (logoFile != null) {
        final logoStream = http.ByteStream(logoFile.openRead());
        final logoLength = await logoFile.length();
        final logoMultipart = http.MultipartFile(
          'logo_file',
          logoStream,
          logoLength,
          filename: 'logo.png',
        );
        request.files.add(logoMultipart);
      }

      if (mediaFile != null) {
        final mediaStream = http.ByteStream(mediaFile.openRead());
        final mediaLength = await mediaFile.length();
        final mediaMultipart = http.MultipartFile(
          'media_file',
          mediaStream,
          mediaLength,
          filename: 'media.db',
        );
        request.files.add(mediaMultipart);
      }

      // 检查是否至少提供了一个文件
      if (request.files.isEmpty) {
        return UploadResult(success: false, error: '请至少选择一个文件进行更新');
      }

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );

      final response = await http.Response.fromStream(streamedResponse);

      Logger.i('更新词典响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return UploadResult(
          success: true,
          dictId: data['dict_id'] as String?,
          name: data['dict_id'] as String?,
        );
      } else if (response.statusCode == 401) {
        return UploadResult(success: false, error: '登录已过期，请重新登录');
      } else if (response.statusCode == 404) {
        return UploadResult(success: false, error: '词典不存在');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = errorData?['detail']?.toString() ?? '更新失败';
        return UploadResult(success: false, error: errorMsg);
      }
    } catch (e) {
      Logger.e('更新词典异常: $e', tag: 'UserDictsService');
      return UploadResult(success: false, error: '更新失败: $e');
    }
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

      final request = http.MultipartRequest('POST', url);

      // 添加认证头
      final headers = _getHeaders();
      request.headers.addAll(headers);

      // 添加消息字段
      request.fields['message'] = message;

      // 添加 zst 文件
      final fileStream = http.ByteStream(zstFile.openRead());
      final fileLength = await zstFile.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: 'entries.zst',
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );

      final response = await http.Response.fromStream(streamedResponse);

      Logger.i('推送条目更新响应: ${response.statusCode}', tag: 'UserDictsService');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return PushUpdateResult(
          success: true,
          count: data['count'] as int? ?? 0,
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
    } catch (e) {
      Logger.e('推送条目更新异常: $e', tag: 'UserDictsService');
      return PushUpdateResult(success: false, error: '推送更新失败: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
