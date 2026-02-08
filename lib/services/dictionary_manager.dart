import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/dictionary_metadata.dart';
import '../logger.dart';

class DictionaryManager {
  static final DictionaryManager _instance = DictionaryManager._internal();
  factory DictionaryManager() => _instance;
  DictionaryManager._internal();

  static const String _dictionariesDirKey = 'dictionaries_base_dir';
  static const String _onlineSubscriptionUrlKey = 'online_subscription_url';
  static const String _enabledDictionariesKey = 'enabled_dictionaries';
  static const String _metaFileName = 'metadata.json';
  static const String _dbFileName = 'dictionary.db';
  static const String _mediaDbFileName = 'media.db';
  static const String _imagesDirName = 'images';
  static const String _audiosDirName = 'audios';

  String? _baseDirectory;
  final Map<String, DictionaryMetadata> _metadataCache = {};

  Future<String> get baseDirectory async {
    if (_baseDirectory != null) return _baseDirectory!;

    final prefs = await SharedPreferences.getInstance();
    Logger.i('SharedPreferences 已加载', tag: 'DictionaryManager');
    String? savedDir = prefs.getString(_dictionariesDirKey);
    Logger.i(
      '词典目录配置: $_dictionariesDirKey = $savedDir',
      tag: 'DictionaryManager',
    );

    if (savedDir == null || !Directory(savedDir).existsSync()) {
      final defaultDir = await _getDefaultDirectory();
      savedDir = defaultDir;
      await setBaseDirectory(defaultDir);
    }

    _baseDirectory = savedDir;
    return _baseDirectory!;
  }

  Future<void> setBaseDirectory(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dictionariesDirKey, directory);
    Logger.i('保存词典目录: $directory', tag: 'DictionaryManager');
    _baseDirectory = directory;
    _metadataCache.clear();
  }

  Future<String> get onlineSubscriptionUrl async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_onlineSubscriptionUrlKey) ?? '';
  }

  Future<void> setOnlineSubscriptionUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_onlineSubscriptionUrlKey, url);
  }

  Future<List<String>> getEnabledDictionaries() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? enabled = prefs.getStringList(_enabledDictionariesKey);
    return enabled ?? [];
  }

  Future<void> setEnabledDictionaries(List<String> dictionaryIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledDictionariesKey, dictionaryIds);
  }

  Future<void> enableDictionary(String dictionaryId) async {
    final enabled = await getEnabledDictionaries();
    if (!enabled.contains(dictionaryId)) {
      enabled.add(dictionaryId);
      await setEnabledDictionaries(enabled);
    }
  }

  Future<void> disableDictionary(String dictionaryId) async {
    final enabled = await getEnabledDictionaries();
    enabled.remove(dictionaryId);
    await setEnabledDictionaries(enabled);
  }

  Future<void> reorderDictionaries(List<String> dictionaryIds) async {
    await setEnabledDictionaries(dictionaryIds);
  }

  Future<String> _getDefaultDirectory() async {
    if (kIsWeb) {
      return 'easydict';
    }

    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, 'easydict');
  }

  Future<String> getDictionaryDir(String dictionaryId) async {
    final base = await baseDirectory;
    return path.join(base, dictionaryId);
  }

  Future<String> getDictionaryDbPath(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    return path.join(dictDir, _dbFileName);
  }

  Future<String> getMediaDbPath(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    return path.join(dictDir, _mediaDbFileName);
  }

  Future<String> getImagesDir(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    final imagesDir = Directory(path.join(dictDir, _imagesDirName));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir.path;
  }

  Future<String> getAudiosDir(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    final audiosDir = Directory(path.join(dictDir, _audiosDirName));
    if (!await audiosDir.exists()) {
      await audiosDir.create(recursive: true);
    }
    return audiosDir.path;
  }

  Future<Uint8List?> readFromUncompressedZip(
    String zipPath,
    String fileName,
  ) async {
    try {
      if (kIsWeb) return null;

      final file = File(zipPath);
      if (!await file.exists()) return null;

      final raf = await file.open(mode: FileMode.read);
      try {
        final fileSize = await raf.length();

        // 1. 查找 EOCD (End of Central Directory Record)
        // 搜索文件末尾 1KB，通常足够找到 EOCD
        int searchSize = 1024;
        if (searchSize > fileSize) searchSize = fileSize;

        final startSearch = fileSize - searchSize;
        await raf.setPosition(startSearch);
        final tailBytes = await raf.read(searchSize);

        int eocdPos = -1;
        // 从后往前找签名 0x06054b50
        for (int i = tailBytes.length - 22; i >= 0; i--) {
          if (tailBytes[i] == 0x50 &&
              tailBytes[i + 1] == 0x4b &&
              tailBytes[i + 2] == 0x05 &&
              tailBytes[i + 3] == 0x06) {
            eocdPos = startSearch + i;
            break;
          }
        }

        if (eocdPos == -1) {
          return null;
        }

        // 2. 读取 Central Directory 信息
        // 跳过签名(4)+磁盘号(2)+起始磁盘号(2)+记录数(2)+总记录数(2) -> 偏移 12
        await raf.setPosition(eocdPos + 12);
        final cdInfo = await raf.read(8); // CD 大小(4) + CD 偏移(4)
        final cdInfoData = ByteData.view(cdInfo.buffer);
        final cdSize = cdInfoData.getUint32(0, Endian.little);
        final cdOffset = cdInfoData.getUint32(4, Endian.little);

        // 3. 一次性读取整个 Central Directory
        await raf.setPosition(cdOffset);
        final cdBytes = await raf.read(cdSize);
        final cdData = ByteData.view(cdBytes.buffer);

        // 4. 在内存中遍历查找
        int currentPos = 0;
        final targetName = fileName.replaceAll('\\', '/');
        final targetNameBytes = utf8.encode(targetName);

        while (currentPos < cdSize) {
          // 检查剩余长度是否足够读取头部
          if (currentPos + 46 > cdSize) break;

          // 检查签名 0x02014b50
          if (cdData.getUint32(currentPos, Endian.little) != 0x02014b50) break;

          final nameLen = cdData.getUint16(currentPos + 28, Endian.little);
          final extraLen = cdData.getUint16(currentPos + 30, Endian.little);
          final commentLen = cdData.getUint16(currentPos + 32, Endian.little);

          // 检查文件名长度匹配，先比较长度再比较内容，性能更高
          if (nameLen == targetNameBytes.length) {
            // 读取文件名
            final nameOffset = currentPos + 46;
            bool match = true;
            for (int i = 0; i < nameLen; i++) {
              if (cdBytes[nameOffset + i] != targetNameBytes[i]) {
                match = false;
                break;
              }
            }

            if (match) {
              final compressionMethod = cdData.getUint16(
                currentPos + 10,
                Endian.little,
              );
              final compressedSize = cdData.getUint32(
                currentPos + 20,
                Endian.little,
              );
              final localHeaderOffset = cdData.getUint32(
                currentPos + 42,
                Endian.little,
              );

              Logger.d(
                '找到文件: $targetName, 方法: $compressionMethod, 压缩大小: $compressedSize, 偏移: $localHeaderOffset',
                tag: 'DictionaryManager',
              );

              // 5. 找到目标文件，跳转到 Local File Header
              await raf.setPosition(localHeaderOffset);
              final localHeaderBytes = await raf.read(30);
              final localHeader = ByteData.view(localHeaderBytes.buffer);

              if (localHeader.getUint32(0, Endian.little) != 0x04034b50) {
                Logger.e('Local Header 签名错误', tag: 'DictionaryManager');
                return null;
              }

              final localNameLen = localHeader.getUint16(26, Endian.little);
              final localExtraLen = localHeader.getUint16(28, Endian.little);

              Logger.d(
                'Local Header: nameLen=$localNameLen, extraLen=$localExtraLen',
                tag: 'DictionaryManager',
              );

              // 6. 定位数据起始位置
              final dataStart =
                  localHeaderOffset + 30 + localNameLen + localExtraLen;
              await raf.setPosition(dataStart);

              // 7. 读取数据
              final data = await raf.read(compressedSize);
              Logger.d('读取数据长度: ${data.length}', tag: 'DictionaryManager');

              // 8. 处理数据
              if (compressionMethod == 0) {
                return Uint8List.fromList(data);
              } else if (compressionMethod == 8) {
                try {
                  final decoded = Inflate(data).getBytes();
                  return Uint8List.fromList(decoded);
                } catch (e) {
                  return null;
                }
              } else {
                Logger.e(
                  '不支持的压缩方法: $compressionMethod',
                  tag: 'DictionaryManager',
                );
                return null;
              }
            }
          }

          // 移动到下一个文件头
          currentPos += 46 + nameLen + extraLen + commentLen;
        }

        return null;
      } finally {
        await raf.close();
      }
    } catch (e) {
      Logger.e('读取 ZIP 失败: $e', tag: 'DictionaryManager', error: e);
      return null;
    }
  }

  Future<Uint8List?> getImageBytes(String dictionaryId, String fileName) async {
    final mediaDbPath = await getMediaDbPath(dictionaryId);
    final mediaDbFile = File(mediaDbPath);

    if (!await mediaDbFile.exists()) {
      return null;
    }

    return await _readBlobFromMediaDb(mediaDbPath, 'images', fileName);
  }

  Future<Uint8List?> getAudioBytes(String dictionaryId, String fileName) async {
    final mediaDbPath = await getMediaDbPath(dictionaryId);
    final mediaDbFile = File(mediaDbPath);

    if (!await mediaDbFile.exists()) {
      return null;
    }

    return _readBlobFromMediaDb(mediaDbPath, 'audios', fileName);
  }

  Future<Uint8List?> _readBlobFromMediaDb(
    String dbPath,
    String tableName,
    String fileName,
  ) async {
    try {
      final db = await openDatabase(dbPath);
      final result = await db.query(
        tableName,
        where: 'name = ?',
        whereArgs: [fileName],
      );
      await db.close();

      if (result.isNotEmpty) {
        return result.first['blob'] as Uint8List;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Uint8List?> extractAudioFromZip(
    Map<String, String> params,
  ) async {
    try {
      final zipPath = params['zipPath']!;
      final fileName = params['fileName']!;

      final file = File(zipPath);
      if (!await file.exists()) {
        Logger.d('zip文件不存在: $zipPath', tag: 'extractAudioFromZip');
        return null;
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        final fileSize = await raf.length();

        int eocdOffset = fileSize - 22;
        if (eocdOffset < 0) eocdOffset = 0;

        while (eocdOffset >= 0) {
          await raf.setPosition(eocdOffset);
          final bytes = await raf.read(4);
          if (bytes[0] == 0x50 &&
              bytes[1] == 0x4b &&
              bytes[2] == 0x05 &&
              bytes[3] == 0x06) {
            break;
          }
          eocdOffset--;
        }

        if (eocdOffset < 0) {
          Logger.d('未找到EOCD', tag: 'extractAudioFromZip');
          return null;
        }

        await raf.setPosition(eocdOffset);
        final eocd = await raf.read(22);
        final eocdData = ByteData.view(eocd.buffer);
        final centralDirOffset = eocdData.getUint32(16, Endian.little);
        final centralDirSize = eocdData.getUint32(12, Endian.little);

        await raf.setPosition(centralDirOffset);
        final centralDirData = await raf.read(centralDirSize);

        final targetName = fileName.replaceAll('\\', '/');

        Logger.d(
          '中央目录偏移: $centralDirOffset, 大小: $centralDirSize',
          tag: 'extractAudioFromZip',
        );

        int pos = 0;
        while (pos < centralDirSize) {
          if (centralDirData[pos] != 0x50 ||
              centralDirData[pos + 1] != 0x4b ||
              centralDirData[pos + 2] != 0x01 ||
              centralDirData[pos + 3] != 0x02) {
            break;
          }

          final headerData = ByteData.view(centralDirData.buffer, pos);
          final nameLen = headerData.getUint16(28, Endian.little);
          final extraLen = headerData.getUint16(30, Endian.little);
          final commentLen = headerData.getUint16(32, Endian.little);
          final compressedSize = headerData.getUint32(20, Endian.little);
          final localHeaderOffset = headerData.getUint32(42, Endian.little);

          final nameBytes = centralDirData.sublist(
            pos + 46,
            pos + 46 + nameLen,
          );
          final entryName = utf8.decode(nameBytes).replaceAll('\\', '/');

          if (entryName == targetName) {
            Logger.d('找到文件: $entryName', tag: 'extractAudioFromZip');

            await raf.setPosition(localHeaderOffset);
            final localHeader = await raf.read(30);
            final localHeaderData = ByteData.view(localHeader.buffer);

            if (localHeaderData.getUint32(0, Endian.little) != 0x04034b50) {
              return null;
            }

            final localNameLen = localHeaderData.getUint16(22, Endian.little);
            final localExtraLen = localHeaderData.getUint16(24, Endian.little);

            final dataOffset =
                localHeaderOffset + 30 + localNameLen + localExtraLen;

            Logger.d(
              '读取文件数据: 偏移=$dataOffset, 大小=$compressedSize',
              tag: 'extractAudioFromZip',
            );

            if (compressedSize > 0) {
              await raf.setPosition(dataOffset);
              final content = await raf.read(compressedSize);
              return Uint8List.fromList(content);
            }
            return Uint8List(0);
          }

          pos += 46 + nameLen + extraLen + commentLen;
        }

        return null;
      } finally {
        await raf.close();
      }
    } catch (e) {
      return null;
    }
  }

  Future<File> getMetadataFile(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    final file = File(path.join(dictDir, _metaFileName));
    return file;
  }

  Future<String?> getLogoPath(String dictionaryId) async {
    final dictDir = await getDictionaryDir(dictionaryId);
    final logoFile = File(path.join(dictDir, 'logo.png'));
    if (await logoFile.exists()) {
      return logoFile.path;
    }
    return null;
  }

  Future<DictionaryMetadata?> getDictionaryMetadata(String dictionaryId) async {
    if (_metadataCache.containsKey(dictionaryId)) {
      return _metadataCache[dictionaryId];
    }

    try {
      final file = await getMetadataFile(dictionaryId);
      if (!await file.exists()) {
        return null;
      }

      final jsonStr = await file.readAsString();
      final metadata = DictionaryMetadata.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonStr) as Map<String, dynamic>),
      );

      _metadataCache[dictionaryId] = metadata;
      return metadata;
    } catch (e) {
      Logger.e('读取词典元数据失败: $e', tag: 'DictionaryManager');
      return null;
    }
  }

  Future<void> saveDictionaryMetadata(DictionaryMetadata metadata) async {
    try {
      final file = await getMetadataFile(metadata.id);
      final jsonStr = jsonEncode(metadata.toJson());
      await file.writeAsString(jsonStr);

      _metadataCache[metadata.id] = metadata;

      Logger.d('保存词典元数据成功: ${metadata.id}', tag: 'DictionaryManager');
    } catch (e) {
      Logger.e('保存词典元数据失败: $e', tag: 'DictionaryManager');
      rethrow;
    }
  }

  Future<List<String>> getInstalledDictionaries() async {
    try {
      final base = await baseDirectory;
      final dir = Directory(base);

      if (!await dir.exists()) {
        return [];
      }

      final entities = await dir.list().toList();
      final dictionaries = <String>[];

      for (final entity in entities) {
        if (entity is Directory) {
          final metadata = await getDictionaryMetadata(
            path.basename(entity.path),
          );
          if (metadata != null) {
            dictionaries.add(metadata.id);
          }
        }
      }

      return dictionaries;
    } catch (e) {
      Logger.e('获取已安装词典列表失败: $e', tag: 'DictionaryManager');
      return [];
    }
  }

  Future<List<DictionaryMetadata>> getAllDictionariesMetadata() async {
    final ids = await getInstalledDictionaries();
    final metadatas = <DictionaryMetadata>[];

    for (final id in ids) {
      final metadata = await getDictionaryMetadata(id);
      if (metadata != null) {
        metadatas.add(metadata);
      }
    }

    return metadatas;
  }

  Future<List<DictionaryMetadata>> getEnabledDictionariesMetadata() async {
    final enabledIds = await getEnabledDictionaries();
    final metadatas = <DictionaryMetadata>[];

    for (final id in enabledIds) {
      final metadata = await getDictionaryMetadata(id);
      if (metadata != null) {
        final dbPath = await getDictionaryDbPath(id);
        if (await File(dbPath).exists()) {
          metadatas.add(metadata);
        }
      }
    }

    return metadatas;
  }

  Future<bool> dictionaryExists(String dictionaryId) async {
    final dbPath = await getDictionaryDbPath(dictionaryId);
    return File(dbPath).exists();
  }

  Future<Database> openDictionaryDatabase(String dictionaryId) async {
    final dbPath = await getDictionaryDbPath(dictionaryId);

    if (!await File(dbPath).exists()) {
      throw Exception('词典数据库不存在: $dictionaryId');
    }

    return openDatabase(dbPath, readOnly: true);
  }

  Future<List<String>> getDictionaryEntries(
    String dictionaryId, {
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final db = await openDictionaryDatabase(dictionaryId);

      try {
        final results = await db.query(
          'entries',
          columns: ['headword'],
          orderBy: 'headword ASC',
          offset: offset,
          limit: limit,
        );

        return results
            .map((row) => row['headword'] as String?)
            .where((word) => word != null && word.isNotEmpty)
            .cast<String>()
            .toList();
      } finally {
        await db.close();
      }
    } catch (e) {
      Logger.e('获取词典词条失败: $e', tag: 'DictionaryManager', error: e);
      return [];
    }
  }

  Future<int> getDictionaryEntryCount(String dictionaryId) async {
    try {
      final db = await openDictionaryDatabase(dictionaryId);

      try {
        final results = await db.query(
          'entries',
          columns: ['COUNT(*) as count'],
        );
        return Sqflite.firstIntValue(results) ?? 0;
      } finally {
        await db.close();
      }
    } catch (e) {
      return 0;
    }
  }

  Future<void> deleteDictionary(String dictionaryId) async {
    try {
      final dictDir = await getDictionaryDir(dictionaryId);
      final dir = Directory(dictDir);

      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _metadataCache.remove(dictionaryId);
        Logger.d('删除词典成功: $dictionaryId', tag: 'DictionaryManager');
      }
    } catch (e) {
      Logger.e('删除词典失败: $e', tag: 'DictionaryManager');
      rethrow;
    }
  }

  Future<void> createDictionaryStructure(
    String dictionaryId,
    DictionaryMetadata metadata,
  ) async {
    try {
      final dictDir = await getDictionaryDir(dictionaryId);
      final dir = Directory(dictDir);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await saveDictionaryMetadata(metadata);

      Logger.d('创建词典目录结构成功: $dictionaryId', tag: 'DictionaryManager');
    } catch (e) {
      Logger.e('创建词典目录结构失败: $e', tag: 'DictionaryManager');
      rethrow;
    }
  }

  /// 获取临时目录
  Future<String> getTempDirectory() async {
    final base = await baseDirectory;
    final tempDir = Directory(path.join(base, '.temp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir.path;
  }

  /// 获取词典目录
  Future<String> getDictionaryDirectory(String dictionaryId) async {
    final base = await baseDirectory;
    final dictDir = Directory(path.join(base, dictionaryId));
    if (!await dictDir.exists()) {
      await dictDir.create(recursive: true);
    }
    return dictDir.path;
  }

  /// 获取所有可用词典 ID
  Future<List<String>> getAvailableDictionaries() async {
    try {
      final base = await baseDirectory;
      final dir = Directory(base);

      if (!await dir.exists()) {
        return [];
      }

      final entities = await dir.list().toList();
      final dictionaries = <String>[];

      for (final entity in entities) {
        if (entity is Directory &&
            !path.basename(entity.path).startsWith('.')) {
          final metadata = await getDictionaryMetadata(
            path.basename(entity.path),
          );
          if (metadata != null) {
            dictionaries.add(metadata.id);
          }
        }
      }

      return dictionaries;
    } catch (e) {
      Logger.e('获取可用词典列表失败: $e', tag: 'DictionaryManager');
      return [];
    }
  }

  Future<String> getCachedImagePath(
    String dictionaryId,
    String imageName,
  ) async {
    final imagesDir = await getImagesDir(dictionaryId);
    return path.join(imagesDir, imageName);
  }

  Future<String> getCachedAudioPath(
    String dictionaryId,
    String audioName,
  ) async {
    final audiosDir = await getAudiosDir(dictionaryId);
    return path.join(audiosDir, audioName);
  }

  Future<bool> cacheResourceFile(
    String dictionaryId,
    String resourceType,
    String fileName,
    List<int> data,
  ) async {
    try {
      String targetPath;
      switch (resourceType.toLowerCase()) {
        case 'image':
          targetPath = await getCachedImagePath(dictionaryId, fileName);
          break;
        case 'audio':
          targetPath = await getCachedAudioPath(dictionaryId, fileName);
          break;
        default:
          return false;
      }

      final file = File(targetPath);
      await file.writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取词典统计信息
  Future<DictionaryStats> getDictionaryStats(String dictionaryId) async {
    int entryCount = 0;
    int audioCount = 0;
    int imageCount = 0;

    try {
      // 获取词条数
      final dbPath = await getDictionaryDbPath(dictionaryId);
      if (await File(dbPath).exists()) {
        final db = await openDatabase(dbPath, readOnly: true);
        try {
          final result = await db.rawQuery(
            'SELECT COUNT(*) as count FROM entries',
          );
          entryCount = Sqflite.firstIntValue(result) ?? 0;
        } catch (e) {
          Logger.w('查询词条数失败: $e', tag: 'DictionaryManager');
        }
        await db.close();
      }

      // 从 media.db 获取音频和图片数量
      final dictDir = await getDictionaryDir(dictionaryId);
      final mediaDbPath = path.join(dictDir, 'media.db');
      final mediaDbFile = File(mediaDbPath);

      if (await mediaDbFile.exists()) {
        final db = await openDatabase(mediaDbPath, readOnly: true);
        try {
          // 获取音频数量
          try {
            final audioResult = await db.rawQuery(
              'SELECT COUNT(*) as count FROM audios',
            );
            audioCount = Sqflite.firstIntValue(audioResult) ?? 0;
          } catch (e) {
            Logger.w('查询音频数失败: $e', tag: 'DictionaryManager');
          }

          // 获取图片数量
          try {
            final imageResult = await db.rawQuery(
              'SELECT COUNT(*) as count FROM images',
            );
            imageCount = Sqflite.firstIntValue(imageResult) ?? 0;
          } catch (e) {
            Logger.w('查询图片数失败: $e', tag: 'DictionaryManager');
          }
        } finally {
          await db.close();
        }
      }
    } catch (e) {
      Logger.e('获取词典统计信息失败: $e', tag: 'DictionaryManager');
    }

    return DictionaryStats(
      entryCount: entryCount,
      audioCount: audioCount,
      imageCount: imageCount,
    );
  }

  /// 获取 zip 文件中的文件数量
  Future<int> _getZipFileCount(String zipPath) async {
    try {
      final file = File(zipPath);
      if (!await file.exists()) return 0;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.where((entry) => entry.isFile).length;
    } catch (e) {
      Logger.e('获取 zip 文件数量失败: $e', tag: 'DictionaryManager');
      return 0;
    }
  }

  /// 检查是否存在 metadata.json
  Future<bool> hasMetadataFile(String dictionaryId) async {
    try {
      final file = await getMetadataFile(dictionaryId);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// 检查是否存在 logo.png
  Future<bool> hasLogoFile(String dictionaryId) async {
    try {
      final logoPath = await getLogoPath(dictionaryId);
      return logoPath != null;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否存在 dictionary.db
  Future<bool> hasDatabaseFile(String dictionaryId) async {
    try {
      final dbPath = await getDictionaryDbPath(dictionaryId);
      return await File(dbPath).exists();
    } catch (e) {
      return false;
    }
  }

  /// 检查是否存在 audios.zip
  Future<bool> hasAudiosZip(String dictionaryId) async {
    try {
      final mediaDbPath = await getMediaDbPath(dictionaryId);
      final mediaDbFile = File(mediaDbPath);
      return await mediaDbFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// 检查是否存在 images.zip
  Future<bool> hasImagesZip(String dictionaryId) async {
    try {
      final mediaDbPath = await getMediaDbPath(dictionaryId);
      final mediaDbFile = File(mediaDbPath);
      return await mediaDbFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// 检查媒体数据库是否存在
  Future<bool> hasMediaDb(String dictionaryId) async {
    try {
      final mediaDbPath = await getMediaDbPath(dictionaryId);
      final mediaDbFile = File(mediaDbPath);
      return await mediaDbFile.exists();
    } catch (e) {
      return false;
    }
  }
}

/// 词典统计信息
class DictionaryStats {
  final int entryCount;
  final int audioCount;
  final int imageCount;

  DictionaryStats({
    required this.entryCount,
    required this.audioCount,
    required this.imageCount,
  });
}
