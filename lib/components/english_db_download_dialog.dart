import 'package:flutter/material.dart';
import '../services/english_db_service.dart';

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
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '准备下载...';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _error != null ? Icons.error_outline : Icons.download,
            color: _error != null ? Colors.orange : colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error != null ? '下载失败' : '下载英语词典数据库',
              style: TextStyle(
                fontSize: 18,
                color: _error != null ? Colors.orange : null,
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
            '英语词典数据库可以帮助您：',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(Icons.search, '单词拼写变体查询'),
          _buildFeatureItem(Icons.swap_horiz, '缩写/首字母缩略词查询'),
          _buildFeatureItem(Icons.change_history, '名词化形式查询'),
          _buildFeatureItem(Icons.format_list_numbered, '动词变形查询'),
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
                    '例如：搜索 "alpacas" 可自动重定向到 "alpaca"（复数形式）',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isDownloading || _progress > 0) ...[
            const SizedBox(height: 16),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_statusText),
                    Text('${(_progress * 100).toInt()}%'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        if (_isDownloading) ...[
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(EnglishDbDownloadResult.notNow),
            child: const Text('取消'),
          ),
        ] else if (_error != null) ...[
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(EnglishDbDownloadResult.notNow),
            child: const Text('暂不'),
          ),
          ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
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
            child: const Text('不再询问'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(EnglishDbDownloadResult.notNow);
            },
            child: const Text('暂不'),
          ),
          ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('下载'),
          ),
        ],
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

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = '正在连接服务器...';
      _error = null;
    });

    final success = await EnglishDbService().downloadDb(
      downloadUrl: widget.downloadUrl,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _statusText = progress < 1.0 ? '下载中...' : '验证中...';
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _error = error;
          });
        }
      },
    );

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(EnglishDbDownloadResult.downloaded);
      }
    }
  }
}
