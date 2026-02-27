import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/remote_dictionary.dart';
import '../services/dictionary_store_service.dart';
import '../core/logger.dart';

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

enum DownloadState { idle, downloading, completed, error, cancelled }

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
  VoidCallback? onComplete;
  void Function(String error)? onError;

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
    this.status = '准备下载...',
    this.error,
    this.speedBytesPerSecond = 0,
    this.onComplete,
    this.onError,
  });

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
  };

  static DownloadTask fromJson(Map<String, dynamic> json) => DownloadTask(
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
    status: json['status'] as String? ?? '准备下载...',
    error: json['error'] as String?,
    speedBytesPerSecond: json['speedBytesPerSecond'] as int? ?? 0,
  );
}

class DownloadManager with ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal() {
    _initialize();
  }

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

  void _saveDownloads() {
    final now = DateTime.now();
    if (now.difference(_lastSaveTime) >= _minSaveInterval) {
      _lastSaveTime = now;
      _saveDownloadsAsync();
    }
  }

  Future<void> _saveDownloadsAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> tasks = _downloads.values
          .where((t) => t.state != DownloadState.completed)
          .map((t) => t.toJson())
          .toList();
      await prefs.setString('download_tasks', jsonEncode(tasks));
    } catch (e) {
      Logger.e('保存下载任务失败: $e', tag: 'DownloadManager');
    }
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadsJson = prefs.getString('download_tasks');
      if (downloadsJson != null) {
        final List<dynamic> decoded = jsonDecode(downloadsJson);
        for (final item in decoded) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          if (task.state == DownloadState.downloading) {
            task.state = DownloadState.idle;
            _downloads[task.dictId] = task;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      Logger.e('加载下载任务失败: $e', tag: 'DownloadManager');
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
    VoidCallback? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_currentDownloadId != null) {
      Logger.w('已有下载任务进行中: $_currentDownloadId', tag: 'DownloadManager');
      return;
    }

    if (_downloads.containsKey(dict.id)) {
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
      status: '准备下载...',
      onComplete: onComplete,
      onError: onError,
    );
    _downloads[dict.id] = task;
    _currentDownloadId = dict.id;
    notifyListeners();
    _saveDownloads();

    await _runDownload(task, dict, options);
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
        throw Exception('未配置词典商店服务');
      }

      await for (final event in _storeService!.downloadDictionaryFilesStream(
        dict: dict,
        options: options,
      )) {
        if (task.state == DownloadState.cancelled) break;

        if (event['type'] == 'progress') {
          final now = DateTime.now();
          final newReceivedBytes =
              (event['receivedBytes'] as num?)?.toInt() ?? 0;

          if (task.lastSpeedUpdate != null) {
            final elapsedMs = now
                .difference(task.lastSpeedUpdate!)
                .inMilliseconds;
            if (elapsedMs > 0) {
              final bytesDiff = newReceivedBytes - task.receivedBytes;
              task.speedBytesPerSecond = (bytesDiff * 1000 / elapsedMs).round();
            }
          } else {
            final elapsedMs = now.difference(task.startTime).inMilliseconds;
            if (elapsedMs > 0) {
              task.speedBytesPerSecond = (newReceivedBytes * 1000 / elapsedMs)
                  .round();
            }
          }

          task.receivedBytes = newReceivedBytes;
          task.lastSpeedUpdate = now;
          task.currentFileName = event['fileName'] as String?;
          task.fileIndex = (event['fileIndex'] as num?)?.toInt() ?? 0;
          task.totalFiles = (event['totalFiles'] as num?)?.toInt() ?? 0;
          task.totalBytes = (event['totalBytes'] as num?)?.toInt() ?? 0;
          task.fileProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          task.overallProgress = task.totalFiles > 0
              ? (task.fileIndex - 1 + task.fileProgress) / task.totalFiles
              : 0.0;
          task.status = event['status'] as String? ?? '下载中...';
          task.error = null;
          // The periodic timer handles UI updates; also notify immediately
          // so the very first chunk is reflected without waiting 100 ms.
          _notifyIfNeeded();
          _saveDownloads();
        } else if (event['type'] == 'complete') {
          progressTimer.cancel();
          task.state = DownloadState.completed;
          task.status = '下载完成';
          task.overallProgress = 1.0;
          task.currentFileName = null;
          notifyListeners();
          _saveDownloads();
          task.onComplete?.call();
          break;
        } else if (event['type'] == 'error') {
          throw Exception(event['error'] ?? '下载失败');
        }
      }

      _currentDownloadId = null;
    } catch (e) {
      Logger.e('下载失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = '下载失败';
      task.error = e.toString();
      notifyListeners();
      _saveDownloads();
      task.onError?.call(e.toString());
      _currentDownloadId = null;
    } finally {
      progressTimer.cancel();
    }
  }

  void cancelDownload(String dictId) {
    final task = _downloads[dictId];
    if (task != null) {
      task.state = DownloadState.cancelled;
      task.status = '已取消';
      notifyListeners();
      _saveDownloads();
    }
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
      }) onProgress,
    ) updateTask, {
    VoidCallback? onComplete,
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
      status: '准备更新...',
      onComplete: onComplete,
      onError: onError,
    );
    _downloads[dictId] = task;
    _currentDownloadId = dictId;
    notifyListeners();
    _saveDownloads();

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
      task.status = '更新完成';
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      _saveDownloads();
      task.onComplete?.call();
    } catch (e) {
      Logger.e('更新失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = '更新失败';
      task.error = e.toString();
      notifyListeners();
      _saveDownloads();
      task.onError?.call(e.toString());
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
    VoidCallback? onComplete,
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
      status: '准备下载...',
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
          task.status = '[1/1] 下载 $fileName';
          _notifyIfNeeded();
        }
      } finally {
        progressTimer.cancel();
      }

      await sink.close();

      task.state = DownloadState.completed;
      task.status = '下载完成';
      task.overallProgress = 1.0;
      task.fileProgress = 1.0;
      notifyListeners();
      _saveDownloads();
      task.onComplete?.call();
    } catch (e) {
      Logger.e('下载失败: $e', tag: 'DownloadManager');
      task.state = DownloadState.error;
      task.status = '下载失败';
      task.error = e.toString();
      notifyListeners();
      _saveDownloads();
      task.onError?.call(e.toString());
    } finally {
      _currentDownloadId = null;
    }
  }
}
