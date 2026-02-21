import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
          final bytes = await file.readAsBytes();
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
