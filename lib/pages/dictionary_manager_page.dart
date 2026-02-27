import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'entries_list_sheet.dart';
import 'cloud_service_page.dart'
    show PushUpdatesDialog, UploadDictionaryDialog, EditDictionaryDialog;
import '../services/dictionary_manager.dart';
import '../services/dictionary_store_service.dart';
import '../services/download_manager.dart';
import '../services/font_loader_service.dart';
import '../services/user_dicts_service.dart';
import '../services/auth_service.dart';
import '../services/zstd_service.dart';
import '../services/dict_update_check_service.dart';
import '../data/models/dictionary_metadata.dart';
import '../data/models/remote_dictionary.dart';
import '../data/models/user_dictionary.dart' hide DictionaryEntry;
import '../data/models/user_dictionary.dart' as user_dict;
import '../data/database_service.dart' hide DictionaryEntry;
import '../data/database_service.dart' as db_service;
import '../core/logger.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/toast_utils.dart';
import 'package:path/path.dart' as path;
import '../components/global_scale_wrapper.dart';
import '../components/transfer_progress_panel.dart';
import '../services/external_storage_service.dart';
import 'package:permission_handler/permission_handler.dart';

class DictionaryManagerPage extends StatefulWidget {
  const DictionaryManagerPage({super.key});

  @override
  State<DictionaryManagerPage> createState() => _DictionaryManagerPageState();
}

class _DictionaryManagerPageState extends State<DictionaryManagerPage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final UserDictsService _userDictsService = UserDictsService();

  List<DictionaryMetadata> _allDictionaries = [];
  List<String> _enabledDictionaryIds = [];
  List<RemoteDictionary> _onlineDictionaries = [];
  bool _isLoading = true;
  bool _isLoadingOnline = false;
  String? _onlineError;
  DictionaryStoreService? _storeService;

  // 创作者中心相关状态
  final AuthService _authService = AuthService();
  bool _isLoggedIn = false;
  List<UserDictionary> _userDictionaries = [];
  bool _isLoadingUserDicts = false;
  String? _userDictsError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeService?.dispose();
    _userDictsService.dispose();
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
        _storeService = DictionaryStoreService(baseUrl: url);
        _userDictsService.setBaseUrl(url);
        _authService.setBaseUrl(url);
        // 设置 DownloadManager 的服务
        final downloadManager = context.read<DownloadManager>();
        downloadManager.setStoreService(_storeService!);
      }

      setState(() {
        _allDictionaries = allDicts;
        _enabledDictionaryIds = enabledIds;
        _isLoading = false;
      });

      // 如果有在线订阅，加载在线词典列表
      if (_storeService != null) {
        _loadOnlineDictionaries();
        _checkLoginAndLoadUserDicts();
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

  Future<void> _selectDictionaryDirectory() async {
    if (!Platform.isAndroid) {
      // 非 Android 平台：直接打开目录选择器
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) {
        await _dictManager.setBaseDirectory(dir);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, '词典目录已设置: $dir');
      }
      return;
    }

    // ── Android 平台 ──────────────────────────────────────────
    final extService = ExternalStorageService();
    final hasPermission = await extService.hasManageStoragePermission();
    final extDir = await getExternalStorageDirectory();
    final appSpecificDir = extDir != null
        ? path.join(extDir.path, 'dictionaries')
        : path.join((await getApplicationDocumentsDirectory()).path, 'easydict');

    if (!mounted) return;

    // 弹出 Android 专属选择对话框
    final result = await _showAndroidDirPickerDialog(
      appSpecificDir: appSpecificDir,
      hasPermission: hasPermission,
    );
    if (result == null || !mounted) return; // 用户取消

    final int choice = result['choice'] as int; // 0=应用专属, 1=外部持久, 2=自定义

    // ── 需要权限时，先申请 ──────────────────────────────────
    if (choice >= 1 && !hasPermission) {
      // 显示权限说明对话框
      final goRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要文件访问权限'),
          content: const Text(
            '访问外部目录需要「所有文件访问」权限。\n\n'
            '点击「去授权」后，系统将跳转到设置页面，'
            '请在「管理所有文件」中找到本应用并开启权限，'
            '然后返回应用即可生效。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (goRequest != true || !mounted) return;

      final status = await extService.requestManageStoragePermission();
      if (!status.isGranted) {
        if (mounted) {
          showToast(context, '未获得文件访问权限，操作已取消');
        }
        return;
      }
    }

    // ── 处理各选项 ──────────────────────────────────────────
    switch (choice) {
      case 0: // 应用专属目录
        await _dictManager.setBaseDirectory(appSpecificDir);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, '词典目录已设置: $appSpecificDir');

      case 1: // 外部公共目录（默认持久路径）
        final targetDir = ExternalStorageService.defaultPersistentDir;
        final ok = await extService.isPathWritable(targetDir);
        if (!ok) {
          if (mounted) showToast(context, '无法写入 $targetDir，请检查权限');
          return;
        }
        await _dictManager.setBaseDirectory(targetDir);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, '词典目录已设置: $targetDir');

      case 2: // 自定义路径
        final picked = await FilePicker.platform.getDirectoryPath(
          initialDirectory: ExternalStorageService.defaultPersistentDir,
        );
        if (picked == null || !mounted) return;
        final ok = await extService.isPathWritable(picked);
        if (!ok) {
          if (mounted) showToast(context, '无法写入所选目录，请重新选择');
          return;
        }
        await _dictManager.setBaseDirectory(picked);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, '词典目录已设置: $picked');
    }
  }

  /// Android 专属词典目录选择对话框。
  /// 返回 `{'choice': int}` 或 `null`（取消）。
  Future<Map<String, dynamic>?> _showAndroidDirPickerDialog({
    required String appSpecificDir,
    required bool hasPermission,
  }) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        int _selected = 1; // 默认推荐「外部持久目录」
        final colorScheme = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            Widget _permBadge() {
              if (hasPermission) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      '权限已授予',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '需申请「所有文件访问」权限',
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('词典存储位置'),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 选项 0：应用专属目录 ───────────────────
                    RadioListTile<int>(
                      value: 0,
                      groupValue: _selected,
                      onChanged: (v) => setLocalState(() => _selected = v!),
                      title: const Text('应用专属目录'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appSpecificDir,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '卸载应用后词典数据将被删除',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),

                    const Divider(height: 8),

                    // ── 选项 1：外部持久目录（推荐）───────────────
                    RadioListTile<int>(
                      value: 1,
                      groupValue: _selected,
                      onChanged: (v) => setLocalState(() => _selected = v!),
                      title: Row(
                        children: [
                          const Text('外部公共目录'),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '推荐',
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ExternalStorageService.defaultPersistentDir,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 13,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  '卸载或更新应用后词典仍可保留',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          _permBadge(),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),

                    const Divider(height: 8),

                    // ── 选项 2：自定义路径 ─────────────────────
                    RadioListTile<int>(
                      value: 2,
                      groupValue: _selected,
                      onChanged: (v) => setLocalState(() => _selected = v!),
                      title: const Text('自定义路径'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '手动选择任意外部目录',
                            style: TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          _permBadge(),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),

                    if (_selected >= 1 && !hasPermission) ...
                      [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '点击「确定」后系统将跳转到设置页面，'
                                  '请开启「管理所有文件」权限后返回应用。',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, {'choice': _selected}),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
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
    final scale = FontLoaderService().getDictionaryContentScale();
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final updateCount = updateCheckService.updatableCount;

    final content = DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('词典管理'),
          bottom: TabBar(
            tabs: [
              const Tab(text: '词典排序'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('词典来源'),
                    if (updateCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$updateCount',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onError,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: '创作者中心'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDictionaryManagementTab(),
            _buildSettingsAndSubscriptionTab(),
            _buildCreatorCenterTab(),
          ],
        ),
        bottomSheet: const DownloadProgressPanel(),
      ),
    );

    if (scale == 1.0) {
      return content;
    }

    return PageScaleWrapper(child: content);
  }

  /// Tab1: 词典牌序 - 按语言分组
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
                  .map(
                    (lang) =>
                        Tab(text: LanguageUtils.getLanguageDisplayName(lang)),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: languages.map((lang) {
                final dicts = _allDictionaries
                    .where((d) => d.sourceLanguage == lang)
                    .toList();
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: _buildLanguageDictionaryList(dicts),
                  ),
                );
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

  /// Tab2: 词典来源 - 包含本地目录设置、在线词典列表
  Widget _buildSettingsAndSubscriptionTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: CustomScrollView(
          slivers: [
            // 本地目录设置
            SliverToBoxAdapter(child: _buildCurrentDirectoryCard()),

            // 在线词典列表标题
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    // const Icon(Icons.cloud, color: Colors.blue, size: 20),
                    const SizedBox(width: 4),
                    const Text(
                      '在线词典列表',
                      style: TextStyle(
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
                          '${_onlineDictionaries.length} 个',
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
                        '加载失败',
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
                          '暂无在线词典',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请先在"设置 - 云服务"中配置订阅地址',
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

  /// Tab3: 创作者中心
  Widget _buildCreatorCenterTab() {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_isLoggedIn)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 48,
                                      color: colorScheme.outline,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '请先在"词典来源"页面配置云服务并登录',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (_isLoadingUserDicts)
                          const Center(child: CircularProgressIndicator())
                        else if (_userDictsError != null)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: colorScheme.error,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '加载失败',
                                    style: TextStyle(color: colorScheme.error),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _userDictsError!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _loadUserDictionaries,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_userDictionaries.isEmpty)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.library_books_outlined,
                                      size: 48,
                                      color: colorScheme.outline,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '暂无上传的词典',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else ...[
                          ..._userDictionaries.map(
                            (dict) => _buildCreatorCenterDictionaryCard(
                              dict,
                              colorScheme,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isLoggedIn && !_isLoadingUserDicts && _userDictsError == null)
          Positioned(
            right: 16,
            bottom: 80,
            child: FloatingActionButton(
              onPressed: _showUploadDialog,
              child: const Icon(Icons.add),
            ),
          ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: UploadProgressPanel(),
        ),
      ],
    );
  }

  void _checkLoginAndLoadUserDicts() async {
    final url = await _dictManager.onlineSubscriptionUrl;
    if (url.isNotEmpty) {
      _authService.setBaseUrl(url);
      _userDictsService.setBaseUrl(url);
      final isLoggedIn = _authService.isLoggedIn;
      if (mounted) {
        setState(() {
          _isLoggedIn = isLoggedIn;
        });
        if (isLoggedIn) {
          _loadUserDictionaries();
        }
      }
    }
  }

  Future<void> _loadUserDictionaries() async {
    if (_storeService == null) return;

    setState(() {
      _isLoadingUserDicts = true;
      _userDictsError = null;
    });

    try {
      final dicts = await _userDictsService.fetchUserDicts();
      if (mounted) {
        setState(() {
          _userDictionaries = dicts;
          _isLoadingUserDicts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userDictsError = e.toString();
          _isLoadingUserDicts = false;
        });
      }
    }
  }

  Widget _buildCreatorCenterDictionaryCard(
    UserDictionary dict,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dict.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '更新于 ${_formatDateTime(dict.updatedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showEditFilesDialog(dict),
                  icon: Icon(Icons.swap_horiz, color: colorScheme.primary),
                  tooltip: '替换文件',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _showPushUpdatesDialog(dict),
                  icon: Icon(
                    Icons.cloud_upload_outlined,
                    color: colorScheme.primary,
                  ),
                  tooltip: '推送更新',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _handleDeleteDictionary(dict),
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Future<void> _handleDeleteDictionary(UserDictionary dict) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除词典 "${dict.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _userDictsService.deleteDictionary(dict.dictId);
      _loadUserDictionaries();
    }
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          UploadDictionaryDialog(onUploadSuccess: _loadUserDictionaries),
    );
  }

  void _showEditFilesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (context) => EditDictionaryDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onUpdateSuccess: _loadUserDictionaries,
      ),
    );
  }

  void _showPushUpdatesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (context) => PushUpdatesDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onPushSuccess: () {
          showToast(context, '推送更新成功');
        },
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
          '更新 ($updateCount)',
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
                  '发现 ${updateCheckService.updatableCount} 个词典有更新',
                );
              } else if (mounted) {
                showToast(context, '所有词典已是最新版本');
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
      label: Text(isChecking ? '检查中...' : '检查更新'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showBatchUpdateDialog(DictUpdateCheckService updateCheckService) {
    showDialog(
      context: context,
      builder: (context) => _BatchUpdateDialog(
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: FutureBuilder<String?>(
          future: _dictManager.getLogoPath(metadata.id),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return CircleAvatar(
                backgroundColor: Colors.transparent,
                backgroundImage: FileImage(File(snapshot.data!)),
                child: null,
              );
            }
            return CircleAvatar(child: Text(metadata.name[0].toUpperCase()));
          },
        ),
        title: Text(metadata.name),
        subtitle: Text(
          '${metadata.sourceLanguage} → ${metadata.targetLanguages.join(", ")}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: isEnabled,
          onChanged: (_) => _toggleDictionary(metadata.id),
        ),
        onTap: () => _showDictionaryDetails(metadata),
      ),
    );
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

  Future<void> _checkAndUpdateDictionary(RemoteDictionary dict) async {
    if (_storeService == null) {
      showToast(context, '请先配置云服务地址');
      return;
    }

    try {
      _dictManager.clearMetadataCache(dict.id);
      final metadata = await _dictManager.getDictionaryMetadata(dict.id);
      if (metadata == null) {
        showToast(context, '无法获取词典信息');
        return;
      }

      final currentVersion = metadata.version;
      Logger.d(
        '检查词典更新: ${dict.id}, 当前版本: $currentVersion',
        tag: 'DictionaryManagerPage',
      );

      final updateInfo = await _userDictsService.getDictUpdateInfo(
        dict.id,
        currentVersion,
      );

      Logger.d('更新信息: $updateInfo', tag: 'DictionaryManagerPage');
      if (updateInfo != null) {
        Logger.d(
          'from: ${updateInfo.from}, to: ${updateInfo.to}, files: ${updateInfo.required.files}, entries: ${updateInfo.required.entries}',
          tag: 'DictionaryManagerPage',
        );
      }

      if (!mounted) return;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _DictUpdateDialog(
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
      showToast(context, '更新失败: $e');
      Logger.e('更新词典失败: $e', tag: 'DictionaryManager');
    }
  }

  Future<void> _executeSmartUpdate(
    RemoteDictionary dict,
    user_dict.DictUpdateInfo updateInfo,
    DictionaryMetadata metadata,
  ) async {
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
            '[$currentStep/$totalSteps] 下载 $fileName',
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
                '[$currentStep/$totalSteps] 下载 $fileName',
                currentStep,
                totalSteps,
                receivedBytes: (event['receivedBytes'] as num).toInt(),
                totalBytes: (event['totalBytes'] as num).toInt(),
                fileProgress: (event['progress'] as num).toDouble(),
                speedBytesPerSecond:
                    (event['speedBytesPerSecond'] as num).toInt(),
              );
            } else if (event['type'] == 'complete') {
              downloadOk = true;
            } else if (event['type'] == 'error') {
              throw Exception('下载文件失败: $fileName — ${event['error']}');
            }
          }
          if (!downloadOk) throw Exception('下载文件失败: $fileName');
        }

        if (updateInfo.required.entries.isNotEmpty) {
          currentStep++;
          onProgress(
            '[$currentStep/$totalSteps] 下载条目更新',
            currentStep,
            totalSteps,
          );

          final zstdData = await _userDictsService.downloadEntryUpdates(
            dict.id,
            updateInfo.required.entries,
          );

          if (zstdData == null) {
            throw Exception('下载条目更新失败');
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

        showToast(context, '更新成功');
        await _refreshLocalDictionaries();
      },
      onError: (error) {
        if (!mounted) return;
        showToast(context, '更新失败: $error');
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
      showToast(context, '没有选择要更新的文件');
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
          onProgress('[$step/$totalSteps] 下载 $fileName', step, totalSteps);

          final savePath = path.join(dictDir, fileName);
          bool downloadOk = false;
          await for (final event in _storeService!.downloadDictFileStream(
            dict.id,
            fileName,
            savePath,
          )) {
            if (event['type'] == 'progress') {
              onProgress(
                '[$step/$totalSteps] 下载 $fileName',
                step,
                totalSteps,
                receivedBytes: (event['receivedBytes'] as num).toInt(),
                totalBytes: (event['totalBytes'] as num).toInt(),
                fileProgress: (event['progress'] as num).toDouble(),
                speedBytesPerSecond:
                    (event['speedBytesPerSecond'] as num).toInt(),
              );
            } else if (event['type'] == 'complete') {
              downloadOk = true;
            } else if (event['type'] == 'error') {
              throw Exception('下载文件失败: $fileName — ${event['error']}');
            }
          }
          if (!downloadOk) throw Exception('下载文件失败: $fileName');
        }
      },
      onComplete: () async {
        if (!mounted) return;

        if (includeMetadata) {
          _dictManager.clearMetadataCache(dict.id);
        }

        showToast(context, '更新成功');
        await _refreshLocalDictionaries();
      },
      onError: (error) {
        if (!mounted) return;
        showToast(context, '更新失败: $error');
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
        await _dictManager.enableDictionary(dict.id);
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
    if (controller.hasClients) {
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
          tooltip: dict.isDownloaded ? '更新词典' : '下载词典',
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
}

class _DictUpdateDialog extends StatefulWidget {
  final String dictName;
  final String dictId;
  final user_dict.DictUpdateInfo? updateInfo;
  final DictionaryStoreService storeService;
  final DictionaryMetadata metadata;

  const _DictUpdateDialog({
    required this.dictName,
    required this.dictId,
    required this.updateInfo,
    required this.storeService,
    required this.metadata,
  });

  @override
  State<_DictUpdateDialog> createState() => _DictUpdateDialogState();
}

class _DictUpdateDialogState extends State<_DictUpdateDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _includeMetadata = false;
  bool _includeLogo = false;
  bool _includeDb = false;
  bool _includeMedia = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '更新词典 - ${widget.dictName}',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '智能更新'),
                Tab(text: '手动选择'),
              ],
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSmartUpdateTab(info, colorScheme),
                  _buildManualUpdateTab(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => _handleUpdate(info),
          icon: const Icon(Icons.update),
          label: const Text('开始更新'),
        ),
      ],
    );
  }

  Widget _buildSmartUpdateTab(
    user_dict.DictUpdateInfo? info,
    ColorScheme colorScheme,
  ) {
    if (info == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '已是最新版本',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '当前词典没有可用的更新',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (info.from == info.to ||
        (info.required.files.isEmpty && info.required.entries.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '已是最新版本',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '当前版本: v${info.to}',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'v${info.from} → v${info.to}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('更新历史:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ...info.history.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v${h.v}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(h.m)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('需要下载:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (info.required.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, size: 16),
                  const SizedBox(width: 4),
                  Text('文件: ${info.required.files.join(", ")}'),
                ],
              ),
            ),
          if (info.required.entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.list, size: 16),
                  const SizedBox(width: 4),
                  Text('条目: ${info.required.entries.length} 个'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManualUpdateTab(ColorScheme colorScheme) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                '选择要更新的内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                title: const Text('metadata.json'),
                subtitle: const Text('词典元数据'),
                secondary: const Icon(Icons.description, color: Colors.grey),
                value: _includeMetadata,
                onChanged: (value) {
                  setState(() {
                    _includeMetadata = value ?? false;
                  });
                },
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('logo.png'),
                subtitle: const Text('词典图标'),
                secondary: const Icon(Icons.image, color: Colors.grey),
                value: _includeLogo,
                onChanged: (value) {
                  setState(() {
                    _includeLogo = value ?? false;
                  });
                },
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('dictionary.db'),
                subtitle: const Text('词典数据库'),
                secondary: const Icon(Icons.storage, color: Colors.blue),
                value: _includeDb,
                onChanged: (value) {
                  setState(() {
                    _includeDb = value ?? false;
                  });
                },
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('media.db'),
                subtitle: const Text('媒体数据库'),
                secondary: const Icon(
                  Icons.library_music,
                  color: Colors.purple,
                ),
                value: _includeMedia,
                onChanged: (value) {
                  setState(() {
                    _includeMedia = value ?? false;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleUpdate(user_dict.DictUpdateInfo? info) {
    if (_tabController.index == 0) {
      if (info == null ||
          info.from == info.to ||
          (info.required.files.isEmpty && info.required.entries.isEmpty)) {
        showToast(context, '没有可用的智能更新');
        return;
      }
      Navigator.pop(context, {'type': 'smart'});
    } else {
      if (!_includeMetadata && !_includeLogo && !_includeDb && !_includeMedia) {
        showToast(context, '请至少选择一项要更新的内容');
        return;
      }
      Navigator.pop(context, {
        'type': 'manual',
        'includeMetadata': _includeMetadata,
        'includeLogo': _includeLogo,
        'includeDb': _includeDb,
        'includeMedia': _includeMedia,
      });
    }
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
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('词典详情'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(metadata),
                      const SizedBox(height: 28),

                      _buildStatsSection(),
                      const SizedBox(height: 28),

                      _buildInfoSection(metadata),
                      const SizedBox(height: 28),

                      _buildFilesSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(DictionaryMetadata metadata) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.3),
            colorScheme.secondaryContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          FutureBuilder<String?>(
            future: DictionaryManager().getLogoPath(metadata.id),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Hero(
                  tag: 'dict_logo_${metadata.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(snapshot.data!),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultIcon(metadata);
                      },
                    ),
                  ),
                );
              }
              return _buildDefaultIcon(metadata);
            },
          ),
          const SizedBox(width: 20),
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
                if (metadata.publisher.isNotEmpty) ...
                  [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            metadata.publisher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultIcon(DictionaryMetadata metadata) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          metadata.name.isNotEmpty ? metadata.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageChip(String language, {required bool isSource}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSourceColor = colorScheme.primary;
    final isTargetColor = colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (isSource ? isSourceColor : isTargetColor).withValues(alpha: 0.15),
            (isSource ? isSourceColor : isTargetColor).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isSource ? isSourceColor : isTargetColor).withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Text(
        language.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSource ? isSourceColor : isTargetColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '统计信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.text_fields,
                  label: '词条数',
                  value: '${_stats!.entryCount}',
                  color: colorScheme.primary,
                  onTap: _stats!.entryCount > 0
                      ? () => _showEntriesList(widget.metadata.id)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.music_note,
                  label: '音频文件',
                  value: '${_stats!.audioCount}',
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.image,
                  label: '图片文件',
                  value: '${_stats!.imageCount}',
                  color: colorScheme.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: child,
      );
    }

    return child;
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '词典信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 版本 + 更新时间: 简洁双列布局
          Row(
            children: [
              Expanded(
                child: _buildMetaChip(
                  icon: Icons.tag,
                  label: '版本',
                  value: 'v${metadata.version}',
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetaChip(
                  icon: Icons.update,
                  label: '更新',
                  value: _formatDate(metadata.updatedAt),
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 简介
          if (metadata.description.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                metadata.description,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // 发布者 / 维护者 / 联系方式
          if (metadata.publisher.isNotEmpty)
            _buildInfoRow(Icons.business_outlined, '发布者', metadata.publisher),
          if (metadata.maintainer.isNotEmpty &&
              metadata.maintainer != metadata.publisher)
            _buildInfoRow(Icons.person_outline, '维护者', metadata.maintainer),
          if (metadata.contactMaintainer != null &&
              metadata.contactMaintainer!.isNotEmpty)
            _buildInfoRow(
              Icons.contact_mail_outlined,
              '联系方式',
              metadata.contactMaintainer!,
            ),
          // ID: 置于底部，次要样式
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.fingerprint, size: 14, color: colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                'ID: ',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
              Expanded(
                child: Text(
                  metadata.id,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '文件信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<Map<String, dynamic>>(
            future: _getFileInfo(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData) {
                return Text(
                  '无法获取文件信息',
                  style: TextStyle(color: colorScheme.error),
                );
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
    );
  }

  Widget _buildFileInfoRow(String filename, String status, bool exists) {
    final colorScheme = Theme.of(context).colorScheme;
    final existsColor = Colors.green;
    final notExistsColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (exists ? existsColor : notExistsColor).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              exists ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: exists ? existsColor : notExistsColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filename,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (exists ? existsColor : notExistsColor).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: exists ? existsColor : notExistsColor,
              ),
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

class _BatchUpdateDialog extends StatefulWidget {
  final DictUpdateCheckService updateCheckService;
  final DictionaryManager dictManager;
  final DictionaryStoreService? storeService;
  final UserDictsService userDictsService;
  final VoidCallback onComplete;

  const _BatchUpdateDialog({
    required this.updateCheckService,
    required this.dictManager,
    required this.storeService,
    required this.userDictsService,
    required this.onComplete,
  });

  @override
  State<_BatchUpdateDialog> createState() => _BatchUpdateDialogState();
}

class _BatchUpdateDialogState extends State<_BatchUpdateDialog> {
  final Set<String> _selectedDictIds = {};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _selectedDictIds.addAll(widget.updateCheckService.updatableDicts.keys);
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await widget.updateCheckService.checkForUpdates();
      setState(() {
        _selectedDictIds.clear();
        _selectedDictIds.addAll(widget.updateCheckService.updatableDicts.keys);
      });
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updatableDicts = widget.updateCheckService.updatableDicts;

    return AlertDialog(
      title: Row(
        children: [
          const Text('批量更新词典'),
          const Spacer(),
          if (_isRefreshing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: '重新检查更新',
            ),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 400,
        child: _buildSelectionContent(colorScheme, updatableDicts),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedDictIds.isEmpty ? null : _startBatchUpdate,
          child: Text('更新 (${_selectedDictIds.length})'),
        ),
      ],
    );
  }

  Widget _buildSelectionContent(
    ColorScheme colorScheme,
    Map<String, user_dict.DictUpdateInfo> updatableDicts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '发现 ${updatableDicts.length} 个词典有更新',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedDictIds.length == updatableDicts.length) {
                    _selectedDictIds.clear();
                  } else {
                    _selectedDictIds.addAll(updatableDicts.keys);
                  }
                });
              },
              child: Text(
                _selectedDictIds.length == updatableDicts.length
                    ? '取消全选'
                    : '全选',
              ),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: updatableDicts.length,
            itemBuilder: (context, index) {
              final entry = updatableDicts.entries.elementAt(index);
              final dictId = entry.key;
              final info = entry.value;
              final isSelected = _selectedDictIds.contains(dictId);

              return CheckboxListTile(
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedDictIds.add(dictId);
                    } else {
                      _selectedDictIds.remove(dictId);
                    }
                  });
                },
                title: Text(dictId),
                subtitle: Text(
                  'v${info.from} → v${info.to} | ${info.required.files.length} 个文件',
                ),
                secondary: Text(
                  '${info.history.length} 条更新',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startBatchUpdate() async {
    if (_selectedDictIds.isEmpty) return;

    final downloadManager = context.read<DownloadManager>();
    final selectedDicts = widget.updateCheckService.updatableDicts.entries
        .where((e) => _selectedDictIds.contains(e.key))
        .toList();

    Navigator.pop(context);

    var successCount = 0;
    var failCount = 0;

    for (final entry in selectedDicts) {
      final dictId = entry.key;
      final updateInfo = entry.value;

      try {
        final metadata = await widget.dictManager.getDictionaryMetadata(dictId);
        if (metadata == null) {
          failCount++;
          continue;
        }

        final dictDir = await widget.dictManager.getDictionaryDir(dictId);
        final totalSteps =
            updateInfo.required.files.length +
            (updateInfo.required.entries.isNotEmpty ? 1 : 0);

        await downloadManager.startUpdate(
          dictId,
          dictId,
          (onProgress) async {
            var step = 0;

            for (final fileName in updateInfo.required.files) {
              step++;
              onProgress('[$step/$totalSteps] 下载 $fileName', step, totalSteps);

              final savePath = path.join(dictDir, fileName);
              bool downloadOk = false;
              await for (final event
                  in widget.storeService!.downloadDictFileStream(
                dictId,
                fileName,
                savePath,
              )) {
                if (event['type'] == 'progress') {
                  onProgress(
                    '[$step/$totalSteps] 下载 $fileName',
                    step,
                    totalSteps,
                    receivedBytes: (event['receivedBytes'] as num).toInt(),
                    totalBytes: (event['totalBytes'] as num).toInt(),
                    fileProgress: (event['progress'] as num).toDouble(),
                    speedBytesPerSecond:
                        (event['speedBytesPerSecond'] as num).toInt(),
                  );
                } else if (event['type'] == 'complete') {
                  downloadOk = true;
                } else if (event['type'] == 'error') {
                  throw Exception('下载文件失败: $fileName — ${event['error']}');
                }
              }
              if (!downloadOk) throw Exception('下载文件失败: $fileName');
            }

            if (updateInfo.required.entries.isNotEmpty) {
              step++;
              onProgress('[$step/$totalSteps] 下载条目更新', step, totalSteps);

              final zstdData = await widget.userDictsService
                  .downloadEntryUpdates(dictId, updateInfo.required.entries);

              if (zstdData == null) {
                throw Exception('下载条目更新失败');
              }

              final zstdDict = await widget.dictManager.getZstdDictionary(
                dictId,
              );
              final databaseService = db_service.DatabaseService();
              final zstdService = ZstdService();

              final decompressed = zstdService.decompress(zstdData, zstdDict);
              final jsonlContent = utf8.decode(decompressed);
              final lines = jsonlContent.split('\n');

              for (final line in lines) {
                if (line.trim().isEmpty) continue;
                final entryJson = jsonDecode(line) as Map<String, dynamic>;
                entryJson['dict_id'] = dictId;
                final entry = db_service.DictionaryEntry.fromJson(entryJson);
                await databaseService.insertOrUpdateEntry(entry);
              }
            }
          },
          onComplete: () async {
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

            await widget.dictManager.saveDictionaryMetadata(newMetadata);
            widget.updateCheckService.clearUpdate(dictId);
            successCount++;
          },
          onError: (error) {
            Logger.e('更新词典 $dictId 失败: $error', tag: 'BatchUpdate');
            failCount++;
          },
        );
      } catch (e) {
        Logger.e('更新词典 $dictId 异常: $e', tag: 'BatchUpdate');
        failCount++;
      }
    }

    widget.onComplete();
  }
}
