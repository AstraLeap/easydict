import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'dictionary_manager.dart';
import '../models/dictionary_metadata.dart';
import '../logger.dart';
import 'database_initializer.dart';

class DataMigrationService {
  final DictionaryManager _dictManager = DictionaryManager();

  Future<bool> needsMigration() async {
    final oldPath = path.join(
      Directory.current.path,
      'assets',
      'easydict',
      'dictionary.db',
    );

    return File(oldPath).exists();
  }

  Future<void> migrateToNewStructure() async {
    try {
      Logger.d('开始数据迁移...', tag: 'DataMigration');

      final oldPath = path.join(
        Directory.current.path,
        'assets',
        'easydict',
        'dictionary.db',
      );

      final oldFile = File(oldPath);
      if (!await oldFile.exists()) {
        Logger.d('未找到旧数据库文件，无需迁移', tag: 'DataMigration');
        return;
      }

      await _getWordCount(oldPath);

      final metadata = DictionaryMetadata(
        id: 'default',
        name: '默认词典',
        version: '1.0.0',
        description: '从旧版本迁移的词典',
        sourceLanguage: 'en',
        targetLanguages: ['zh'],
        publisher: '',
        maintainer: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _dictManager.createDictionaryStructure(metadata.id, metadata);

      final newPath = await _dictManager.getDictionaryDbPath(metadata.id);
      await oldFile.copy(newPath);

      final backupPath = '$oldPath.backup';
      await oldFile.rename(backupPath);

      Logger.d('数据迁移完成！', tag: 'DataMigration');
      Logger.d('新位置: $newPath', tag: 'DataMigration');
      Logger.d('备份位置: $backupPath', tag: 'DataMigration');
    } catch (e) {
      Logger.e('数据迁移失败: $e', tag: 'DataMigration');
      rethrow;
    }
  }

  Future<int> _getWordCount(String dbPath) async {
    try {
      if (kIsWeb) {
        return 0;
      }

      // 使用统一的数据库初始化器
      DatabaseInitializer().initialize();

      Logger.d(
        '_getWordCount: 打开数据库 (readOnly=true): $dbPath',
        tag: 'DataMigration',
      );

      final db = await openDatabase(dbPath, readOnly: true);
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM entries');
      await db.close();

      return result.first['count'] as int? ?? 0;
    } catch (e) {
      Logger.e('获取词条数量失败: $e', tag: 'DataMigration');
      return 0;
    }
  }

  Future<MigrationSummary> checkMigrationStatus() async {
    final oldPath = path.join(
      Directory.current.path,
      'assets',
      'easydict',
      'dictionary.db',
    );

    final oldFile = File(oldPath);
    final oldExists = await oldFile.exists();

    final installedDicts = await _dictManager.getInstalledDictionaries();
    final hasDefaultDict = installedDicts.contains('default');

    return MigrationSummary(
      oldDatabaseExists: oldExists,
      defaultDictionaryInstalled: hasDefaultDict,
      needsMigration: oldExists && !hasDefaultDict,
    );
  }

  Future<void> cleanupOldFiles() async {
    try {
      final oldDir = Directory(
        path.join(Directory.current.path, 'assets', 'easydict'),
      );

      if (await oldDir.exists()) {
        await oldDir.delete(recursive: true);
      }
    } catch (e) {
      // Error handling without debug output
    }
  }
}

class MigrationSummary {
  final bool oldDatabaseExists;
  final bool defaultDictionaryInstalled;
  final bool needsMigration;

  MigrationSummary({
    required this.oldDatabaseExists,
    required this.defaultDictionaryInstalled,
    required this.needsMigration,
  });

  String get message {
    if (!oldDatabaseExists) {
      return '未检测到旧版数据库';
    }
    if (defaultDictionaryInstalled) {
      return '已完成迁移';
    }
    if (needsMigration) {
      return '检测到旧版数据，建议迁移';
    }
    return '无需迁移';
  }
}
