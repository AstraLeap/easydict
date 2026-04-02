import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/download_manager.dart';
import '../services/user_dicts_service.dart';
import '../services/dict_update_check_service.dart';
import '../services/font_loader_service.dart';
import '../services/zstd_service.dart';
import '../data/models/remote_dictionary.dart';
import '../data/models/dictionary_metadata.dart';
import '../data/models/user_dictionary.dart' as user_dict;
import '../data/database_service.dart' as db_service;
import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../components/global_scale_wrapper.dart';
import '../components/transfer_progress_panel.dart';
import 'dictionary_manager_page.dart' show BatchUpdateDialog, DictUpdateDialog;

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

    Widget result = content;
    if (scale != 1.0) {
      result = PageScaleWrapper(child: content);
    }

    // 如果有 onBack 回调，使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            widget.onBack!();
          }
        },
        child: result,
      );
    }

    return result;
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

  Future<void> _checkAndUpdateDictionary(RemoteDictionary dict) async {
    if (_storeService == null) {
      showToast(context, context.t.dict.configCloudFirst);
      return;
    }

    try {
      _dictManager.clearMetadataCache(dict.id);
      final metadata = await _dictManager.getDictionaryMetadata(dict.id);
      if (metadata == null) {
        showToast(context, context.t.dict.getDictInfoFailed);
        return;
      }

      final currentVersion = metadata.version;
      Logger.d(
        '检查词典更新: ${dict.id}, 当前版本: $currentVersion',
        tag: 'DictionarySourcePage',
      );

      var updateInfo = await _userDictsService.getDictUpdateInfo(
        dict.id,
        currentVersion,
      );

      Logger.d('更新信息: $updateInfo', tag: 'DictionarySourcePage');
      if (updateInfo != null) {
        Logger.d(
          'from: ${updateInfo.from}, to: ${updateInfo.to}, files: ${updateInfo.required.files}, entries: ${updateInfo.required.entries}',
          tag: 'DictionarySourcePage',
        );

        // 检查本地是否存在 media.db
        final hasMediaDb = await _dictManager.hasMediaDb(dict.id);
        if (!hasMediaDb) {
          // 过滤掉 media.db 相关的更新
          final filteredFiles = updateInfo.required.files
              .where((file) => file != 'media.db')
              .toList();

          // 创建过滤后的更新信息
          updateInfo = user_dict.DictUpdateInfo(
            dictId: updateInfo.dictId,
            from: updateInfo.from,
            to: updateInfo.to,
            history: updateInfo.history,
            required: user_dict.DictUpdateRequired(
              files: filteredFiles,
              entries: updateInfo.required.entries,
            ),
          );
          Logger.d(
            '过滤后的更新信息: files: ${updateInfo.required.files}',
            tag: 'DictionarySourcePage',
          );
        }
      }

      if (!mounted) return;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => DictUpdateDialog(
          dictName: dict.name,
          dictId: dict.id,
          updateInfo: updateInfo,
          storeService: _storeService!,
          metadata: metadata,
        ),
      );

      if (result == null) return;

      if (result['type'] == 'smart' && updateInfo != null) {
        await _executeSmartUpdate(dict, updateInfo, metadata);
      } else if (result['type'] == 'manual') {
        await _executeManualUpdate(dict, result, metadata, updateInfo);
      }
    } catch (e) {
      showToast(context, context.t.dict.updateFailed(error: '$e'));
      Logger.e('更新词典失败: $e', tag: 'DictionarySourcePage');
    }
  }

  Future<void> _executeSmartUpdate(
    RemoteDictionary dict,
    user_dict.DictUpdateInfo updateInfo,
    DictionaryMetadata metadata,
  ) async {
    // 若既无文件更新也无条目更新，则只更新本地版本号
    if (updateInfo.required.files.isEmpty &&
        updateInfo.required.entries.isEmpty) {
      final newMetadata = DictionaryMetadata(
        id: metadata.id,
        name: metadata.name,
        version: updateInfo.to,
        description: metadata.description,
        sourceLanguage: metadata.sourceLanguage,
        targetLanguages: metadata.targetLanguages,
        publisher: metadata.publisher,
        maintainer: metadata.maintainer,
        contactMaintainer: metadata.contactMaintainer,
        updatedAt: DateTime.now(),
      );
      await _dictManager.saveDictionaryMetadata(newMetadata);
      if (mounted) {
        showToast(
          context,
          context.t.dict.versionUpdated(version: updateInfo.to),
        );
        _loadOnlineDictionaries();
      }
      return;
    }

    final downloadManager = context.read<DownloadManager>();
    final dictDir = await _dictManager.getDictionaryDir(dict.id);
    final totalSteps =
        updateInfo.required.files.length +
        (updateInfo.required.entries.isNotEmpty ? 1 : 0);

    await downloadManager.startUpdate(
      dict.id,
      dict.name,
      (onProgress) async {
        var currentStep = 0;

        for (final fileName in updateInfo.required.files) {
          currentStep++;
          onProgress(
            context.t.dict.downloading(
              step: currentStep,
              total: totalSteps,
              name: fileName,
            ),
            currentStep,
            totalSteps,
          );

          final savePath = path.join(dictDir, fileName);
          bool downloadOk = false;
          await for (final event in _storeService!.downloadDictFileStream(
            dict.id,
            fileName,
            savePath,
          )) {
            if (event['type'] == 'progress') {
              onProgress(
                context.t.dict.downloading(
                  step: currentStep,
                  total: totalSteps,
                  name: fileName,
                ),
                currentStep,
                totalSteps,
                receivedBytes: (event['receivedBytes'] as num).toInt(),
                totalBytes: (event['totalBytes'] as num).toInt(),
                fileProgress: (event['progress'] as num).toDouble(),
                speedBytesPerSecond: (event['speedBytesPerSecond'] as num)
                    .toInt(),
              );
            } else if (event['type'] == 'complete') {
              downloadOk = true;
            } else if (event['type'] == 'error') {
              throw Exception(
                context.t.dict.downloadFileFailedError(
                  name: fileName,
                  error: '${event['error']}',
                ),
              );
            }
          }
          if (!downloadOk)
            throw Exception(context.t.dict.downloadFileFailed(name: fileName));
        }

        if (updateInfo.required.entries.isNotEmpty) {
          currentStep++;
          onProgress(
            context.t.dict.downloadingEntries(
              step: currentStep,
              total: totalSteps,
            ),
            currentStep,
            totalSteps,
          );

          final zstdData = await _userDictsService.downloadEntryUpdates(
            dict.id,
            updateInfo.required.entries,
          );

          if (zstdData == null) {
            throw Exception(context.t.dict.downloadEntriesFailed);
          }

          final zstdDict = await _dictManager.getZstdDictionary(dict.id);
          final databaseService = db_service.DatabaseService();
          final zstdService = ZstdService();

          final decompressed = zstdService.decompress(zstdData, zstdDict);
          final jsonlContent = utf8.decode(decompressed);
          final lines = jsonlContent.split('\n');

          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final entryJson = jsonDecode(line) as Map<String, dynamic>;
            entryJson['dict_id'] = dict.id;
            final entry = db_service.DictionaryEntry.fromJson(entryJson);
            await databaseService.insertOrUpdateEntry(entry);
          }
        }
      },
      onComplete: () async {
        if (!mounted) return;

        final newMetadata = DictionaryMetadata(
          id: metadata.id,
          name: metadata.name,
          version: updateInfo.to,
          description: metadata.description,
          sourceLanguage: metadata.sourceLanguage,
          targetLanguages: metadata.targetLanguages,
          publisher: metadata.publisher,
          maintainer: metadata.maintainer,
          contactMaintainer: metadata.contactMaintainer,
          updatedAt: DateTime.now(),
        );
        await _dictManager.saveDictionaryMetadata(newMetadata);

        showToast(context, context.t.dict.updateSuccess);
        _loadOnlineDictionaries();
      },
      onError: (error) {
        if (!mounted) return;
        showToast(context, context.t.dict.updateFailed(error: '$error'));
      },
    );
  }

  Future<void> _executeManualUpdate(
    RemoteDictionary dict,
    Map<String, dynamic> options,
    DictionaryMetadata metadata,
    user_dict.DictUpdateInfo? updateInfo,
  ) async {
    final includeMetadata = options['includeMetadata'] as bool;
    final includeLogo = options['includeLogo'] as bool;
    final includeDb = options['includeDb'] as bool;
    final includeMedia = options['includeMedia'] as bool;

    final filesToDownload = <String>[];
    if (includeMetadata) filesToDownload.add('metadata.json');
    if (includeLogo) filesToDownload.add('logo.png');
    if (includeDb) filesToDownload.add('dictionary.db');
    if (includeMedia) filesToDownload.add('media.db');

    if (filesToDownload.isEmpty) {
      showToast(context, context.t.dict.noFileSelected);
      return;
    }

    final downloadManager = context.read<DownloadManager>();
    final dictDir = await _dictManager.getDictionaryDir(dict.id);
    final totalSteps = filesToDownload.length;

    await downloadManager.startUpdate(
      dict.id,
      dict.name,
      (onProgress) async {
        for (var i = 0; i < filesToDownload.length; i++) {
          final fileName = filesToDownload[i];
          final step = i + 1;
          onProgress(
            context.t.dict.downloading(
              step: step,
              total: totalSteps,
              name: fileName,
            ),
            step,
            totalSteps,
          );

          final savePath = path.join(dictDir, fileName);
          bool downloadOk = false;
          await for (final event in _storeService!.downloadDictFileStream(
            dict.id,
            fileName,
            savePath,
          )) {
            if (event['type'] == 'progress') {
              onProgress(
                context.t.dict.downloading(
                  step: step,
                  total: totalSteps,
                  name: fileName,
                ),
                step,
                totalSteps,
                receivedBytes: (event['receivedBytes'] as num).toInt(),
                totalBytes: (event['totalBytes'] as num).toInt(),
                fileProgress: (event['progress'] as num).toDouble(),
                speedBytesPerSecond: (event['speedBytesPerSecond'] as num)
                    .toInt(),
              );
            } else if (event['type'] == 'complete') {
              downloadOk = true;
            } else if (event['type'] == 'error') {
              throw Exception(
                context.t.dict.downloadFileFailedError(
                  name: fileName,
                  error: '${event['error']}',
                ),
              );
            }
          }
          if (!downloadOk)
            throw Exception(context.t.dict.downloadFileFailed(name: fileName));
        }
      },
      onComplete: () async {
        if (!mounted) return;

        if (includeMetadata) {
          _dictManager.clearMetadataCache(dict.id);
        }

        showToast(context, context.t.dict.updateSuccess);
        _loadOnlineDictionaries();
      },
      onError: (error) {
        if (!mounted) return;
        showToast(context, context.t.dict.updateFailed(error: '$error'));
      },
    );
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
