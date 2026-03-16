import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../data/models/remote_dictionary.dart';
import 'dictionary_manager.dart';
import 'dictionary_store_service.dart';
import '../core/logger.dart';
import '../i18n/strings.g.dart';

class DownloadOptionsResult {
  final bool includeMetadata;
  final bool includeLogo;
  final bool includeDb;
  final bool includeMedia;

  DownloadOptionsResult({
    this.includeMetadata = true,
    this.includeLogo = true,
    required this.includeDb,
    required this.includeMedia,
  });
}

enum DownloadState { idle, downloading, completed, error, cancelled, paused }

/// 单个文件的下载进度信息
class FileDownloadProgress {
  final String fileName;
  final int downloadedBytes;
  final int totalBytes;
  final bool isCompleted;

  FileDownloadProgress({
    required this.fileName,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.isCompleted = false,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'isCompleted': isCompleted,
  };

  factory FileDownloadProgress.fromJson(Map<String, dynamic> json) =>
      FileDownloadProgress(
        fileName: json['fileName'] as String,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        totalBytes: json['totalBytes'] as int? ?? 0,
        isCompleted: json['isCompleted'] as bool? ?? false,
      );

  FileDownloadProgress copyWith({
    String? fileName,
    int? downloadedBytes,
    int? totalBytes,
    bool? isCompleted,
  }) {
    return FileDownloadProgress(
      fileName: fileName ?? this.fileName,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class DownloadTask {
  final String dictId;
  final String dictName;
  final DateTime startTime;
  DownloadState state;
  String? currentFileName;
  int fileIndex;
  int totalFiles;
  int receivedBytes;
  int totalBytes;
  double fileProgress;
  double overallProgress;
  String status;
  String? error;
  int speedBytesPerSecond;
  DateTime? lastSpeedUpdate;
  Future<void> Function()? onComplete;
  void Function(String error)? onError;

  /// 断点续传：记录每个文件的下载进度
  final Map<String, FileDownloadProgress> fileProgresses;

  /// 下载选项（用于断点续传时恢复）
  DownloadOptionsResult? downloadOptions;

  /// 远程词典信息（用于断点续传时恢复）
  Map<String, dynamic>? remoteDictJson;

  /// 更新任务相关字段
  /// 是否是更新任务
  bool isUpdate;

  /// 需要更新的文件列表
  List<String> updateFiles;

  /// 需要更新的条目 ID 列表
  List<int> updateEntryIds;

  /// 更新到的版本号
  int? updateToVersion;

  /// 元数据 JSON（用于更新完成后保存）
  Map<String, dynamic>? metadataJson;

  DownloadTask({
    required this.dictId,
    required this.dictName,
    required this.startTime,
    this.state = DownloadState.idle,
    this.currentFileName,
    this.fileIndex = 0,
    this.totalFiles = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fileProgress = 0.0,
    this.overallProgress = 0.0,
    this.status = '\u51c6\u5907\u4e0b\u8f7d...',
    this.error,
    this.speedBytesPerSecond = 0,
    this.onComplete,
    this.onError,
    Map<String, FileDownloadProgress>? fileProgresses,
    this.downloadOptions,
    this.remoteDictJson,
    this.isUpdate = false,
    List<String>? updateFiles,
    List<int>? updateEntryIds,
    this.updateToVersion,
    this.metadataJson,
  }) : fileProgresses = fileProgresses ?? {},
       updateFiles = updateFiles ?? [],
       updateEntryIds = updateEntryIds ?? [];

  Map<String, dynamic> toJson() => {
    'dictId': dictId,
    'dictName': dictName,
    'startTime': startTime.toIso8601String(),
    'state': state.index,
    'currentFileName': currentFileName,
    'fileIndex': fileIndex,
    'totalFiles': totalFiles,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'fileProgress': fileProgress,
    'overallProgress': overallProgress,
    'status': status,
    'error': error,
    'speedBytesPerSecond': speedBytesPerSecond,
    'fileProgresses': fileProgresses.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'downloadOptions': downloadOptions != null
        ? {
            'includeMetadata': downloadOptions!.includeMetadata,
            'includeLogo': downloadOptions!.includeLogo,
            'includeDb': downloadOptions!.includeDb,
            'includeMedia': downloadOptions!.includeMedia,
          }
        : null,
    'remoteDictJson': remoteDictJson,
    'isUpdate': isUpdate,
    'updateFiles': updateFiles,
    'updateEntryIds': updateEntryIds,
    'updateToVersion': updateToVersion,
    'metadataJson': metadataJson,
  };

  static DownloadTask fromJson(Map<String, dynamic> json) {
    final fileProgressesMap = <String, FileDownloadProgress>{};
    final fileProgressesJson = json['fileProgresses'] as Map<String, dynamic>?;
    if (fileProgressesJson != null) {
      fileProgressesJson.forEach((key, value) {
        fileProgressesMap[key] = FileDownloadProgress.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
      });
    }

    DownloadOptionsResult? downloadOptions;
    final optionsJson = json['downloadOptions'] as Map<String, dynamic>?;
    if (optionsJson != null) {
      downloadOptions = DownloadOptionsResult(
        includeMetadata: optionsJson['includeMetadata'] as bool? ?? true,
        includeLogo: optionsJson['includeLogo'] as bool? ?? true,
        includeDb: optionsJson['includeDb'] as bool? ?? false,
        includeMedia: optionsJson['includeMedia'] as bool? ?? false,
      );
    }

    return DownloadTask(
      dictId: json['dictId'] as String,
      dictName: json['dictName'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      state: DownloadState.values[json['state'] as int],
      currentFileName: json['currentFileName'] as String?,
      fileIndex: json['fileIndex'] as int? ?? 0,
      totalFiles: json['totalFiles'] as int? ?? 0,
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      fileProgress: (json['fileProgress'] as num?)?.toDouble() ?? 0.0,
      overallProgress: (json['overallProgress'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? t.dict.statusPreparing,
      error: json['error'] as String?,
      speedBytesPerSecond: json['speedBytesPerSecond'] as int? ?? 0,
      fileProgresses: fileProgressesMap,
      downloadOptions: downloadOptions,
      remoteDictJson: json['remoteDictJson'] as Map<String, dynamic>?,
      isUpdate: json['isUpdate'] as bool? ?? false,
      updateFiles:
          (json['updateFiles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      updateEntryIds:
          (json['updateEntryIds'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      updateToVersion: json['updateToVersion'] as int?,
      metadataJson: json['metadataJson'] as Map<String, dynamic>?,
    );
  }

  /// 获取指定文件的已下载字节数
  int getFileDownloadedBytes(String fileName) {
    return fileProgresses[fileName]?.downloadedBytes ?? 0;
  }

  /// 更新文件下载进度
  void updateFileProgress(
    String fileName, {
    int? downloadedBytes,
    int? totalBytes,
    bool? isCompleted,
  }) {
    final existing =
        fileProgresses[fileName] ?? FileDownloadProgress(fileName: fileName);
    fileProgresses[fileName] = existing.copyWith(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      isCompleted: isCompleted,
    );
  }

  /// 标记文件下载完成
  void markFileCompleted(String fileName) {
    updateFileProgress(fileName, isCompleted: true);
  }
}

/// 未完成下载文件的信息
class _IncompleteFileInfo {
  final String tempFilePath;
  final String originalFileName;
  final int downloadedBytes;

  _IncompleteFileInfo({
    required this.tempFilePath,
    required this.originalFileName,
    required this.downloadedBytes,
  });
}

class DownloadManager with ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal() {
    _initCompleter = Completer<void>();
    _initialize()
        .then((_) {
          _initCompleter!.complete();
        })
        .catchError((e) {
          Logger.e('初始化失败: $e', tag: 'DownloadManager');
          _initCompleter!.complete();
        });
  }

  /// 初始化完成的 Future，用于确保初始化完成后再执行恢复操作
  Completer<void>? _initCompleter;

  /// 等待初始化完成
  Future<void> get initialized => _initCompleter?.future ?? Future.value();

  DictionaryStoreService? _storeService;
  final Map<String, DownloadTask> _downloads = {};
  String? _currentDownloadId;
  DateTime _lastNotifyTime = DateTime.now();
  DateTime _lastSaveTime = DateTime.now();
  static const _minNotifyInterval = Duration(milliseconds: 100);
  static const _minSaveInterval = Duration(seconds: 2);

  void _notifyIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastNotifyTime) >= _minNotifyInterval) {
      notifyListeners();
      _lastNotifyTime = now;
    }
  }

  // 不再需要保存到 SharedPreferences
  // 断点续传改为扫描词典文件夹检测 .downloading 文件
  void _saveDownloads() {
    // 空方法，保留以兼容现有代码
  }

  Future<void> _saveDownloadsAsync() async {
    // 空方法，保留以兼容现有代码
  }
  Future<void> _initialize() async {
    // 不再从 SharedPreferences 加载任务
    // 断点续传改为扫描词典文件夹检测 .downloading 文件
    Logger.i('DownloadManager 初始化完成', tag: 'DownloadManager');
  }

  /// 自动恢复所有未完成的下载任务
  ///
  /// 通过扫描词典文件夹检测 .downloading 文件来发现未完成的下载任务
  Future<void> resumeAllDownloads() async {
    // 确保初始化完成
    await initialized;

    if (_storeService == null) {
      Logger.w('StoreService 未配置，无法恢复下载', tag: 'DownloadManager');
      return;
    }

    // 扫描词典文件夹，检测 .downloading 文件
    final incompleteDownloads = await _scanIncompleteDownloads();

    if (incompleteDownloads.isEmpty) {
      Logger.i('没有需要恢复的下载任务', tag: 'DownloadManager');
      return;
    }

    Logger.i(
      '发现 ${incompleteDownloads.length} 个未完成的下载任务',
      tag: 'DownloadManager',
    );

    for (final entry in incompleteDownloads.entries) {
      if (_currentDownloadId != null) {
        Logger.w('已有下载任务进行中，跳过恢复: ${entry.key}', tag: 'DownloadManager');
        continue;
      }

      try {
        await _resumeDownloadFromFiles(entry.key, entry.value);
      } catch (e) {
        Logger.e('恢复下载任务失败: ${entry.key}, $e', tag: 'DownloadManager');
      }
    }
  }

  /// 扫描词典文件夹，检测未完成的下载任务
  ///
  /// 返回 Map<词典ID, 未完成文件列表>
  Future<Map<String, List<_IncompleteFileInfo>>>
  _scanIncompleteDownloads() async {
    final result = <String, List<_IncompleteFileInfo>>{};

    try {
      final dictManager = DictionaryManager();
      final baseDir = await dictManager.baseDirectory;
      final baseDirObj = Directory(baseDir);

      if (!await baseDirObj.exists()) {
        Logger.d('词典目录不存在: $baseDir', tag: 'DownloadManager');
        return result;
      }

      // 遍历词典文件夹
      await for (final entity in baseDirObj.list()) {
        if (entity is! Directory) continue;

        final dictId = path.basename(entity.path);
        final downloadingFiles = <_IncompleteFileInfo>[];

        // 检查该词典文件夹中的 .downloading 文件
        await for (final file in entity.list()) {
          if (file is! File) continue;

          final fileName = path.basename(file.path);
          if (fileName.endsWith('.downloading')) {
            // 找到未完成的下载文件
            final originalFileName = fileName.substring(
              0,
              fileName.length - '.downloading'.length,
            );
            final tempFileSize = await file.length();

            downloadingFiles.add(
              _IncompleteFileInfo(
                tempFilePath: file.path,
                originalFileName: originalFileName,
                downloadedBytes: tempFileSize,
              ),
            );

            Logger.d(
              '发现未完成下载: $dictId/$originalFileName, 已下载 $tempFileSize 字节',
              tag: 'DownloadManager',
            );
          }
        }

        if (downloadingFiles.isNotEmpty) {
          result[dictId] = downloadingFiles;
        }
      }
    } catch (e) {
      Logger.e('扫描未完成下载失败: $e', tag: 'DownloadManager');
    }

    return result;
  }

  /// 从文件恢复下载
  Future<void> _resumeDownloadFromFiles(
    String dictId,
    List<_IncompleteFileInfo> incompleteFiles,
  ) async {
    if (_storeService == null) {
      Logger.w('StoreService 未配置，无法恢复下载', tag: 'DownloadManager');
      return;
    }

    Logger.i('恢复下载: $dictId', tag: 'DownloadManager');

    // 获取词典目录
    final dictDir = await _getDictionaryDir(dictId);
    if (dictDir == null) {
      Logger.w('无法获取词典目录: $dictId', tag: 'DownloadManager');
      return;
    }

    // 创建下载任务
    final task = DownloadTask(
      dictId: dictId,
      dictName: dictId, // 暂时使用 ID 作为名称
      startTime: DateTime.now(),
      state: DownloadState.downloading,
      status: t.dict.statusResuming,
      totalFiles: incompleteFiles.length,
    );

    _downloads[dictId] = task;
    _currentDownloadId = dictId;
    notifyListeners();

    final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
      if (task.state == DownloadState.downloading) {
        notifyListeners();
      }
    });

    try {
      var currentStep = 0;

      for (final fileInfo in incompleteFiles) {
        currentStep++;
        task.currentFileName = fileInfo.originalFileName;
        task.fileIndex = currentStep;
        task.status = t.dict.downloading(
          step: currentStep,
          total: incompleteFiles.length,
          name: fileInfo.originalFileName,
        );
        notifyListeners();

        final savePath = path.join(dictDir, fileInfo.originalFileName);

        bool downloadOk = false;
        await for (final event in _storeService!.downloadDictFileStream(
          dictId,
          fileInfo.originalFileName,
          savePath,
          startBytes: fileInfo.downloadedBytes,
        )) {
          if (event['type'] == 'progress') {
            task.receivedBytes = (event['receivedBytes'] as num).toInt();
            task.totalBytes = (event['totalBytes'] as num).toInt();
            task.fileProgress = (event['progress'] as num).toDouble();
            task.speedBytesPerSecond = (event['speedBytesPerSecond'] as num)
                .toInt();
            task.overallProgress = incompleteFiles.isNotEmpty
                ? (currentStep - 1 + task.fileProgress) / incompleteFiles.length
                : 0.0;

            _notifyIfNeeded();
          } else if (event['type'] == 'complete') {
            downloadOk = true;
          } else if (event['type'] == 'error') {
            throw Exception('${event['error']}');
          }
        }

        if (!downloadOk) {
          throw Exception('下载文件失败: ${fileInfo.originalFileName}');
        }
      }

      progressTimer.cancel();
      task.state = DownloadState.completed;
      task.status = t.dict.statusCompleted;
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      task.currentFileName = null;
      notifyListeners();
      Logger.i('下载恢复完成: $dictId', tag: 'DownloadManager');
    } catch (e) {
      Logger.e('恢复下载失败: $dictId, $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusFailed;
      task.error = e.toString();
      notifyListeners();
    } finally {
      progressTimer.cancel();
      _currentDownloadId = null;
    }
  }

  /// 恢复更新任务
  Future<void> _resumeUpdate(DownloadTask task) async {
    if (_storeService == null) {
      Logger.w('StoreService 未配置，无法恢复更新', tag: 'DownloadManager');
      return;
    }

    Logger.i('恢复更新任务: ${task.dictId}', tag: 'DownloadManager');

    task.state = DownloadState.downloading;
    task.status = t.dict.statusResuming;
    _currentDownloadId = task.dictId;
    notifyListeners();

    final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
      if (task.state == DownloadState.downloading) {
        notifyListeners();
      }
    });

    try {
      // 获取词典目录
      final dictDir = await _getDictionaryDir(task.dictId);
      if (dictDir == null) {
        throw Exception('无法获取词典目录');
      }

      // 计算总步骤数
      final totalSteps =
          task.updateFiles.length + (task.updateEntryIds.isNotEmpty ? 1 : 0);
      var currentStep = 0;

      // 下载文件
      for (final fileName in task.updateFiles) {
        // 检查文件是否已下载完成
        final fileProgress = task.fileProgresses[fileName];
        if (fileProgress != null && fileProgress.isCompleted) {
          currentStep++;
          continue;
        }

        currentStep++;
        task.currentFileName = fileName;
        task.fileIndex = currentStep;
        task.totalFiles = totalSteps;
        task.status = t.dict.downloading(
          step: currentStep,
          total: totalSteps,
          name: fileName,
        );
        notifyListeners();

        final savePath = path.join(dictDir, fileName);

        // 检查临时文件大小，用于断点续传
        int startBytes = task.getFileDownloadedBytes(fileName);
        final tempFile = File('$savePath.downloading');
        if (await tempFile.exists()) {
          final tempSize = await tempFile.length();
          if (tempSize > startBytes) {
            Logger.i(
              '发现临时文件大小($tempSize)大于记录的进度($startBytes)，使用临时文件大小',
              tag: 'DownloadManager',
            );
            startBytes = tempSize;
            task.updateFileProgress(fileName, downloadedBytes: startBytes);
          }
        }

        bool downloadOk = false;
        await for (final event in _storeService!.downloadDictFileStream(
          task.dictId,
          fileName,
          savePath,
          startBytes: startBytes,
        )) {
          if (event['type'] == 'progress') {
            task.receivedBytes = (event['receivedBytes'] as num).toInt();
            task.totalBytes = (event['totalBytes'] as num).toInt();
            task.fileProgress = (event['progress'] as num).toDouble();
            task.speedBytesPerSecond = (event['speedBytesPerSecond'] as num)
                .toInt();
            task.overallProgress = totalSteps > 0
                ? (currentStep - 1 + task.fileProgress) / totalSteps
                : 0.0;

            task.updateFileProgress(
              fileName,
              downloadedBytes: task.receivedBytes,
              totalBytes: task.totalBytes,
            );

            _notifyIfNeeded();
            _saveDownloads();
          } else if (event['type'] == 'complete') {
            downloadOk = true;
            task.markFileCompleted(fileName);
            _saveDownloads();
          } else if (event['type'] == 'error') {
            throw Exception('${event['error']}');
          }
        }

        if (!downloadOk) {
          throw Exception('下载文件失败: $fileName');
        }
      }

      // 下载条目更新（如果有）
      if (task.updateEntryIds.isNotEmpty) {
        currentStep++;
        task.currentFileName = null;
        task.fileIndex = currentStep;
        task.status = t.dict.downloadingEntries(
          step: currentStep,
          total: totalSteps,
        );
        notifyListeners();

        // 这里需要 UserDictionariesService 来下载条目更新
        // 由于恢复时可能没有这个服务，我们暂时跳过条目更新
        Logger.w('恢复更新任务时跳过条目更新，需要重新检查更新', tag: 'DownloadManager');
      }

      progressTimer.cancel();
      task.state = DownloadState.completed;
      task.status = t.dict.statusUpdateCompleted;
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      await _saveDownloadsAsync();
      await task.onComplete?.call();

      Logger.i('更新任务恢复完成: ${task.dictId}', tag: 'DownloadManager');
    } catch (e) {
      Logger.e('恢复更新任务失败: ${task.dictId}, $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusUpdateFailed;
      task.error = e.toString();
      notifyListeners();
      await _saveDownloadsAsync();
      task.onError?.call(e.toString());
    } finally {
      progressTimer.cancel();
      _currentDownloadId = null;
    }
  }

  /// 获取词典目录
  Future<String?> _getDictionaryDir(String dictId) async {
    try {
      // 使用 DictionaryManager 获取正确的词典目录
      final dictManager = DictionaryManager();
      return await dictManager.getDictionaryDir(dictId);
    } catch (e) {
      Logger.e('获取词典目录失败: $e', tag: 'DownloadManager');
      return null;
    }
  }

  void setStoreService(DictionaryStoreService service) {
    _storeService = service;
  }

  List<DownloadTask> getAllDownloads() {
    return _downloads.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  DownloadTask? getDownload(String dictId) => _downloads[dictId];

  DownloadTask? get currentDownload =>
      _currentDownloadId != null ? _downloads[_currentDownloadId] : null;

  bool get isDownloading => _currentDownloadId != null;

  Future<void> startDownload(
    RemoteDictionary dict,
    DownloadOptionsResult options, {
    Future<void> Function()? onComplete,
    void Function(String error)? onError,
    bool isResume = false,
  }) async {
    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中: $_currentDownloadId', tag: 'DownloadManager');
      return;
    }

    if (_downloads.containsKey(dict.id) && !isResume) {
      final existingTask = _downloads[dict.id];
      if (existingTask?.state == DownloadState.downloading) {
        Logger.w('该词典正在下载中: ${dict.id}', tag: 'DownloadManager');
        return;
      }
    }

    final task = DownloadTask(
      dictId: dict.id,
      dictName: dict.name,
      startTime: DateTime.now(),
      state: DownloadState.downloading,
      status: t.dict.statusPreparing,
      onComplete: onComplete,
      onError: onError,
      downloadOptions: options,
      remoteDictJson: dict.toJson(),
    );
    _downloads[dict.id] = task;
    _currentDownloadId = dict.id;
    notifyListeners();
    // 立即保存任务，不使用节流
    await _saveDownloadsAsync();

    await _runDownload(task, dict, options);
  }

  /// 恢复下载任务
  Future<void> _resumeDownload(
    DownloadTask task,
    RemoteDictionary dict,
    DownloadOptionsResult options,
  ) async {
    Logger.i('恢复下载: ${dict.name}', tag: 'DownloadManager');

    task.state = DownloadState.downloading;
    task.status = t.dict.statusResuming;
    task.error = null;
    _currentDownloadId = task.dictId;
    notifyListeners();

    await _runDownload(task, dict, options);
  }

  /// 手动恢复指定词典的下载
  Future<void> resumeDownload(String dictId) async {
    final task = _downloads[dictId];
    if (task == null) {
      Logger.w('找不到下载任务: $dictId', tag: 'DownloadManager');
      return;
    }

    if (task.state != DownloadState.idle &&
        task.state != DownloadState.paused &&
        task.state != DownloadState.error) {
      Logger.w('任务状态不允许恢复: ${task.state}', tag: 'DownloadManager');
      return;
    }

    if (task.downloadOptions == null || task.remoteDictJson == null) {
      Logger.w('任务缺少恢复所需的信息', tag: 'DownloadManager');
      return;
    }

    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中', tag: 'DownloadManager');
      return;
    }

    try {
      final dict = RemoteDictionary.fromJson(task.remoteDictJson!);
      await _resumeDownload(task, dict, task.downloadOptions!);
    } catch (e) {
      Logger.e('恢复下载失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.error = e.toString();
      notifyListeners();
      _saveDownloads();
    }
  }

  Future<void> _runDownload(
    DownloadTask task,
    RemoteDictionary dict,
    DownloadOptionsResult options,
  ) async {
    // Guarantee periodic UI refreshes independent of HTTP chunk delivery.
    // On Android, large chunks may arrive infrequently; without this timer
    // the UI could freeze between chunks even though bytes are flowing.
    final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
      if (task.state == DownloadState.downloading) {
        notifyListeners();
      }
    });

    try {
      if (_storeService == null) {
        throw Exception(t.dict.storeNotConfigured);
      }

      final dictManager = DictionaryManager();
      final dictDir = await dictManager.getDictionaryDirectory(dict.id);

      // 确保目录存在
      final dir = Directory(dictDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 计算总文件数
      int totalFiles = 0;
      if (options.includeMetadata) totalFiles++;
      if (options.includeLogo && dict.hasLogo) totalFiles++;
      if (options.includeDb && dict.hasDatabase) totalFiles++;
      if (options.includeMedia && (dict.hasAudios || dict.hasImages))
        totalFiles++;

      if (totalFiles == 0) {
        throw Exception(t.dict.noContentSelected);
      }

      int currentFileIndex = 0;

      // 滞动窗口算速变量（完全局部，不持久化）
      const speedUpdateInterval = Duration(seconds: 5);
      var speedWindowStart = DateTime.now();
      var speedWindowBytes = 0;
      var lastWindowSpeed = 0;

      // 辅助函数：处理单个文件的下载事件
      void handleProgressEvent(Map<String, dynamic> event) {
        if (event['type'] == 'progress') {
          final now = DateTime.now();
          final newReceivedBytes =
              (event['receivedBytes'] as num?)?.toInt() ?? 0;

          speedWindowBytes += (newReceivedBytes - task.receivedBytes).clamp(
            0,
            double.maxFinite.toInt(),
          );
          final windowElapsed = now.difference(speedWindowStart);
          if (windowElapsed >= speedUpdateInterval) {
            final windowSecs = windowElapsed.inMilliseconds / 1000.0;
            final windowSpeed = (speedWindowBytes / windowSecs).round();
            task.speedBytesPerSecond = lastWindowSpeed == 0
                ? windowSpeed
                : ((0.4 * windowSpeed) + (0.6 * lastWindowSpeed)).round();
            lastWindowSpeed = task.speedBytesPerSecond;
            speedWindowStart = now;
            speedWindowBytes = 0;
          }

          task.receivedBytes = newReceivedBytes;
          task.currentFileName = event['fileName'] as String?;
          task.fileIndex = (event['fileIndex'] as num?)?.toInt() ?? 0;
          task.totalFiles = (event['totalFiles'] as num?)?.toInt() ?? 0;
          task.totalBytes = (event['totalBytes'] as num?)?.toInt() ?? 0;
          task.fileProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          task.overallProgress = task.totalFiles > 0
              ? (task.fileIndex - 1 + task.fileProgress) / task.totalFiles
              : 0.0;
          task.status = event['status'] as String? ?? t.dict.statusDownloading;
          task.error = null;

          final fileName = event['fileName'] as String?;
          if (fileName != null) {
            task.updateFileProgress(
              fileName,
              downloadedBytes: newReceivedBytes,
              totalBytes: task.totalBytes,
            );
          }

          _notifyIfNeeded();
          _saveDownloads();
        }
      }

      // 1. 下载 metadata.json（小文件，特殊处理）
      if (options.includeMetadata) {
        if (task.state == DownloadState.cancelled) {
          progressTimer.cancel();
          return;
        }
        currentFileIndex++;
        task.currentFileName = 'metadata.json';
        task.fileIndex = currentFileIndex;
        task.totalFiles = totalFiles;
        task.status = t.dict.downloadingMeta(
          step: currentFileIndex.toString(),
          total: totalFiles.toString(),
        );
        notifyListeners();

        final url = Uri.parse(
          _storeService!.baseUrl.endsWith('/')
              ? '${_storeService!.baseUrl}download/${dict.id}/file/metadata.json'
              : '${_storeService!.baseUrl}/download/${dict.id}/file/metadata.json',
        );
        Logger.i('正在下载元数据: $url', tag: 'DownloadManager');

        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          final metadataFile = File(path.join(dictDir, 'metadata.json'));
          final body = utf8.decode(response.bodyBytes);
          final metadata = jsonDecode(body) as Map<String, dynamic>;
          metadata['id'] = dict.id;
          final encoder = JsonEncoder.withIndent('  ');
          await metadataFile.writeAsString(encoder.convert(metadata));
          Logger.i('元数据下载完成', tag: 'DownloadManager');
          task.markFileCompleted('metadata.json');
          _saveDownloads();
        } else {
          throw Exception(
            t.dict.downloadMetaFailed(
              url: url.toString(),
              code: response.statusCode.toString(),
            ),
          );
        }
      }

      // 2. 下载 logo.png（小文件，特殊处理）
      if (options.includeLogo && dict.hasLogo) {
        if (task.state == DownloadState.cancelled) {
          progressTimer.cancel();
          return;
        }
        currentFileIndex++;
        task.currentFileName = 'logo.png';
        task.fileIndex = currentFileIndex;
        task.totalFiles = totalFiles;
        task.status = t.dict.downloadingIcon(
          step: currentFileIndex.toString(),
          total: totalFiles.toString(),
        );
        notifyListeners();

        final url = Uri.parse(
          _storeService!.baseUrl.endsWith('/')
              ? '${_storeService!.baseUrl}download/${dict.id}/file/logo.png'
              : '${_storeService!.baseUrl}/download/${dict.id}/file/logo.png',
        );
        Logger.i('正在下载图标: $url', tag: 'DownloadManager');

        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) {
          final bodyBytes = response.bodyBytes;
          if (bodyBytes.isNotEmpty && _isValidPng(bodyBytes)) {
            final logoFile = File(path.join(dictDir, 'logo.png'));
            await logoFile.writeAsBytes(bodyBytes);
            Logger.i(
              '图标下载完成: ${bodyBytes.length} bytes',
              tag: 'DownloadManager',
            );
          } else {
            Logger.w('图标下载失败: 响应内容无效', tag: 'DownloadManager');
          }
          task.markFileCompleted('logo.png');
          _saveDownloads();
        } else {
          Logger.w(
            '图标下载失败: HTTP ${response.statusCode}',
            tag: 'DownloadManager',
          );
        }
      }

      // 3. 下载 dictionary.db
      if (options.includeDb && dict.hasDatabase) {
        if (task.state == DownloadState.cancelled) {
          progressTimer.cancel();
          return;
        }
        currentFileIndex++;
        final fileName = 'dictionary.db';
        final savePath = path.join(dictDir, fileName);

        // 获取已有的下载进度
        int startBytes = 0;
        if (task.fileProgresses.containsKey(fileName)) {
          startBytes = task.fileProgresses[fileName]!.downloadedBytes;
        }

        // 检查临时文件的实际大小
        final tempFile = File('$savePath.downloading');
        if (await tempFile.exists()) {
          final tempSize = await tempFile.length();
          if (tempSize > startBytes) {
            startBytes = tempSize;
          }
        }

        await for (final event in _storeService!.downloadDictFileStream(
          dict.id,
          fileName,
          savePath,
          startBytes: startBytes,
          fileIndex: currentFileIndex,
          totalFiles: totalFiles,
          status: t.dict.downloadingDatabase(
            step: currentFileIndex.toString(),
            total: totalFiles.toString(),
          ),
        )) {
          if (task.state == DownloadState.cancelled) break;
          handleProgressEvent(event);
          if (event['type'] == 'file_complete') {
            task.markFileCompleted(fileName);
            _saveDownloads();
          } else if (event['type'] == 'error') {
            throw Exception(event['error']);
          }
        }
      }

      // 4. 下载 media.db
      if (options.includeMedia && (dict.hasAudios || dict.hasImages)) {
        if (task.state == DownloadState.cancelled) {
          progressTimer.cancel();
          return;
        }
        currentFileIndex++;
        final fileName = 'media.db';
        final savePath = path.join(dictDir, fileName);

        // 获取已有的下载进度
        int startBytes = 0;
        if (task.fileProgresses.containsKey(fileName)) {
          startBytes = task.fileProgresses[fileName]!.downloadedBytes;
        }

        // 检查临时文件的实际大小
        final tempFile = File('$savePath.downloading');
        if (await tempFile.exists()) {
          final tempSize = await tempFile.length();
          if (tempSize > startBytes) {
            startBytes = tempSize;
          }
        }

        await for (final event in _storeService!.downloadDictFileStream(
          dict.id,
          fileName,
          savePath,
          startBytes: startBytes,
          fileIndex: currentFileIndex,
          totalFiles: totalFiles,
          status: t.dict.downloadingMedia(
            step: currentFileIndex.toString(),
            total: totalFiles.toString(),
          ),
        )) {
          if (task.state == DownloadState.cancelled) break;
          handleProgressEvent(event);
          if (event['type'] == 'file_complete') {
            task.markFileCompleted(fileName);
            _saveDownloads();
          } else if (event['type'] == 'error') {
            throw Exception(event['error']);
          }
        }
      }

      progressTimer.cancel();
      task.state = DownloadState.completed;
      task.status = t.dict.statusCompleted;
      task.overallProgress = 1.0;
      task.currentFileName = null;
      notifyListeners();
      _saveDownloads();
      await task.onComplete?.call();

      _currentDownloadId = null;
    } catch (e) {
      Logger.e('下载失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusFailed;
      task.error = e.toString();
      notifyListeners();
      await _saveDownloadsAsync();
      try {
        task.onError?.call(e.toString());
      } catch (err) {
        Logger.w('错误回调执行失败: $err', tag: 'DownloadManager');
      }
      _currentDownloadId = null;
    } finally {
      progressTimer.cancel();
    }
  }

  /// 验证 PNG 文件头
  bool _isValidPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    // PNG 文件头: 89 50 4E 47 0D 0A 1A 0A
    return bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
  }

  void cancelDownload(String dictId) {
    final task = _downloads[dictId];
    if (task != null) {
      task.state = DownloadState.cancelled;
      task.status = t.dict.cancelled;
      notifyListeners();
      _saveDownloads();
    }
  }

  /// 暂停下载任务
  void pauseDownload(String dictId) {
    final task = _downloads[dictId];
    if (task != null && task.state == DownloadState.downloading) {
      task.state = DownloadState.paused;
      task.status = t.dict.paused;
      notifyListeners();
      _saveDownloads();
    }
  }

  /// 恢复暂停的下载任务
  Future<void> resumePausedDownload(String dictId) async {
    final task = _downloads[dictId];
    if (task == null || task.state != DownloadState.paused) {
      return;
    }

    if (_currentDownloadId != null && _currentDownloadId != dictId) {
      Logger.w('已有下载任务进行中', tag: 'DownloadManager');
      return;
    }

    // 重新扫描该词典的未完成文件并恢复下载
    final incompleteFiles = await _scanIncompleteDownloadsForDict(dictId);
    if (incompleteFiles.isEmpty) {
      Logger.w('没有找到未完成的下载文件', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusFailed;
      task.error = 'No incomplete download files found';
      notifyListeners();
      return;
    }

    await _resumeDownloadFromFiles(dictId, incompleteFiles);
  }

  /// 扫描指定词典的未完成下载文件
  Future<List<_IncompleteFileInfo>> _scanIncompleteDownloadsForDict(
    String dictId,
  ) async {
    final result = <_IncompleteFileInfo>[];

    try {
      final dictDir = await _getDictionaryDir(dictId);
      if (dictDir == null) {
        return result;
      }

      final dictDirObj = Directory(dictDir);
      if (!await dictDirObj.exists()) {
        return result;
      }

      await for (final file in dictDirObj.list()) {
        if (file is! File) continue;

        final fileName = path.basename(file.path);
        if (fileName.endsWith('.downloading')) {
          final originalFileName = fileName.substring(
            0,
            fileName.length - '.downloading'.length,
          );
          final tempFileSize = await file.length();

          result.add(
            _IncompleteFileInfo(
              tempFilePath: file.path,
              originalFileName: originalFileName,
              downloadedBytes: tempFileSize,
            ),
          );

          Logger.d(
            '发现未完成下载: $dictId/$originalFileName, 已下载 $tempFileSize 字节',
            tag: 'DownloadManager',
          );
        }
      }
    } catch (e) {
      Logger.e('扫描未完成下载失败: $e', tag: 'DownloadManager');
    }

    return result;
  }

  /// 终止下载任务并删除临时文件
  Future<void> terminateDownload(String dictId) async {
    final task = _downloads[dictId];
    if (task != null) {
      task.state = DownloadState.cancelled;
      task.status = t.dict.cancelled;
      notifyListeners();
    }

    // 删除 .downloading 临时文件
    try {
      final dictDir = await _getDictionaryDir(dictId);
      if (dictDir != null) {
        final dictDirObj = Directory(dictDir);
        if (await dictDirObj.exists()) {
          await for (final file in dictDirObj.list()) {
            if (file is! File) continue;

            final fileName = path.basename(file.path);
            if (fileName.endsWith('.downloading')) {
              await file.delete();
              Logger.i('已删除临时文件: $fileName', tag: 'DownloadManager');
            }
          }
        }
      }
    } catch (e) {
      Logger.e('删除临时文件失败: $e', tag: 'DownloadManager');
    }

    // 清除任务
    _downloads.remove(dictId);
    if (_currentDownloadId == dictId) {
      _currentDownloadId = null;
    }
    notifyListeners();
    _saveDownloads();
  }

  void clearDownload(String dictId) {
    _downloads.remove(dictId);
    if (_currentDownloadId == dictId) {
      _currentDownloadId = null;
    }
    notifyListeners();
    _saveDownloads();
  }

  void clearCompletedDownloads() {
    _downloads.removeWhere((_, task) => task.state == DownloadState.completed);
    notifyListeners();
    _saveDownloads();
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
  }

  Future<void> startUpdate(
    String dictId,
    String dictName,
    Future<void> Function(
      void Function(
        String status,
        int fileIndex,
        int totalFiles, {
        int receivedBytes,
        int totalBytes,
        double fileProgress,
        int speedBytesPerSecond,
      })
      onProgress,
    )
    updateTask, {
    Future<void> Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中: $_currentDownloadId', tag: 'DownloadManager');
      return;
    }

    final task = DownloadTask(
      dictId: dictId,
      dictName: dictName,
      startTime: DateTime.now(),
      state: DownloadState.downloading,
      status: t.dict.statusPreparingUpdate,
      onComplete: onComplete,
      onError: onError,
      isUpdate: true, // 标记为更新任务
    );
    _downloads[dictId] = task;
    _currentDownloadId = dictId;
    notifyListeners();
    // 立即保存任务，不使用节流
    await _saveDownloadsAsync();

    // Periodic timer keeps the UI refreshed even between chunk events.
    final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
      if (task.state == DownloadState.downloading) {
        notifyListeners();
      }
    });

    try {
      await updateTask((
        status,
        current,
        total, {
        int receivedBytes = 0,
        int totalBytes = 0,
        double fileProgress = 0.0,
        int speedBytesPerSecond = 0,
      }) {
        task.status = status;
        task.fileIndex = current;
        task.totalFiles = total;
        task.receivedBytes = receivedBytes;
        task.totalBytes = totalBytes;
        task.fileProgress = fileProgress;
        task.speedBytesPerSecond = speedBytesPerSecond;
        // Overall = completed files + fraction of current file
        task.overallProgress = total > 0
            ? ((current - 1) + fileProgress) / total
            : 0.0;
        _notifyIfNeeded();
      });

      progressTimer.cancel();
      task.state = DownloadState.completed;
      task.status = t.dict.statusUpdateCompleted;
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      await _saveDownloadsAsync();
      // 安全调用完成回调
      try {
        await task.onComplete?.call();
      } catch (e) {
        Logger.w('完成回调执行失败: $e', tag: 'DownloadManager');
      }
    } catch (e) {
      Logger.e('更新失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusUpdateFailed;
      task.error = e.toString();
      notifyListeners();
      // 立即保存错误状态
      await _saveDownloadsAsync();
      // 安全调用错误回调
      try {
        task.onError?.call(e.toString());
      } catch (err) {
        Logger.w('错误回调执行失败: $err', tag: 'DownloadManager');
      }
    } finally {
      progressTimer.cancel();
      _currentDownloadId = null;
    }
  }

  /// 开始更新任务（支持断点续传）
  ///
  /// [updateFiles] 需要更新的文件列表
  /// [updateEntryIds] 需要更新的条目 ID 列表
  /// [updateToVersion] 更新到的版本号
  /// [metadataJson] 元数据 JSON（用于更新完成后保存）
  /// [dictDir] 词典目录路径
  /// [onEntriesDownload] 下载条目的回调（返回条目数据）
  /// [onCompleteWithMetadata] 完成时的回调（包含元数据）
  Future<void> startUpdateWithInfo({
    required String dictId,
    required String dictName,
    required List<String> updateFiles,
    required List<int> updateEntryIds,
    required int updateToVersion,
    required Map<String, dynamic> metadataJson,
    required String dictDir,
    Future<List<int>?> Function(List<int> entries)? onEntriesDownload,
    void Function(Map<String, dynamic> metadata)? onCompleteWithMetadata,
    Future<void> Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中: $_currentDownloadId', tag: 'DownloadManager');
      return;
    }

    final task = DownloadTask(
      dictId: dictId,
      dictName: dictName,
      startTime: DateTime.now(),
      state: DownloadState.downloading,
      status: t.dict.statusPreparingUpdate,
      isUpdate: true,
      updateFiles: updateFiles,
      updateEntryIds: updateEntryIds,
      updateToVersion: updateToVersion,
      metadataJson: metadataJson,
      onComplete: onComplete,
      onError: onError,
    );
    _downloads[dictId] = task;
    _currentDownloadId = dictId;
    notifyListeners();
    // 立即保存任务，不使用节流
    await _saveDownloadsAsync();

    final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
      if (task.state == DownloadState.downloading) {
        notifyListeners();
      }
    });

    try {
      final totalSteps =
          updateFiles.length + (updateEntryIds.isNotEmpty ? 1 : 0);
      var currentStep = 0;

      // 下载文件
      for (final fileName in updateFiles) {
        // 检查文件是否已下载完成
        final fileProgress = task.fileProgresses[fileName];
        if (fileProgress != null && fileProgress.isCompleted) {
          currentStep++;
          continue;
        }

        currentStep++;
        task.currentFileName = fileName;
        task.fileIndex = currentStep;
        task.totalFiles = totalSteps;
        task.status = t.dict.downloading(
          step: currentStep,
          total: totalSteps,
          name: fileName,
        );
        notifyListeners();

        final savePath = path.join(dictDir, fileName);

        // 检查临时文件大小，用于断点续传
        int startBytes = task.getFileDownloadedBytes(fileName);
        final tempFile = File('$savePath.downloading');
        if (await tempFile.exists()) {
          final tempSize = await tempFile.length();
          if (tempSize > startBytes) {
            Logger.i(
              '发现临时文件大小($tempSize)大于记录的进度($startBytes)，使用临时文件大小',
              tag: 'DownloadManager',
            );
            startBytes = tempSize;
            task.updateFileProgress(fileName, downloadedBytes: startBytes);
          }
        }

        bool downloadOk = false;
        await for (final event in _storeService!.downloadDictFileStream(
          dictId,
          fileName,
          savePath,
          startBytes: startBytes,
        )) {
          if (event['type'] == 'progress') {
            task.receivedBytes = (event['receivedBytes'] as num).toInt();
            task.totalBytes = (event['totalBytes'] as num).toInt();
            task.fileProgress = (event['progress'] as num).toDouble();
            task.speedBytesPerSecond = (event['speedBytesPerSecond'] as num)
                .toInt();
            task.overallProgress = totalSteps > 0
                ? (currentStep - 1 + task.fileProgress) / totalSteps
                : 0.0;

            task.updateFileProgress(
              fileName,
              downloadedBytes: task.receivedBytes,
              totalBytes: task.totalBytes,
            );

            _notifyIfNeeded();
            _saveDownloads();
          } else if (event['type'] == 'complete') {
            downloadOk = true;
            task.markFileCompleted(fileName);
            _saveDownloads();
          } else if (event['type'] == 'error') {
            throw Exception('${event['error']}');
          }
        }

        if (!downloadOk) {
          throw Exception('下载文件失败: $fileName');
        }
      }

      // 下载条目更新（如果有）
      if (updateEntryIds.isNotEmpty && onEntriesDownload != null) {
        currentStep++;
        task.currentFileName = null;
        task.fileIndex = currentStep;
        task.status = t.dict.downloadingEntries(
          step: currentStep,
          total: totalSteps,
        );
        notifyListeners();

        await onEntriesDownload(updateEntryIds);
      }

      progressTimer.cancel();
      task.state = DownloadState.completed;
      task.status = t.dict.statusUpdateCompleted;
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      await _saveDownloadsAsync();

      // 安全调用回调
      try {
        if (onCompleteWithMetadata != null) {
          onCompleteWithMetadata(metadataJson);
        }
        await task.onComplete?.call();
      } catch (e) {
        Logger.w('完成回调执行失败: $e', tag: 'DownloadManager');
      }
    } catch (e) {
      Logger.e('更新失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusUpdateFailed;
      task.error = e.toString();
      notifyListeners();
      // 立即保存错误状态
      await _saveDownloadsAsync();
      // 安全调用错误回调
      try {
        task.onError?.call(e.toString());
      } catch (err) {
        Logger.w('错误回调执行失败: $err', tag: 'DownloadManager');
      }
    } finally {
      progressTimer.cancel();
      _currentDownloadId = null;
    }
  }

  Future<void> startFileDownload(
    String fileId,
    String fileName,
    String url,
    String savePath, {
    Future<void> Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中: $_currentDownloadId', tag: 'DownloadManager');
      return;
    }

    final task = DownloadTask(
      dictId: fileId,
      dictName: fileName,
      startTime: DateTime.now(),
      state: DownloadState.downloading,
      status: t.dict.statusPreparing,
      totalFiles: 1,
      onComplete: onComplete,
      onError: onError,
    );
    _downloads[fileId] = task;
    _currentDownloadId = fileId;
    notifyListeners();
    _saveDownloads();

    try {
      final file = File(savePath);
      await file.parent.create(recursive: true);

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final sink = file.openWrite();
      var receivedBytes = 0;

      task.totalBytes = contentLength;
      task.currentFileName = fileName;
      task.fileIndex = 1;
      task.totalFiles = 1;

      // Periodic timer guarantees UI refreshes on all platforms.
      final progressTimer = Timer.periodic(_minNotifyInterval, (_) {
        if (task.state == DownloadState.downloading) {
          notifyListeners();
        }
      });

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final now = DateTime.now();
          if (task.lastSpeedUpdate != null) {
            final elapsedMs = now
                .difference(task.lastSpeedUpdate!)
                .inMilliseconds;
            if (elapsedMs > 0) {
              final bytesDiff = receivedBytes - task.receivedBytes;
              task.speedBytesPerSecond = (bytesDiff * 1000 / elapsedMs).round();
            }
          } else {
            final elapsedMs = now.difference(task.startTime).inMilliseconds;
            if (elapsedMs > 0) {
              task.speedBytesPerSecond = (receivedBytes * 1000 / elapsedMs)
                  .round();
            }
          }

          task.receivedBytes = receivedBytes;
          task.lastSpeedUpdate = now;
          task.fileProgress = contentLength > 0
              ? receivedBytes / contentLength
              : 0.0;
          task.overallProgress = task.fileProgress;
          task.status = t.dict.downloadingFile(name: fileName);
          _notifyIfNeeded();
        }
      } finally {
        progressTimer.cancel();
      }

      await sink.close();

      task.state = DownloadState.completed;
      task.status = t.dict.statusCompleted;
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      _saveDownloads();
      await task.onComplete?.call();
    } catch (e) {
      Logger.e('下载失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = t.dict.statusFailed;
      task.error = e.toString();
      notifyListeners();
      _saveDownloads();
      task.onError?.call(e.toString());
    } finally {
      _currentDownloadId = null;
    }
  }
}
