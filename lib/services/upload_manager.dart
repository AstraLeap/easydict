import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/logger.dart';

enum UploadState { idle, uploading, completed, error, cancelled }

class UploadTask {
  final String dictId;
  final String dictName;
  final DateTime startTime;
  UploadState state;
  String? currentFileName;
  int fileIndex;
  int totalFiles;
  int sentBytes;
  int totalBytes;
  double fileProgress;
  double overallProgress;
  String status;
  String? error;
  int speedBytesPerSecond;
  DateTime? lastSpeedUpdate;
  int lastSentBytes;
  final List<(DateTime time, int bytes)> _speedHistory;
  static const int _maxSpeedHistory = 5;
  VoidCallback? onComplete;
  void Function(String error)? onError;

  UploadTask({
    required this.dictId,
    required this.dictName,
    required this.startTime,
    this.state = UploadState.idle,
    this.currentFileName,
    this.fileIndex = 0,
    this.totalFiles = 0,
    this.sentBytes = 0,
    this.totalBytes = 0,
    this.fileProgress = 0.0,
    this.overallProgress = 0.0,
    this.status = '',
    this.error,
    this.speedBytesPerSecond = 0,
    this.lastSpeedUpdate,
    this.lastSentBytes = 0,
    List<(DateTime time, int bytes)>? speedHistory,
    this.onComplete,
    this.onError,
  }) : _speedHistory = speedHistory ?? [];

  void addSpeedSample(DateTime time, int bytes) {
    _speedHistory.add((time, bytes));
    if (_speedHistory.length > _maxSpeedHistory) {
      _speedHistory.removeAt(0);
    }
  }

  int calculateAverageSpeed() {
    if (_speedHistory.length < 2) return 0;

    // 使用指数移动平均 (EMA) 计算速度，更平滑
    double emaSpeed = 0;
    double alpha = 0.3; // 平滑因子，越小越平滑

    for (int i = 1; i < _speedHistory.length; i++) {
      final prev = _speedHistory[i - 1];
      final curr = _speedHistory[i];
      final elapsedMs = curr.$1.difference(prev.$1).inMilliseconds;
      if (elapsedMs > 0) {
        final bytesDiff = curr.$2 - prev.$2;
        final instantSpeed = bytesDiff * 1000 / elapsedMs;
        if (emaSpeed == 0) {
          emaSpeed = instantSpeed;
        } else {
          emaSpeed = alpha * instantSpeed + (1 - alpha) * emaSpeed;
        }
      }
    }

    return emaSpeed.round();
  }
}

class UploadManager with ChangeNotifier {
  static final UploadManager _instance = UploadManager._internal();
  factory UploadManager() => _instance;
  UploadManager._internal();

  final Map<String, UploadTask> _uploads = {};
  String? _currentUploadId;
  DateTime _lastNotifyTime = DateTime.now();
  static const _minNotifyInterval = Duration(milliseconds: 100);

  void _notifyIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastNotifyTime) >= _minNotifyInterval) {
      notifyListeners();
      _lastNotifyTime = now;
    }
  }

  List<UploadTask> getAllUploads() {
    return _uploads.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  UploadTask? getUpload(String dictId) => _uploads[dictId];

  UploadTask? get currentUpload =>
      _currentUploadId != null ? _uploads[_currentUploadId] : null;

  bool get isUploading => _currentUploadId != null;

  Future<void> startUpload(
    String dictId,
    String dictName,
    int totalFiles,
    Future<void> Function(void Function(String, int, int, int, int) onProgress)
    uploadTask, {
    VoidCallback? onComplete,
    void Function(String error)? onError,
  }) async {
    if (_currentUploadId != null) {
      Logger.w('已有上传任务进行中: $_currentUploadId', tag: 'UploadManager');
      return;
    }

    final task = UploadTask(
      dictId: dictId,
      dictName: dictName,
      startTime: DateTime.now(),
      state: UploadState.uploading,
      status: '准备上传...',
      totalFiles: totalFiles,
      onComplete: onComplete,
      onError: onError,
    );
    _uploads[dictId] = task;
    _currentUploadId = dictId;
    notifyListeners();

    try {
      await uploadTask((fileName, current, total, sent, totalBytes) {
        task.currentFileName = fileName;
        task.fileIndex = current;
        task.totalFiles = total;
        task.sentBytes = sent;
        task.totalBytes = totalBytes;
        task.fileProgress = totalBytes > 0 ? sent / totalBytes : 0.0;
        task.overallProgress = total > 0
            ? (current - 1 + task.fileProgress) / total
            : 0.0;
        task.status = '[$current/$total] 上传 $fileName';

        final now = DateTime.now();
        // 每 0.5 秒更新一次速度
        if (task.lastSpeedUpdate == null ||
            now.difference(task.lastSpeedUpdate!).inMilliseconds >= 500) {
          task.addSpeedSample(now, sent);
          task.speedBytesPerSecond = task.calculateAverageSpeed();
          task.lastSpeedUpdate = now;
        }

        _notifyIfNeeded();
      });

      task.state = UploadState.completed;
      task.status = '上传完成';
      task.overallProgress = 1.0;
      task.currentFileName = null;
      notifyListeners();
      task.onComplete?.call();
    } catch (e) {
      Logger.e('上传失败: $e', tag: 'UploadManager');
      task.state = UploadState.error;
      task.status = '上传失败';
      task.error = e.toString();
      notifyListeners();
      task.onError?.call(e.toString());
    } finally {
      _currentUploadId = null;
    }
  }

  void cancelUpload(String dictId) {
    final task = _uploads[dictId];
    if (task != null) {
      task.state = UploadState.cancelled;
      task.status = '已取消';
      notifyListeners();
    }
  }

  void clearUpload(String dictId) {
    _uploads.remove(dictId);
    if (_currentUploadId == dictId) {
      _currentUploadId = null;
    }
    notifyListeners();
  }

  void clearCompletedUploads() {
    _uploads.removeWhere((_, task) => task.state == UploadState.completed);
    notifyListeners();
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
}
