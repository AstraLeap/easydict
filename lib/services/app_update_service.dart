import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'preferences_service.dart';
import '../core/logger.dart';

/// GitHub Release 信息
class GitHubRelease {
  final String tagName;
  final String name;
  final String htmlUrl;
  final String body;
  final DateTime publishedAt;

  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.body,
    required this.publishedAt,
  });

  /// 版本号（去掉 'v' 前缀）
  String get version => tagName.startsWith('v') ? tagName.substring(1) : tagName;
}

class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  static const String _repoOwner = 'AstraLeap';
  static const String _repoName = 'easydict';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  final PreferencesService _preferencesService = PreferencesService();

  GitHubRelease? _latestRelease;
  String? _currentVersion;
  bool _hasUpdate = false;
  bool _isChecking = false;
  String? _errorMessage;
  DateTime? _lastCheckTime;

  GitHubRelease? get latestRelease => _latestRelease;
  String? get currentVersion => _currentVersion;
  bool get hasUpdate => _hasUpdate;
  bool get isChecking => _isChecking;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckTime => _lastCheckTime;

  /// 启动时检查：若超过 24 小时未检查则在后台触发
  Future<void> checkOnStartup() async {
    try {
      final lastCheck = await _preferencesService.getLastAppUpdateCheckTime();
      if (lastCheck != null) {
        _lastCheckTime = lastCheck;
      }
      final now = DateTime.now();
      if (lastCheck == null || now.difference(lastCheck).inHours >= 24) {
        checkForUpdates();
      }
    } catch (e) {
      Logger.w('AppUpdateService.checkOnStartup 失败: $e', tag: 'AppUpdate');
    }
  }

  /// 手动检查更新（await 可等待结果）
  Future<void> checkForUpdates() async {
    if (_isChecking) return;

    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;

      // 请求 GitHub API
      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final release = GitHubRelease(
          tagName: json['tag_name'] as String? ?? '',
          name: json['name'] as String? ?? '',
          htmlUrl: json['html_url'] as String? ?? '',
          body: json['body'] as String? ?? '',
          publishedAt: DateTime.tryParse(
                json['published_at'] as String? ?? '',
              ) ??
              DateTime.now(),
        );
        _latestRelease = release;
        _hasUpdate = _isNewerVersion(release.version, _currentVersion ?? '');
        Logger.i(
          '最新版本: ${release.version}, 当前版本: $_currentVersion, 有更新: $_hasUpdate',
          tag: 'AppUpdate',
        );
      } else if (response.statusCode == 404) {
        Logger.i('未找到 GitHub Release（可能还没有发布），statusCode=404', tag: 'AppUpdate');
        _hasUpdate = false;
      } else {
        _errorMessage = 'GitHub API 错误 (${response.statusCode})';
        Logger.w(_errorMessage!, tag: 'AppUpdate');
      }

      _lastCheckTime = DateTime.now();
      await _preferencesService.setLastAppUpdateCheckTime(_lastCheckTime!);
    } catch (e) {
      _errorMessage = '检查更新失败: $e';
      Logger.w(_errorMessage!, tag: 'AppUpdate');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// 比较版本号，若 latest > current 返回 true
  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // 补齐长度
      while (latestParts.length < 3) latestParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false; // 相等
    } catch (e) {
      Logger.w('版本号比较失败: $e', tag: 'AppUpdate');
      return false;
    }
  }
}
