import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'entries_list_sheet.dart';
import 'cloud_service_page.dart'
    show
        PushUpdatesDialog,
        UploadDictionaryDialog,
        EditDictionaryDialog,
        UpdateJsonDialog;
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
import '../services/advanced_search_settings_service.dart';
import '../services/entry_event_bus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../i18n/strings.g.dart';

class DictionaryManagerPage extends StatefulWidget {
  const DictionaryManagerPage({super.key});

  @override
  State<DictionaryManagerPage> createState() => _DictionaryManagerPageState();
}

class _DictionaryManagerPageState extends State<DictionaryManagerPage> {
  final DictionaryManager _dictManager = DictionaryManager();
  final UserDictsService _userDictsService = UserDictsService();
  final AdvancedSearchSettingsService _advancedSettingsService =
      AdvancedSearchSettingsService();

  List<DictionaryMetadata> _allDictionaries = [];
  List<String> _enabledDictionaryIds = [];
  List<RemoteDictionary> _onlineDictionaries = [];
  bool _isLoading = true;
  bool _isLoadingOnline = false;
  String? _onlineError;
  DictionaryStoreService? _storeService;

  // 语言分组 tab 顺序（可拖拽排序）
  List<String> _languageOrder = [];
  String? _selectedDictLang;

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
    // 若后台下载仍在进行，不关闭 HTTP 客户端，让 DownloadManager 继续使用
    if (!DownloadManager().isDownloading) {
      _storeService?.dispose();
    }
    _userDictsService.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      // 加载本地词典
      final allDicts = await _dictManager.getAllDictionariesMetadata();
      final enabledIds = await _dictManager.getEnabledDictionaries();

      // 加载已保存的语言顺序
      final savedOrder = await _advancedSettingsService.getLanguageOrder();
      final allLangs = allDicts
          .map((d) => LanguageUtils.normalizeSourceLanguage(d.sourceLanguage))
          .toSet()
          .toList();
      final orderedLangs = AdvancedSearchSettingsService.sortLanguagesByOrder(
        allLangs,
        savedOrder,
      );

      // 加载在线订阅URL
      final url = await _dictManager.onlineSubscriptionUrl;
      if (url.isNotEmpty) {
        _storeService = DictionaryStoreService(baseUrl: url);
        _userDictsService.setBaseUrl(url);
        _authService.setBaseUrl(url);
        // 设置 DownloadManager 的服务并恢复未完成的下载
        final downloadManager = context.read<DownloadManager>();
        downloadManager.setStoreService(_storeService!);
        // 自动恢复未完成的下载任务
        downloadManager.resumeAllDownloads();
      }

      setState(() {
        _allDictionaries = allDicts;
        _enabledDictionaryIds = enabledIds;
        _languageOrder = orderedLangs;
        // 如果当前选中语言不在列表中，重置为空（会自动选首个）
        if (!orderedLangs.contains(_selectedDictLang)) {
          _selectedDictLang = null;
        }
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

  /// 保存语言显示顺序到持久化存储，并通知消费方页面刷新
  Future<void> _saveLanguageOrder() async {
    await _advancedSettingsService.setLanguageOrder(_languageOrder);
    EntryEventBus().emitLanguageOrderChanged();
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
        if (mounted) showToast(context, context.t.dict.dirSet(dir: dir));
      }
      return;
    }

    // ── Android 平台 ──────────────────────────────────────────
    final extService = ExternalStorageService();
    final hasPermission = await extService.hasManageStoragePermission();
    final extDir = await getExternalStorageDirectory();
    final appSpecificDir = extDir != null
        ? path.join(extDir.path, 'dictionaries')
        : path.join(
            (await getApplicationDocumentsDirectory()).path,
            'easydict',
          );

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
          title: Text(ctx.t.cloud.permissionTitle),
          content: Text(ctx.t.cloud.permissionBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.t.cloud.goAuthorize),
            ),
          ],
        ),
      );
      if (goRequest != true || !mounted) return;

      final status = await extService.requestManageStoragePermission();
      if (!status.isGranted) {
        if (mounted) {
          showToast(context, context.t.cloud.permissionDenied);
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
        if (mounted)
          showToast(context, context.t.dict.dirSet(dir: appSpecificDir));

      case 1: // 外部公共目录（默认持久路径）
        final targetDir = ExternalStorageService.defaultPersistentDir;
        final ok = await extService.isPathWritable(targetDir);
        if (!ok) {
          if (mounted)
            showToast(context, context.t.dict.cantWrite(dir: targetDir));
          return;
        }
        await _dictManager.setBaseDirectory(targetDir);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, context.t.dict.dirSet(dir: targetDir));

      case 2: // 自定义路径
        final picked = await FilePicker.platform.getDirectoryPath();
        if (picked == null || !mounted) return;
        final ok = await extService.isPathWritable(picked);
        if (!ok) {
          if (mounted) showToast(context, context.t.dict.cantWritePicked);
          return;
        }
        await _dictManager.setBaseDirectory(picked);
        _enabledDictionaryIds = [];
        await _loadSettings();
        if (mounted) showToast(context, context.t.dict.dirSet(dir: picked));
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
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ctx.t.dict.permissionGranted,
                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
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
                    ctx.t.dict.permissionNeeded,
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text(context.t.dict.androidChoiceTitle),
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
                      title: Text(context.t.dict.androidAppDir),
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
                                  context.t.dict.androidAppDirWarning,
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
                          Text(ctx.t.dict.androidExtDir),
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
                              ctx.t.dict.androidRecommended,
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
                              Expanded(
                                child: Text(
                                  ctx.t.dict.androidExtDirNote,
                                  style: const TextStyle(fontSize: 11),
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
                      title: Text(ctx.t.dict.androidCustomDir),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ctx.t.dict.androidCustomDirNote,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          _permBadge(),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),

                    if (_selected >= 1 && !hasPermission) ...[
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
                                ctx.t.dict.permissionDialogBody,
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
                  child: Text(ctx.t.common.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, {'choice': _selected}),
                  child: Text(ctx.t.common.ok),
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

  void _onReorder(int oldIndex, int newIndex, String language) {
    // 获取当前语言分组内的已启用词典
    final langDicts = _allDictionaries
        .where(
          (d) =>
              LanguageUtils.normalizeSourceLanguage(d.sourceLanguage) ==
              language,
        )
        .where((d) => _enabledDictionaryIds.contains(d.id))
        .toList();

    // 按照全局启用列表的顺序排序
    langDicts.sort((a, b) {
      final indexA = _enabledDictionaryIds.indexOf(a.id);
      final indexB = _enabledDictionaryIds.indexOf(b.id);
      return indexA.compareTo(indexB);
    });

    if (oldIndex < 0 || oldIndex >= langDicts.length) return;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > langDicts.length) newIndex = langDicts.length;

    // 在语言分组内移动
    final movedDictId = langDicts[oldIndex].id;
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;

    // 从全局列表中移除该词典
    _enabledDictionaryIds.remove(movedDictId);

    // 计算在全局列表中的插入位置
    if (targetIndex == 0) {
      // 插入到该语言分组的最前面
      // 找到该语言分组在全局列表中的第一个词典的位置
      final firstLangDictIndex = _enabledDictionaryIds.indexWhere(
        (id) => langDicts.any((d) => d.id == id),
      );
      if (firstLangDictIndex == -1) {
        _enabledDictionaryIds.insert(0, movedDictId);
      } else {
        _enabledDictionaryIds.insert(firstLangDictIndex, movedDictId);
      }
    } else if (targetIndex >= langDicts.length - 1) {
      // 插入到该语言分组的最后面
      // 找到该语言分组在全局列表中的最后一个词典的位置
      int lastLangDictIndex = -1;
      for (int i = _enabledDictionaryIds.length - 1; i >= 0; i--) {
        if (langDicts.any((d) => d.id == _enabledDictionaryIds[i])) {
          lastLangDictIndex = i;
          break;
        }
      }
      if (lastLangDictIndex == -1) {
        _enabledDictionaryIds.add(movedDictId);
      } else {
        _enabledDictionaryIds.insert(lastLangDictIndex + 1, movedDictId);
      }
    } else {
      // 插入到目标位置
      // 获取目标位置的词典ID（在移动前的列表中）
      final targetDictId = langDicts[targetIndex].id;
      final targetGlobalIndex = _enabledDictionaryIds.indexOf(targetDictId);
      if (targetGlobalIndex == -1) {
        _enabledDictionaryIds.add(movedDictId);
      } else {
        _enabledDictionaryIds.insert(targetGlobalIndex, movedDictId);
      }
    }

    setState(() {});
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
          title: Text(context.t.dict.title),
          bottom: TabBar(
            tabs: [
              Tab(text: context.t.dict.tabSort),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.t.dict.tabSource),
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
              Tab(text: context.t.dict.tabCreator),
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

  /// Tab1: 词典排序 - 按语言分组（语言 tab 本身支持长按拖动排序）
  Widget _buildDictionaryManagementTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allDictionaries.isEmpty) {
      return _buildEmptyState();
    }

    // 获取所有源语言（规范化后去重）
    final allLangs = _allDictionaries
        .map((d) => LanguageUtils.normalizeSourceLanguage(d.sourceLanguage))
        .toSet()
        .toList();

    // 按已保存顺序排序（新增语言追加到末尾）
    final displayLangs = AdvancedSearchSettingsService.sortLanguagesByOrder(
      allLangs,
      _languageOrder,
    );

    if (displayLangs.isEmpty) {
      return _buildEmptyState();
    }

    // 确定当前选中的语言
    final currentLang = displayLangs.contains(_selectedDictLang)
        ? _selectedDictLang!
        : displayLangs.first;

    return Column(
      children: [
        // 可拖动排序的语言 tab 栏
        Container(
          color: Theme.of(context).colorScheme.surface,
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final newOrder = List<String>.from(displayLangs);
                    final item = newOrder.removeAt(oldIndex);
                    newOrder.insert(newIndex, item);
                    setState(() {
                      _languageOrder = newOrder;
                    });
                    _saveLanguageOrder();
                  },
                  itemCount: displayLangs.length,
                  itemBuilder: (context, index) {
                    final lang = displayLangs[index];
                    final isSelected = lang == currentLang;
                    return ReorderableDragStartListener(
                      key: ValueKey(lang),
                      index: index,
                      child: InkWell(
                        onTap: () => setState(() => _selectedDictLang = lang),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              LanguageUtils.getDisplayName(lang, context.t),
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 长按拖动提示图标
              Tooltip(
                message: context.t.dict.dragHint,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.swap_horiz,
                    size: 18,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 当前语言的词典列表
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: _buildLanguageDictionaryList(
                _allDictionaries
                    .where(
                      (d) =>
                          LanguageUtils.normalizeSourceLanguage(
                            d.sourceLanguage,
                          ) ==
                          currentLang,
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
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
                  Text(
                    context.t.dict.enabled,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.t.dict.enabledCount(count: enabledDicts.length),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildReorderableList(
              enabledDicts,
              LanguageUtils.normalizeSourceLanguage(dicts.first.sourceLanguage),
            ),
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
                    context.t.dict.disabled,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.t.dict.disabledCount(count: disabledDicts.length),
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
                                      context.t.dict.noCreatorDictsHint,
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
                                    context.t.dict.loadFailed,
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
                                    label: Text(context.t.common.retry),
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
                                      context.t.dict.noCreatorDicts,
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

    if (!mounted) return;
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
    final metadata = _allDictionaries
        .where((m) => m.id == dict.dictId)
        .firstOrNull;
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
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  metadata != null ? 'v${metadata.version}' : '',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showUpdateJsonDialog(dict),
                  icon: Icon(Icons.data_object, color: colorScheme.primary),
                  tooltip: context.t.dict.tooltipUpdateJson,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _showPushUpdatesDialog(dict),
                  icon: Icon(
                    Icons.cloud_upload_outlined,
                    color: colorScheme.primary,
                  ),
                  tooltip: context.t.dict.tooltipPushUpdate,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _showEditFilesDialog(dict),
                  icon: Icon(Icons.swap_horiz, color: colorScheme.primary),
                  tooltip: context.t.dict.tooltipReplaceFile,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _handleDeleteDictionary(dict),
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  tooltip: context.t.dict.tooltipDelete,
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
        title: Text(context.t.dict.deleteConfirmTitle),
        content: Text(context.t.dict.deleteConfirmBody(name: dict.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _userDictsService.deleteDictionary(dict.dictId);
        _loadUserDictionaries();
        if (mounted) showToast(context, context.t.dict.deleteSuccess);
      } catch (e) {
        if (mounted)
          showToast(context, context.t.dict.deleteFailed(error: '$e'));
      }
    }
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (_) => UploadDictionaryDialog(
        onUploadSuccess: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadUserDictionaries();
            _refreshLocalDictionaries();
            showToast(context, context.t.cloud.uploadSuccess);
          });
        },
      ),
    );
  }

  void _showUpdateJsonDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (context) => UpdateJsonDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onUpdateSuccess: () {
          if (mounted) showToast(context, context.t.cloud.uploadSuccess);
        },
      ),
    );
  }

  Future<void> _showEditFilesDialog(UserDictionary dict) async {
    final dbPath = await _dictManager.getDictionaryDbPath(dict.dictId);
    // 获取数据库文件所在的目录（跨平台）
    final localPath = path.dirname(dbPath);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => EditDictionaryDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onUpdateSuccess: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadUserDictionaries();
            _refreshLocalDictionaries();
            showToast(context, context.t.cloud.updateEntry);
          });
        },
        localPath: localPath,
      ),
    );
  }

  void _showPushUpdatesDialog(UserDictionary dict) {
    showDialog(
      context: context,
      builder: (_) => PushUpdatesDialog(
        dictId: dict.dictId,
        dictName: dict.name,
        onPushSuccess: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _refreshLocalDictionaries();
            showToast(context, context.t.cloud.pushSuccess);
          });
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
        final directory = snapshot.data ?? context.t.common.loading;

        return Card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(context.t.dict.localDir),
            subtitle: Text(
              directory,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _selectDictionaryDirectory,
              tooltip: context.t.dict.changeDirTooltip,
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
          Text(
            context.t.dict.noDict,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.t.dict.noDictHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableList(
    List<DictionaryMetadata> dictionaries,
    String language,
  ) {
    return ReorderableSliverList(
      onReorder: (oldIndex, newIndex) =>
          _onReorder(oldIndex, newIndex, language),
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
        tag: 'DictionaryManagerPage',
      );

      var updateInfo = await _userDictsService.getDictUpdateInfo(
        dict.id,
        currentVersion,
      );

      Logger.d('更新信息: $updateInfo', tag: 'DictionaryManagerPage');
      if (updateInfo != null) {
        Logger.d(
          'from: ${updateInfo.from}, to: ${updateInfo.to}, files: ${updateInfo.required.files}, entries: ${updateInfo.required.entries}',
          tag: 'DictionaryManagerPage',
        );

        // 检查本地是否存在 media.db
        final hasMediaDb = await _dictManager.hasMediaDb(dict.id);
        if (!hasMediaDb) {
          // 过滤掉 media.db 相关的更新
          final filteredFiles = updateInfo.required.files
              .where((file) => file != 'media.db')
              .toList();

          // 如果过滤后没有文件需要更新且没有条目更新，则视为无需更新
          // 但仍然弹出对话框显示"已是最新版本"
          if (filteredFiles.isEmpty && updateInfo.required.entries.isEmpty) {
            Logger.i(
              '词典 ${dict.id} 只有 media.db 需要更新，但本地没有 media.db，视为无需更新',
              tag: 'DictionaryManagerPage',
            );
            // 将 updateInfo 设为 null，让对话框显示"已是最新版本"
            updateInfo = null;
          } else {
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
              tag: 'DictionaryManagerPage',
            );
          }
        }
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
      showToast(context, context.t.dict.updateFailed(error: '$e'));
      Logger.e('更新词典失败: $e', tag: 'DictionaryManager');
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
        await _refreshLocalDictionaries();
      }
      return;
    }

    final downloadManager = context.read<DownloadManager>();
    final dictDir = await _dictManager.getDictionaryDir(dict.id);

    // 构建新的元数据
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

    await downloadManager.startUpdateWithInfo(
      dictId: dict.id,
      dictName: dict.name,
      updateFiles: updateInfo.required.files,
      updateEntryIds: updateInfo.required.entries,
      updateToVersion: updateInfo.to,
      metadataJson: newMetadata.toJson(),
      dictDir: dictDir,
      onEntriesDownload: (entries) async {
        final zstdData = await _userDictsService.downloadEntryUpdates(
          dict.id,
          entries,
        );

        if (zstdData == null) {
          throw Exception(t.dict.downloadEntriesFailed);
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

        return zstdData;
      },
      onCompleteWithMetadata: (metadataJson) async {
        // 保存元数据（不依赖 context）
        final meta = DictionaryMetadata.fromJson(metadataJson);
        await _dictManager.saveDictionaryMetadata(meta);

        // 只有在页面仍然挂载时才显示 toast 和刷新
        if (!mounted) return;
        showToast(context, context.t.dict.updateSuccess);
        await _refreshLocalDictionaries();
      },
      onError: (error) {
        // 错误处理不依赖 context，只在页面挂载时显示 toast
        if (!mounted) return;
        showToast(context, context.t.dict.updateFailed(error: error));
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
            t.dict.downloading(step: step, total: totalSteps, name: fileName),
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
                t.dict.downloading(
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
                t.dict.downloadFileFailedError(
                  name: fileName,
                  error: '${event['error']}',
                ),
              );
            }
          }
          if (!downloadOk)
            throw Exception(t.dict.downloadFileFailed(name: fileName));
        }
      },
      onComplete: () async {
        // 清除缓存不依赖 context
        if (includeMetadata) {
          _dictManager.clearMetadataCache(dict.id);
        }

        // 只有在页面仍然挂载时才显示 toast 和刷新
        if (!mounted) return;
        showToast(context, context.t.dict.updateSuccess);
        await _refreshLocalDictionaries();
      },
      onError: (error) {
        // 错误处理不依赖 context，只在页面挂载时显示 toast
        if (!mounted) return;
        showToast(context, context.t.dict.updateFailed(error: '$error'));
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
        // 清除 metadata 缓存，确保重新从文件加载
        _dictManager.clearMetadataCache(dict.id);
        // 关闭旧数据库连接，确保查词时重新打开新下载的文件
        await _dictManager.closeDatabase(dict.id);
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

  // 格式化更新时间
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
  bool _hasMediaDb = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkMediaDb();
  }

  Future<void> _checkMediaDb() async {
    final hasMediaDb = await DictionaryManager().hasMediaDb(widget.dictId);
    if (mounted) {
      setState(() {
        _hasMediaDb = hasMediaDb;
      });
    }
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
              context.t.dict.updateDictTitle(name: widget.dictName),
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
              tabs: [
                Tab(text: context.t.dict.smartUpdate),
                Tab(text: context.t.dict.manualSelect),
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
          child: Text(context.t.common.cancel),
        ),
        FilledButton.icon(
          onPressed: () => _handleUpdate(info),
          icon: const Icon(Icons.update),
          label: Text(context.t.dict.startDownload),
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
              context.t.dict.upToDate,
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
                context.t.dict.noUpdates,
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
              context.t.dict.upToDate,
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
                context.t.dict.currentVersion(version: info.to),
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
          Text(
            context.t.dict.updateHistory,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
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
          Text(
            context.t.dict.filesToDownload,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (info.required.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    context.t.dict.fileLabel(
                      files: info.required.files.join(', '),
                    ),
                  ),
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
                  Text(
                    context.t.dict.entryLabel(
                      count: info.required.entries.length,
                    ),
                  ),
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
              Text(
                context.t.dict.selectContent,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                title: const Text('metadata.json'),
                subtitle: Text(context.t.dict.dictMeta),
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
                subtitle: Text(context.t.dict.dictIcon),
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
                subtitle: Text(context.t.dict.dictDb),
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
                subtitle: _hasMediaDb
                    ? Text(context.t.dict.mediaDb)
                    : Text(
                        context.t.dict.mediaDbNotExistsCanDownload,
                        style: TextStyle(color: colorScheme.primary),
                      ),
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
        showToast(context, context.t.dict.noSmartUpdate);
        return;
      }
      Navigator.pop(context, {'type': 'smart'});
    } else {
      if (!_includeMetadata && !_includeLogo && !_includeDb && !_includeMedia) {
        showToast(context, context.t.dict.selectAtLeastOneItem);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.dict.detailTitle),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;
            final hPad = isNarrow ? 12.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(metadata, isNarrow: isNarrow),
                      const SizedBox(height: 28),

                      _buildStatsSection(),
                      const SizedBox(height: 28),

                      _buildInfoSection(metadata),
                      const SizedBox(height: 28),

                      _buildFilesSection(),
                      const SizedBox(height: 28),

                      // 删除词典按鈕
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _deleteDictionary(metadata),
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                          ),
                          label: Text(
                            context.t.dict.deleteDictTitle,
                            style: const TextStyle(color: Colors.red),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
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

  Widget _buildHeader(DictionaryMetadata metadata, {bool isNarrow = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final logoSize = isNarrow ? 52.0 : 72.0;
    final containerPad = isNarrow ? 14.0 : 20.0;

    return Container(
      padding: EdgeInsets.all(containerPad),
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
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(snapshot.data!),
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultIcon(metadata, size: logoSize);
                      },
                    ),
                  ),
                );
              }
              return _buildDefaultIcon(metadata, size: logoSize);
            },
          ),
          SizedBox(width: isNarrow ? 12.0 : 20.0),
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
                if (metadata.publisher.isNotEmpty) ...[
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

  Widget _buildDefaultIcon(DictionaryMetadata metadata, {double size = 72}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
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
            fontSize: size * 0.44,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
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
                context.t.dict.statsTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.text_fields,
                    label: context.t.dict.entryCount,
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
                    label: context.t.dict.audioFiles,
                    value: '${_stats!.audioCount}',
                    color: colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.image,
                    label: context.t.dict.imageFiles,
                    value: '${_stats!.imageCount}',
                    color: colorScheme.secondary,
                  ),
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
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
                context.t.dict.dictInfoTitle,
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
                  label: context.t.dict.versionLabel,
                  value: 'v${metadata.version}',
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetaChip(
                  icon: Icons.update,
                  label: context.t.dict.updatedLabel,
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
            _buildInfoRow(
              Icons.business_outlined,
              context.t.dict.publisher,
              metadata.publisher,
            ),
          if (metadata.maintainer.isNotEmpty &&
              metadata.maintainer != metadata.publisher)
            _buildInfoRow(
              Icons.person_outline,
              context.t.dict.maintainer,
              metadata.maintainer,
            ),
          if (metadata.contactMaintainer != null &&
              metadata.contactMaintainer!.isNotEmpty)
            _buildInfoRow(
              Icons.contact_mail_outlined,
              context.t.dict.contact,
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
                context.t.dict.filesTitle,
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
                  context.t.dict.cannotGetFileInfo,
                  style: TextStyle(color: colorScheme.error),
                );
              }

              final info = snapshot.data!;
              return Column(
                children: [
                  _buildFileInfoRow(
                    'metadata.json',
                    info['hasMetadata'] == true
                        ? context.t.dict.fileExists
                        : context.t.dict.fileMissing,
                    info['hasMetadata'] == true,
                  ),
                  _buildFileInfoRow(
                    'logo.png',
                    info['hasLogo'] == true
                        ? context.t.dict.fileExists
                        : context.t.dict.fileMissing,
                    info['hasLogo'] == true,
                  ),
                  _buildFileInfoRow(
                    'dictionary.db',
                    info['hasDatabase'] == true
                        ? context.t.dict.fileExists
                        : context.t.dict.fileMissing,
                    info['hasDatabase'] == true,
                  ),
                  if (info['hasAudios'] == true || info['hasImages'] == true)
                    _buildFileInfoRow(
                      'media.db',
                      context.t.dict.fileExists,
                      true,
                    ),
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

  Future<void> _deleteDictionary(DictionaryMetadata metadata) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.red),
            const SizedBox(width: 8),
            Text(context.t.dict.deleteDictTitle),
          ],
        ),
        content: Text(context.t.dict.deleteDictBody(name: metadata.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final dictManager = DictionaryManager();
      // 如果已启用，先禁用
      final enabledIds = await dictManager.getEnabledDictionaries();
      if (enabledIds.contains(metadata.id)) {
        await dictManager.disableDictionary(metadata.id);
      }
      // 删除词典文件夹
      await dictManager.deleteDictionary(metadata.id);
      if (mounted) {
        showToast(
          context,
          context.t.dict.deleteDictSuccess(name: metadata.name),
        );
        Navigator.pop(context); // 返回词典管理页
      }
    } catch (e) {
      if (mounted)
        showToast(context, context.t.dict.deleteDictFailed(error: '$e'));
    }
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
          Text(context.t.dict.batchUpdateTitle),
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
              tooltip: context.t.dict.recheck,
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
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: _selectedDictIds.isEmpty ? null : _startBatchUpdate,
          child: Text(
            context.t.dict.batchUpdateCount(count: _selectedDictIds.length),
          ),
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
              context.t.dict.batchHasUpdates(count: updatableDicts.length),
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
                    ? context.t.dict.deselectAll
                    : context.t.dict.selectAll,
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
                  context.t.dict.versionRange(
                    from: info.from,
                    to: info.to,
                    files: info.required.files.length,
                  ),
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

    for (final entry in selectedDicts) {
      final dictId = entry.key;
      final updateInfo = entry.value;

      try {
        final metadata = await widget.dictManager.getDictionaryMetadata(dictId);
        if (metadata == null) {
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
              onProgress(
                t.dict.downloading(
                  step: step,
                  total: totalSteps,
                  name: fileName,
                ),
                step,
                totalSteps,
              );

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
                    t.dict.downloading(
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
                    t.dict.downloadFileFailedError(
                      name: fileName,
                      error: '${event['error']}',
                    ),
                  );
                }
              }
              if (!downloadOk)
                throw Exception(t.dict.downloadFileFailed(name: fileName));
            }

            if (updateInfo.required.entries.isNotEmpty) {
              step++;
              onProgress(
                t.dict.downloadingEntries(step: step, total: totalSteps),
                step,
                totalSteps,
              );

              final zstdData = await widget.userDictsService
                  .downloadEntryUpdates(dictId, updateInfo.required.entries);

              if (zstdData == null) {
                throw Exception(t.dict.downloadEntriesFailed);
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
          },
          onError: (error) {
            Logger.e('更新词典 $dictId 失败: $error', tag: 'BatchUpdate');
          },
        );
      } catch (e) {
        Logger.e('更新词典 $dictId 异常: $e', tag: 'BatchUpdate');
      }
    }

    widget.onComplete();
  }
}
