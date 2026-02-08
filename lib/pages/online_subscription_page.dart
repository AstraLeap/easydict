import 'package:flutter/material.dart';
import '../services/online_dictionary_service.dart';
import '../services/dictionary_manager.dart';
import '../logger.dart';
import '../utils/toast_utils.dart';

class OnlineSubscriptionPage extends StatefulWidget {
  const OnlineSubscriptionPage({super.key});

  @override
  State<OnlineSubscriptionPage> createState() => _OnlineSubscriptionPageState();
}

class _OnlineSubscriptionPageState extends State<OnlineSubscriptionPage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final TextEditingController _urlController = TextEditingController();

  OnlineDictionaryService? _service;
  List<OnlineDictionaryInfo> _availableDictionaries = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Map<String, DictionaryDownloadProgress> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _urlController.text = url;
      _initializeService();
    }
  }

  void _initializeService() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      setState(() {
        _service = OnlineDictionaryService(baseUrl: url);
        _errorMessage = null;
      });
      _fetchDictionaries();
    }
  }

  Future<void> _fetchDictionaries() async {
    if (_service == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dictionaries = await _service!.fetchAvailableDictionaries();
      setState(() {
        _availableDictionaries = dictionaries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _saveSettings() async {
    final url = _urlController.text.trim();
    await _dictManager.setOnlineSubscriptionUrl(url);

    if (mounted) {
      showToast(context, '设置已保存');
    }

    _initializeService();
  }

  Future<void> _downloadDictionary(OnlineDictionaryInfo info) async {
    if (_service == null) return;

    final isInstalled = await _dictManager.dictionaryExists(info.id);
    if (isInstalled) {
      if (mounted) {
        showToast(context, '词典已安装');
      }
      return;
    }

    setState(() {
      _downloadProgress[info.id] = DictionaryDownloadProgress(
        fileName: info.name,
        downloadedBytes: 0,
        totalBytes: info.fileSize,
      );
    });

    try {
      await _service!.downloadDictionary(
        info.id,
        (fileName, current, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress[info.id] = DictionaryDownloadProgress(
              fileName: fileName,
              downloadedBytes: current,
              totalBytes: total,
            );
          });
        },
        downloadAudios: info.hasAudios,
        downloadImages: info.hasImages,
      );

      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(info.id);
      });

      showToast(context, '${info.name} 下载完成');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(info.id);
      });

      showToast(context, '下载失败: $e');
      Logger.e('下载词典失败: $e', tag: 'OnlineSubscriptionPage');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在线词典订阅')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSubscriptionSettings(),
          const SizedBox(height: 24),
          if (_service != null) ...[
            _buildDictionariesList(),
          ] else ...[
            _buildEmptyState(),
          ],
        ],
      ),
    );
  }

  Widget _buildSubscriptionSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '订阅源设置',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '订阅源URL',
                hintText: 'https://example.com/dictionaries',
                suffixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('保存并连接'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('未连接到订阅源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '请在上面的输入框中输入订阅源URL',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDictionariesList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchDictionaries,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_availableDictionaries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text('暂无可用词典', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '可用词典 (${_availableDictionaries.length})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._availableDictionaries.map((info) => _buildDictionaryCard(info)),
      ],
    );
  }

  Widget _buildDictionaryCard(OnlineDictionaryInfo info) {
    final progress = _downloadProgress[info.id];
    // 使用 service 中的 baseUrl，确保与列表来源一致，避免受输入框编辑影响
    final logoUrl = info.buildLogoUrl(
      _service?.baseUrl ?? _urlController.text.trim(),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDictionaryDetails(info),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  logoUrl,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    Logger.e(
                      'Logo加载失败: $logoUrl, 错误: $error',
                      tag: 'OnlineSubscriptionPage',
                    );
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.book,
                        size: 32,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      info.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(
                          label: Text(info.language),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        Chip(
                          label: Text('v${info.version}'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        Chip(
                          label: Text(info.formattedFileSize),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (progress != null)
                _buildProgressIndicator(progress)
              else
                IconButton.filled(
                  onPressed: () => _downloadDictionary(info),
                  icon: const Icon(Icons.download),
                  tooltip: '下载',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDictionaryDetails(OnlineDictionaryInfo info) {
    final logoUrl = info.buildLogoUrl(
      _service?.baseUrl ?? _urlController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(info.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      logoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        Logger.e(
                          '详情页Logo加载失败: $logoUrl, 错误: $error',
                          tag: 'OnlineSubscriptionPage',
                        );
                        return Icon(
                          Icons.book,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildDetailItem('ID', info.id),
              _buildDetailItem('版本', info.version),
              _buildDetailItem('语言', info.language),
              _buildDetailItem('词条数', '${info.wordCount}'),
              _buildDetailItem('文件大小', info.formattedFileSize),
              const SizedBox(height: 16),
              const Text('简介', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(info.description),
              if (info.sourceUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('来源', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  info.sourceUrl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (info.hasImages)
                    const Chip(
                      avatar: Icon(Icons.image, size: 16),
                      label: Text('包含图片'),
                    ),
                  if (info.hasAudios)
                    const Chip(
                      avatar: Icon(Icons.audiotrack, size: 16),
                      label: Text('包含音频'),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _downloadDictionary(info);
            },
            icon: const Icon(Icons.download),
            label: const Text('下载'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(DictionaryDownloadProgress progress) {
    return SizedBox(
      width: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: progress.progress),
          const SizedBox(height: 4),
          Text(
            progress.progressText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            progress.fileName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
