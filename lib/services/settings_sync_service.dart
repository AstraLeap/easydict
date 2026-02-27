import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';

class SettingsSyncResult {
  final bool success;
  final String? error;
  final String? filePath;

  SettingsSyncResult({required this.success, this.error, this.filePath});
}

class SettingsSyncService {
  static final SettingsSyncService _instance = SettingsSyncService._internal();
  factory SettingsSyncService() => _instance;
  SettingsSyncService._internal();

  /// 不参与云同步的 SharedPreferences 键前缀（字体配置页、词典管理页相关设置）
  static const List<String> _excludedSyncKeyPrefixes = [
    'font_config_',   // 字体配置页 - 自定义字体映射
    'font_scale_',    // 字体配置页 - 字体缩放
  ];

  /// 不参与云同步的 SharedPreferences 精确键（字体配置页、词典管理页相关设置）
  static const List<String> _excludedSyncKeys = [
    'font_folder_path',          // 字体配置页 - 字体文件夹路径（设备相关）
    'dictionaries_base_dir',     // 词典管理页 - 词典目录路径（设备相关）
    'online_subscription_url',   // 词典管理页 - 在线订阅地址
    'enabled_dictionaries',      // 词典管理页 - 启用的词典列表
    'auto_check_dict_update',    // 词典管理页 - 自动检查更新
    'last_dict_update_check_time', // 词典管理页 - 上次检查时间
  ];

  bool _isExcludedFromSync(String rawKey) {
    // 去除平台前缀
    String key = rawKey.startsWith('flutter.') ? rawKey.substring(8) : rawKey;
    if (_excludedSyncKeys.contains(key)) return true;
    for (final prefix in _excludedSyncKeyPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  static const List<String> _syncFiles = [
    'ai_chat_history.db',
    'shared_preferences.json',
    'word_list.db',
  ];

  Future<String> get _configDir async {
    final appDir = await getApplicationSupportDirectory();
    return appDir.path;
  }

  Future<SettingsSyncResult> createSettingsZip() async {
    try {
      final configDir = await _configDir;
      final tempDir = await getTemporaryDirectory();
      final zipPath = join(
        tempDir.path,
        'settings_${DateTime.now().millisecondsSinceEpoch}.zip',
      );

      final archive = Archive();

      for (final fileName in _syncFiles) {
        final filePath = join(configDir, fileName);
        final file = File(filePath);

        if (await file.exists()) {
          List<int> bytes;
          // 对 shared_preferences.json 过滤不需要同步的键
          if (fileName == 'shared_preferences.json') {
            try {
              final jsonStr = await file.readAsString();
              final raw = jsonDecode(jsonStr);
              if (raw is Map<String, dynamic>) {
                final filtered = Map<String, dynamic>.fromEntries(
                  raw.entries.where((e) => !_isExcludedFromSync(e.key)),
                );
                bytes = utf8.encode(jsonEncode(filtered));
                Logger.i(
                  '过滤后 shared_preferences.json: ${raw.length} 键 → ${filtered.length} 键',
                  tag: 'SettingsSync',
                );
              } else {
                bytes = await file.readAsBytes();
              }
            } catch (e) {
              Logger.w('过滤 shared_preferences.json 失败，使用原始文件: $e', tag: 'SettingsSync');
              bytes = await file.readAsBytes();
            }
          } else {
            bytes = await file.readAsBytes();
          }
          final archiveFile = ArchiveFile.noCompress(
            fileName,
            bytes.length,
            bytes,
          );
          archive.addFile(archiveFile);
          Logger.i(
            '添加文件到压缩包: $fileName (${bytes.length} bytes)',
            tag: 'SettingsSync',
          );
        } else {
          Logger.w('文件不存在，跳过: $fileName', tag: 'SettingsSync');
        }
      }

      if (archive.isEmpty) {
        return SettingsSyncResult(success: false, error: '没有可同步的设置文件');
      }

      final zipData = ZipEncoder().encode(archive);
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);

      Logger.i(
        '设置压缩包创建成功: $zipPath (${zipData.length} bytes)',
        tag: 'SettingsSync',
      );
      return SettingsSyncResult(success: true, filePath: zipPath);
    } catch (e) {
      Logger.e('创建设置压缩包失败: $e', tag: 'SettingsSync');
      return SettingsSyncResult(success: false, error: '创建压缩包失败: $e');
    }
  }

  Future<SettingsSyncResult> extractSettingsZip(String zipPath) async {
    try {
      final configDir = await _configDir;
      final zipFile = File(zipPath);

      if (!await zipFile.exists()) {
        return SettingsSyncResult(success: false, error: '压缩包文件不存在');
      }

      final zipBytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      int extractedCount = 0;
      for (final file in archive) {
        if (_syncFiles.contains(file.name)) {
          final outputPath = join(configDir, file.name);
          final outputFile = File(outputPath);

          if (file.isFile) {
            final content = file.content as List<int>;
            await outputFile.writeAsBytes(content);
            extractedCount++;
            Logger.i(
              '解压文件: ${file.name} (${content.length} bytes)',
              tag: 'SettingsSync',
            );
          }
        }
      }

      if (extractedCount == 0) {
        return SettingsSyncResult(success: false, error: '压缩包中没有有效的设置文件');
      }

      Logger.i('设置解压成功，共 $extractedCount 个文件', tag: 'SettingsSync');
      return SettingsSyncResult(success: true);
    } catch (e) {
      Logger.e('解压设置压缩包失败: $e', tag: 'SettingsSync');
      return SettingsSyncResult(success: false, error: '解压失败: $e');
    }
  }

  Future<SettingsSyncResult> extractSettingsZipFromBytes(
    List<int> zipBytes,
  ) async {
    try {
      final configDir = await _configDir;
      final archive = ZipDecoder().decodeBytes(zipBytes);

      int extractedCount = 0;
      for (final file in archive) {
        if (_syncFiles.contains(file.name)) {
          final outputPath = join(configDir, file.name);
          final outputFile = File(outputPath);

          if (file.isFile) {
            final content = file.content as List<int>;
            await outputFile.writeAsBytes(content);
            extractedCount++;
            Logger.i(
              '解压文件: ${file.name} (${content.length} bytes)',
              tag: 'SettingsSync',
            );
          }
        }
      }

      if (extractedCount == 0) {
        return SettingsSyncResult(success: false, error: '压缩包中没有有效的设置文件');
      }

      Logger.i('设置解压成功，共 $extractedCount 个文件', tag: 'SettingsSync');
      return SettingsSyncResult(success: true);
    } catch (e) {
      Logger.e('解压设置压缩包失败: $e', tag: 'SettingsSync');
      return SettingsSyncResult(success: false, error: '解压失败: $e');
    }
  }

  /// 将已写入磁盘的 shared_preferences.json 直接解析并逐键写入内存SharedPreferences实例。
  /// 不依赖 prefs.reload()（平台通道实现延迟/缓存可能不生效），直接操作内存状态。
  Future<void> applyPrefsFromFile() async {
    try {
      final configDir = await _configDir;
      final prefsFile = File(join(configDir, 'shared_preferences.json'));
      if (!await prefsFile.exists()) {
        Logger.w('shared_preferences.json 不存在，跳过应用', tag: 'SettingsSync');
        return;
      }

      final jsonStr = await prefsFile.readAsString();
      final raw = jsonDecode(jsonStr);
      if (raw is! Map<String, dynamic>) {
        Logger.w('shared_preferences.json 格式错误', tag: 'SettingsSync');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      int count = 0;
      for (final entry in raw.entries) {
        // shared_preferences_windows/linux/macos 在文件中以 'flutter.' 前缀存储键，
        // 而 Dart 侧 setX() 方法会自动添加该前缀，故这里需要去除它
        String key = entry.key;
        if (key.startsWith('flutter.')) {
          key = key.substring(8);
        }
        // 跳过不参与云同步的键（字体配置页、词典管理页相关设置）
        if (_isExcludedFromSync(key)) continue;
        final value = entry.value;
        try {
          if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is String) {
            await prefs.setString(key, value);
          } else if (value is List) {
            await prefs.setStringList(key, List<String>.from(value));
          }
          count++;
        } catch (e) {
          Logger.w('写入 SharedPreferences 键 "$key" 失败: $e', tag: 'SettingsSync');
        }
      }
      Logger.i('SharedPreferences 已手动更新，共 $count 个键', tag: 'SettingsSync');
    } catch (e) {
      Logger.e('应用 SharedPreferences 失败: $e', tag: 'SettingsSync', error: e);
    }
  }

  Future<void> cleanupTempZip(String? zipPath) async {
    if (zipPath == null) return;
    try {
      final file = File(zipPath);
      if (await file.exists()) {
        await file.delete();
        Logger.i('已清理临时文件: $zipPath', tag: 'SettingsSync');
      }
    } catch (e) {
      Logger.w('清理临时文件失败: $e', tag: 'SettingsSync');
    }
  }

  Future<Map<String, dynamic>> getSettingsInfo() async {
    final configDir = await _configDir;
    final info = <String, dynamic>{};

    for (final fileName in _syncFiles) {
      final filePath = join(configDir, fileName);
      final file = File(filePath);

      if (await file.exists()) {
        final stat = await file.stat();
        info[fileName] = {
          'exists': true,
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
        };
      } else {
        info[fileName] = {'exists': false};
      }
    }

    return info;
  }
}
