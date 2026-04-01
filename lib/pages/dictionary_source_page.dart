import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/download_manager.dart';
import '../services/user_dicts_service.dart';
import '../services/dict_update_check_service.dart';
import '../services/font_loader_service.dart';
import '../data/models/remote_dictionary.dart';
import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../components/global_scale_wrapper.dart';
import '../components/transfer_progress_panel.dart';
import 'dictionary_manager_page.dart' show BatchUpdateDialog;

class DictionarySourcePage extends StatefulWidget {
  final VoidCallback? onBack;

  const DictionarySourcePage({super.key, this.onBack});

  @override
  State<DictionarySourcePage> createState() => _DictionarySourcePageState();
}

class _DictionarySourcePageState extends State<DictionarySourcePage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final UserDictsService _userDictsService = UserDictsService();

  List<RemoteDictionary> _onlineDictionaries = [];
  bool _isLoadingOnline = false;
  String? _onlineError;
  DictionaryStoreService? _storeService;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    if (!DownloadManager().isDownloading) {
      _storeService?.dispose();
    }
    _userDictsService.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _storeService = DictionaryStoreService(baseUrl: url);
      _userDictsService.setBaseUrl(url);
      final downloadManager = context.read<DownloadManager>();
      downloadManager.setStoreService(_storeService!);
      downloadManager.resumeAllDownloads();
      _loadOnlineDictionaries();
    }
  }

  Future<void> _loadOnlineDictionaries() async {
    if (_storeService == null) return;

    setState(() {
      _isLoadingOnline = true;
      _onlineError = null;
    });

    try {
      final dictionaries = await _storeService!.fetchDictionaryList();
      final downloadedIds = await _storeService!.getDownloadedDictionaryIds();
      for (var dict in dictionaries) {
        dict.isDownloaded = downloadedIds.contains(dict.id);
      }

      setState(() {
        _onlineDictionaries = dictionaries;
        _isLoadingOnline = false;
      });
    } catch (e) {
      Logger.e('加载在线词典失败: $e', tag: 'DictionarySourcePage');
      setState(() {
        _onlineError = e.toString();
        _isLoadingOnline = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = FontLoaderService().getDictionaryContentScale();
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final updateCount = updateCheckService.updatableCount;

    final content = Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(context.t.dict.tabStore),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildContent(),
      bottomSheet: const DownloadProgressPanel(),
    );

    if (scale == 1.0) {
      return content;
    }

    return PageScaleWrapper(child: content);
  }

  Widget _buildContent() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: CustomScrollView(
          slivers: [
            // 在线词典列表标题
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Text(
                      context.t.dict.onlineDicts,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_isLoadingOnline)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      if (_onlineDictionaries.isNotEmpty)
                        Text(
                          context.t.dict.onlineCount(
                            count: _onlineDictionaries.length,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      const SizedBox(width: 8),
                      _buildCheckUpdateButton(),
                    ],
                  ],
                ),
              ),
            ),

            // 错误提示
            if (_onlineError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Card(
                    color: Colors.red[50],
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.red),
                      title: Text(
                        context.t.dict.loadFailed,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                      subtitle: Text(_onlineError!),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadOnlineDictionaries,
                      ),
                    ),
                  ),
                ),
              ),

            // 在线词典列表
            if (_onlineDictionaries.isEmpty && !_isLoadingOnline)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.t.dict.noOnlineDicts,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.t.dict.noOnlineDictsHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildOnlineDictionaryCard(_onlineDictionaries[index]),
                    childCount: _onlineDictionaries.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckUpdateButton() {
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final isChecking = updateCheckService.isChecking;
    final updateCount = updateCheckService.updatableCount;
    final colorScheme = Theme.of(context).colorScheme;

    if (updateCount > 0) {
      return TextButton.icon(
        onPressed: isChecking
            ? null
            : () => _showBatchUpdateDialog(updateCheckService),
        icon: Icon(
          Icons.cloud_download,
          size: 18,
          color: colorScheme.onPrimary,
        ),
        label: Text(
          context.t.dict.updateCount(count: updateCount),
          style: TextStyle(color: colorScheme.onPrimary),
        ),
        style: TextButton.styleFrom(
          backgroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return TextButton.icon(
      onPressed: isChecking
          ? null
          : () async {
              await updateCheckService.checkForUpdates();
              if (updateCheckService.updatableCount > 0 && mounted) {
                showToast(
                  context,
                  context.t.dict.hasUpdates(
                    count: updateCheckService.updatableCount,
                  ),
                );
              } else if (mounted) {
                showToast(context, context.t.dict.allUpToDate);
              }
            },
      icon: isChecking
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : Icon(Icons.refresh, size: 18),
      label: Text(
        isChecking ? context.t.dict.checking : context.t.dict.checkUpdates,
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showBatchUpdateDialog(DictUpdateCheckService updateCheckService) {
    showDialog(
      context: context,
      builder: (context) => BatchUpdateDialog(
        updateCheckService: updateCheckService,
        dictManager: _dictManager,
        storeService: _storeService,
        userDictsService: _userDictsService,
        onComplete: () {
          updateCheckService.clearAllUpdates();
        },
      ),
    );
  }

  Widget _buildOnlineDictionaryCard(RemoteDictionary dict) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          dict.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _formatLargeNumber(dict.entryCount),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              if (dict.hasAudios) ...[
                Icon(Icons.audiotrack, size: 14, color: colorScheme.tertiary),
                const SizedBox(width: 4),
                Text(
                  _formatLargeNumber(dict.audioCount),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (dict.hasImages) ...[
                Icon(Icons.image, size: 14, color: colorScheme.secondary),
                const SizedBox(width: 4),
                Text(
                  _formatLargeNumber(dict.imageCount),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.update, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                _formatUpdateTime(dict.updatedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            dict.isDownloaded
                ? Icons.cloud_download_outlined
                : Icons.download_outlined,
            color: colorScheme.primary,
          ),
          tooltip: dict.isDownloaded
              ? context.t.dict.tooltipUpdate
              : context.t.dict.tooltipDownload,
          onPressed: () {
            if (dict.isDownloaded) {
              _checkAndUpdateDictionary(dict);
            } else {
              _startDownload(dict);
            }
          },
        ),
      ),
    );
  }

  Future<void> _startDownload(RemoteDictionary dict) async {
    final options = await _showDownloadOptionsDialog(dict);
    if (options == null) return;

    if (!mounted) return;

    final downloadManager = context.read<DownloadManager>();
    await downloadManager.startDownload(
      dict,
      options,
      onComplete: () async {
        if (!mounted) return;
        // 清除 metadata 缓存，确保重新从文件加载
        _dictManager.clearMetadataCache(dict.id);
        // 关闭旧数据库连接，确保查词时重新打开新下载的文件
        await _dictManager.closeDatabase(dict.id);
        // 启用词典
        await _dictManager.enableDictionary(dict.id);
        // 更新在线词典列表中的下载状态
        _updateOnlineDictionaryStatus(dict.id, isDownloaded: true);
      },
      onError: (error) async {
        if (!mounted) return;
        // 可以在这里处理错误
      },
    );
  }

  void _updateOnlineDictionaryStatus(String dictId, {required bool isDownloaded}) {
    final index = _onlineDictionaries.indexWhere((d) => d.id == dictId);
    if (index != -1) {
      setState(() {
        _onlineDictionaries[index] = _onlineDictionaries[index].copyWith(
          isDownloaded: isDownloaded,
        );
      });
    }
  }

  Future<DownloadOptionsResult?> _showDownloadOptionsDialog(
    RemoteDictionary dict,
  ) async {
    // metadata.json、logo.png、dictionary.db 强制选择
    // media.db 默认不选择
    bool includeMetadata = true;
    bool includeLogo = true;
    bool includeDb = dict.hasDatabase;
    bool includeMedia = false; // media.db 默认不选择

    return showDialog<DownloadOptionsResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.download, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t.dict.downloadDict(name: dict.name),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.dict.selectContent,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // metadata.json 强制选择，不可取消
                    CheckboxListTile(
                      dense: true,
                      title: const Text('metadata.json'),
                      subtitle: Text(context.t.dict.dictMeta),
                      secondary: const Icon(
                        Icons.description,
                        color: Colors.grey,
                      ),
                      value: includeMetadata,
                      onChanged: null, // 强制选择，不可取消
                    ),
                    if (dict.hasLogo)
                      // logo.png 强制选择，不可取消
                      CheckboxListTile(
                        dense: true,
                        title: const Text('logo.png'),
                        subtitle: Text(context.t.dict.dictIcon),
                        secondary: const Icon(Icons.image, color: Colors.grey),
                        value: includeLogo,
                        onChanged: null, // 强制选择，不可取消
                      ),
                    if (dict.hasDatabase)
                      // dictionary.db 强制选择，不可取消
                      CheckboxListTile(
                        dense: true,
                        title: const Text('dictionary.db'),
                        subtitle: Text(
                          dict.formattedDictSize.isNotEmpty
                              ? context.t.dict.dictDbWithSize(
                                  size: dict.formattedDictSize,
                                )
                              : context.t.dict.dictDb,
                        ),
                        secondary: const Icon(
                          Icons.storage,
                          color: Colors.blue,
                        ),
                        value: includeDb,
                        onChanged: null, // 强制选择，不可取消
                      ),
                    if (dict.hasAudios || dict.hasImages)
                      // media.db 可选择，默认不选择
                      CheckboxListTile(
                        dense: true,
                        title: const Text('media.db'),
                        subtitle: Text(
                          dict.formattedMediaSize.isNotEmpty
                              ? context.t.dict.mediaDbWithSize(
                                  size: dict.formattedMediaSize,
                                )
                              : context.t.dict.mediaDb,
                        ),
                        secondary: const Icon(
                          Icons.library_music,
                          color: Colors.purple,
                        ),
                        value: includeMedia,
                        onChanged: (value) {
                          setState(() {
                            includeMedia = value ?? false;
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.t.common.cancel),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(
                      DownloadOptionsResult(
                        includeMetadata: includeMetadata,
                        includeLogo: includeLogo,
                        includeDb: includeDb,
                        includeMedia: includeMedia,
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: Text(context.t.dict.startDownload),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _checkAndUpdateDictionary(RemoteDictionary dict) {
    _startDownload(dict);
  }

  String _formatLargeNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatUpdateTime(DateTime? dateTime) {
    if (dateTime == null) return context.t.dict.dateUnknown;
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 365) {
      return context.t.dict.yearsAgo(n: (diff.inDays / 365).floor());
    } else if (diff.inDays > 30) {
      return context.t.dict.monthsAgo(n: (diff.inDays / 30).floor());
    } else if (diff.inDays > 0) {
      return context.t.dict.daysAgo(n: diff.inDays);
    } else if (diff.inHours > 0) {
      return context.t.dict.hoursAgo(n: diff.inHours);
    } else if (diff.inMinutes > 0) {
      return context.t.dict.minutesAgo(n: diff.inMinutes);
    } else {
      return context.t.dict.justNow;
    }
  }
}
