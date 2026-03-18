// ignore_for_file: duplicate_ignore

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../components/component_renderer.dart';
import '../components/dictionary_logo.dart';
import '../components/dictionary_navigation_panel.dart';
import '../components/global_scale_wrapper.dart';
import '../core/logger.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/word_list_dialog.dart';
import '../data/database_service.dart';
import '../data/models/ai_chat_record.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/services/ai_chat_database_service.dart';
import '../data/word_bank_service.dart';
import '../i18n/strings.g.dart';
import '../services/ai_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_search_service.dart';
import '../services/entry_event_bus.dart';
import '../services/font_loader_service.dart';
import '../services/llm_client.dart';
import '../services/preferences_service.dart';
import '../services/search_history_service.dart';
import '../services/user_dicts_service.dart';
import '../widgets/path_navigator.dart';
import 'json_editor_bottom_sheet.dart';

part 'entry_detail_page_private_widgets.dart';

class EntryDetailPage extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final String initialWord;
  final Map<String, List<SearchRelation>>? searchRelations;

  const EntryDetailPage({
    super.key,
    required this.entryGroup,
    required this.initialWord,
    this.searchRelations,
  });

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final _preferencesService = PreferencesService();

  final WordBankService _wordBankService = WordBankService();
  final AIService _aiService = AIService();
  final AiChatDatabaseService _aiChatDatabaseService = AiChatDatabaseService();
  late DictionaryEntryGroup _entryGroup;
  bool _isFavorite = false;

  /// 路径历史栈，用于撤回功能
  final List<List<String>> _pathHistory = [];
  int _historyIndex = -1;

  /// AI聊天记录 - 懒加载，首次打开AI面板时才加载
  final List<AiChatRecord> _aiChatHistory = [];
  bool _isAiChatHistoryLoaded = false;

  /// 正在进行的AI请求（流式 StreamSubscription）
  final Map<String, StreamSubscription<LLMChunk>> _pendingAiRequests = {};

  /// 应自动展开的消息ID集合（新建流式请求时加入）
  final Set<String> _autoExpandIds = {};

  /// 当前正在加载的AI请求ID
  String? _currentLoadingId;

  /// AI聊天历史弹窗的 setState，用于在请求完成时刷新弹窗内容
  StateSetter? _modalSetState;
  bool _isModalActive = false;

  // 导航栏位置状态（固定在右侧，只保存垂直位置）
  double _navPanelDy = 0.7; // 相对屏幕高度的比例
  bool _isNavPanelLoaded = false;

  // 导航面板的 GlobalKey，用于访问其状态
  final GlobalKey<DictionaryNavigationPanelState> _navPanelKey =
      GlobalKey<DictionaryNavigationPanelState>();

  bool? _areNonTargetLanguagesVisible;

  /// 折叠状态：存储已折叠的词典 dictId
  final Set<String> _collapsedDicts = {};

  /// 词形关系搜索的缓存 Future，所有词典共享，只搜索一次
  Future<List<WordRelationRow>>? _wordRelationsFuture;

  DateTime? _lastScrollUpdateTime;
  static const _scrollUpdateThrottle = Duration(milliseconds: 100);
  bool _isProgrammaticScroll = false;
  DateTime? _lastDictionaryChangeTime;
  static const _dictionaryChangeCooldown = Duration(milliseconds: 200);

  /// 滚动结束检测计时器
  Timer? _scrollEndTimer;
  static const _scrollEndDelay = Duration(milliseconds: 150);

  List<String> _toolbarActions = [];
  List<String> _overflowActions = [];

  /// 导航面板状态通知器，用于在滚动时只更新导航面板而不重建整个页面
  final ValueNotifier<int> _navPanelVersionNotifier = ValueNotifier(0);

  /// 流式输出状态通知器，避免在每个chunk时重建整个列表
  final Map<String, ValueNotifier<(String, String?, bool)>>
  _streamingNotifiers = {};

  /// 流式输出节流计时器（80ms 批量推送，减少 Markdown 重渲染频率）
  final Map<String, Timer?> _streamingThrottleTimers = {};

  /// 请求状态版本通知，用于在流式开始/结束时精确更新单个消息卡片，避免全模态重建影响滚动
  final ValueNotifier<int> _pendingRequestsVersionNotifier = ValueNotifier(0);

  /// 桌面端搜索模式
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _entryGroup = widget.entryGroup;
    // 关键数据：导航栏位置（影响UI布局）
    _loadNavPanelPosition();
    // 初始化单词关系搜索（缓存 Future，所有词典共享）
    _initWordRelationsSearch();
    // 非关键数据延迟加载
    _loadDeferredData();
    // 软件布局缩放已从 FontLoaderService 同步获取，无需异步加载
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionChanged);
  }

  /// 延迟加载非关键数据，避免阻塞首屏渲染
  void _loadDeferredData() {
    // 使用微任务延迟执行，确保首帧渲染优先
    Future.microtask(() async {
      await _loadFavoriteStatus();
      await _loadToolbarConfig();
    });
    // AI聊天历史只在需要时加载，不在初始化时加载
  }

  Future<void> _loadToolbarConfig() async {
    final (toolbarActions, overflowActions) = await _preferencesService
        .getToolbarAndOverflowActions();
    if (mounted) {
      setState(() {
        _toolbarActions = toolbarActions;
        _overflowActions = overflowActions;
      });
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _onScrollPositionChanged,
    );
    _scrollEndTimer?.cancel();
    // 取消所有正在进行的流式AI请求
    for (final sub in _pendingAiRequests.values) {
      sub.cancel();
    }
    _pendingAiRequests.clear();
    // 释放所有流式通知器与节流计时器
    for (final t in _streamingThrottleTimers.values) {
      t?.cancel();
    }
    _streamingThrottleTimers.clear();
    for (final notifier in _streamingNotifiers.values) {
      notifier.dispose();
    }
    _streamingNotifiers.clear();
    _pendingRequestsVersionNotifier.dispose();
    super.dispose();
  }

  void _onScrollPositionChanged() {
    if (_isProgrammaticScroll) {
      return;
    }

    final now = DateTime.now();
    if (_lastScrollUpdateTime != null &&
        now.difference(_lastScrollUpdateTime!) < _scrollUpdateThrottle) {
      return;
    }
    _lastScrollUpdateTime = now;
    _updateCurrentSectionFromScroll();

    // 重置滚动结束检测计时器
    _scrollEndTimer?.cancel();
    _scrollEndTimer = Timer(_scrollEndDelay, () {
      // 滚动结束后强制更新一次（绕过冷却机制）
      _forceUpdateCurrentSection();
    });
  }

  // 缓存当前entry的索引位置，避免每次滚动都遍历查找
  int? _lastEntryIndex;
  String? _lastEntryId;

  void _updateCurrentSectionFromScroll() {
    _updateCurrentSectionInternal(skipCooldown: false);
  }

  /// 强制更新当前 section（滚动结束后调用，绕过冷却机制）
  void _forceUpdateCurrentSection() {
    _updateCurrentSectionInternal(skipCooldown: true);
  }

  void _updateCurrentSectionInternal({required bool skipCooldown}) {
    // 检查词典切换冷却时间，防止在词典交界处快速来回切换
    if (!skipCooldown) {
      final now = DateTime.now();
      if (_lastDictionaryChangeTime != null &&
          now.difference(_lastDictionaryChangeTime!) <
              _dictionaryChangeCooldown) {
        return;
      }
    }

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final entries = _getAllEntriesInOrder();
    if (entries.isEmpty) return;

    // 只考虑真正可见区域内的 items（排除预加载区域）
    // itemLeadingEdge < 1 且 itemTrailingEdge > 0 表示至少部分可见
    final visiblePositions = positions
        .where((pos) => pos.itemLeadingEdge < 1 && pos.itemTrailingEdge > 0)
        .toList();

    if (visiblePositions.isEmpty) return;

    int lastFullyVisibleIndex = -1;
    double maxVisibleHeight = 0;
    int targetVisibleIndex = -1;

    for (final pos in visiblePositions) {
      double visibleHeight;
      if (pos.itemLeadingEdge < 0 && pos.itemTrailingEdge > 1) {
        visibleHeight = 1.0;
      } else if (pos.itemLeadingEdge < 0) {
        visibleHeight = pos.itemTrailingEdge;
      } else if (pos.itemTrailingEdge > 1) {
        visibleHeight = 1.0 - pos.itemLeadingEdge;
      } else {
        visibleHeight = pos.itemTrailingEdge - pos.itemLeadingEdge;
      }

      bool isFullyVisible =
          pos.itemLeadingEdge >= 0 && pos.itemTrailingEdge <= 1;
      if (isFullyVisible && pos.index > lastFullyVisibleIndex) {
        lastFullyVisibleIndex = pos.index;
      }

      if (visibleHeight > maxVisibleHeight) {
        maxVisibleHeight = visibleHeight;
        targetVisibleIndex = pos.index;
      }
    }

    int targetIndex = lastFullyVisibleIndex >= 0
        ? lastFullyVisibleIndex
        : targetVisibleIndex;
    if (targetIndex < 0) return;

    // 索引 0: 词形关系横幅（始终存在）
    int entryIndex = targetIndex - 1;

    if (entryIndex < 0 || entryIndex >= entries.length) return;

    // 快速检查：如果entry索引没变，直接返回（避免重复查找）
    if (_lastEntryIndex == entryIndex && _lastEntryId != null) {
      return;
    }

    final targetEntry = entries[entryIndex];

    // 更新缓存
    _lastEntryIndex = entryIndex;
    _lastEntryId = targetEntry.id;

    final currentDictIndex = _entryGroup.currentDictionaryIndex;

    // 使用索引直接定位，避免三重循环
    // 先找到entry所属的词典
    int entryCount = 0;
    for (int i = 0; i < _entryGroup.dictionaryGroups.length; i++) {
      final dict = _entryGroup.dictionaryGroups[i];
      final currentPage = dict.currentPageGroup;
      final pageEntryCount = currentPage.sections.length;

      if (entryIndex < entryCount + pageEntryCount) {
        // entry在这个词典中
        final localIndex = entryIndex - entryCount;
        final section = currentPage.sections[localIndex];

        if (section.entry.id == targetEntry.id) {
          if (i != currentDictIndex || localIndex != dict.currentSectionIndex) {
            _entryGroup.setCurrentDictionaryIndex(i);
            _entryGroup.dictionaryGroups[i].setCurrentSectionIndex(localIndex);
            // 记录词典切换时间，用于冷却机制
            _lastDictionaryChangeTime = DateTime.now();
            // 只通知导航面板更新，不重建整个页面
            _navPanelVersionNotifier.value++;
            // 通知导航面板活跃section已改变
            _navPanelKey.currentState?.handleActiveSectionChanged();
          }
        }
        return;
      }
      entryCount += pageEntryCount;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在 didChangeDependencies 中初始化，确保 context 可用
    if (_areNonTargetLanguagesVisible == null) {
      _initializeTargetLanguagesVisibility();
    }
  }

  /// 获取当前目标语言显示状态，如果未初始化则返回 true
  bool get _isNonTargetLanguagesVisible =>
      _areNonTargetLanguagesVisible ?? true;

  /// 初始化目标语言显示状态
  /// 从全局设置读取，如果没有设置则默认为 true（显示所有语言）
  Future<void> _initializeTargetLanguagesVisibility() async {
    final globalVisibility = await PreferencesService()
        .getGlobalTranslationVisibility();
    if (mounted) {
      setState(() {
        _areNonTargetLanguagesVisible = globalVisibility;
      });
      // 应用全局状态到 ComponentRenderer
      _applyGlobalTranslationVisibility(globalVisibility);
    }
  }

  /// 应用全局翻译显示状态到 ComponentRenderer
  Future<void> _applyGlobalTranslationVisibility(bool visible) async {
    try {
      final entries = _getAllEntriesInOrder();
      if (entries.isEmpty) return;

      // 获取当前词典的元数据
      final currentDictId = _entryGroup.currentDictionaryId;
      if (currentDictId.isEmpty) return;

      final metadata = await DictionaryManager().getDictionaryMetadata(
        currentDictId,
      );
      if (metadata == null) return;

      final sourceLang = metadata.sourceLanguage;
      final targetLangs = metadata.targetLanguages;

      // 收集所有需要切换的语言路径
      final Set<String> languagePaths = {};

      for (final entry in entries) {
        final json = entry.toJson();
        _collectLanguagePaths(json, '', languagePaths, sourceLang, targetLangs);
      }

      final pathsToHide = visible ? <String>[] : languagePaths.toList();
      final pathsToShow = visible ? languagePaths.toList() : <String>[];

      EntryEventBus().emitBatchToggleHiddenLanguages(
        BatchToggleHiddenLanguagesEvent(
          pathsToHide: pathsToHide,
          pathsToShow: pathsToShow,
        ),
      );
    } catch (e) {
      Logger.d(
        'Error in _applyGlobalTranslationVisibility: $e',
        tag: 'Translation',
      );
    }
  }

  Future<void> _loadNavPanelPosition() async {
    final position = await PreferencesService().getNavPanelPosition();
    if (mounted) {
      setState(() {
        // 导航栏固定在右侧，只读取垂直位置
        _navPanelDy = position['dy'] ?? 0.7;
        _isNavPanelLoaded = true;
      });
    }
  }

  /// 加载AI聊天记录
  Future<void> _loadAiChatHistory() async {
    final records = await _aiChatDatabaseService.getAllRecords();
    setState(() {
      _aiChatHistory.clear();
      _aiChatHistory.addAll(
        records.map(
          (r) => AiChatRecord(
            id: r.id,
            conversationId: r.conversationId,
            word: r.word,
            question: r.question,
            answer: r.answer,
            timestamp: r.timestamp,
            path: r.path,
            elementJson: r.elementJson,
          ),
        ),
      );
    });
  }

  /// 获取所有会话ID，按最新消息时间降序排列
  List<String> _getConversationIds() {
    final Map<String, DateTime> latestTimestamps = {};
    for (final record in _aiChatHistory) {
      final cid = record.conversationId;
      if (!latestTimestamps.containsKey(cid) ||
          record.timestamp.isAfter(latestTimestamps[cid]!)) {
        latestTimestamps[cid] = record.timestamp;
      }
    }
    final ids = latestTimestamps.keys.toList();
    ids.sort((a, b) => latestTimestamps[b]!.compareTo(latestTimestamps[a]!));
    return ids;
  }

  /// 获取某会话的所有消息，按时间升序排列
  List<AiChatRecord> _getConversationMessages(String conversationId) {
    return _aiChatHistory
        .where((r) => r.conversationId == conversationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  void didUpdateWidget(EntryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWord != widget.initialWord) {
      _entryGroup = widget.entryGroup;
      _loadFavoriteStatus();
      _initWordRelationsSearch();
    }
  }

  /// 初始化单词关系搜索，所有词典只搜索一次
  void _initWordRelationsSearch() {
    final word = widget.initialWord;
    if (word.isNotEmpty) {
      _wordRelationsFuture = EnglishSearchService().searchWordRelations(word);
    } else {
      _wordRelationsFuture = null;
    }
  }

  /// 获取当前词典的语言
  Future<String> _getCurrentLanguage() async {
    final currentDictId = _entryGroup.currentDictionaryId;
    if (currentDictId.isEmpty) return 'en';

    final metadata = await DictionaryManager().getDictionaryMetadata(
      currentDictId,
    );
    final raw = metadata?.sourceLanguage ?? 'en';
    return LanguageUtils.normalizeSourceLanguage(raw);
  }

  Future<void> _loadFavoriteStatus() async {
    final language = await _getCurrentLanguage();
    final isFavorite = await _wordBankService.isInWordBank(
      widget.initialWord,
      language,
    );
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  /// 构建搜索关系信息横幅
  /// 在词典头部下方显示该词典通过词形关系找到词条的提示横幅
  Widget _buildInlineDictRelationBanner(List<SearchRelation> relations) {
    final colorScheme = Theme.of(context).colorScheme;
    const hPad = 16.0;

    return Container(
      margin: EdgeInsets.only(
        left: hPad + 4,
        right: hPad + 4,
        top: 2,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colorScheme.primary.withOpacity(0.4),
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 10, top: 5, bottom: 5),
      child: Wrap(
        spacing: 20,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: relations
            .fold<List<SearchRelation>>([], (deduped, relation) {
              // 去重：相同的 (description/relationType, pos, mappedWord) 只显示一次
              final key =
                  '${relation.description ?? relation.relationType}|${relation.pos}|${relation.mappedWord}';
              final alreadyAdded = deduped.any((r) {
                return '${r.description ?? r.relationType}|${r.pos}|${r.mappedWord}' ==
                    key;
              });
              if (!alreadyAdded) deduped.add(relation);
              return deduped;
            })
            .map((relation) {
              final posLabel = _shortenPos(relation.pos);
              final desc = relation.description ?? relation.relationType;
              final label = posLabel.isNotEmpty ? '$desc $posLabel' : desc;

              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.initialWord,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.55),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '($label)',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.65),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: colorScheme.primary.withOpacity(0.55),
                    ),
                  ),
                  Text(
                    relation.mappedWord,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              );
            })
            .toList(),
      ),
    );
  }

  /// 更新_entryGroup中对应的entry
  void _updateEntryInGroup(
    DictionaryEntry updatedEntry, {
    bool shouldSetState = true,
  }) {
    Null updateLogic() {
      for (final dictGroup in _entryGroup.dictionaryGroups) {
        for (final pageGroup in dictGroup.pageGroups) {
          for (int i = 0; i < pageGroup.sections.length; i++) {
            final section = pageGroup.sections[i];
            if (section.entry.id == updatedEntry.id) {
              pageGroup.sections[i] = DictionarySection(
                section: section.section,
                entry: updatedEntry,
              );
              return;
            }
          }
        }
      }
    }

    if (shouldSetState) {
      setState(updateLogic);
    } else {
      updateLogic();
    }
  }

  List<DictionaryEntry> get entries => _getAllEntriesInOrder();

  List<DictionaryEntry> _getAllEntriesInOrder() {
    final List<DictionaryEntry> entries = [];

    final allDicts = _entryGroup.dictionaryGroups;

    // 按固定顺序添加所有词典的【当前 page】的 entries
    // 每个词典只显示其当前选中的 page
    for (int i = 0; i < allDicts.length; i++) {
      final dict = allDicts[i];
      final currentPage = dict.currentPageGroup;
      for (final section in currentPage.sections) {
        entries.add(section.entry);
      }
    }

    return entries;
  }

  void _scrollToEntry(DictionaryEntry entry, {String? targetPath}) async {
    final entries = _getAllEntriesInOrder();
    int index = entries.indexWhere((e) => e.id == entry.id);

    Logger.d(
      'Scrolling to entry: ${entry.headword}, index: $index, total entries: ${entries.length}, targetPath: $targetPath',
      tag: 'EntryDetail',
    );

    if (index != -1) {
      // 始终 +1 跳过词形关系横幅 (index 0)
      index += 1;

      // 如果有 targetPath，直接滚动到精确位置，不再先滚动到 entry 顶部
      if (targetPath != null) {
        _scrollToElement(entry.id, targetPath);
        return;
      }

      // SafeArea 已处理状态栏偏移，滚动 alignment 直接对齐视口顶部
      const scrollAlignment = 0.0;

      if (_itemScrollController.isAttached) {
        Logger.d('Controller attached, scrolling now', tag: 'EntryDetail');

        _isProgrammaticScroll = true;
        _itemScrollController
            .scrollTo(
              index: index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: scrollAlignment,
            )
            .then((_) {
              // 动画结束后额外缓冲，防止位置监听器在动画完成后触发误判
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) _isProgrammaticScroll = false;
              });
            });
      } else {
        Logger.d(
          'Controller not attached, waiting for post frame',
          tag: 'EntryDetail',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (_itemScrollController.isAttached) {
            Logger.d(
              'Controller attached in post frame, scrolling now',
              tag: 'EntryDetail',
            );

            _isProgrammaticScroll = true;
            _itemScrollController
                .scrollTo(
                  index: index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: scrollAlignment,
                )
                .then((_) {
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (mounted) _isProgrammaticScroll = false;
                  });
                });
          } else {
            Logger.w(
              'Controller still not attached after post frame',
              tag: 'EntryDetail',
            );
          }
        });
      }
    } else {
      Logger.w('Entry not found in current list', tag: 'EntryDetail');
    }
  }

  void _scrollToElement(String entryId, String path) {
    Logger.d(
      'Emitting scroll to element event: $path in entry: $entryId',
      tag: 'EntryDetail',
    );
    // 设置标志位，表示这是程序触发的滚动，不应更新活跃section
    _isProgrammaticScroll = true;
    EntryEventBus().emitScrollToElement(
      ScrollToElementEvent(entryId: entryId, path: path),
    );
    // 延迟重置标志位，给滚动动画留出时间（含额外缓冲）
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        _isProgrammaticScroll = false;
      }
    });
  }

  void _onDictionaryChanged() {
    Logger.d('Dictionary changed, rebuilding list', tag: 'EntryDetail');
    setState(() {});
  }

  void _onPageChanged() {
    Logger.d('Page changed, rebuilding list', tag: 'EntryDetail');
    setState(() {});
    // 移除这里的自动滚动逻辑，因为 _onSectionTapped 已经处理了具体的跳转
    // 如果这里保留，会导致每次切换 Page 都强制滚动到第一个 Section，覆盖用户的点击意图
    /*
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentDict = _entryGroup.currentDictionaryGroup;
      if (currentDict.pageGroups.isNotEmpty &&
          currentDict.currentPageIndex < currentDict.pageGroups.length) {
        final currentPage =
            currentDict.pageGroups[currentDict.currentPageIndex];
        if (currentPage.sections.isNotEmpty) {
          _scrollToEntry(currentPage.sections[0].entry);
        }
      }
    });
    */
  }

  void _onSectionChanged() {
    setState(() {});
  }

  Future<void> _toggleFavorite() async {
    final word = widget.initialWord;
    final language = await _getCurrentLanguage();

    final selectedLists = await WordListDialog.show(
      context,
      language: language,
      word: word,
      isNewWord: !_isFavorite,
      wordBankService: _wordBankService,
    );

    if (selectedLists == null) {
      return;
    }

    if (selectedLists.contains('__REMOVE__')) {
      await _wordBankService.removeWord(word, language);
      if (mounted) {
        showToast(context, context.t.entry.wordRemoved(word: word));
        setState(() => _isFavorite = false);
      }
      return;
    }

    if (_isFavorite) {
      final listChanges = <String, int>{};
      final allLists = await _wordBankService.getWordLists(language);
      for (final list in allLists) {
        listChanges[list.name] = selectedLists.contains(list.name) ? 1 : 0;
      }
      await _wordBankService.updateWordLists(word, language, listChanges);
      if (mounted) {
        showToast(context, context.t.entry.wordListUpdated(word: word));
      }
    } else {
      if (selectedLists.isEmpty) {
        if (mounted) {
          showToast(context, context.t.entry.selectAtLeastOne);
        }
      } else {
        final success = await _wordBankService.addWord(
          word,
          language,
          lists: selectedLists,
        );
        if (mounted) {
          if (success) {
            showToast(context, context.t.entry.wordAdded(word: word));
            setState(() => _isFavorite = true);
          } else {
            showToast(context, context.t.entry.addFailed);
          }
        }
      }
    }
  }

  Future<void> _resetCurrentEntry() async {
    final currentEntry = _entryGroup.currentDictionaryGroup.currentEntry;
    if (currentEntry == null) {
      showToast(context, context.t.entry.noEntry);
      return;
    }

    final dictId = currentEntry.dictId;
    var entryId = currentEntry.id;
    if (dictId == null || entryId.isEmpty) {
      showToast(context, context.t.entry.entryIncomplete);
      return;
    }

    final prefix = '${dictId}_';
    if (entryId.startsWith(prefix)) {
      entryId = entryId.substring(prefix.length);
    }

    showToast(context, context.t.entry.resetting);

    try {
      final userDictsService = UserDictsService();
      final entryData = await userDictsService.fetchEntry(dictId, entryId);

      if (entryData == null) {
        if (mounted) {
          showToast(context, context.t.entry.notFoundOnServer);
        }
        return;
      }

      entryData['dict_id'] = dictId;
      final newEntry = DictionaryEntry.fromJson(entryData);

      final databaseService = DatabaseService();
      // 重置到服务器原始状态，不写 commit；并删除该词条已有的 commit 记录
      final success = await databaseService.insertOrUpdateEntry(
        newEntry,
        skipCommit: true,
      );
      if (success) {
        await databaseService.deleteUpdateRecord(dictId, newEntry.id);
      }

      if (success && mounted) {
        final currentDictGroup = _entryGroup.currentDictionaryGroup;
        final currentPage = currentDictGroup.currentPageGroup;
        final sectionIndex = currentDictGroup.currentSectionIndex;

        if (sectionIndex >= 0 && sectionIndex < currentPage.sections.length) {
          final section = currentPage.sections[sectionIndex];
          currentPage.sections[sectionIndex] = DictionarySection(
            section: section.section,
            entry: newEntry,
          );

          setState(() {});

          showToast(context, context.t.entry.resetSuccess);
        }
      } else if (mounted) {
        showToast(context, context.t.entry.resetFailed);
      }
    } catch (e) {
      Logger.e('重置词条失败: $e', tag: 'EntryDetailPage');
      if (mounted) {
        showToast(context, context.t.entry.resetFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // item 0: 词形关系横幅（始终占一个位置，无结果时 FutureBuilder 返回 SizedBox.shrink()）
    const wordRelationsOffset = 1;
    // 搜索关系横幅现在内嵌在各词典的词典头部下方，不占独立 item
    final totalCount = wordRelationsOffset + entries.length;

    final content = Scaffold(
      // 禁止键盘顶起页面，手动处理底部工具栏位置
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 主内容区域 - 全屏，内容可以滚动到工具栏下方
            SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // 手机端：滚动时退出搜索模式
                  if (_isSearchMode &&
                      notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    setState(() {
                      _isSearchMode = false;
                      _searchController.clear();
                    });
                  }
                  return false;
                },
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  padding: _getDynamicPadding(
                    context,
                  ).copyWith(top: 16, bottom: 100),
                  itemCount: totalCount,
                  minCacheExtent: 1500,
                  itemBuilder: (context, index) {
                    // 索引 0: 单词形态关系横幅
                    if (index == 0) return _buildWordRelationsBanner();

                    final entryIndex = index - wordRelationsOffset;
                    final entry = entries[entryIndex];

                    // 仅在该词典第一条 entry 处显示词典 Logo+名称
                    final showDictHeader =
                        entryIndex == 0 ||
                        entries[entryIndex - 1].dictId != entry.dictId;

                    // 当该词典是通过词形关系找到时，在词典头部下方显示关系横幅
                    List<SearchRelation>? entryRelations;
                    if (showDictHeader && widget.searchRelations != null) {
                      final headword = entry.headword.toLowerCase();
                      for (final rel in widget.searchRelations!.entries) {
                        if (rel.key.toLowerCase() == headword) {
                          entryRelations = rel.value;
                          break;
                        }
                      }
                    }

                    return _buildEntryContent(
                      entry,
                      showDictHeader: showDictHeader,
                      relations: entryRelations,
                    );
                  },
                ),
              ),
            ),
            if (_entryGroup.dictionaryGroups.isNotEmpty && _isNavPanelLoaded)
              _DraggableNavPanel(
                entryGroup: _entryGroup,
                onDictionaryChanged: _onDictionaryChanged,
                onPageChanged: _onPageChanged,
                onSectionChanged: _onSectionChanged,
                onNavigateToEntry: _scrollToEntry,
                initialDy: _navPanelDy,
                navPanelKey: _navPanelKey,
                navPanelVersionNotifier: _navPanelVersionNotifier,
              ),
            // 搜索模式下的透明遮罩层，拦截点击事件（放在底部工具栏之前，覆盖主内容和导航面板）
            if (_isSearchMode)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSearchMode = false;
                      _searchController.clear();
                    });
                  },
                  // 使用 opaque 确保拦截所有点击事件，不传递到下层
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
            // 浮动底部工具栏 - 使用独立的 Widget 避免整个页面重建
            _KeyboardAwareBottomBar(
              child: _buildBottomActionBarWithBackButton(),
            ),
          ],
        ),
      ),
    );

    // 应用软件布局缩放
    final scale = FontLoaderService().getDictionaryContentScale();
    if (scale == 1.0) {
      return content;
    }

    return PageScaleWrapper(scale: scale, child: content);
  }

  /// 桌面端左上角悬浮返回按钮
  /// 桌面端底部工具栏（带左侧独立返回按钮）
  Widget _buildBottomActionBarWithBackButton() {
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (isDesktop) {
      return Row(
        children: [
          // 左侧独立的返回按钮（搜索模式下也保持显示）
          Expanded(child: _buildDesktopBackButton()),
          const SizedBox(width: 16),
          // 右侧工具栏或搜索栏
          Expanded(
            flex:
                _toolbarActions.length + (_overflowActions.isNotEmpty ? 1 : 0),
            child: _isSearchMode
                ? _buildSearchBar()
                : _buildBottomActionBar(isDesktop: true),
          ),
        ],
      );
    }

    // 手机端：搜索模式显示搜索栏，否则显示工具栏
    return _isSearchMode ? _buildSearchBar() : _buildBottomActionBar();
  }

  /// 桌面端返回按钮（与底部工具栏按钮样式相同）
  Widget _buildDesktopBackButton() {
    return GestureDetector(
      // 阻止点击事件冒泡到外层
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      clearAllToasts();
                      Navigator.of(context).pop();
                    },
                    onLongPress: () {
                      clearAllToasts();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 桌面端搜索栏
  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 阻止点击事件冒泡到外层
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                // 关闭按钮（圆形）
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _isSearchMode = false;
                        _searchController.clear();
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close, size: 24),
                    ),
                  ),
                ),
                // 搜索输入框
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: context.t.search.hint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      isDense: true,
                    ),
                    onSubmitted: _onSearchSubmitted,
                  ),
                ),
                // 搜索按钮（圆形）
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _onSearchSubmitted(_searchController.text),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.search, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSearchSubmitted(String query) async {
    if (query.trim().isEmpty) return;
    final word = query.trim();

    // 执行搜索
    final dbService = DatabaseService();
    final searchResult = await dbService.getAllEntries(word);

    if (searchResult.entries.isNotEmpty) {
      // 记录搜索历史（进入首页查词页的历史记录）
      final historyService = SearchHistoryService();
      await historyService.addSearchRecord(word);

      // 搜索成功，跳转到新的词典内容页
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                EntryDetailPage(entryGroup: entryGroup, initialWord: word),
          ),
        );
        // 返回后退出搜索模式
        setState(() {
          _isSearchMode = false;
          _searchController.clear();
        });
      }
    } else {
      // 无搜索结果
      if (mounted) {
        showToast(context, context.t.search.noResult(word: word));
      }
    }
  }

  Widget _buildBottomActionBar({bool isDesktop = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final toolbarWidgets = _toolbarActions
        .map(
          (action) => Expanded(
            child: _buildToolbarAction(
              action,
              colorScheme,
              isDesktop: isDesktop,
            ),
          ),
        )
        .toList();

    return Container(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ...toolbarWidgets,
              if (_overflowActions.isNotEmpty)
                Expanded(child: _buildOverflowButton(colorScheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarAction(
    String action,
    ColorScheme colorScheme, {
    bool isDesktop = false,
  }) {
    switch (action) {
      case PreferencesService.actionBack:
        return _buildActionButton(
          icon: Icons.arrow_back,
          onPressed: () {
            clearAllToasts();
            Navigator.of(context).pop();
          },
          onLongPress: () {
            clearAllToasts();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        );
      case PreferencesService.actionSearch:
        return _buildActionButton(
          icon: Icons.search,
          onPressed: () {
            setState(() {
              _isSearchMode = true;
            });
            _searchFocusNode.requestFocus();
          },
        );
      case PreferencesService.actionFavorite:
        return _buildActionButton(
          icon: _isFavorite ? Icons.bookmark : Icons.bookmark_outline,
          isActive: _isFavorite,
          onPressed: _toggleFavorite,
        );
      case PreferencesService.actionToggleTranslate:
        return _buildActionButton(
          icon: _isNonTargetLanguagesVisible
              ? Icons.translate
              : Icons.translate_outlined,
          isActive: _isNonTargetLanguagesVisible,
          onPressed: _toggleAllNonTargetLanguages,
        );
      case PreferencesService.actionAiHistory:
        return _buildActionButton(
          icon: Icons.auto_awesome,
          onPressed: () => _showAiChatHistory(),
        );
      case PreferencesService.actionResetEntry:
        return _buildActionButton(
          icon: Icons.refresh,
          onPressed: _resetCurrentEntry,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildOverflowButton(ColorScheme colorScheme) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showOverflowMenu(context, colorScheme),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Icon(
            Icons.more_horiz,
            size: 24,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _showOverflowMenu(BuildContext context, ColorScheme colorScheme) {
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Size overlaySize = overlay.size;

    // 获取底部安全区域高度
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    // 计算底部工具栏的高度（约56dp + 边距）
    const toolbarHeight = 72.0;
    const menuMargin = 8.0;

    // 计算菜单应该显示的底部位置（在底部工具栏上方）
    final menuBottom = bottomPadding > 0
        ? bottomPadding + toolbarHeight + menuMargin
        : 16.0 + toolbarHeight + menuMargin;

    final menuPosition = RelativeRect.fromLTRB(
      overlaySize.width - 200, // 右侧对齐，预留菜单宽度
      overlaySize.height -
          menuBottom -
          (_overflowActions.length * 48), // 从底部向上计算
      16, // 右边距
      menuBottom, // 底部距离
    );

    showMenu<String>(
      context: context,
      position: menuPosition,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _overflowActions
          .map(
            (action) => PopupMenuItem(
              value: action,
              child: Row(
                children: [
                  Icon(_getActionIcon(action), size: 20),
                  const SizedBox(width: 12),
                  Text(_getActionLabel(action)),
                ],
              ),
            ),
          )
          .toList(),
    ).then((value) {
      if (value != null) {
        _handleOverflowAction(value);
      }
    });
  }

  IconData _getActionIcon(String action) {
    return PreferencesService.getActionIcon(action);
  }

  String _getActionLabel(String action) {
    final t = context.t.settings.actionLabel;
    switch (action) {
      case PreferencesService.actionAiTranslate:
        return t.aiTranslate;
      case PreferencesService.actionCopy:
        return t.copy;
      case PreferencesService.actionAskAi:
        return t.askAi;
      case PreferencesService.actionEdit:
        return t.edit;
      case PreferencesService.actionSpeak:
        return t.speak;
      case PreferencesService.actionBack:
        return t.back;
      case PreferencesService.actionFavorite:
        return t.favorite;
      case PreferencesService.actionToggleTranslate:
        return t.toggleTranslate;
      case PreferencesService.actionAiHistory:
        return t.aiHistory;
      case PreferencesService.actionResetEntry:
        return t.resetEntry;
      default:
        return action;
    }
  }

  void _handleOverflowAction(String action) {
    switch (action) {
      case PreferencesService.actionBack:
        clearAllToasts();
        Navigator.of(context).pop();
        break;
      case PreferencesService.actionFavorite:
        _toggleFavorite();
        break;
      case PreferencesService.actionToggleTranslate:
        _toggleAllNonTargetLanguages();
        break;
      case PreferencesService.actionAiHistory:
        _showAiChatHistory();
        break;
      case PreferencesService.actionResetEntry:
        _resetCurrentEntry();
        break;
    }
  }

  // 构建单个操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    bool isActive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Icon(
            icon,
            size: 24,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 根据屏幕宽度动态计算边距
  EdgeInsets _getDynamicPadding(BuildContext context) {
    // 使用 MediaQuery.sizeOf(context) 替代 MediaQuery.of(context).size
    // 这样可以避免不必要的重建，但在这个场景下，我们更需要确保在布局过程中不直接依赖可能变化的 MediaQuery
    // 或者将 Padding 计算移到 build 方法外部，或者使用 LayoutBuilder
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth < 600) {
      return const EdgeInsets.symmetric(horizontal: 2, vertical: 6);
    } else if (screenWidth < 900) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    } else {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 6);
    }
  }

  Widget _buildEntryContent(
    DictionaryEntry entry, {
    bool showDictHeader = false,
    List<SearchRelation>? relations,
  }) {
    final dictId = entry.dictId ?? '';
    final isCollapsed = dictId.isNotEmpty && _collapsedDicts.contains(dictId);

    // 折叠状态：非第一条 entry 直接隐藏
    if (isCollapsed && !showDictHeader) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDictHeader)
              _buildDictionaryHeader(
                entry,
                isCollapsed: isCollapsed,
                onToggle: dictId.isEmpty
                    ? null
                    : () => setState(() {
                        if (_collapsedDicts.contains(dictId)) {
                          _collapsedDicts.remove(dictId);
                        } else {
                          _collapsedDicts.add(dictId);
                        }
                      }),
              ),
            if (!isCollapsed)
              ...([
                if (relations != null && relations.isNotEmpty)
                  _buildInlineDictRelationBanner(relations),
                ComponentRenderer(
                  key: ValueKey(entry.id),
                  entry: entry,
                  topPadding: 12,
                  onElementTap: (path, label) {
                    _handleTranslationTap(entry, path, label);
                  },
                  onEditElement: (path, label) {
                    _showJsonElementEditorFromPath(entry, path);
                  },
                  onAiAsk: (path, label) {
                    _handleAiElementTap(entry, path, label);
                  },
                  onTranslationInsert: (path, newEntry) {
                    EntryEventBus().emitTranslationInsert(
                      TranslationInsertEvent(
                        entryId: entry.id,
                        path: path,
                        newEntry: newEntry.toJson(),
                      ),
                    );
                  },
                ),
              ]),
          ],
        ),
      ),
    );
  }

  /// 每个词典条目顶部显示词典 Logo + 名称，可点击折叠/展开
  Widget _buildDictionaryHeader(
    DictionaryEntry entry, {
    bool isCollapsed = false,
    VoidCallback? onToggle,
  }) {
    final dictId = entry.dictId ?? '';
    if (dictId.isEmpty) return const SizedBox.shrink();

    final cachedMeta = DictionaryManager().getCachedMetadata(dictId);
    final dictName = cachedMeta?.name ?? dictId;
    final colorScheme = Theme.of(context).colorScheme;
    const hPad = 16.0;

    // 过滤出非空的 anchor
    final nonEmptyAnchors = entry.matchedAnchors
        .where((item) => item.$2.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(),
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.only(
                left: hPad,
                right: hPad,
                top: 6,
                bottom: 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: DictionaryLogo(
                      dictionaryId: dictId,
                      dictionaryName: dictName,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    dictName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface.withOpacity(0.75),
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 居中横线充满剩余空间
                  Expanded(
                    child: Divider(
                      thickness: 1,
                      color: colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 显示 anchor 图标
                  ...nonEmptyAnchors.map((item) {
                    final anchor = item.$2;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: '跳转到: $anchor',
                        child: InkWell(
                          onTap: () => _scrollToElement(entry.id, anchor),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.link,
                              size: 16,
                              color: colorScheme.primary.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 词性缩写辅助方法
  String _shortenPos(String? pos) {
    switch (pos) {
      case 'noun':
        return 'n.';
      case 'verb':
        return 'v.';
      case 'adj':
        return 'adj.';
      case 'adv':
        return 'adv.';
      case 'prep':
        return 'prep.';
      default:
        return pos ?? '';
    }
  }

  /// 单词关系横幅，显示在所有词典条目顶部，展示 spelling_variant / nominalization / inflection 命中结果
  Widget _buildWordRelationsBanner() {
    if (_wordRelationsFuture == null) {
      // SafeArea 已处理顶部安全区域，此处无需额外间距
      return const SizedBox.shrink();
    }

    // 列名显示标签
    final Map<String, String> colLabels = {
      'word1': '',
      'word2': '',
      'base': context.t.entry.morphBase,
      'nominal': context.t.entry.morphNominal,
      'plural': context.t.entry.morphPlural,
      'past': context.t.entry.morphPast,
      'past_part': context.t.entry.morphPastPart,
      'pres_part': context.t.entry.morphPresPart,
      'third_sing': context.t.entry.morphThirdSing,
      'comp': context.t.entry.morphComp,
      'superl': context.t.entry.morphSuperl,
    };
    final Map<String, String> tableLabels = {
      'spelling_variant': context.t.entry.morphSpellingVariant,
      'nominalization': context.t.entry.morphNominalization,
      'inflection': context.t.entry.morphInflection,
    };

    return FutureBuilder<List<WordRelationRow>>(
      future: _wordRelationsFuture,
      builder: (context, snapshot) {
        final rows = snapshot.data;

        if (rows == null || rows.isEmpty) {
          return const SizedBox.shrink();
        }

        // 预处理：合并 inflection 行并处理不可数名词、空行过滤
        final processedRows = _preprocessInflectionRows(rows);

        final colorScheme = Theme.of(context).colorScheme;
        const hPad = 16.0;

        // 预先过滤掉没有有效字段的行，方便 Table 逐行渲染
        final visibleRows = processedRows.where((row) {
          return row.fields.entries.any(
            (e) => e.key != 'pos' && e.value != null && e.value!.isNotEmpty,
          );
        }).toList();

        if (visibleRows.isEmpty) return const SizedBox.shrink();

        // 用 Table 代替 Column+Row，第一列宽度由内容决定，第二列占满剩余空间
        return Container(
          width: double.infinity,
          color: colorScheme.surface,
          padding: EdgeInsets.only(left: hPad, right: hPad, top: 6, bottom: 28),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: visibleRows.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;

              final pos = row.fields['pos'];
              final posLabel = _shortenPos(pos);
              final baseLabel = tableLabels[row.tableName] ?? row.tableName;
              final tableLabel = posLabel.isNotEmpty
                  ? '$baseLabel $posLabel'
                  : baseLabel;

              final nonNullFields = row.fields.entries
                  .where(
                    (e) =>
                        e.key != 'pos' &&
                        e.value != null &&
                        e.value!.isNotEmpty,
                  )
                  .toList();

              return TableRow(
                children: [
                  // ── 第一列：表类型+词性标签，宽度自适应，右对齐 ──────────
                  TableCell(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: rowIndex == 0 ? 0 : 10,
                        right: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer.withOpacity(
                              0.7,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tableLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSecondaryContainer,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── 第二列：词形chips ────────────────────────────────────
                  TableCell(
                    child: Padding(
                      padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 10),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: nonNullFields.map((field) {
                          final colLabel = colLabels[field.key] ?? field.key;
                          final wordVal = field.value!;
                          // 合并胶囊（如"sawn, sawed"）：拆分后检查任一分量是否命中当前词
                          final isCurrentWord = wordVal
                              .split(', ')
                              .any(
                                (v) =>
                                    v.toLowerCase() ==
                                    widget.initialWord.toLowerCase(),
                              );

                          // 将词值按 ", " 拆分，分别渲染（支持单词点击查词，"不可数"不可点击且字体更小）
                          final tokens = wordVal.split(', ');
                          final tokenWidgets = <Widget>[];
                          for (int ti = 0; ti < tokens.length; ti++) {
                            final token = tokens[ti];
                            final isNotCount = token == '不可数';
                            final isTokenCurrentWord =
                                token.toLowerCase() ==
                                widget.initialWord.toLowerCase();
                            if (ti > 0) {
                              tokenWidgets.add(
                                Text(
                                  ', ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    color: isCurrentWord
                                        ? colorScheme.onPrimaryContainer
                                              .withOpacity(0.5)
                                        : colorScheme.onSurfaceVariant
                                              .withOpacity(0.5),
                                  ),
                                ),
                              );
                            }
                            Widget tokenWidget = Text(
                              isNotCount ? context.t.entry.uncountable : token,
                              style: TextStyle(
                                fontSize: isNotCount ? 11 : 13,
                                height: 1.2,
                                fontWeight: isTokenCurrentWord
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isNotCount
                                    ? (isCurrentWord
                                          ? colorScheme.onPrimaryContainer
                                                .withOpacity(0.55)
                                          : colorScheme.onSurfaceVariant
                                                .withOpacity(0.65))
                                    : (isTokenCurrentWord
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.primary),
                              ),
                            );
                            if (!isNotCount && !isTokenCurrentWord) {
                              tokenWidget = MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _navigateToWord(token),
                                  child: tokenWidget,
                                ),
                              );
                            }
                            tokenWidgets.add(tokenWidget);
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrentWord
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isCurrentWord
                                    ? colorScheme.primary.withOpacity(0.4)
                                    : colorScheme.outlineVariant.withOpacity(
                                        0.4,
                                      ),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (colLabel.isNotEmpty)
                                  ...(([
                                    Text(
                                      colLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.2,
                                        color: isCurrentWord
                                            ? colorScheme.onPrimaryContainer
                                                  .withOpacity(0.65)
                                            : colorScheme.onSurfaceVariant
                                                  .withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ])),
                                ...tokenWidgets,
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// 预处理 inflection 名词行：不可数名词显示"不可数"，多行合并为一行
  /// 预处理 inflection 行：
  /// - 相同 base+pos 的多个 inflection 行合并为一行（各字段去重后 ', ' 连接）
  /// - 名词行：plural 为空且无其他变形列时，视为不可数名词，plural 显示"不可数"
  /// - 名词以外的词性：如果除 base/pos 外所有字段均无数据，则整行跳过
  List<WordRelationRow> _preprocessInflectionRows(List<WordRelationRow> rows) {
    // 非 inflection 行直接保留，inflection 行按 base|pos 分组
    final nonInflectionRows = <WordRelationRow>[];

    // 'base|pos' → (firstIndex, list of rows) ── firstIndex 用于保持原始顺序
    final Map<String, (int, List<WordRelationRow>)> inflectionGroups = {};
    int inflectionFirstSeen = 0;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.tableName != 'inflection') {
        nonInflectionRows.add(row);
        continue;
      }
      final base = row.fields['base'] ?? '';
      final pos = row.fields['pos'] ?? '';
      final groupKey = '$base|$pos';
      if (!inflectionGroups.containsKey(groupKey)) {
        inflectionGroups[groupKey] = (inflectionFirstSeen++, []);
      }
      inflectionGroups[groupKey]!.$2.add(row);
    }

    // 名词变形以外的列（用于判断是否"仅有 base"）
    const nonNounCols = [
      'plural',
      'past',
      'past_part',
      'pres_part',
      'third_sing',
      'comp',
      'superl',
    ];

    // 逐 base|pos 组合并
    final mergedInflections = <(int, WordRelationRow)>[];

    inflectionGroups.forEach((groupKey, record) {
      final (sortKey, groupRows) = record;
      if (groupRows.isEmpty) return;

      final pos = groupRows.first.fields['pos'] ?? '';
      final isNoun = pos == 'noun';

      if (isNoun) {
        // ── 名词：收集每行的 plural 值（空 plural = 不可数）──────────────
        final seenPluralValues = <String>[];
        for (final row in groupRows) {
          final plural = row.fields['plural'];
          final hasOtherNonNounContent = nonNounCols
              .where((c) => c != 'plural')
              .any((col) {
                final v = row.fields[col];
                return v != null && v.isNotEmpty;
              });
          if ((plural == null || plural.isEmpty) && !hasOtherNonNounContent) {
            if (!seenPluralValues.contains('不可数')) {
              seenPluralValues.add('不可数');
            }
          } else if (plural != null && plural.isNotEmpty) {
            if (!seenPluralValues.contains(plural)) {
              seenPluralValues.add(plural);
            }
          }
        }

        // 用第一行作为模板，写入合并后的 plural
        final template = groupRows.first;
        final mergedFields = <String, String?>{};
        for (final entry in template.fields.entries) {
          mergedFields[entry.key] = entry.value;
        }
        mergedFields['plural'] = seenPluralValues.isNotEmpty
            ? seenPluralValues.join(', ')
            : null;

        mergedInflections.add((
          sortKey,
          WordRelationRow(tableName: 'inflection', fields: mergedFields),
        ));
      } else {
        // ── 非名词：按字段收集所有唯一非空值 ────────────────────────────
        // 先检查是否所有行除了 base/pos 全为空
        final allEmpty = groupRows.every((row) {
          return nonNounCols.every((col) {
            final v = row.fields[col];
            return v == null || v.isEmpty;
          });
        });
        if (allEmpty) return; // 跳过无实际变形数据的行

        // 收集每列的唯一值
        final colValues = <String, List<String>>{};
        for (final row in groupRows) {
          for (final entry in row.fields.entries) {
            if (entry.key == 'pos' || entry.key == 'base') continue;
            final v = entry.value;
            if (v != null && v.isNotEmpty) {
              colValues.putIfAbsent(entry.key, () => []);
              if (!colValues[entry.key]!.contains(v)) {
                colValues[entry.key]!.add(v);
              }
            }
          }
        }

        // 用第一行作为模板
        final template = groupRows.first;
        final mergedFields = <String, String?>{};
        for (final entry in template.fields.entries) {
          if (entry.key == 'pos' || entry.key == 'base') {
            mergedFields[entry.key] = entry.value;
          } else {
            final vals = colValues[entry.key];
            mergedFields[entry.key] = (vals != null && vals.isNotEmpty)
                ? vals.join(', ')
                : null;
          }
        }

        mergedInflections.add((
          sortKey,
          WordRelationRow(tableName: 'inflection', fields: mergedFields),
        ));
      }
    });

    // 按原始出现顺序排序合并后的 inflection 行
    mergedInflections.sort((a, b) => a.$1.compareTo(b.$1));

    // 重新拼回：非 inflection 行在前，inflection 合并行按顺序追加
    // 保持原始结构中非 inflection 先出现的顺序不变
    // 实际上原始列表可能交错，这里简化为：先遍历原列表，遇到第一个 inflection 时插入所有合并结果
    final result = <WordRelationRow>[];
    bool inflectionInserted = false;
    for (final row in rows) {
      if (row.tableName != 'inflection') {
        result.add(row);
      } else if (!inflectionInserted) {
        inflectionInserted = true;
        for (final pair in mergedInflections) {
          result.add(pair.$2);
        }
      }
      // 后续 inflection 行全部跳过（已合并）
    }
    if (!inflectionInserted) {
      for (final pair in mergedInflections) {
        result.add(pair.$2);
      }
    }

    return result;
  }

  /// 导航到指定单词的详情页
  void _navigateToWord(String word) async {
    if (word.isEmpty) return;
    if (word.toLowerCase() == widget.initialWord.toLowerCase()) return;

    final dbService = DatabaseService();
    final historyService = SearchHistoryService();

    final result = await dbService.getAllEntries(word, sourceLanguage: 'auto');

    if (result.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(result.entries);
      await historyService.addSearchRecord(word);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                EntryDetailPage(entryGroup: entryGroup, initialWord: word),
          ),
        );
      }
    } else {
      if (mounted) {
        showToast(context, context.t.entry.wordNotFound(word: word));
      }
    }
  }

  void _showJsonElementEditorFromPath(
    DictionaryEntry entry,
    String pathStr,
  ) async {
    try {
      final json = entry.toJson();
      final pathParts = pathStr.split('.');

      // 移除可能的根路径 'entry'
      if (pathParts.isNotEmpty && pathParts.first == 'entry') {
        pathParts.removeAt(0);
      }

      dynamic currentValue = json;

      for (final part in pathParts) {
        if (currentValue is Map) {
          if (currentValue.containsKey(part)) {
            currentValue = currentValue[part];
          } else {
            throw Exception('Key "$part" not found in map');
          }
        } else if (currentValue is List) {
          int? index;
          if (part.startsWith('[') && part.endsWith(']')) {
            index = int.tryParse(part.substring(1, part.length - 1));
          } else {
            index = int.tryParse(part);
          }

          if (index != null && index >= 0 && index < currentValue.length) {
            currentValue = currentValue[index];
          } else {
            throw Exception('Index "$part" out of bounds or invalid');
          }
        } else {
          throw Exception(
            'Cannot traverse path "$part" on ${currentValue.runtimeType}',
          );
        }
      }

      _showJsonElementEditor(entry, pathParts, currentValue);
    } catch (e) {
      Logger.d(
        'Error in _showJsonElementEditorFromPath: $e',
        tag: 'EntryDetailPage',
      );
      showToast(context, context.t.entry.processFailed(error: '$e'));
    }
  }

  void _showJsonElementEditor(
    DictionaryEntry entry,
    List<String> pathParts,
    dynamic initialValue, {
    bool isFromHistory = false,
    List<String>? initialPath,
  }) async {
    if (!isFromHistory) {
      if (_historyIndex < _pathHistory.length - 1) {
        _pathHistory.removeRange(_historyIndex + 1, _pathHistory.length);
      }
      _pathHistory.add(List<String>.from(pathParts));
      _historyIndex = _pathHistory.length - 1;
    }

    final startPath =
        initialPath ?? (isFromHistory ? null : List<String>.from(pathParts));

    final currentEntry = _getEntryById(entry.id) ?? entry;

    dynamic currentValue = initialValue;
    if (pathParts.isEmpty) {
      currentValue = currentEntry.toJson();
    } else {
      final json = currentEntry.toJson();
      dynamic temp = json;
      for (final part in pathParts) {
        if (temp is Map) {
          temp = temp[part];
        } else if (temp is List) {
          int? index;
          if (part.startsWith('[') && part.endsWith(']')) {
            index = int.tryParse(part.substring(1, part.length - 1));
          } else {
            index = int.tryParse(part);
          }
          if (index != null) {
            temp = temp[index];
          }
        }
      }
      currentValue = temp;
    }

    final initialText = const JsonEncoder.withIndent(
      '  ',
    ).convert(currentValue);

    final pageContext = context;
    // 提前从父级 context 获取状态栏高度，底部弹出层的 context 中 viewPadding.top 为 0
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => JsonEditorBottomSheet(
        entry: currentEntry,
        pathParts: pathParts,
        initialText: initialText,
        historyIndex: _historyIndex,
        pathHistory: _pathHistory,
        initialPath: startPath,
        statusBarHeight: statusBarHeight,
        onSave: (newValue) async {
          await _saveElementChange(
            currentEntry,
            pathParts,
            newValue,
            toastContext: pageContext,
          );
          if (mounted) {
            setState(() {});
          }
        },
        onNavigate: (newPathParts, newValue) {
          _showJsonElementEditor(
            currentEntry,
            newPathParts,
            newValue,
            isFromHistory: true,
            initialPath: startPath,
          );
        },
      ),
    );
  }

  DictionaryEntry? _getEntryById(String entryId) {
    for (final dictGroup in _entryGroup.dictionaryGroups) {
      for (final pageGroup in dictGroup.pageGroups) {
        for (final section in pageGroup.sections) {
          if (section.entry.id == entryId) {
            return section.entry;
          }
        }
      }
    }
    return null;
  }

  Future<DictionaryEntry?> _saveElementChange(
    DictionaryEntry entry,
    List<String> pathParts,
    dynamic newValue, {
    BuildContext? toastContext,
  }) async {
    try {
      final fullJson = entry.toJson();

      if (pathParts.isEmpty) {
        if (newValue is! Map<String, dynamic>) {
          throw Exception(context.t.entry.rootMustBeObject);
        }
        fullJson.clear();
        fullJson.addAll(newValue);
      } else {
        dynamic current = fullJson;

        for (int i = 0; i < pathParts.length - 1; i++) {
          final part = pathParts[i];
          if (current is Map) {
            current = current[part];
          } else if (current is List) {
            int? index;
            if (part.startsWith('[') && part.endsWith(']')) {
              index = int.tryParse(part.substring(1, part.length - 1));
            } else {
              index = int.tryParse(part);
            }
            current = current[index!];
          }
        }

        final lastPart = pathParts.last;
        if (current is Map) {
          current[lastPart] = newValue;
        } else if (current is List) {
          int? index;
          if (lastPart.startsWith('[') && lastPart.endsWith(']')) {
            index = int.tryParse(lastPart.substring(1, lastPart.length - 1));
          } else {
            index = int.tryParse(lastPart);
          }
          current[index!] = newValue;
        }
      }

      // Preserve the original entry ID (which may be a composite like 'dictid_42')
      // so that _updateEntryInGroup can find and replace the entry correctly.
      fullJson['entry_id'] = entry.id;
      final newEntry = DictionaryEntry.fromJson(fullJson);
      final success = await DatabaseService().insertOrUpdateEntry(newEntry);

      if (success) {
        _updateEntryInGroup(newEntry);
        if (mounted) {
          showToast(toastContext ?? context, context.t.entry.saveSuccess);
        }
        return newEntry;
      } else {
        throw Exception(context.t.entry.dbUpdateFailed);
      }
    } catch (e) {
      if (mounted) {
        showToast(
          toastContext ?? context,
          context.t.entry.saveFailed(error: '$e'),
        );
      }
      return null;
    }
  }

  // ==================== AI模式相关函数 ====================

  /// 处理AI模式下点击元素
  void _handleAiElementTap(DictionaryEntry entry, String path, String label) {
    _processAiDialog(entry, path, label);
  }

  /// 处理普通模式下点击元素（尝试翻译或查词）
  void _handleTranslationTap(
    DictionaryEntry entry,
    String path,
    String label,
  ) async {
    // 处理查词请求（来自文本选择）
    if (path.startsWith('lookup:')) {
      final word = path.substring(7); // 移除 'lookup:' 前缀
      _navigateToWord(word);
      return;
    }

    try {
      final metadata = await DictionaryManager().getDictionaryMetadata(
        entry.dictId ?? '',
      );
      if (metadata == null) {
        return;
      }

      final sourceLang = metadata.sourceLanguage;
      final targetLangs = metadata.targetLanguages;
      final targetLang = targetLangs.firstWhere(
        (lang) => lang != sourceLang,
        orElse: () => '',
      );

      if (targetLang.isEmpty) {
        return;
      }

      final pathParts = path.split('.');
      if (pathParts.isNotEmpty && pathParts.first == 'entry') {
        pathParts.removeAt(0);
      }

      // 获取最后一个 key（即被点击的字段名）
      final lastKey = pathParts.isNotEmpty ? pathParts.last : '';

      // 检查最后一个 key 是否是语言代码（在 languageNames 中定义的 key）
      final isLanguageCode =
          LanguageUtils.getLanguageDisplayName(lastKey) !=
          lastKey.toUpperCase();

      if (!isLanguageCode) {
        return;
      }

      final json = entry.toJson();
      dynamic parentValue = json;
      dynamic currentValue = json;

      for (int i = 0; i < pathParts.length; i++) {
        final part = pathParts[i];

        if (i < pathParts.length - 1) {
          if (parentValue is Map) {
            parentValue = parentValue[part];
          } else if (parentValue is List) {
            int? index = int.tryParse(part);
            if (index != null) parentValue = parentValue[index];
          }
        }

        if (currentValue is Map) {
          currentValue = currentValue[part];
        } else if (currentValue is List) {
          int? index = int.tryParse(part);
          if (index != null) currentValue = currentValue[index];
        }
      }

      String textToTranslate = '';
      bool needTranslation = false;
      bool needToggleTranslation = false;

      // 如果点击的是源语言 key
      if (lastKey == sourceLang) {
        if (parentValue is Map) {
          if (!parentValue.containsKey(targetLang)) {
            // 没有目标语言翻译，需要翻译
            textToTranslate = currentValue as String;
            needTranslation = true;
          } else {
            // 已有目标语言翻译，需要切换显示/隐藏
            needToggleTranslation = true;
          }
        }
      } else if (lastKey == targetLang) {
        // 点击的是目标语言，需要切换显示/隐藏
        needToggleTranslation = true;
      } else {
        // 如果点击的是其他语言代码 key
        if (currentValue is String) {
          // 直接翻译当前值
          textToTranslate = currentValue;
          needTranslation = true;
        } else if (currentValue is Map) {
          if (currentValue.containsKey(sourceLang) &&
              !currentValue.containsKey(targetLang)) {
            textToTranslate = currentValue[sourceLang] as String;
            needTranslation = true;
          }
        }
      }

      if (needTranslation && textToTranslate.isNotEmpty) {
        // 去除格式标记并替换波浪线后再进行翻译
        final plainText = _substituteHeadword(
          _removeFormatting(textToTranslate),
          entry,
        );
        _performTranslation(
          entry,
          pathParts,
          plainText,
          targetLang,
          sourceLang,
        );
      } else if (needToggleTranslation) {
        // 如果是语言切换，ComponentRenderer 已经本地更新了 UI，这里不需要 setState
        _toggleTranslationVisibility(
          entry,
          pathParts,
          targetLang,
          sourceLang,
          shouldSetState: false,
        );
      }
    } catch (e) {
      showToast(context, context.t.entry.processFailed(error: '$e'));
    }
  }

  /// 根据元素路径判断翻译类型，返回对应的 system prompt。
  /// - 路径中包含 "definition" → 词典释义专用提示词
  /// - 路径中包含 "example" → 例句专用提示词
  /// - 其他 → 通用补充信息提示词
  String _getTranslationSystemPrompt(List<String> pathParts) {
    final pathStr = pathParts.join('.').toLowerCase();
    if (pathStr.contains('definition')) {
      return 'You are a professional lexicographer and translator. '
          'Translate the given dictionary definition to be concise, precise, and formal. '
          'Ensure the translation matches the grammatical category of the original '
          '(e.g., using noun phrases for nouns). '
          'Output only the translated text — no explanations, no commentary.';
    } else if (pathStr.contains('example')) {
      return 'You are a professional translator specializing in linguistic context. '
          'Translate the given dictionary example sentence to be natural and idiomatic. '
          'Ensure the translation accurately reflects the specific usage and nuance '
          'of the keyword in context. '
          'Output only the translated text — no explanations, no commentary.';
    } else {
      return 'You are a professional linguistic consultant. '
          'Translate the given supplementary dictionary information '
          '(such as usage notes, etymology, or grammatical labels). '
          'Maintain technical accuracy, use professional terminology, '
          'and preserve any abbreviations or special symbols. '
          'Output only the translated text — no explanations, no commentary.';
    }
  }

  Future<void> _performTranslation(
    DictionaryEntry entry,
    List<String> pathParts,
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    showToast(context, context.t.entry.translating);

    try {
      final systemPrompt = _getTranslationSystemPrompt(pathParts);
      final translation = await AIService().translate(
        text,
        targetLang,
        systemPrompt: systemPrompt,
      );
      // 给AI翻译结果添加格式化标记
      final formattedTranslation = '[$translation](ai)';

      final json = entry.toJson();
      dynamic current = json;

      List<String> targetPath = List.from(pathParts);
      if (targetPath.isNotEmpty && targetPath.last == sourceLang) {
        targetPath.removeLast();
      }

      for (final part in targetPath) {
        if (current is Map) {
          current = current[part];
        } else if (current is List) {
          int? index = int.tryParse(part);
          if (index != null) current = current[index];
        }
      }

      if (current is Map) {
        current[targetLang] = formattedTranslation;

        final newEntry = DictionaryEntry.fromJson(json);
        await DatabaseService().insertOrUpdateEntry(newEntry, skipCommit: true);

        final hiddenPath = targetPath.join('.');
        final hiddenKey = '$hiddenPath.$targetLang';

        EntryEventBus().emitTranslationInsert(
          TranslationInsertEvent(
            entryId: entry.id,
            path: hiddenKey,
            newEntry: newEntry.toJson(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(context, context.t.entry.translateFailed(error: '$e'));
      }
    }
  }

  Future<void> _toggleTranslationVisibility(
    DictionaryEntry entry,
    List<String> pathParts,
    String targetLang,
    String sourceLang, {
    bool shouldSetState = true,
  }) async {
    // 不再保存到数据库，只通过 ComponentRenderer 的 _hiddenLanguagesNotifier 更新本地状态
    // 这样每次重新查词时都会重置为显示状态
    try {
      List<String> parentPath = List.from(pathParts);
      if (parentPath.isNotEmpty && parentPath.last == sourceLang) {
        parentPath.removeLast();
      } else if (parentPath.isNotEmpty && parentPath.last == targetLang) {
        parentPath.removeLast();
      }

      final hiddenPath = parentPath.join('.');
      final hiddenKey = '$hiddenPath.$targetLang';

      EntryEventBus().emitToggleHiddenLanguage(
        ToggleHiddenLanguageEvent(entryId: entry.id, languageKey: hiddenKey),
      );
    } catch (e) {
      Logger.d('Error in _toggleTranslationVisibility: $e', tag: 'Translation');
      if (mounted) {
        showToast(context, context.t.entry.toggleFailed(error: '$e'));
      }
    }
  }

  /// 一键切换所有非目标语言的显示/隐藏
  /// 保存到全局设置（shared_preferences），同时更新本地状态
  Future<void> _toggleAllNonTargetLanguages() async {
    try {
      final entries = _getAllEntriesInOrder();
      if (entries.isEmpty) return;

      // 获取当前词典的元数据
      final currentDictId = _entryGroup.currentDictionaryId;
      if (currentDictId.isEmpty) return;

      final metadata = await DictionaryManager().getDictionaryMetadata(
        currentDictId,
      );
      if (metadata == null) return;

      final sourceLang = metadata.sourceLanguage;
      final targetLangs = metadata.targetLanguages;

      // 收集所有需要切换的语言路径（目标语言列表扣除源语言）
      final Set<String> languagePaths = {};

      for (final entry in entries) {
        final json = entry.toJson();
        _collectLanguagePaths(json, '', languagePaths, sourceLang, targetLangs);
      }

      // 切换显示状态
      final newVisibility = !_isNonTargetLanguagesVisible;
      setState(() {
        _areNonTargetLanguagesVisible = newVisibility;
      });

      // 保存到全局设置
      await PreferencesService().setGlobalTranslationVisibility(newVisibility);

      // 应用全局状态到 ComponentRenderer，实现实时切换
      await _applyGlobalTranslationVisibility(newVisibility);
    } catch (e) {
      Logger.d('Error in _toggleAllNonTargetLanguages: $e', tag: 'Translation');
      if (mounted) {
        showToast(context, context.t.entry.toggleFailed(error: '$e'));
      }
    }
  }

  /// 递归收集所有目标语言的路径（目标语言列表扣除源语言，只收集有实际翻译内容的）
  void _collectLanguagePaths(
    dynamic data,
    String currentPath,
    Set<String> languagePaths,
    String sourceLang,
    List<String> targetLangs,
  ) {
    // 计算有效的目标语言列表（目标语言列表扣除源语言）
    final effectiveTargetLangs = targetLangs
        .where((lang) => lang != sourceLang)
        .toSet();

    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        final newPath = currentPath.isEmpty ? key : '$currentPath.$key';

        // 检查是否是有效的目标语言（在目标语言列表中且不是源语言）
        final isLanguageCode =
            LanguageUtils.getLanguageDisplayName(key) != key.toUpperCase();
        if (isLanguageCode && effectiveTargetLangs.contains(key)) {
          // 只收集有实际翻译内容的目标语言
          // 值可以是字符串、非空列表或非空Map
          final hasTranslation = _hasTranslationContent(value);
          if (hasTranslation) {
            languagePaths.add(newPath);
          }
        }

        // 递归处理
        if (value is Map || value is List) {
          _collectLanguagePaths(
            value,
            newPath,
            languagePaths,
            sourceLang,
            targetLangs,
          );
        }
      }
    } else if (data is List<dynamic>) {
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        // 使用与 ComponentRenderer 相同的格式：直接数字，不带方括号
        final newPath = currentPath.isEmpty ? '$i' : '$currentPath.$i';
        if (item is Map || item is List) {
          _collectLanguagePaths(
            item,
            newPath,
            languagePaths,
            sourceLang,
            targetLangs,
          );
        }
      }
    }
  }

  /// 检查是否有翻译内容
  bool _hasTranslationContent(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  void _processAiDialog(DictionaryEntry entry, String path, String label) {
    final pathParts = path.split('.');
    if (pathParts.isNotEmpty && pathParts.first == 'entry') {
      pathParts.removeAt(0);
    }

    final json = entry.toJson();
    dynamic currentValue = json;
    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index = int.tryParse(part);
        if (index != null) currentValue = currentValue[index];
      }
    }

    // 去除格式化文本中的格式标记并替换波浪线
    if (currentValue is String) {
      currentValue = _substituteHeadword(
        _removeFormatting(currentValue),
        entry,
      );
    } else if (currentValue is Map) {
      // 如果是对象，递归处理所有字符串字段
      currentValue = _removeFormattingFromMap(currentValue);
    }

    _showAiElementDialog(entry, pathParts, currentValue);
  }

  /// 从Map中递归去除格式化
  dynamic _removeFormattingFromMap(Map map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      if (entry.value is String) {
        result[entry.key] = _removeFormatting(entry.value as String);
      } else if (entry.value is Map) {
        result[entry.key] = _removeFormattingFromMap(entry.value as Map);
      } else if (entry.value is List) {
        result[entry.key] = _removeFormattingFromList(entry.value as List);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// 从List中递归去除格式化
  List<dynamic> _removeFormattingFromList(List list) {
    final result = <dynamic>[];
    for (final item in list) {
      if (item is String) {
        result.add(_removeFormatting(item));
      } else if (item is Map) {
        result.add(_removeFormattingFromMap(item));
      } else if (item is List) {
        result.add(_removeFormattingFromList(item));
      } else {
        result.add(item);
      }
    }
    return result;
  }

  /// 去除文本格式，将 [text](style) 转换为 text
  String _removeFormatting(String text) {
    final RegExp pattern = RegExp(r'\[([^\]]*?)\]\([^\)]*?\)');
    return text.replaceAllMapped(pattern, (match) => match.group(1) ?? '');
  }

  /// 对中文词典的文本，将波浪线（～、～）替换为 entry 的 headword
  String _substituteHeadword(String text, DictionaryEntry entry) {
    final dictId = entry.dictId ?? '';
    final meta = DictionaryManager().getCachedMetadata(dictId);
    if (LanguageUtils.normalizeSourceLanguage(meta?.sourceLanguage ?? '') ==
        'zh') {
      return text
          .replaceAll('～', entry.headword)
          .replaceAll('\u301c', entry.headword);
    }
    return text;
  }

  /// 显示AI元素对话框
  void _showAiElementDialog(
    DictionaryEntry entry,
    List<String> pathParts,
    dynamic elementValue, {
    bool isFromHistory = false,
    List<String>? initialPath, // 新增：初始路径
  }) {
    // 如果不是从历史记录导航过来的，添加新路径到历史
    if (!isFromHistory) {
      // 如果当前不是历史栈的末尾，删除后面的历史
      if (_historyIndex < _pathHistory.length - 1) {
        _pathHistory.removeRange(_historyIndex + 1, _pathHistory.length);
      }
      _pathHistory.add(List<String>.from(pathParts));
      _historyIndex = _pathHistory.length - 1;
    }

    // 记录初始路径（如果是第一次打开）
    final startPath =
        initialPath ?? (isFromHistory ? null : List<String>.from(pathParts));

    final questionController = TextEditingController();
    final elementJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(elementValue);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PathNavigator(
                        pathParts: pathParts,
                        onNavigate: (newPathParts) {
                          Navigator.pop(context);
                          final json = entry.toJson();
                          dynamic currentValue = json;
                          for (final part in newPathParts) {
                            if (currentValue is Map) {
                              currentValue = currentValue[part];
                            } else if (currentValue is List) {
                              int? index;
                              if (part.startsWith('[') && part.endsWith(']')) {
                                index = int.tryParse(
                                  part.substring(1, part.length - 1),
                                );
                              } else {
                                index = int.tryParse(part);
                              }
                              if (index != null &&
                                  index < currentValue.length) {
                                currentValue = currentValue[index];
                              }
                            }
                          }
                          _showAiElementDialog(
                            entry,
                            newPathParts,
                            currentValue,
                            initialPath: startPath,
                          );
                        },
                        onHomeTap: () {
                          Navigator.pop(context);
                          final json = entry.toJson();
                          _showAiElementDialog(
                            entry,
                            [],
                            json,
                            initialPath: startPath,
                          );
                        },
                        showReturnToStart:
                            startPath != null &&
                            pathParts.join('.') != startPath.join('.'),
                        onReturnToStart:
                            startPath != null &&
                                pathParts.join('.') != startPath.join('.')
                            ? () {
                                Navigator.pop(context);
                                final json = entry.toJson();
                                dynamic currentValue = json;
                                for (final part in startPath) {
                                  if (currentValue is Map) {
                                    currentValue = currentValue[part];
                                  } else if (currentValue is List) {
                                    int? index;
                                    if (part.startsWith('[') &&
                                        part.endsWith(']')) {
                                      index = int.tryParse(
                                        part.substring(1, part.length - 1),
                                      );
                                    } else {
                                      index = int.tryParse(part);
                                    }
                                    if (index != null &&
                                        index < currentValue.length) {
                                      currentValue = currentValue[index];
                                    }
                                  }
                                }
                                _showAiElementDialog(
                                  entry,
                                  startPath,
                                  currentValue,
                                  initialPath: startPath,
                                );
                              }
                            : null,
                        validatePath: (newPath) {
                          final json = entry.toJson();
                          dynamic currentValue = json;
                          for (final part in newPath) {
                            if (currentValue is Map) {
                              if (currentValue.containsKey(part)) {
                                currentValue = currentValue[part];
                              } else {
                                return context.t.entry.pathNotFound;
                              }
                            } else if (currentValue is List) {
                              int? index;
                              if (part.startsWith('[') && part.endsWith(']')) {
                                index = int.tryParse(
                                  part.substring(1, part.length - 1),
                                );
                              } else {
                                index = int.tryParse(part);
                              }
                              if (index != null &&
                                  index >= 0 &&
                                  index < currentValue.length) {
                                currentValue = currentValue[index];
                              } else {
                                return context.t.entry.pathNotFound;
                              }
                            } else {
                              return context.t.entry.pathNotFound;
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 显示JSON内容（直接显示，限制最大高度）
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      elementJson,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 问题输入框
                TextField(
                  controller: questionController,
                  maxLines: 3,
                  minLines: 1,
                  style: TextStyle(
                    color: questionController.text.isEmpty
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: context.t.entry.explainPrompt(
                      word: entry.headword,
                    ),
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.7),
                    ),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () async {
                        final inputText = questionController.text.trim();
                        // 如果用户输入为空，使用默认问题
                        final question = inputText.isEmpty
                            ? context.t.entry.explainPrompt(
                                word: entry.headword,
                              )
                            : inputText;
                        Navigator.pop(context);
                        await _askAiAboutElement(
                          elementJson,
                          pathParts.join('.'),
                          question,
                          word: entry.headword,
                          dictionaryId:
                              _entryGroup.currentDictionaryGroup.dictionaryId,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.t.common.cancel),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 向AI询问元素（流式输出）
  Future<void> _askAiAboutElement(
    String elementJson,
    String path,
    String question, {
    String? word,
    String? dictionaryId,
  }) async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final targetWord = word ?? widget.initialWord;

    // 格式化JSON为密集文本（移除换行和多余空格）
    final compactJson = _formatCompactJson(elementJson);

    // 每次询问词典元素都开一个新会话
    final conversationId = requestId;

    // 创建加载中的记录
    final record = AiChatRecord(
      id: requestId,
      conversationId: conversationId,
      word: targetWord,
      question: question,
      answer: '',
      timestamp: DateTime.now(),
      path: path,
      elementJson: compactJson,
      dictionaryId: dictionaryId,
    );
    _aiChatHistory.add(record);
    _currentLoadingId = requestId;
    _autoExpandIds.add(requestId);
    _streamingNotifiers[requestId] = ValueNotifier<(String, String?, bool)>((
      '',
      null,
      false,
    ));

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        conversationId: conversationId,
        word: targetWord,
        question: question,
        answer: '',
        timestamp: record.timestamp,
        path: path,
        elementJson: compactJson,
        dictionaryId: dictionaryId,
      ),
    );

    // 刷新UI：面板已打开则更新列表，否则立即打开面板
    setState(() {});
    if (_isModalActive) {
      _safeModalSetState();
    } else if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAiChatHistory(initialConversationId: conversationId);
      });
    }

    // 启动流式请求
    final appLanguage = LocaleSettings.instance.currentLocale == AppLocale.zh
        ? 'Chinese'
        : 'English';
    final stream = _aiService.askAboutElementStream(
      elementJson,
      question,
      appLanguage: appLanguage,
    );
    final sub = stream.listen(
      (chunk) {
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx == -1) return;
        if (chunk.text != null) {
          _aiChatHistory[idx].answer += chunk.text!;
        }
        if (chunk.thinking != null) {
          _aiChatHistory[idx].thinkingContent =
              (_aiChatHistory[idx].thinkingContent ?? '') + chunk.thinking!;
        }
        // 80ms 节流：每个周期内第一个 chunk 启动一个定时器，到期再批量推送 UI更新
        if (_streamingThrottleTimers[requestId] == null) {
          _streamingThrottleTimers[requestId] = Timer(
            const Duration(milliseconds: 80),
            () {
              _streamingThrottleTimers[requestId] = null;
              final i = _aiChatHistory.indexWhere((r) => r.id == requestId);
              if (i != -1) {
                _streamingNotifiers[requestId]?.value = (
                  _aiChatHistory[i].answer,
                  _aiChatHistory[i].thinkingContent,
                  false,
                );
              }
            },
          );
        }
      },
      onDone: () {
        // 取消节流定时器并做最终一次全量刷新
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        _pendingRequestsVersionNotifier.value++;
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _streamingNotifiers[requestId]?.value = (
            _aiChatHistory[idx].answer,
            _aiChatHistory[idx].thinkingContent,
            true,
          );
        }
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        if (idx != -1) {
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: conversationId,
              word: targetWord,
              question: question,
              answer: _aiChatHistory[idx].answer,
              timestamp: _aiChatHistory[idx].timestamp,
              path: path,
              elementJson: compactJson,
              dictionaryId: dictionaryId,
            ),
          );
        }
      },
      onError: (e) {
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        _pendingRequestsVersionNotifier.value++;
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _aiChatHistory[idx].answer =
              '${context.t.entry.aiRequestFailedShort} $e';
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: conversationId,
              word: targetWord,
              question: question,
              answer: '${context.t.entry.aiRequestFailedShort} $e',
              timestamp: _aiChatHistory[idx].timestamp,
              path: path,
              elementJson: compactJson,
              dictionaryId: dictionaryId,
            ),
          );
        }
        if (mounted) {
          showToast(context, context.t.entry.aiRequestFailed(error: '$e'));
        }
      },
      cancelOnError: true,
    );
    _pendingAiRequests[requestId] = sub;
    _pendingRequestsVersionNotifier.value++;
  }

  /// 将JSON格式化为紧凑文本（移除换行和多余空格）
  String _formatCompactJson(String jsonStr) {
    try {
      // 先解析再重新编码，确保是有效的JSON
      final decoded = jsonDecode(jsonStr);
      // 使用自定义编码，不换行
      final buffer = StringBuffer();
      _writeCompactJson(decoded, buffer);
      return buffer.toString();
    } catch (e) {
      // 如果解析失败，直接返回原字符串并移除换行
      return jsonStr.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    }
  }

  /// 递归写入紧凑JSON
  void _writeCompactJson(dynamic value, StringBuffer buffer) {
    if (value == null) {
      buffer.write('null');
    } else if (value is bool) {
      buffer.write(value);
    } else if (value is num) {
      buffer.write(value);
    } else if (value is String) {
      // 截断过长的字符串
      final displayStr = value.length > 100
          ? '${value.substring(0, 100)}...'
          : value;
      buffer.write('"$displayStr"');
    } else if (value is List) {
      buffer.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buffer.write(',');
        _writeCompactJson(value[i], buffer);
      }
      buffer.write(']');
    } else if (value is Map) {
      buffer.write('{');
      var first = true;
      value.forEach((key, val) {
        if (!first) buffer.write(',');
        first = false;
        buffer.write('"$key":');
        _writeCompactJson(val, buffer);
      });
      buffer.write('}');
    }
  }

  /// 安全调用弹窗 setState，防止弹窗已被 dispose 但 _isModalActive 尚未清除时崩溃
  void _safeModalSetState() {
    if (!_isModalActive || _modalSetState == null) return;
    try {
      _modalSetState!(() {});
    } catch (_) {
      _isModalActive = false;
      _modalSetState = null;
    }
  }

  /// 重新生成AI回答（支持"重新生成"/"简洁点"/"详细点"三种模式）
  Future<void> _regenerateAiRecord(
    AiChatRecord record,
    StateSetter setModalState, {
    String mode = 'regenerate', // 'regenerate' | 'concise' | 'detailed'
  }) async {
    // 取消该记录正在进行的请求
    _pendingAiRequests[record.id]?.cancel();
    _pendingAiRequests.remove(record.id);
    _streamingThrottleTimers.remove(record.id)?.cancel();
    _streamingNotifiers.remove(record.id)?.dispose();

    // 从内存和数据库删除旧记录
    final conversationId = record.conversationId;
    setState(() => _aiChatHistory.removeWhere((r) => r.id == record.id));
    await _aiChatDatabaseService.deleteRecord(record.id);

    // 构造发给 AI 的问题（界面上仍显示原始问题）
    String aiQuestion = record.question;
    if (mode == 'concise') {
      aiQuestion =
          '${record.question}\n\n(Please provide a shorter, more concise answer.)';
    } else if (mode == 'detailed') {
      aiQuestion =
          '${record.question}\n\n(Please provide a more detailed and comprehensive answer.)';
    }

    // 创建新记录（保持同一会话）
    final newId = 'regen_${DateTime.now().millisecondsSinceEpoch}';
    final newRecord = AiChatRecord(
      id: newId,
      conversationId: conversationId,
      word: record.word,
      question: record.question, // 显示原始问题
      answer: '',
      timestamp: DateTime.now(),
      path: record.path,
      elementJson: record.elementJson,
    );
    _aiChatHistory.add(newRecord);
    _currentLoadingId = newId;
    _autoExpandIds.add(newId);
    _streamingNotifiers[newId] = ValueNotifier<(String, String?, bool)>((
      '',
      null,
      false,
    ));

    await _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: newId,
        conversationId: conversationId,
        word: record.word,
        question: record.question,
        answer: '',
        timestamp: newRecord.timestamp,
        path: record.path,
        elementJson: record.elementJson,
      ),
    );

    setState(() {});
    setModalState(() {});

    // 启动流式请求，根据记录类型分派到正确的 stream：
    // 1. path == '__summary__' → summarizeDictionaryStream（页面总结，使用存储的词典JSON）
    // 2. elementJson != null → askAboutElementStream（词典元素提问）
    // 3. 其他 → freeChatStream（自由聊天续问，携带会话历史）
    final appLanguage = LocaleSettings.instance.currentLocale == AppLocale.zh
        ? 'Chinese'
        : 'English';
    final Stream<LLMChunk> stream;
    if (record.path == '__summary__' && record.elementJson != null) {
      // 总结类型：将 mode 转为 instruction
      String? instruction;
      if (mode == 'concise') {
        instruction = 'Be more concise and brief.';
      } else if (mode == 'detailed') {
        instruction =
            'Be more detailed and comprehensive, covering more examples and nuances.';
      }
      stream = _aiService.summarizeDictionaryStream(
        record.elementJson!,
        appLanguage: appLanguage,
        instruction: instruction,
      );
    } else if (record.elementJson != null) {
      // 元素提问类型
      stream = _aiService.askAboutElementStream(
        record.elementJson!,
        aiQuestion,
        appLanguage: appLanguage,
      );
    } else {
      // 自由聊天续问：删除旧记录后 _buildChatHistory 自动返回会话内前序消息
      final history = _buildChatHistory(conversationId);
      stream = _aiService.freeChatStream(
        aiQuestion,
        history: history,
        context: 'Current word: ${record.word}',
        appLanguage: appLanguage,
      );
    }

    final sub = stream.listen(
      (chunk) {
        final idx = _aiChatHistory.indexWhere((r) => r.id == newId);
        if (idx == -1) return;
        if (chunk.text != null) _aiChatHistory[idx].answer += chunk.text!;
        if (chunk.thinking != null) {
          _aiChatHistory[idx].thinkingContent =
              (_aiChatHistory[idx].thinkingContent ?? '') + chunk.thinking!;
        }
        if (_streamingThrottleTimers[newId] == null) {
          _streamingThrottleTimers[newId] = Timer(
            const Duration(milliseconds: 80),
            () {
              _streamingThrottleTimers[newId] = null;
              final i = _aiChatHistory.indexWhere((r) => r.id == newId);
              if (i != -1) {
                _streamingNotifiers[newId]?.value = (
                  _aiChatHistory[i].answer,
                  _aiChatHistory[i].thinkingContent,
                  false,
                );
              }
            },
          );
        }
      },
      onDone: () {
        _streamingThrottleTimers.remove(newId)?.cancel();
        _pendingAiRequests.remove(newId);
        _pendingRequestsVersionNotifier.value++;
        final idx = _aiChatHistory.indexWhere((r) => r.id == newId);
        if (idx != -1) {
          _streamingNotifiers[newId]?.value = (
            _aiChatHistory[idx].answer,
            _aiChatHistory[idx].thinkingContent,
            true,
          );
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: newId,
              conversationId: conversationId,
              word: record.word,
              question: record.question,
              answer: _aiChatHistory[idx].answer,
              timestamp: _aiChatHistory[idx].timestamp,
              path: record.path,
              elementJson: record.elementJson,
            ),
          );
        }
        _streamingNotifiers.remove(newId)?.dispose();
        if (_currentLoadingId == newId) _currentLoadingId = null;
      },
      onError: (e) {
        _streamingThrottleTimers.remove(newId)?.cancel();
        _pendingAiRequests.remove(newId);
        _pendingRequestsVersionNotifier.value++;
        _streamingNotifiers.remove(newId)?.dispose();
        if (_currentLoadingId == newId) _currentLoadingId = null;
        final idx = _aiChatHistory.indexWhere((r) => r.id == newId);
        if (idx != -1) {
          _aiChatHistory[idx].answer =
              '${context.t.entry.aiRequestFailedShort} $e';
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: newId,
              conversationId: conversationId,
              word: record.word,
              question: record.question,
              answer: '${context.t.entry.aiRequestFailedShort} $e',
              timestamp: _aiChatHistory[idx].timestamp,
              path: record.path,
              elementJson: record.elementJson,
            ),
          );
        }
        if (mounted) {
          showToast(context, context.t.entry.aiRequestFailed(error: '$e'));
        }
      },
      cancelOnError: true,
    );
    _pendingAiRequests[newId] = sub;
    _pendingRequestsVersionNotifier.value++;
  }

  /// 显示AI聊天记录
  void _showAiChatHistory({
    bool startFullscreen = false,
    bool expandNewest = false,
    String? initialConversationId,
  }) async {
    // 首次打开时加载聊天记录
    if (!_isAiChatHistoryLoaded) {
      await _loadAiChatHistory();
      _isAiChatHistoryLoaded = true;
    }

    // 确定要进入的会话和视图模式
    String? activeConversationId = initialConversationId;
    if (activeConversationId == null &&
        expandNewest &&
        _aiChatHistory.isNotEmpty) {
      activeConversationId = _aiChatHistory.last.conversationId;
    }
    bool isThreadView = activeConversationId != null;

    final ScrollController threadScrollController = ScrollController();
    final ScrollController listScrollController = ScrollController();
    final freeChatController = TextEditingController();
    final freeChatFocusNode = FocusNode();
    bool isFullScreen = startFullscreen;
    // 提前从父级 context 获取状态栏高度，底部弹出层的 context 中 viewPadding.top 为 0
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    _isModalActive = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _modalSetState = setModalState;
          final screenSize = MediaQuery.of(context).size;
          final colorScheme = Theme.of(context).colorScheme;

          return DraggableScrollableSheet(
            initialChildSize: isFullScreen ? 1.0 : 0.7,
            minChildSize: isFullScreen ? 1.0 : 0.5,
            // 非全屏时限制最大拖动高度，确保内容不压住状态栏底部
            maxChildSize: isFullScreen
                ? 1.0
                : (screenSize.height - statusBarHeight - 8) / screenSize.height,
            expand: false,
            builder: (context, scrollController) {
              final aiMdStyleSheet = _buildAiMarkdownStyleSheet(context);
              // 预计算当前会话消息和会话列表（随 setModalState 重建）
              final threadMessages =
                  (isThreadView && activeConversationId != null)
                  ? _getConversationMessages(activeConversationId!)
                  : <AiChatRecord>[];
              final conversationIds = isThreadView
                  ? <String>[]
                  : _getConversationIds();
              Widget content = Container(
                width: isFullScreen ? screenSize.width : null,
                padding: EdgeInsets.only(
                  top: isFullScreen ? statusBarHeight + 8 : 16,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Column(
                  children: [
                    // ── 标题栏（列表/线程模式自适应）──
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          if (isThreadView) ...[
                            // 对话线程模式：返回列表按钮
                            IconButton(
                              onPressed: () => setModalState(() {
                                isThreadView = false;
                                activeConversationId = null;
                              }),
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                size: 18,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                activeConversationId != null
                                    ? (_getConversationMessages(
                                            activeConversationId!,
                                          ).firstOrNull?.question ??
                                          context.t.entry.continueAsk)
                                    : context.t.entry.continueAsk,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else ...[
                            // 列表模式：AI 总结按钮
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  _modalSetState = null;
                                  _isModalActive = false;
                                  Navigator.pop(context);
                                  await _summarizeCurrentPage();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: LinearGradient(
                                      colors: [
                                        Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.10),
                                        Theme.of(context).colorScheme.tertiary
                                            .withOpacity(0.07),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        context.t.entry.aiSummaryButton,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 1,
                                        height: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      DictionaryLogo(
                                        dictionaryId: _entryGroup
                                            .currentDictionaryGroup
                                            .dictionaryId,
                                        dictionaryName: _entryGroup
                                            .currentDictionaryGroup
                                            .dictionaryName,
                                        size: 14,
                                      ),
                                      if (_entryGroup
                                              .currentDictionaryGroup
                                              .pageGroups
                                              .length >
                                          1) ...[
                                        const SizedBox(width: 4),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 80,
                                          ),
                                          child: Text(
                                            _entryGroup
                                                .currentDictionaryGroup
                                                .currentPage,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outline,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                          ],
                          // 清除全部聊天记录按钮（仅在消息列表界面显示）
                          if (!isThreadView)
                            IconButton(
                              onPressed: () =>
                                  _showClearAllChatHistoryConfirmDialog(
                                    context,
                                    () {
                                      _aiChatHistory.clear();
                                      _aiChatDatabaseService.clearAllRecords();
                                      _isAiChatHistoryLoaded = false;
                                      freeChatFocusNode.dispose();
                                      Navigator.pop(context);
                                    },
                                  ),
                              icon: Icon(
                                Icons.delete_sweep_outlined,
                                size: 20,
                                color: colorScheme.error.withOpacity(0.7),
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: context.t.settings.misc_page.clearAll,
                            ),
                          // 全屏切换和关闭（始终显示）
                          IconButton(
                            onPressed: () {
                              setModalState(() {
                                isFullScreen = !isFullScreen;
                              });
                            },
                            icon: Icon(
                              isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              size: 20,
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: isFullScreen
                                ? context.t.common.exitFullscreen
                                : context.t.common.fullscreen,
                          ),
                          IconButton(
                            onPressed: () {
                              _modalSetState = null;
                              _isModalActive = false;
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── 内容区：对话线程 ↔ 历史消息列表 ──
                    Expanded(
                      child: isThreadView
                          ? (threadMessages.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          context.t.entry.noChatHistory,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    controller: threadScrollController,
                                    itemCount: threadMessages.length,
                                    padding: EdgeInsets.zero,
                                    itemBuilder: (ctx, i) {
                                      final record = threadMessages[i];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // 用户消息气泡（右对齐）
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Container(
                                                constraints: BoxConstraints(
                                                  maxWidth:
                                                      screenSize.width * 0.75,
                                                ),
                                                margin: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: SelectableText(
                                                  record.question,
                                                  style: TextStyle(
                                                    color: colorScheme
                                                        .onPrimaryContainer,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // AI 回复（左对齐，Markdown 渲染，支持流式更新）
                                            ValueListenableBuilder<int>(
                                              valueListenable:
                                                  _pendingRequestsVersionNotifier,
                                              builder: (ctx2, _, _) {
                                                final notifier =
                                                    _streamingNotifiers[record
                                                        .id];
                                                final inProgress =
                                                    _pendingAiRequests
                                                        .containsKey(record.id);
                                                if (notifier != null) {
                                                  return ValueListenableBuilder<
                                                    (String, String?, bool)
                                                  >(
                                                    valueListenable: notifier,
                                                    builder: (ctx3, val, _) {
                                                      final text =
                                                          val.$1.isNotEmpty
                                                          ? val.$1
                                                          : record.answer;
                                                      if (text.isEmpty) {
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                8,
                                                              ),
                                                          child: SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: colorScheme
                                                                  .primary,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      return RepaintBoundary(
                                                        child: MarkdownBody(
                                                          data: text,
                                                          selectable: true,
                                                          styleSheet:
                                                              aiMdStyleSheet,
                                                        ),
                                                      );
                                                    },
                                                  );
                                                }
                                                if (record.answer.isEmpty) {
                                                  return inProgress
                                                      ? Padding(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                8,
                                                              ),
                                                          child: SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: colorScheme
                                                                  .primary,
                                                            ),
                                                          ),
                                                        )
                                                      : const SizedBox.shrink();
                                                }
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    RepaintBoundary(
                                                      child: MarkdownBody(
                                                        data: record.answer,
                                                        selectable: true,
                                                        styleSheet:
                                                            aiMdStyleSheet,
                                                      ),
                                                    ),
                                                    Row(
                                                      children: [
                                                        IconButton(
                                                          onPressed: () {
                                                            Clipboard.setData(
                                                              ClipboardData(
                                                                text: record
                                                                    .answer,
                                                              ),
                                                            );
                                                            showToast(
                                                              context,
                                                              context
                                                                  .t
                                                                  .entry
                                                                  .copiedToClipboard,
                                                            );
                                                          },
                                                          icon: const Icon(
                                                            Icons.copy_outlined,
                                                            size: 16,
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          tooltip: context
                                                              .t
                                                              .common
                                                              .copy,
                                                        ),
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons
                                                                .delete_outline,
                                                            size: 16,
                                                            color: colorScheme
                                                                .error
                                                                .withOpacity(
                                                                  0.7,
                                                                ),
                                                          ),
                                                          onPressed: () async {
                                                            final confirmed = await showDialog<bool>(
                                                              context: context,
                                                              builder: (dlgCtx) => AlertDialog(
                                                                title: Text(
                                                                  context
                                                                      .t
                                                                      .entry
                                                                      .deleteRecord,
                                                                ),
                                                                content: Text(
                                                                  context
                                                                      .t
                                                                      .entry
                                                                      .deleteRecordConfirm,
                                                                ),
                                                                actions: [
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                          dlgCtx,
                                                                          false,
                                                                        ),
                                                                    child: Text(
                                                                      context
                                                                          .t
                                                                          .common
                                                                          .cancel,
                                                                    ),
                                                                  ),
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                          dlgCtx,
                                                                          true,
                                                                        ),
                                                                    style: TextButton.styleFrom(
                                                                      foregroundColor:
                                                                          colorScheme
                                                                              .error,
                                                                    ),
                                                                    child: Text(
                                                                      context
                                                                          .t
                                                                          .common
                                                                          .delete,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                            if (confirmed ==
                                                                    true &&
                                                                mounted) {
                                                              final isLast = _aiChatHistory
                                                                  .where(
                                                                    (r) =>
                                                                        r.conversationId ==
                                                                            activeConversationId &&
                                                                        r.id !=
                                                                            record.id,
                                                                  )
                                                                  .isEmpty;
                                                              await _aiChatDatabaseService
                                                                  .deleteRecord(
                                                                    record.id,
                                                                  );
                                                              if (mounted) {
                                                                setState(
                                                                  () => _aiChatHistory
                                                                      .removeWhere(
                                                                        (r) =>
                                                                            r.id ==
                                                                            record.id,
                                                                      ),
                                                                );
                                                                setModalState(() {
                                                                  if (isLast) {
                                                                    isThreadView =
                                                                        false;
                                                                    activeConversationId =
                                                                        null;
                                                                  }
                                                                });
                                                              }
                                                            }
                                                          },
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          tooltip: context
                                                              .t
                                                              .common
                                                              .delete,
                                                        ),
                                                        PopupMenuButton<String>(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(
                                                                minWidth: 40,
                                                                minHeight: 40,
                                                              ),
                                                          icon: Icon(
                                                            Icons.refresh,
                                                            size: 16,
                                                            color: colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                          tooltip: context
                                                              .t
                                                              .entry
                                                              .regenerate,
                                                          onSelected: (mode) {
                                                            _regenerateAiRecord(
                                                              record,
                                                              setModalState,
                                                              mode: mode,
                                                            );
                                                          },
                                                          itemBuilder: (ctx) => [
                                                            PopupMenuItem(
                                                              value:
                                                                  'regenerate',
                                                              child: Row(
                                                                children: [
                                                                  const Icon(
                                                                    Icons
                                                                        .refresh,
                                                                    size: 18,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Text(
                                                                    context
                                                                        .t
                                                                        .entry
                                                                        .regenerate,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'concise',
                                                              child: Row(
                                                                children: [
                                                                  const Icon(
                                                                    Icons
                                                                        .compress,
                                                                    size: 18,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Text(
                                                                    context
                                                                        .t
                                                                        .entry
                                                                        .moreConc,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'detailed',
                                                              child: Row(
                                                                children: [
                                                                  const Icon(
                                                                    Icons
                                                                        .expand,
                                                                    size: 18,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Text(
                                                                    context
                                                                        .t
                                                                        .entry
                                                                        .moreDetailed,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ))
                          : (conversationIds.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          context.t.entry.noChatHistory,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    controller: listScrollController,
                                    itemCount: conversationIds.length,
                                    itemBuilder: (ctx, i) {
                                      final cid = conversationIds[i];
                                      final msgs = _getConversationMessages(
                                        cid,
                                      );
                                      if (msgs.isEmpty) {
                                        // ignore: curly_braces_in_flow_control_structures
                                        return const SizedBox.shrink();
                                      }
                                      // ignore: duplicate_ignore
                                      final firstMsg = msgs.first;
                                      final lastMsg = msgs.last;
                                      final isStreaming = _pendingAiRequests
                                          .containsKey(lastMsg.id);
                                      final isLoading =
                                          lastMsg.answer.isEmpty && isStreaming;
                                      final isError = lastMsg.answer.startsWith(
                                        context.t.entry.aiRequestFailedShort,
                                      );
                                      return ValueListenableBuilder<int>(
                                        valueListenable:
                                            _pendingRequestsVersionNotifier,
                                        builder: (ctx2, _, _) {
                                          return Card(
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              side: BorderSide(
                                                color: colorScheme
                                                    .outlineVariant
                                                    .withOpacity(0.5),
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              onTap: () {
                                                setModalState(() {
                                                  activeConversationId = cid;
                                                  isThreadView = true;
                                                });
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) {
                                                      if (threadScrollController
                                                          .hasClients) {
                                                        threadScrollController.jumpTo(
                                                          threadScrollController
                                                              .position
                                                              .maxScrollExtent,
                                                        );
                                                      }
                                                    });
                                              },
                                              onLongPress: () =>
                                                  _deleteConversation(
                                                    cid,
                                                    context,
                                                    colorScheme,
                                                    setModalState,
                                                  ),
                                              onSecondaryTap: () =>
                                                  _deleteConversation(
                                                    cid,
                                                    context,
                                                    colorScheme,
                                                    setModalState,
                                                  ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 14,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    if (isLoading)
                                                      SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: colorScheme
                                                                  .primary,
                                                            ),
                                                      )
                                                    else if (isError)
                                                      Icon(
                                                        Icons.error_outline,
                                                        size: 16,
                                                        color:
                                                            colorScheme.error,
                                                      ),
                                                    SizedBox(
                                                      width:
                                                          isLoading || isError
                                                          ? 8
                                                          : 0,
                                                    ),
                                                    Text(
                                                      firstMsg.word,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        _buildConversationSubtitle(
                                                          firstMsg,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: colorScheme
                                                              .outline,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _formatTimestamp(
                                                        lastMsg.timestamp,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            colorScheme.outline,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      Icons.chevron_right,
                                                      size: 18,
                                                      color: colorScheme
                                                          .outlineVariant,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  )),
                    ),
                    const SizedBox(height: 6),
                    // ── 输入框（发送即进入对话线程）──
                    Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom > 0
                            ? MediaQuery.of(context).viewInsets.bottom
                            : 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Shortcuts(
                              shortcuts: {
                                LogicalKeySet(LogicalKeyboardKey.enter):
                                    const _SendIntent(),
                                LogicalKeySet(
                                  LogicalKeyboardKey.shift,
                                  LogicalKeyboardKey.enter,
                                ): const _NewLineIntent(),
                                LogicalKeySet(
                                  LogicalKeyboardKey.control,
                                  LogicalKeyboardKey.enter,
                                ): const _NewLineIntent(),
                                LogicalKeySet(
                                  LogicalKeyboardKey.meta,
                                  LogicalKeyboardKey.enter,
                                ): const _NewLineIntent(),
                              },
                              child: Actions(
                                actions: {
                                  _SendIntent: _SendAction(
                                    onSend: () {
                                      final text = freeChatController.text
                                          .trim();
                                      if (text.isEmpty) return;
                                      _sendFreeChatMessage(
                                        text,
                                        conversationId: isThreadView
                                            ? activeConversationId
                                            : null,
                                        onMessageSent: (String newConvId) {
                                          freeChatController.clear();
                                          setModalState(() {
                                            activeConversationId = newConvId;
                                            isThreadView = true;
                                          });
                                          setState(() {});
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                Future.delayed(
                                                  const Duration(
                                                    milliseconds: 100,
                                                  ),
                                                  () {
                                                    if (threadScrollController
                                                        .hasClients) {
                                                      threadScrollController
                                                          .animateTo(
                                                            threadScrollController
                                                                .position
                                                                .maxScrollExtent,
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      300,
                                                                ),
                                                            curve:
                                                                Curves.easeOut,
                                                          );
                                                    }
                                                  },
                                                );
                                              });
                                        },
                                      );
                                    },
                                  ),
                                  _NewLineIntent: _NewLineAction(
                                    controller: freeChatController,
                                  ),
                                },
                                child: TextField(
                                  controller: freeChatController,
                                  focusNode: freeChatFocusNode,
                                  maxLines: 3,
                                  minLines: 1,
                                  decoration: InputDecoration(
                                    hintText: context.t.entry.chatInputHint,
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    filled: true,
                                    fillColor: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () {
                              final text = freeChatController.text.trim();
                              if (text.isEmpty) return;
                              freeChatFocusNode.unfocus();
                              _sendFreeChatMessage(
                                text,
                                conversationId: isThreadView
                                    ? activeConversationId
                                    : null,
                                onMessageSent: (String newConvId) {
                                  freeChatController.clear();
                                  setModalState(() {
                                    activeConversationId = newConvId;
                                    isThreadView = true;
                                  });
                                  setState(() {});
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () {
                                        if (threadScrollController.hasClients) {
                                          threadScrollController.animateTo(
                                            threadScrollController
                                                .position
                                                .maxScrollExtent,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOut,
                                          );
                                        }
                                      },
                                    );
                                  });
                                },
                              );
                            },
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              Widget modalContent = Material(
                color: colorScheme.surfaceContainerLow,
                borderRadius: isFullScreen
                    ? null
                    : const BorderRadius.vertical(top: Radius.circular(16)),
                clipBehavior: isFullScreen ? Clip.none : Clip.antiAlias,
                child: content,
              );
              if (isThreadView) {
                modalContent = PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) {
                      setModalState(() {
                        isThreadView = false;
                        activeConversationId = null;
                      });
                    }
                  },
                  child: modalContent,
                );
              }
              return modalContent;
            },
          );
        },
      ),
    ).then((_) {
      _modalSetState = null;
      _isModalActive = false;
      threadScrollController.dispose();
      listScrollController.dispose();
      freeChatController.dispose();
      try {
        freeChatFocusNode.dispose();
      } catch (_) {}
    });
  }

  /// 发送自由聊天消息（流式输出）
  Future<void> _sendFreeChatMessage(
    String message, {
    required void Function(String conversationId) onMessageSent,
    String? conversationId,
  }) async {
    final requestId = 'free_${DateTime.now().millisecondsSinceEpoch}';
    final actualConversationId = conversationId ?? requestId;

    // 构建当前单词上下文
    final currentWord = widget.initialWord;
    final String context = 'Current word: $currentWord';

    // 创建记录
    final record = AiChatRecord(
      id: requestId,
      conversationId: actualConversationId,
      word: currentWord,
      question: message,
      answer: '',
      timestamp: DateTime.now(),
      path: null,
      elementJson: null,
    );
    _aiChatHistory.add(record);
    _currentLoadingId = requestId;
    _autoExpandIds.add(requestId);
    _streamingNotifiers[requestId] = ValueNotifier<(String, String?, bool)>((
      '',
      null,
      false,
    ));

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        conversationId: actualConversationId,
        word: currentWord,
        question: message,
        answer: '',
        timestamp: record.timestamp,
        path: null,
        elementJson: null,
      ),
    );

    onMessageSent(actualConversationId);

    // 准备历史对话（当前会话最近5轮）
    final history = _buildChatHistory(actualConversationId);

    // 启动流式请求
    final appLanguage = LocaleSettings.instance.currentLocale == AppLocale.zh
        ? 'Chinese'
        : 'English';
    final stream = _aiService.freeChatStream(
      message,
      history: history,
      context: context,
      appLanguage: appLanguage,
    );
    final sub = stream.listen(
      (chunk) {
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx == -1) return;
        if (chunk.text != null) _aiChatHistory[idx].answer += chunk.text!;
        if (chunk.thinking != null) {
          _aiChatHistory[idx].thinkingContent =
              (_aiChatHistory[idx].thinkingContent ?? '') + chunk.thinking!;
        }
        // 80ms 节流批量推送 UI 更新
        if (_streamingThrottleTimers[requestId] == null) {
          _streamingThrottleTimers[requestId] = Timer(
            const Duration(milliseconds: 80),
            () {
              _streamingThrottleTimers[requestId] = null;
              final i = _aiChatHistory.indexWhere((r) => r.id == requestId);
              if (i != -1) {
                _streamingNotifiers[requestId]?.value = (
                  _aiChatHistory[i].answer,
                  _aiChatHistory[i].thinkingContent,
                  false,
                );
              }
            },
          );
        }
      },
      onDone: () {
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        _pendingRequestsVersionNotifier.value++;
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _streamingNotifiers[requestId]?.value = (
            _aiChatHistory[idx].answer,
            _aiChatHistory[idx].thinkingContent,
            true,
          );
        }
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        if (idx != -1) {
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: actualConversationId,
              word: currentWord,
              question: message,
              answer: _aiChatHistory[idx].answer,
              timestamp: _aiChatHistory[idx].timestamp,
              path: null,
              elementJson: null,
            ),
          );
        }
      },
      onError: (e) {
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        _pendingRequestsVersionNotifier.value++;
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _aiChatHistory[idx].answer =
              '${this.context.t.entry.aiRequestFailedShort} $e';
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: actualConversationId,
              word: currentWord,
              question: message,
              answer: '${this.context.t.entry.aiRequestFailedShort} $e',
              timestamp: _aiChatHistory[idx].timestamp,
              path: null,
              elementJson: null,
            ),
          );
        }
      },
      cancelOnError: true,
    );
    _pendingAiRequests[requestId] = sub;
    _pendingRequestsVersionNotifier.value++;
  }

  /// 构建聊天历史（用于连续对话，只包含当前会话的消息）
  List<Map<String, String>> _buildChatHistory(String conversationId) {
    final history = <Map<String, String>>[];

    final allRecords =
        _aiChatHistory
            .where(
              (r) =>
                  r.conversationId == conversationId &&
                  r.answer.isNotEmpty &&
                  !r.answer.startsWith(context.t.entry.aiRequestFailedShort),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (allRecords.isEmpty) return history;

    // 为每条记录重建发送给LLM的原始用户消息：
    // 含有 elementJson 的记录在首次请求时携带了完整 JSON，
    // 这里还原该格式，确保 LLM 在多轮对话中始终能看到原始词典内容。
    String buildUserContent(AiChatRecord r) {
      if (r.elementJson == null) return r.question;
      if (r.path == '__summary__') {
        return 'Analyze the following dictionary JSON data and output a structured summary as instructed.\n\n```json\n${r.elementJson}\n```';
      }
      // askAboutElement 格式
      return 'Dictionary content:\n```json\n${r.elementJson}\n```\n\nQuestion: ${r.question}';
    }

    // 滑动窗口：最近5轮
    const maxWindow = 5;
    final startIdx = allRecords.length > maxWindow
        ? allRecords.length - maxWindow
        : 0;

    // 若首条记录（携带词典 JSON 上下文）被窗口截断，始终将其锚定在历史开头，
    // 避免 LLM 丢失原始词典内容，导致后续回答"凭空作答"。
    final root = allRecords.first;
    if (startIdx > 0 && root.elementJson != null) {
      history.add({'role': 'user', 'content': buildUserContent(root)});
      history.add({'role': 'assistant', 'content': root.answer});
    }

    for (var i = startIdx; i < allRecords.length; i++) {
      final r = allRecords[i];
      history.add({'role': 'user', 'content': buildUserContent(r)});
      history.add({'role': 'assistant', 'content': r.answer});
    }
    return history;
  }

  /// 格式化时间戳
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return context.t.entry.justNow;
    } else if (diff.inHours < 1) {
      return context.t.entry.minutesAgo(n: diff.inMinutes);
    } else if (diff.inDays < 1) {
      return context.t.entry.hoursAgo(n: diff.inHours);
    } else if (diff.inDays < 7) {
      return context.t.entry.daysAgo(n: diff.inDays);
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 构建消息概览单行布局的副标题：自由聊天显示"AI自由聊天"，总结显示"词典+page AI总结"，询问显示"词典 AI询问"
  String _buildConversationSubtitle(AiChatRecord firstMsg) {
    final path = firstMsg.path;
    if (path == '__summary__') {
      final dictId =
          firstMsg.dictionaryId ?? _parseSummaryDictId(firstMsg.elementJson);
      final page = _parseSummaryPage(firstMsg.elementJson);
      final dictLabel = (dictId != null && dictId.isNotEmpty) ? dictId : '';
      if (page != null && page.isNotEmpty) {
        return context.t.entry.chatOverviewSummary(dict: dictLabel, page: page);
      }
      return context.t.entry.chatOverviewSummaryNoPage(dict: dictLabel);
    } else if (path != null) {
      final dictId = firstMsg.dictionaryId;
      final dictLabel = (dictId != null && dictId.isNotEmpty) ? dictId : '';
      return context.t.entry.chatOverviewAsk(dict: dictLabel);
    } else {
      return context.t.entry.chatOverviewFreeChat;
    }
  }

  String? _parseSummaryDictId(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['dictionary'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _parseSummaryPage(String? elementJson) {
    if (elementJson == null) return null;
    try {
      final data = jsonDecode(elementJson) as Map<String, dynamic>?;
      return data?['page'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 一键总结当前词典当前页的所有entry（流式输出）
  Future<void> _summarizeCurrentPage() async {
    final requestId = 'summary_${DateTime.now().millisecondsSinceEpoch}';
    final currentDict = _entryGroup.currentDictionaryGroup;
    final currentPageIndex = currentDict.currentPageIndex;

    // 获取当前词典当前页的所有entries
    if (currentDict.pageGroups.isEmpty ||
        currentPageIndex >= currentDict.pageGroups.length) {
      showToast(context, context.t.entry.noPageContent);
      return;
    }

    final currentPage = currentDict.pageGroups[currentPageIndex];
    final entries = currentPage.sections.map((s) => s.entry).toList();

    if (entries.isEmpty) {
      showToast(context, context.t.entry.noPageContent);
      return;
    }

    final targetWord = entries[0].headword;

    // 每次总结都开一个新会话
    final conversationId = requestId;

    // 构建当前页所有entries的JSON内容
    // compactJson 用于持久化存储（不缩进，空白少），重新生成时可恢复上下文
    final summaryData = {
      'dictionary': currentDict.dictionaryId,
      'page': currentPage.page,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final compactJson = jsonEncode(summaryData);
    final jsonContent = const JsonEncoder.withIndent('  ').convert(summaryData);

    // 创建记录（path 标记为 __summary__ ，以便重新生成时识别类型）
    final record = AiChatRecord(
      id: requestId,
      conversationId: conversationId,
      word: targetWord,
      question: context.t.entry.summaryQuestion,
      answer: '',
      timestamp: DateTime.now(),
      path: '__summary__',
      elementJson: compactJson,
      dictionaryId: currentDict.dictionaryId,
    );
    _aiChatHistory.add(record);
    _currentLoadingId = requestId;
    _autoExpandIds.add(requestId);
    _streamingNotifiers[requestId] = ValueNotifier<(String, String?, bool)>((
      '',
      null,
      false,
    ));

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        conversationId: conversationId,
        word: targetWord,
        question: context.t.entry.summaryQuestion,
        answer: '',
        timestamp: record.timestamp,
        path: '__summary__',
        elementJson: compactJson,
        dictionaryId: currentDict.dictionaryId,
      ),
    );

    // 刷新UI：面板已打开则更新列表，否则立即打开面板
    setState(() {});
    if (_isModalActive) {
      _safeModalSetState();
    } else if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAiChatHistory(initialConversationId: conversationId);
      });
    }

    // 启动流式请求
    final appLanguage = LocaleSettings.instance.currentLocale == AppLocale.zh
        ? 'Chinese'
        : 'English';
    final stream = _aiService.summarizeDictionaryStream(
      jsonContent,
      appLanguage: appLanguage,
    );
    final sub = stream.listen(
      (chunk) {
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx == -1) return;
        if (chunk.text != null) {
          _aiChatHistory[idx].answer += chunk.text!;
        }
        if (chunk.thinking != null) {
          _aiChatHistory[idx].thinkingContent =
              (_aiChatHistory[idx].thinkingContent ?? '') + chunk.thinking!;
        }
        // 80ms 节流批量推送 UI 更新
        if (_streamingThrottleTimers[requestId] == null) {
          _streamingThrottleTimers[requestId] = Timer(
            const Duration(milliseconds: 80),
            () {
              _streamingThrottleTimers[requestId] = null;
              final i = _aiChatHistory.indexWhere((r) => r.id == requestId);
              if (i != -1) {
                _streamingNotifiers[requestId]?.value = (
                  _aiChatHistory[i].answer,
                  _aiChatHistory[i].thinkingContent,
                  false,
                );
              }
            },
          );
        }
      },
      onDone: () {
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          // 更新问题标题
          final finalAnswer = _aiChatHistory[idx].answer;
          _aiChatHistory[idx] = AiChatRecord(
            id: requestId,
            conversationId: conversationId,
            word: targetWord,
            question: context.t.entry.summaryTitle,
            answer: finalAnswer,
            thinkingContent: _aiChatHistory[idx].thinkingContent,
            timestamp: _aiChatHistory[idx].timestamp,
            path: '__summary__',
            elementJson: compactJson,
            dictionaryId: currentDict.dictionaryId,
          );
          // 最终全量刷新一次
          _streamingNotifiers[requestId]?.value = (
            finalAnswer,
            _aiChatHistory[idx].thinkingContent,
            true,
          );
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: conversationId,
              word: targetWord,
              question: context.t.entry.summaryTitle,
              answer: finalAnswer,
              timestamp: _aiChatHistory[idx].timestamp,
              path: '__summary__',
              elementJson: compactJson,
              dictionaryId: currentDict.dictionaryId,
            ),
          );
        }
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        if (mounted) {
          _pendingRequestsVersionNotifier.value++;
        }
      },
      onError: (e) {
        _streamingThrottleTimers.remove(requestId)?.cancel();
        _pendingAiRequests.remove(requestId);
        _streamingNotifiers.remove(requestId)?.dispose();
        if (_currentLoadingId == requestId) _currentLoadingId = null;
        final idx = _aiChatHistory.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _aiChatHistory[idx].answer =
              '${context.t.entry.aiRequestFailedShort} $e';
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              conversationId: conversationId,
              word: targetWord,
              question: context.t.entry.summaryQuestion,
              answer: '${context.t.entry.aiRequestFailedShort} $e',
              timestamp: _aiChatHistory[idx].timestamp,
              path: '__summary__',
              elementJson: compactJson,
              dictionaryId: currentDict.dictionaryId,
            ),
          );
        }
        if (mounted) {
          _pendingRequestsVersionNotifier.value++;
          showToast(context, context.t.entry.aiSumFailed(error: '$e'));
        }
      },
      cancelOnError: true,
    );
    _pendingAiRequests[requestId] = sub;
    _pendingRequestsVersionNotifier.value++;
  }

  Future<void> _deleteConversation(
    String conversationId,
    BuildContext context,
    ColorScheme colorScheme,
    StateSetter setModalState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(context.t.common.delete),
        content: Text(context.t.entry.deleteRecordConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text(context.t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final recordsToDelete = _aiChatHistory
          .where((r) => r.conversationId == conversationId)
          .toList();
      for (final r in recordsToDelete) {
        await _aiChatDatabaseService.deleteRecord(r.id);
      }
      if (mounted) {
        setState(() {
          _aiChatHistory.removeWhere((r) => r.conversationId == conversationId);
        });
        setModalState(() {});
      }
    }
  }

  void _showClearAllChatHistoryConfirmDialog(
    BuildContext ctx,
    VoidCallback onConfirm,
  ) {
    final colorScheme = Theme.of(ctx).colorScheme;
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(ctx.t.settings.misc_page.clearAllConfirmTitle),
          ],
        ),
        content: Text(ctx.t.settings.misc_page.clearAllConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.t.common.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(ctx.t.common.clear),
          ),
        ],
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _NewLineIntent extends Intent {
  const _NewLineIntent();
}

class _SendAction extends Action<_SendIntent> {
  final VoidCallback onSend;

  _SendAction({required this.onSend});

  @override
  Object? invoke(_SendIntent intent) {
    onSend();
    return null;
  }
}

class _NewLineAction extends Action<_NewLineIntent> {
  final TextEditingController controller;

  _NewLineAction({required this.controller});

  @override
  Object? invoke(_NewLineIntent intent) {
    final text = controller.text;
    final selection = controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\n');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
    return null;
  }
}
