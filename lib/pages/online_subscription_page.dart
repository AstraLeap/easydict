import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/dictionary_store_service.dart';
import '../services/font_loader_service.dart';
import '../data/models/remote_dictionary.dart';
import '../services/dictionary_manager.dart';
import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../components/scale_layout_wrapper.dart';
import '../components/global_scale_wrapper.dart';

class OnlineSubscriptionPage extends StatefulWidget {
  const OnlineSubscriptionPage({super.key});

  @override
  State<OnlineSubscriptionPage> createState() => _OnlineSubscriptionPageState();
}

class _OnlineSubscriptionPageState extends State<OnlineSubscriptionPage> {
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
  final DictionaryManager _dictManager = DictionaryManager();
  final TextEditingController _urlController = TextEditingController();

  DictionaryStoreService? _service;
  List<RemoteDictionary> _availableDictionaries = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _service?.dispose();
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
      _service?.dispose();
      setState(() {
        _service = DictionaryStoreService(baseUrl: url);
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
      final dictionaries = await _service!.fetchDictionaryList();
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

  Future<void> _downloadDictionary(RemoteDictionary dict) async {
    if (_service == null) return;

    final isInstalled = await _dictManager.dictionaryExists(dict.id);
    if (isInstalled) {
      if (mounted) {
        showToast(context, '词典已安装');
      }
      return;
    }

    setState(() {
      _downloadProgress[dict.id] = 0;
    });

    try {
      await _service!.downloadDictionary(
        dict: dict,
        options: DownloadOptions(
          includeDatabase: true,
          includeMedia: dict.hasAudios || dict.hasImages,
        ),
        onProgress: (current, total, status) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _downloadProgress[dict.id] = current / total;
            });
          }
        },
        onComplete: () {
          if (!mounted) return;
          setState(() {
            _downloadProgress.remove(dict.id);
          });
          showToast(context, '${dict.name} 下载完成');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _downloadProgress.remove(dict.id);
          });
          showToast(context, '下载失败: $error');
          Logger.e('下载词典失败: $error', tag: 'OnlineSubscriptionPage');
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(dict.id);
      });
      showToast(context, '下载失败: $e');
      Logger.e('下载词典失败: $e', tag: 'OnlineSubscriptionPage');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在线词典订阅')),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: ListView(
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
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '订阅源URL',
                      hintText: 'https://example.com/dictionaries',
                      suffixIcon: Icon(Icons.link),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_urlController.text.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _openContributorPage,
                    icon: const Icon(Icons.favorite_outline, size: 18),
                    label: const Text('贡献'),
                  ),
                ],
              ],
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

  Future<void> _openContributorPage() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    Uri contributorUrl;
    try {
      final uri = Uri.parse(url);
      contributorUrl = uri.replace(path: '/contributor');
    } catch (e) {
      showToast(context, '无效的URL');
      return;
    }

    try {
      if (await canLaunchUrl(contributorUrl)) {
        await launchUrl(contributorUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showToast(context, '无法打开链接');
        }
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '打开链接失败: $e');
      }
    }
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
        ..._availableDictionaries.map((dict) => _buildDictionaryCard(dict)),
      ],
    );
  }

  Widget _buildDictionaryCard(RemoteDictionary dict) {
    final progress = _downloadProgress[dict.id];
    final logoUrl = dict.getLogoUrl(
      _service?.baseUrl ?? _urlController.text.trim(),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDictionaryDetails(dict),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dict.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dict.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(
                          label: Text(dict.language),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        Chip(
                          label: Text('v${dict.version}'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        Chip(
                          label: Text(dict.formattedDictSize),
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
                  onPressed: () => _downloadDictionary(dict),
                  icon: const Icon(Icons.download),
                  tooltip: '下载',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDictionaryDetails(RemoteDictionary dict) {
    final logoUrl = dict.getLogoUrl(
      _service?.baseUrl ?? _urlController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dict.name),
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
              _buildDetailItem('ID', dict.id),
              _buildDetailItem('版本', dict.version),
              _buildDetailItem('语言', dict.language),
              _buildDetailItem('词条数', '${dict.entryCount}'),
              _buildDetailItem('文件大小', dict.formattedDictSize),
              const SizedBox(height: 16),
              const Text('简介', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dict.description),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (dict.hasImages)
                    const Chip(
                      avatar: Icon(Icons.image, size: 16),
                      label: Text('包含图片'),
                    ),
                  if (dict.hasAudios)
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
              _downloadDictionary(dict);
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

  Widget _buildProgressIndicator(double progress) {
    return SizedBox(
      width: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
