import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:typed_data';
import 'entries_list_sheet.dart';
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/download_manager.dart';
import '../models/dictionary_metadata.dart';
import '../models/remote_dictionary.dart';
import '../logger.dart';
import '../utils/toast_utils.dart';

class DictionaryManagerPage extends StatefulWidget {
  const DictionaryManagerPage({super.key});

  @override
  State<DictionaryManagerPage> createState() => _DictionaryManagerPageState();
}

class _DictionaryManagerPageState extends State<DictionaryManagerPage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final TextEditingController _urlController = TextEditingController();

  List<DictionaryMetadata> _allDictionaries = [];
  List<String> _enabledDictionaryIds = [];
  List<RemoteDictionary> _onlineDictionaries = [];
  bool _isLoading = true;
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
    _urlController.dispose();
    _storeService?.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      // 加载本地词典
      final allDicts = await _dictManager.getAllDictionariesMetadata();
      final enabledIds = await _dictManager.getEnabledDictionaries();

      // 加载在线订阅URL
      final url = await _dictManager.onlineSubscriptionUrl;
      if (url.isNotEmpty) {
        _urlController.text = url;
        _storeService = DictionaryStoreService(baseUrl: url);
      }

      setState(() {
        _allDictionaries = allDicts;
        _enabledDictionaryIds = enabledIds;
        _isLoading = false;
      });

      // 如果有在线订阅，加载在线词典列表
      if (_storeService != null) {
        _loadOnlineDictionaries();
      }
    } catch (e) {
      Logger.e('加载设置失败: $e', tag: 'DictionaryManagerPage');
      setState(() => _isLoading = false);
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

      // 检查哪些在线词典已下载
      final downloadedIds = await _storeService!.getDownloadedDictionaryIds();
      for (var dict in dictionaries) {
        dict.isDownloaded = downloadedIds.contains(dict.id);
      }

      setState(() {
        _onlineDictionaries = dictionaries;
        _isLoadingOnline = false;
      });
    } catch (e) {
      Logger.e('加载在线词典失败: $e', tag: 'DictionaryManagerPage');
      setState(() {
        _onlineError = e.toString();
        _isLoadingOnline = false;
      });
    }
  }

  Future<void> _saveOnlineSubscriptionUrl() async {
    final url = _urlController.text.trim();
    await _dictManager.setOnlineSubscriptionUrl(url);

    if (url.isNotEmpty) {
      _storeService?.dispose();
      _storeService = DictionaryStoreService(baseUrl: url);
      _loadOnlineDictionaries();
    } else {
      setState(() {
        _onlineDictionaries = [];
        _onlineError = null;
      });
    }

    if (mounted) {
      showToast(context, '在线订阅地址已保存');
    }
  }

  Future<void> _selectDictionaryDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      await _dictManager.setBaseDirectory(selectedDirectory);
      _enabledDictionaryIds = [];
      await _loadSettings();

      if (mounted) {
        showToast(context, '词典目录已设置: $selectedDirectory');
      }
    }
  }

  Future<void> _toggleDictionary(String dictionaryId) async {
    setState(() {
      if (_enabledDictionaryIds.contains(dictionaryId)) {
        _enabledDictionaryIds.remove(dictionaryId);
      } else {
        _enabledDictionaryIds.add(dictionaryId);
      }
    });
    await _dictManager.setEnabledDictionaries(_enabledDictionaryIds);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _enabledDictionaryIds.removeAt(oldIndex);
      _enabledDictionaryIds.insert(newIndex, item);
    });
    _dictManager.reorderDictionaries(_enabledDictionaryIds);
  }

  Future<void> _showDictionaryDetails(DictionaryMetadata metadata) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DictionaryDetailPage(metadata: metadata),
      ),
    );
    await _loadSettings();
  }

  bool _isEnabled(String dictionaryId) {
    return _enabledDictionaryIds.contains(dictionaryId);
  }

  /// 检查本地词典是否有在线订阅
  bool _hasOnlineSubscription(String dictionaryId) {
    return _onlineDictionaries.any((dict) => dict.id == dictionaryId);
  }

  /// 检查本地词典是否已链接在线词表
  bool _isLinkedOnline(String dictionaryId) {
    if (_onlineDictionaries.isEmpty) return false;
    final onlineDict = _onlineDictionaries.firstWhere(
      (dict) => dict.id == dictionaryId,
      orElse: () => _onlineDictionaries.first.copyWith(isLinked: false),
    );
    return onlineDict.isLinked;
  }

  /// 格式化大数字，例如 235000 -> 235k, 1500000 -> 1.5M
  String _formatLargeNumber(int number) {
    if (number >= 1000000) {
      final value = number / 1000000;
      return value == value.truncateToDouble()
          ? '${value.toInt()}M'
          : '${value.toStringAsFixed(1)}M';
    } else if (number >= 10000) {
      final value = number / 1000;
      return value == value.truncateToDouble()
          ? '${value.toInt()}k'
          : '${value.toStringAsFixed(0)}k';
    }
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('词典管理'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '词典启用'),
              Tab(text: '词典来源'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDictionaryManagementTab(),
            _buildSettingsAndSubscriptionTab(),
          ],
        ),
        bottomSheet: const DownloadProgressPanel(),
      ),
    );
  }

  /// Tab1: 词典启用 - 按语言分组
  Widget _buildDictionaryManagementTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allDictionaries.isEmpty) {
      return _buildEmptyState();
    }

    // 获取所有源语言
    final languages =
        _allDictionaries.map((d) => d.sourceLanguage).toSet().toList()..sort();

    if (languages.isEmpty) {
      return _buildEmptyState();
    }

    return DefaultTabController(
      length: languages.length,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: languages
                  .map((lang) => Tab(text: lang.toUpperCase()))
                  .toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: languages.map((lang) {
                final dicts = _allDictionaries
                    .where((d) => d.sourceLanguage == lang)
                    .toList();
                return _buildLanguageDictionaryList(dicts);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageDictionaryList(List<DictionaryMetadata> dicts) {
    final enabledDicts = dicts
        .where((d) => _enabledDictionaryIds.contains(d.id))
        .toList();
    // 按照全局启用列表的顺序排序
    enabledDicts.sort((a, b) {
      final indexA = _enabledDictionaryIds.indexOf(a.id);
      final indexB = _enabledDictionaryIds.indexOf(b.id);
      return indexA.compareTo(indexB);
    });

    final disabledDicts = dicts
        .where((d) => !_enabledDictionaryIds.contains(d.id))
        .toList();

    return CustomScrollView(
      slivers: [
        // 已启用词典（可排序）
        if (enabledDicts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '已启用（长按拖动排序）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${enabledDicts.length} 个',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildReorderableList(enabledDicts),
          ),
        ],

        // 已禁用词典
        if (disabledDicts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: Colors.grey[600], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '已禁用',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${disabledDicts.length} 个',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildDictionaryCard(disabledDicts[index]),
                childCount: disabledDicts.length,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  /// Tab2: 在线订阅 - 包含本地目录设置、订阅网址、在线词典列表
  Widget _buildSettingsAndSubscriptionTab() {
    return CustomScrollView(
      slivers: [
        // 本地目录设置
        SliverToBoxAdapter(child: _buildCurrentDirectoryCard()),

        // 在线订阅设置
        SliverToBoxAdapter(child: _buildOnlineSubscriptionCard()),

        // 在线词典列表标题
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '在线词典列表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoadingOnline)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_onlineDictionaries.isNotEmpty)
                  Text(
                    '${_onlineDictionaries.length} 个',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),

        // 错误提示
        if (_onlineError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                color: Colors.red[50],
                child: ListTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text('加载失败', style: TextStyle(color: Colors.red[700])),
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
                      '暂无在线词典',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '设置订阅地址后点击刷新按钮',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    );
  }

  Widget _buildCurrentDirectoryCard() {
    return FutureBuilder<String>(
      future: _dictManager.baseDirectory,
      builder: (context, snapshot) {
        final directory = snapshot.data ?? '加载中...';

        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('本地词典目录'),
            subtitle: Text(
              directory,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _selectDictionaryDirectory,
              tooltip: '更改目录',
            ),
          ),
        );
      },
    );
  }

  Widget _buildOnlineSubscriptionCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '在线订阅地址',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://easydict.org',
                prefixIcon: const Icon(Icons.language),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: _saveOnlineSubscriptionUrl,
                      tooltip: '保存',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _isLoadingOnline
                          ? null
                          : _loadOnlineDictionaries,
                      tooltip: '刷新列表',
                    ),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '设置订阅地址后可查看和下载在线词典',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('还没有词典', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '切换到"在线订阅"Tab设置订阅地址\n或点击右下角的商店按钮浏览在线词典',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableList(List<DictionaryMetadata> dictionaries) {
    return ReorderableSliverList(
      onReorder: _onReorder,
      delegate: ReorderableSliverChildBuilderDelegate(
        (context, index) => _buildDictionaryCard(dictionaries[index]),
        childCount: dictionaries.length,
      ),
    );
  }

  Widget _buildDictionaryCard(DictionaryMetadata metadata) {
    final isEnabled = _isEnabled(metadata.id);
    final hasOnlineSubscription = _hasOnlineSubscription(metadata.id);
    final isLinkedOnline = _isLinkedOnline(metadata.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          children: [
            FutureBuilder<String?>(
              future: _dictManager.getLogoPath(metadata.id),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return CircleAvatar(
                    backgroundImage: FileImage(File(snapshot.data!)),
                    child: null,
                  );
                }
                return CircleAvatar(
                  child: Text(metadata.name[0].toUpperCase()),
                );
              },
            ),
            // 在线订阅链接状态指示器（小绿灯）
            if (hasOnlineSubscription && isLinkedOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        title: Text(metadata.name),
        subtitle: Text(
          '版本: ${metadata.version} | ${metadata.sourceLanguage} → ${metadata.targetLanguages.join(", ")}',
        ),
        trailing: Switch(
          value: isEnabled,
          onChanged: (_) => _toggleDictionary(metadata.id),
        ),
        onTap: () => _showDictionaryDetails(metadata),
      ),
    );
  }

  void _toggleDictionaryLink(String dictId) {
    setState(() {
      final index = _onlineDictionaries.indexWhere((d) => d.id == dictId);
      if (index != -1) {
        _onlineDictionaries[index] = _onlineDictionaries[index].copyWith(
          isLinked: !_onlineDictionaries[index].isLinked,
        );
      }
    });
    // TODO: 保存链接状态到本地存储
  }

  Future<void> _toggleDictionaryLinkWithSave(String dictId) async {
    setState(() {
      final index = _onlineDictionaries.indexWhere((d) => d.id == dictId);
      if (index != -1) {
        _onlineDictionaries[index] = _onlineDictionaries[index].copyWith(
          isLinked: !_onlineDictionaries[index].isLinked,
        );
      }
    });
    // TODO: 保存链接状态到本地存储
  }

  /// 显示下载选项对话框
  Future<DownloadOptionsResult?> _showDownloadOptionsDialog(
    RemoteDictionary dict,
  ) async {
    // 默认全选
    bool includeMetadata = true;
    bool includeLogo = true;
    bool includeDb = dict.hasDatabase;
    bool includeMedia = dict.hasAudios || dict.hasImages;

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
                      '下载: ${dict.name}',
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
                    const Text(
                      '选择要下载的内容:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      dense: true,
                      title: const Text('metadata.json'),
                      subtitle: const Text('[必选]词典元数据'),
                      secondary: const Icon(
                        Icons.description,
                        color: Colors.grey,
                      ),
                      value: includeMetadata,
                      onChanged: (value) {
                        setState(() {
                          includeMetadata = value ?? false;
                        });
                      },
                    ),
                    if (dict.hasLogo)
                      CheckboxListTile(
                        dense: true,
                        title: const Text('logo.png'),
                        subtitle: const Text('[必选]词典图标'),
                        secondary: const Icon(Icons.image, color: Colors.grey),
                        value: includeLogo,
                        onChanged: (value) {
                          setState(() {
                            includeLogo = value ?? false;
                          });
                        },
                      ),
                    if (dict.hasDatabase)
                      CheckboxListTile(
                        dense: true,
                        title: const Text('dictionary.db'),
                        subtitle: Text(
                          '[必选]词典数据库${dict.formattedDictSize.isNotEmpty ? '（${dict.formattedDictSize}）' : ''}',
                        ),
                        secondary: const Icon(
                          Icons.storage,
                          color: Colors.blue,
                        ),
                        value: includeDb,
                        onChanged: (value) {
                          setState(() {
                            includeDb = value ?? false;
                          });
                        },
                      ),
                    if (dict.hasAudios || dict.hasImages)
                      CheckboxListTile(
                        dense: true,
                        title: const Text('media.db'),
                        subtitle: Text(
                          '媒体数据库${dict.formattedMediaSize.isNotEmpty ? '（${dict.formattedMediaSize}）' : ''}',
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
                  child: const Text('取消'),
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
                  label: const Text('开始下载'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 开始下载词典
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
        await _refreshLocalDictionaries();
      },
      onError: (error) async {
        if (!mounted) return;
        await _refreshLocalDictionaries();
      },
    );

    _scrollToBottomSheet();
  }

  Future<void> _refreshLocalDictionaries() async {
    final allDicts = await _dictManager.getAllDictionariesMetadata();
    final enabledIds = await _dictManager.getEnabledDictionaries();

    setState(() {
      _allDictionaries = allDicts;
      _enabledDictionaryIds = enabledIds;
    });
  }

  void _scrollToBottomSheet() {
    final controller = PrimaryScrollController.of(context);
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildOnlineDictionaryCard(RemoteDictionary dict) {
    final baseUrl = _urlController.text.trim();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showOnlineDictionaryDetails(dict),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: dict.hasLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _OnlineDictionaryLogo(dict: dict, baseUrl: baseUrl),
                  )
                : Icon(Icons.cloud, color: colorScheme.primary),
          ),
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
                Icon(
                  Icons.update,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  dict.isDownloaded ? Icons.update : Icons.download,
                  color: colorScheme.primary,
                ),
                tooltip: dict.isDownloaded ? '更新词典' : '下载词典',
                onPressed: () => _startDownload(dict),
              ),
              IconButton(
                icon: Icon(
                  dict.isLinked ? Icons.link : Icons.link_off,
                  color: dict.isLinked
                      ? colorScheme.primary
                      : colorScheme.outline,
                ),
                tooltip: dict.isLinked ? '已链接' : '未链接',
                onPressed: () => _toggleDictionaryLinkWithSave(dict.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 格式化更新时间
  String _formatUpdateTime(DateTime? dateTime) {
    if (dateTime == null) return '未知';
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}年前';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _showOnlineDictionaryDetails(RemoteDictionary dict) {
    final baseUrl = _urlController.text.trim();

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
                    child: dict.hasLogo
                        ? _OnlineDictionaryLogo(
                            dict: dict,
                            baseUrl: baseUrl,
                            size: 100,
                          )
                        : Icon(
                            Icons.book,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildDetailItem('ID', dict.id),
              _buildDetailItem('版本', dict.version),
              _buildDetailItem('语言', dict.language),
              _buildDetailItem('作者', dict.author),
              _buildDetailItem('词条数', _formatLargeNumber(dict.entryCount)),
              _buildDetailItem('数据库大小', dict.formattedDatabaseSize),
              const SizedBox(height: 16),
              const Text('简介', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dict.description),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (dict.hasDatabase)
                    const Chip(
                      avatar: Icon(Icons.storage, size: 16),
                      label: Text('包含数据库'),
                    ),
                  if (dict.hasAudios || dict.hasImages)
                    Chip(
                      avatar: const Icon(Icons.library_music, size: 16),
                      label: Text(
                        '包含媒体 (${_formatLargeNumber(dict.audioCount + dict.imageCount)})',
                      ),
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
          if (!dict.isDownloaded && !dict.isDownloading)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _startDownload(dict);
              },
              icon: const Icon(Icons.download),
              label: const Text('下载'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
}

/// 词典详情页面
class DictionaryDetailPage extends StatefulWidget {
  final DictionaryMetadata metadata;

  const DictionaryDetailPage({super.key, required this.metadata});

  @override
  State<DictionaryDetailPage> createState() => _DictionaryDetailPageState();
}

class _DictionaryDetailPageState extends State<DictionaryDetailPage> {
  DictionaryStats? _stats;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await DictionaryManager().getDictionaryStats(
        widget.metadata.id,
      );
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;

    return Scaffold(
      appBar: AppBar(title: Text(metadata.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 词典图标和基本信息
            _buildHeader(metadata),
            const SizedBox(height: 24),

            // 统计信息
            _buildStatsSection(),
            const SizedBox(height: 24),

            // 详细信息
            _buildInfoSection(metadata),
            const SizedBox(height: 24),

            // 文件信息
            _buildFilesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DictionaryMetadata metadata) {
    return Row(
      children: [
        FutureBuilder<String?>(
          future: DictionaryManager().getLogoPath(metadata.id),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(snapshot.data!),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildDefaultIcon(metadata);
                  },
                ),
              );
            }
            return _buildDefaultIcon(metadata);
          },
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metadata.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '版本 ${metadata.version}',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildLanguageChip(metadata.sourceLanguage, isSource: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16),
                  ),
                  ...metadata.targetLanguages.map(
                    (lang) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _buildLanguageChip(lang, isSource: false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultIcon(DictionaryMetadata metadata) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          metadata.name.isNotEmpty ? metadata.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageChip(String language, {required bool isSource}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSource ? Colors.blue[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSource ? Colors.blue[200]! : Colors.green[200]!,
        ),
      ),
      child: Text(
        language.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isSource ? Colors.blue[700] : Colors.green[700],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stats == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '统计信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    label: '词条数',
                    value: '${_stats!.entryCount}',
                    onTap: _stats!.entryCount > 0
                        ? () => _showEntriesList(widget.metadata.id)
                        : null,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: '音频文件',
                    value: '${_stats!.audioCount}',
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    label: '图片文件',
                    value: '${_stats!.imageCount}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final child = Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  Future<void> _showEntriesList(String dictId) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return EntriesListSheet(dictId: dictId);
      },
    );
  }

  Widget _buildInfoSection(DictionaryMetadata metadata) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '词典信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (metadata.description.isNotEmpty) ...[
              Text(metadata.description, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
            ],
            _buildInfoRow(Icons.fingerprint, 'ID', metadata.id),
            _buildInfoRow(Icons.business, '发布者', metadata.publisher),
            _buildInfoRow(Icons.person, '维护者', metadata.maintainer),
            if (metadata.contactMaintainer != null &&
                metadata.contactMaintainer!.isNotEmpty)
              _buildInfoRow(
                Icons.contact_mail,
                '联系维护者',
                metadata.contactMaintainer!,
              ),
            if (metadata.repository != null && metadata.repository!.isNotEmpty)
              _buildInfoRow(Icons.link, '仓库', metadata.repository!),
            _buildInfoRow(
              Icons.calendar_today,
              '创建时间',
              _formatDate(metadata.createdAt),
            ),
            _buildInfoRow(
              Icons.update,
              '更新时间',
              _formatDate(metadata.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '文件信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<Map<String, dynamic>>(
              future: _getFileInfo(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) {
                  return const Text('无法获取文件信息');
                }

                final info = snapshot.data!;
                return Column(
                  children: [
                    _buildFileInfoRow(
                      'metadata.json',
                      info['hasMetadata'] == true ? '存在' : '缺失',
                      info['hasMetadata'] == true,
                    ),
                    _buildFileInfoRow(
                      'logo.png',
                      info['hasLogo'] == true ? '存在' : '缺失',
                      info['hasLogo'] == true,
                    ),
                    _buildFileInfoRow(
                      'dictionary.db',
                      info['hasDatabase'] == true ? '存在' : '缺失',
                      info['hasDatabase'] == true,
                    ),
                    if (info['hasAudios'] == true || info['hasImages'] == true)
                      _buildFileInfoRow('media.db', '存在', true),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileInfoRow(String filename, String status, bool exists) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            exists ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: exists ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(filename)),
          Text(
            status,
            style: TextStyle(
              color: exists ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _getFileInfo() async {
    final dictManager = DictionaryManager();
    final dictId = widget.metadata.id;

    return {
      'hasMetadata': await dictManager.hasMetadataFile(dictId),
      'hasLogo': await dictManager.hasLogoFile(dictId),
      'hasDatabase': await dictManager.hasDatabaseFile(dictId),
      'hasAudios': await dictManager.hasAudiosZip(dictId),
      'hasImages': await dictManager.hasImagesZip(dictId),
    };
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _OnlineDictionaryLogo extends StatefulWidget {
  final RemoteDictionary dict;
  final String baseUrl;
  final double size;

  const _OnlineDictionaryLogo({
    required this.dict,
    required this.baseUrl,
    this.size = 48,
  });

  @override
  State<_OnlineDictionaryLogo> createState() => _OnlineDictionaryLogoState();
}

class _OnlineDictionaryLogoState extends State<_OnlineDictionaryLogo> {
  Future<Uint8List?>? _logoFuture;

  @override
  void initState() {
    super.initState();
    _logoFuture = _fetchLogo();
  }

  Future<Uint8List?> _fetchLogo() async {
    final dictManager = DictionaryManager();
    final dictId = widget.dict.id;

    try {
      final localExists = await dictManager.dictionaryExists(dictId);
      if (localExists) {
        final logoPath = await dictManager.getLogoPath(dictId);
        if (logoPath != null) {
          final file = File(logoPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              Logger.d(
                '使用本地Logo: $logoPath (${bytes.length} bytes)',
                tag: 'DictionaryManagerPage',
              );
              return bytes;
            }
          }
        }
      }
    } catch (e) {
      Logger.e('读取本地Logo失败: $e', tag: 'DictionaryManagerPage');
    }

    final url = widget.dict.getLogoUrl(widget.baseUrl);
    try {
      Logger.d('开始加载Logo: $url', tag: 'DictionaryManagerPage');
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'EasyDict/1.0.0'},
      );

      if (response.statusCode == 200) {
        Logger.d(
          'Logo加载成功: ${response.bodyBytes.length} bytes',
          tag: 'DictionaryManagerPage',
        );
        return response.bodyBytes;
      } else {
        Logger.e(
          'Logo加载失败 HTTP ${response.statusCode}: $url',
          tag: 'DictionaryManagerPage',
        );
        return null;
      }
    } catch (e) {
      Logger.e('Logo请求异常: $e', tag: 'DictionaryManagerPage');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _logoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: widget.size,
            height: widget.size,
            color: Colors.grey[200],
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              Logger.e('Logo渲染失败: $error', tag: 'DictionaryManagerPage');
              return Icon(
                Icons.cloud,
                color: Colors.blue,
                size: widget.size * 0.6,
              );
            },
          );
        }

        return Icon(Icons.cloud, color: Colors.blue, size: widget.size * 0.6);
      },
    );
  }
}

class DownloadProgressPanel extends StatelessWidget {
  const DownloadProgressPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadManager = context.watch<DownloadManager>();
    final currentTask = downloadManager.currentDownload;

    if (currentTask == null ||
        currentTask.state == DownloadState.completed ||
        currentTask.state == DownloadState.idle) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isError = currentTask.state == DownloadState.error;
    final isCancelled = currentTask.state == DownloadState.cancelled;

    final statusText = currentTask.totalFiles > 0
        ? (currentTask.status.startsWith(
                '[${currentTask.fileIndex}/${currentTask.totalFiles}]',
              )
              ? currentTask.status
              : '[${currentTask.fileIndex}/${currentTask.totalFiles}] ${currentTask.status}')
        : currentTask.status;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentTask.dictName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
            if (currentTask.currentFileName != null &&
                !isError &&
                !isCancelled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: currentTask.fileProgress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isError ? colorScheme.error : colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(currentTask.fileProgress * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (currentTask.speedBytesPerSecond > 0 &&
                  !isError &&
                  !isCancelled) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      downloadManager.formatSpeed(
                        currentTask.speedBytesPerSecond,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
