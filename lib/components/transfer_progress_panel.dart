import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/download_manager.dart';
import '../services/upload_manager.dart';

class DownloadProgressPanel extends StatefulWidget {
  const DownloadProgressPanel({super.key});

  @override
  State<DownloadProgressPanel> createState() => _DownloadProgressPanelState();
}

class _DownloadProgressPanelState extends State<DownloadProgressPanel> {
  String _displayedSpeed = '';
  int? _lastSpeedValue;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _updateSpeedWithDebounce(
    int speedBytesPerSecond,
    DownloadManager manager,
  ) {
    if (_lastSpeedValue != speedBytesPerSecond) {
      _lastSpeedValue = speedBytesPerSecond;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        if (mounted) {
          setState(() {
            _displayedSpeed = manager.formatSpeed(speedBytesPerSecond);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadManager = context.watch<DownloadManager>();
    final currentTask = downloadManager.currentDownload;

    if (currentTask == null ||
        currentTask.state == DownloadState.completed ||
        currentTask.state == DownloadState.idle) {
      _displayedSpeed = '';
      _lastSpeedValue = null;
      _debounceTimer?.cancel();
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isError = currentTask.state == DownloadState.error;
    final isCancelled = currentTask.state == DownloadState.cancelled;

    if (!isError && !isCancelled && currentTask.speedBytesPerSecond > 0) {
      _updateSpeedWithDebounce(
        currentTask.speedBytesPerSecond,
        downloadManager,
      );
    }

    String statusText;
    if (isError) {
      statusText = '下载失败: ${currentTask.error ?? "未知错误"}';
    } else if (isCancelled) {
      statusText = '已取消';
    } else {
      statusText = currentTask.status;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.download,
                  color: isError ? colorScheme.error : colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentTask.dictName,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isError || isCancelled)
                  TextButton(
                    onPressed: () {
                      downloadManager.clearDownload(currentTask.dictId);
                    },
                    child: Text(isError ? '清除' : '关闭'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isError && !isCancelled && _displayedSpeed.isNotEmpty)
                  Text(
                    _displayedSpeed,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (!isError && !isCancelled) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: currentTask.fileProgress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UploadProgressPanel extends StatefulWidget {
  const UploadProgressPanel({super.key});

  @override
  State<UploadProgressPanel> createState() => _UploadProgressPanelState();
}

class _UploadProgressPanelState extends State<UploadProgressPanel> {
  String _displayedSpeed = '';
  int? _lastSpeedValue;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _updateSpeedWithDebounce(
    int speedBytesPerSecond,
    UploadManager manager,
  ) {
    if (_lastSpeedValue != speedBytesPerSecond) {
      _lastSpeedValue = speedBytesPerSecond;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        if (mounted) {
          setState(() {
            _displayedSpeed = manager.formatSpeed(speedBytesPerSecond);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadManager = context.watch<UploadManager>();
    final currentTask = uploadManager.currentUpload;

    if (currentTask == null || currentTask.state == UploadState.idle) {
      _displayedSpeed = '';
      _lastSpeedValue = null;
      _debounceTimer?.cancel();
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isError = currentTask.state == UploadState.error;
    final isCancelled = currentTask.state == UploadState.cancelled;
    final isCompleted = currentTask.state == UploadState.completed;

    if (!isError &&
        !isCancelled &&
        !isCompleted &&
        currentTask.speedBytesPerSecond > 0) {
      _updateSpeedWithDebounce(currentTask.speedBytesPerSecond, uploadManager);
    }

    String statusText;
    if (isError) {
      statusText = '上传失败: ${currentTask.error ?? "未知错误"}';
    } else if (isCancelled) {
      statusText = '已取消';
    } else if (isCompleted) {
      statusText = '上传成功';
    } else {
      statusText = currentTask.status;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline
                      : isCompleted
                      ? Icons.check_circle_outline
                      : Icons.upload,
                  color: isError
                      ? colorScheme.error
                      : isCompleted
                      ? Colors.green
                      : colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentTask.dictName,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isError || isCancelled || isCompleted)
                  TextButton(
                    onPressed: () {
                      uploadManager.clearUpload(currentTask.dictId);
                    },
                    child: Text(isError ? '清除' : '关闭'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isError
                          ? colorScheme.error
                          : isCompleted
                          ? Colors.green
                          : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isError &&
                    !isCancelled &&
                    !isCompleted &&
                    _displayedSpeed.isNotEmpty)
                  Text(
                    _displayedSpeed,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (!isError && !isCancelled && !isCompleted) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: currentTask.fileProgress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
