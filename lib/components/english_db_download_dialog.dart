import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/english_db_service.dart';
import '../services/download_manager.dart';
import '../core/logger.dart';
import '../i18n/strings.g.dart';

enum EnglishDbDownloadResult { downloaded, notNow, neverAskAgain }

class EnglishDbDownloadDialog extends StatefulWidget {
  final String? downloadUrl;

  const EnglishDbDownloadDialog({super.key, this.downloadUrl});

  static Future<EnglishDbDownloadResult?> show(
    BuildContext context, {
    String? downloadUrl,
  }) async {
    return showDialog<EnglishDbDownloadResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EnglishDbDownloadDialog(downloadUrl: downloadUrl),
    );
  }

  @override
  State<EnglishDbDownloadDialog> createState() =>
      _EnglishDbDownloadDialogState();
}

class _EnglishDbDownloadDialogState extends State<EnglishDbDownloadDialog> {
  static const String _englishDbId = 'english_db';
  bool _downloadStarted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final downloadManager = context.watch<DownloadManager>();
    final task = downloadManager.getDownload(_englishDbId);
    final isDownloading =
        task != null && task.state == DownloadState.downloading;
    final isError = task != null && task.state == DownloadState.error;
    final isCompleted = task != null && task.state == DownloadState.completed;

    if (isCompleted && !_downloadStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop(EnglishDbDownloadResult.downloaded);
      });
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.download,
            color: isError ? Colors.orange : colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isError
                  ? context.t.dict.dbDialogTitleError
                  : context.t.dict.dbDialogTitle,
              style: TextStyle(
                fontSize: 18,
                color: isError ? Colors.orange : null,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '', // replaced by i18n below
          ),

          const SizedBox(height: 12),
          _buildFeatureItem(Icons.search, context.t.dict.dbFeatureVariant),
          _buildFeatureItem(Icons.swap_horiz, context.t.dict.dbFeatureAbbr),
          _buildFeatureItem(
            Icons.change_history,
            context.t.dict.dbFeatureNominal,
          ),
          _buildFeatureItem(
            Icons.format_list_numbered,
            context.t.dict.dbFeatureInflection,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t.dict.dbExample,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isDownloading || task != null) ...[
            const SizedBox(height: 16),
            _buildProgressSection(task!, colorScheme),
          ],
          if (isError && task?.error != null) ...[
            const SizedBox(height: 12),
            Text(
              task!.error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        if (isDownloading) ...[
          TextButton(
            onPressed: () {
              downloadManager.cancelDownload(_englishDbId);
              Navigator.of(context).pop(EnglishDbDownloadResult.notNow);
            },
            child: Text(context.t.common.cancel),
          ),
        ] else if (isError) ...[
          TextButton(
            onPressed: () {
              downloadManager.clearDownload(_englishDbId);
              Navigator.of(context).pop(EnglishDbDownloadResult.notNow);
            },
            child: Text(context.t.common.notNow),
          ),
          ElevatedButton.icon(
            onPressed: () => _startDownload(downloadManager),
            icon: const Icon(Icons.refresh),
            label: Text(context.t.common.retry),
          ),
        ] else ...[
          TextButton(
            onPressed: () async {
              await EnglishDbService().setNeverAskAgain(true);
              if (mounted) {
                Navigator.of(
                  context,
                ).pop(EnglishDbDownloadResult.neverAskAgain);
              }
            },
            child: Text(context.t.common.neverAskAgain),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(EnglishDbDownloadResult.notNow);
            },
            child: Text(context.t.common.notNow),
          ),
          ElevatedButton.icon(
            onPressed: () => _startDownload(downloadManager),
            icon: const Icon(Icons.download),
            label: Text(context.t.common.download),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressSection(DownloadTask task, ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.status,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (task.speedBytesPerSecond > 0)
              Text(
                DownloadManager().formatSpeed(task.speedBytesPerSecond),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: task.fileProgress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  Future<void> _startDownload(DownloadManager downloadManager) async {
    Logger.i('EnglishDbDownloadDialog: 开始下载...', tag: 'EnglishDB');
    setState(() {
      _downloadStarted = true;
    });

    final dbPath = await EnglishDbService().getDbPath();
    Logger.d('EnglishDbDownloadDialog: 目标路径: $dbPath', tag: 'EnglishDB');
    final url =
        widget.downloadUrl ?? await EnglishDbService().getDefaultDownloadUrl();
    Logger.d('EnglishDbDownloadDialog: 下载URL: $url', tag: 'EnglishDB');

    if (url.isEmpty) {
      Logger.e('EnglishDbDownloadDialog: URL为空，取消下载', tag: 'EnglishDB');
      downloadManager.clearDownload(_englishDbId);
      return;
    }

    await downloadManager.startFileDownload(
      _englishDbId,
      'en.db',
      url,
      dbPath,
      onComplete: () async {
        Logger.i('EnglishDbDownloadDialog: 下载完成!', tag: 'EnglishDB');
        if (mounted) {
          Navigator.of(context).pop(EnglishDbDownloadResult.downloaded);
        }
      },
      onError: (error) {
        Logger.e('EnglishDbDownloadDialog: 下载错误: $error', tag: 'EnglishDB');
        if (mounted) {
          setState(() {});
        }
      },
    );
  }
}
