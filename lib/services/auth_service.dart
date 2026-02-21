import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import '../data/models/user.dart';
import '../core/logger.dart';

class AuthResult {
  final bool success;
  final String? error;
  final User? user;
  final String? token;

  AuthResult({required this.success, this.error, this.user, this.token});
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final http.Client _client = http.Client();

  String? _baseUrl;
  String? _token;
  User? _currentUser;

  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _token != null && _currentUser != null;

  void setBaseUrl(String? url) {
    _baseUrl = url;
    Logger.i('AuthService baseUrl 设置为: $url', tag: 'AuthService');
  }

  String _buildUrl(String path) {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      throw Exception('服务器地址未设置');
    }
    final cleanBaseUrl = _baseUrl!.endsWith('/')
        ? _baseUrl!.substring(0, _baseUrl!.length - 1)
        : _baseUrl!;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBaseUrl/$cleanPath';
  }

  Map<String, String> _getHeaders({bool withAuth = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'EasyDict/1.0.0',
    };
    if (withAuth && _token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return AuthResult(success: false, error: '请先设置服务器地址');
      }

      final url = Uri.parse(_buildUrl('user/register'));
      Logger.i('注册请求: $url', tag: 'AuthService');

      final requestBody = jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      });
      Logger.i('注册请求体: $requestBody', tag: 'AuthService');

      final response = await _client
          .post(url, headers: _getHeaders(), body: requestBody)
          .timeout(const Duration(seconds: 30));

      Logger.i('注册响应: ${response.statusCode}', tag: 'AuthService');
      Logger.i('注册响应体: ${utf8.decode(response.bodyBytes)}', tag: 'AuthService');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _token = data['access_token'] as String?;
        if (data['user'] != null) {
          _currentUser = User.fromJson(Map<String, dynamic>.from(data['user']));
        }
        Logger.i('注册成功: ${_currentUser?.email}', tag: 'AuthService');
        return AuthResult(success: true, user: _currentUser, token: _token);
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = _parseErrorMessage(errorData);
        Logger.w('注册失败: $errorMsg, 响应数据: $errorData', tag: 'AuthService');
        return AuthResult(success: false, error: errorMsg);
      }
    } on TimeoutException {
      Logger.e('注册超时', tag: 'AuthService');
      return AuthResult(success: false, error: '请求超时，请检查网络连接');
    } catch (e) {
      Logger.e('注册异常: $e', tag: 'AuthService');
      return AuthResult(success: false, error: '注册失败: $e');
    }
  }

  Future<AuthResult> login({
    required String identifier,
    required String password,
  }) async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return AuthResult(success: false, error: '请先设置服务器地址');
      }

      final url = Uri.parse(_buildUrl('user/login'));
      Logger.i('登录请求: $url', tag: 'AuthService');

      final requestBody = jsonEncode({
        'identifier': identifier,
        'password': password,
      });
      Logger.i('登录请求体: $requestBody', tag: 'AuthService');

      final response = await _client
          .post(url, headers: _getHeaders(), body: requestBody)
          .timeout(const Duration(seconds: 30));

      Logger.i('登录响应: ${response.statusCode}', tag: 'AuthService');
      Logger.i('登录响应体: ${utf8.decode(response.bodyBytes)}', tag: 'AuthService');

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _token = data['access_token'] as String?;
        if (data['user'] != null) {
          _currentUser = User.fromJson(Map<String, dynamic>.from(data['user']));
        }
        Logger.i('登录成功: ${_currentUser?.email}', tag: 'AuthService');
        return AuthResult(success: true, user: _currentUser, token: _token);
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = _parseErrorMessage(errorData);
        Logger.w('登录失败: $errorMsg, 响应数据: $errorData', tag: 'AuthService');
        return AuthResult(success: false, error: errorMsg);
      }
    } on TimeoutException {
      Logger.e('登录超时', tag: 'AuthService');
      return AuthResult(success: false, error: '请求超时，请检查网络连接');
    } catch (e) {
      Logger.e('登录异常: $e', tag: 'AuthService');
      return AuthResult(success: false, error: '登录失败: $e');
    }
  }

  Future<AuthResult> getCurrentUser() async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return AuthResult(success: false, error: '请先设置服务器地址');
      }

      if (_token == null) {
        return AuthResult(success: false, error: '未登录');
      }

      final url = Uri.parse(_buildUrl('user/me'));
      Logger.i('获取用户信息: $url', tag: 'AuthService');

      final response = await _client
          .get(url, headers: _getHeaders(withAuth: true))
          .timeout(const Duration(seconds: 30));

      Logger.i('获取用户信息响应: ${response.statusCode}', tag: 'AuthService');

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _currentUser = User.fromJson(Map<String, dynamic>.from(data));
        Logger.i('获取用户信息成功: ${_currentUser?.email}', tag: 'AuthService');
        return AuthResult(success: true, user: _currentUser);
      } else if (response.statusCode == 401) {
        logout();
        return AuthResult(success: false, error: '登录已过期，请重新登录');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg =
            errorData?['error'] ?? errorData?['message'] ?? '获取用户信息失败';
        return AuthResult(success: false, error: errorMsg.toString());
      }
    } on TimeoutException {
      return AuthResult(success: false, error: '请求超时，请检查网络连接');
    } catch (e) {
      Logger.e('获取用户信息异常: $e', tag: 'AuthService');
      return AuthResult(success: false, error: '获取用户信息失败: $e');
    }
  }

  String _parseErrorMessage(Map<String, dynamic>? errorData) {
    if (errorData == null) return '请求失败';

    if (errorData['detail'] != null) {
      return errorData['detail'].toString();
    }
    if (errorData['error'] != null) {
      return errorData['error'].toString();
    }
    if (errorData['message'] != null) {
      return errorData['message'].toString();
    }

    return '请求失败';
  }

  void logout() {
    _token = null;
    _currentUser = null;
    Logger.i('已退出登录', tag: 'AuthService');
  }

  void restoreSession({
    required String? token,
    required Map<String, dynamic>? userData,
  }) {
    if (token != null && token.isNotEmpty) {
      _token = token;
      if (userData != null) {
        try {
          _currentUser = User.fromJson(userData);
          Logger.i('恢复登录状态: ${_currentUser?.email}', tag: 'AuthService');
        } catch (e) {
          Logger.e('恢复用户信息失败: $e', tag: 'AuthService');
        }
      }
    }
  }

  void dispose() {
    _client.close();
  }

  Future<SettingsResult> downloadSettings() async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return SettingsResult(success: false, error: '请先设置服务器地址');
      }

      if (_token == null) {
        return SettingsResult(success: false, error: '未登录');
      }

      final url = Uri.parse(_buildUrl('settings'));
      Logger.i('下载设置: $url', tag: 'AuthService');

      final response = await _client
          .get(url, headers: _getHeaders(withAuth: true))
          .timeout(const Duration(seconds: 60));

      Logger.i('下载设置响应: ${response.statusCode}', tag: 'AuthService');

      if (response.statusCode == 200) {
        return SettingsResult(success: true, data: response.bodyBytes);
      } else if (response.statusCode == 404) {
        return SettingsResult(success: false, error: '云端暂无设置数据');
      } else if (response.statusCode == 401) {
        logout();
        return SettingsResult(success: false, error: '登录已过期，请重新登录');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = _parseErrorMessage(errorData);
        return SettingsResult(success: false, error: errorMsg);
      }
    } on TimeoutException {
      return SettingsResult(success: false, error: '请求超时，请检查网络连接');
    } catch (e) {
      Logger.e('下载设置异常: $e', tag: 'AuthService');
      return SettingsResult(success: false, error: '下载设置失败: $e');
    }
  }

  Future<SettingsResult> uploadSettings(String zipFilePath) async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return SettingsResult(success: false, error: '请先设置服务器地址');
      }

      if (_token == null) {
        return SettingsResult(success: false, error: '未登录');
      }

      final file = File(zipFilePath);
      if (!await file.exists()) {
        return SettingsResult(success: false, error: '设置文件不存在');
      }

      final url = Uri.parse(_buildUrl('settings'));
      Logger.i('上传设置: $url', tag: 'AuthService');

      final request = http.MultipartRequest('POST', url);
      request.headers.addAll(_getHeaders(withAuth: true));
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          zipFilePath,
          filename: basename(zipFilePath),
        ),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      Logger.i('上传设置响应: ${response.statusCode}', tag: 'AuthService');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return SettingsResult(success: true);
      } else if (response.statusCode == 401) {
        logout();
        return SettingsResult(success: false, error: '登录已过期，请重新登录');
      } else {
        final errorData =
            jsonDecode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>?;
        final errorMsg = _parseErrorMessage(errorData);
        return SettingsResult(success: false, error: errorMsg);
      }
    } on TimeoutException {
      return SettingsResult(success: false, error: '请求超时，请检查网络连接');
    } catch (e) {
      Logger.e('上传设置异常: $e', tag: 'AuthService');
      return SettingsResult(success: false, error: '上传设置失败: $e');
    }
  }

  Future<bool> deleteSettings() async {
    try {
      if (_baseUrl == null || _baseUrl!.isEmpty) {
        return false;
      }

      if (_token == null) {
        return false;
      }

      final url = Uri.parse(_buildUrl('settings'));
      Logger.i('删除设置: $url', tag: 'AuthService');

      final response = await _client
          .delete(url, headers: _getHeaders(withAuth: true))
          .timeout(const Duration(seconds: 30));

      Logger.i('删除设置响应: ${response.statusCode}', tag: 'AuthService');

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      Logger.e('删除设置异常: $e', tag: 'AuthService');
      return false;
    }
  }
}

class SettingsResult {
  final bool success;
  final String? error;
  final List<int>? data;

  SettingsResult({required this.success, this.error, this.data});
}
