import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/models/dictionary_metadata.dart';
import '../components/dictionary_navigation_panel.dart';
import '../components/dictionary_logo.dart';
import '../components/scale_layout_wrapper.dart';
import '../components/global_scale_wrapper.dart';
import '../components/component_renderer.dart';
import '../data/word_bank_service.dart';
import '../services/search_history_service.dart';
import '../services/ai_service.dart';
import '../data/services/ai_chat_database_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_search_service.dart';
import '../services/entry_event_bus.dart';
import '../core/logger.dart';
import '../services/preferences_service.dart';
import '../services/font_loader_service.dart';
import '../services/user_dicts_service.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/word_list_dialog.dart';
import '../core/utils/language_utils.dart';

/// AI聊天记录模型
class AiChatRecord {
  final String id;
  final String word;
  final String question;
  final String answer;
  final DateTime timestamp;
  final String? path;
  final String? elementJson; // 存储查询的JSON内容

  AiChatRecord({
    required this.id,
    required this.word,
    required this.question,
    required this.answer,
    required this.timestamp,
    this.path,
    this.elementJson,
  });
}

class _DraggableNavPanel extends StatefulWidget {
  final DictionaryEntryGroup entryGroup;
  final VoidCallback onDictionaryChanged;
  final VoidCallback onPageChanged;
  final VoidCallback onSectionChanged;
  final Function(DictionaryEntry entry, {String? targetPath})?
  onNavigateToEntry;
  final double initialDy;
  final GlobalKey<DictionaryNavigationPanelState>? navPanelKey;

  const _DraggableNavPanel({
    required this.entryGroup,
    required this.onDictionaryChanged,
    required this.onPageChanged,
    required this.onSectionChanged,
    required this.onNavigateToEntry,
    required this.initialDy,
    this.navPanelKey,
  });

  @override
  State<_DraggableNavPanel> createState() => _DraggableNavPanelState();
}

class _DraggableNavPanelState extends State<_DraggableNavPanel> {
  late double _dy;
  double? _dragY;

  @override
  void initState() {
    super.initState();
    _dy = widget.initialDy;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    double top;

    if (_dragY != null) {
      top = _dragY!;
    } else {
      top = screenSize.height * _dy;
      // 确保不超出屏幕底部
      if (top > screenSize.height - 100) {
        top = screenSize.height - 100;
      }
    }

    // 固定在右边缘，手机端更贴近边缘
    return Positioned(
      top: top,
      right: isMobile ? 4 : 16,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _dragY = screenSize.height * _dy;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _dragY = _dragY! + details.delta.dy;
          });
        },
        onPanEnd: (details) {
          // 只保存垂直位置，固定在右侧
          final newDy = (_dragY! / screenSize.height).clamp(0.1, 0.8);

          setState(() {
            _dy = newDy;
            _dragY = null;
          });
          PreferencesService().setNavPanelPosition(true, _dy);
        },
        child: DictionaryNavigationPanel(
          key: widget.navPanelKey,
          entryGroup: widget.entryGroup,
          onDictionaryChanged: widget.onDictionaryChanged,
          onPageChanged: widget.onPageChanged,
          onSectionChanged: widget.onSectionChanged,
          onNavigateToEntry: widget.onNavigateToEntry,
        ),
      ),
    );
  }
}

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
  // 同步从 FontLoaderService 获取软件布局缩放，避免异步加载导致的闪烁问题
  final double _dictionaryContentScale = FontLoaderService()
      .getDictionaryContentScale();

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

  /// 正在进行的AI请求
  final Map<String, Future<String>> _pendingAiRequests = {};

  /// 当前正在加载的AI请求ID
  String? _currentLoadingId;

  /// AI聊天历史弹窗的 setState，用于在请求完成时刷新弹窗内容
  StateSetter? _modalSetState;

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

  List<String> _toolbarActions = [];
  List<String> _overflowActions = [];

  /// 是否有新的AI回答尚未查看（用于工具栏按鈕闪烁）
  bool _hasNewAiAnswer = false;

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
    super.dispose();
  }

  void _onScrollPositionChanged() {
    if (_isProgrammaticScroll) return;

    final now = DateTime.now();
    if (_lastScrollUpdateTime != null &&
        now.difference(_lastScrollUpdateTime!) < _scrollUpdateThrottle) {
      return;
    }
    _lastScrollUpdateTime = now;
    _updateCurrentSectionFromScroll();
  }

  void _updateCurrentSectionFromScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final entries = _getAllEntriesInOrder();
    if (entries.isEmpty) return;

    int lastFullyVisibleIndex = -1;
    double maxVisibleHeight = 0;
    int maxVisibleIndex = -1;

    for (final pos in positions) {
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
        maxVisibleIndex = pos.index;
      }
    }

    int targetIndex = lastFullyVisibleIndex >= 0
        ? lastFullyVisibleIndex
        : maxVisibleIndex;
    if (targetIndex < 0) return;

    // 索引 0: 词形关系横幅（始终存在）
    int entryIndex = targetIndex - 1;
    if (entryIndex < 0 || entryIndex >= entries.length) return;

    final targetEntry = entries[entryIndex];
    final currentDictIndex = _entryGroup.currentDictionaryIndex;

    for (int i = 0; i < _entryGroup.dictionaryGroups.length; i++) {
      final dict = _entryGroup.dictionaryGroups[i];
      for (int j = 0; j < dict.pageGroups.length; j++) {
        final page = dict.pageGroups[j];
        for (int k = 0; k < page.sections.length; k++) {
          if (page.sections[k].entry.id == targetEntry.id) {
            if (i != currentDictIndex ||
                j != dict.currentPageIndex ||
                k != dict.currentSectionIndex) {
              _entryGroup.setCurrentDictionaryIndex(i);
              _entryGroup.dictionaryGroups[i].setCurrentPageIndex(j);
              _entryGroup.dictionaryGroups[i].setCurrentSectionIndex(k);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {});
                  // 通知导航面板活跃section已改变
                  _navPanelKey.currentState?.handleActiveSectionChanged();
                }
              });
            }
            return;
          }
        }
      }
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
    return metadata?.sourceLanguage ?? 'en';
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
                      fontSize: 13.5,
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

  List<DictionaryEntry> _getAllEntriesInOrder() {
    final List<DictionaryEntry> entries = [];

    final allDicts = _entryGroup.dictionaryGroups;
    final currentDict = _entryGroup.currentDictionaryGroup;
    final currentDictIndex = _entryGroup.currentDictionaryIndex;
    final currentPageIndex = currentDict.currentPageIndex;

    for (int i = 0; i < currentDictIndex; i++) {
      final dict = allDicts[i];
      // 添加该词典所有 page 的 entries
      for (final pageGroup in dict.pageGroups) {
        for (final section in pageGroup.sections) {
          entries.add(section.entry);
        }
      }
    }

    // 当前词典：只添加当前 page 的 entries
    if (currentDict.pageGroups.isNotEmpty &&
        currentPageIndex < currentDict.pageGroups.length) {
      final currentPage = currentDict.pageGroups[currentPageIndex];
      for (final section in currentPage.sections) {
        entries.add(section.entry);
      }
    }

    for (int i = currentDictIndex + 1; i < allDicts.length; i++) {
      final dict = allDicts[i];
      // 添加该词典所有 page 的 entries
      for (final pageGroup in dict.pageGroups) {
        for (final section in pageGroup.sections) {
          entries.add(section.entry);
        }
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
        showToast(context, '已将 "$word" 从单词本移除');
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
        showToast(context, '已更新 "$word" 的词表归属');
      }
    } else {
      if (selectedLists.isEmpty) {
        if (mounted) {
          showToast(context, '请至少选择一个词表');
        }
      } else {
        final success = await _wordBankService.addWord(
          word,
          language,
          lists: selectedLists,
        );
        if (mounted) {
          if (success) {
            showToast(context, '已将 "$word" 加入单词本');
            setState(() => _isFavorite = true);
          } else {
            showToast(context, '添加失败');
          }
        }
      }
    }
  }

  Future<void> _resetCurrentEntry() async {
    final currentEntry = _entryGroup.currentDictionaryGroup.currentEntry;
    if (currentEntry == null) {
      showToast(context, '无法获取当前词条');
      return;
    }

    final dictId = currentEntry.dictId;
    var entryId = currentEntry.id;
    if (dictId == null || entryId.isEmpty) {
      showToast(context, '词条信息不完整');
      return;
    }

    final prefix = '${dictId}_';
    if (entryId.startsWith(prefix)) {
      entryId = entryId.substring(prefix.length);
    }

    showToast(context, '正在重置词条...');

    try {
      final userDictsService = UserDictsService();
      final entryData = await userDictsService.fetchEntry(dictId, entryId);

      if (entryData == null) {
        if (mounted) {
          showToast(context, '服务器上未找到该词条');
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

          showToast(context, '词条已重置');
        }
      } else if (mounted) {
        showToast(context, '重置失败');
      }
    } catch (e) {
      Logger.e('重置词条失败: $e', tag: 'EntryDetailPage');
      if (mounted) {
        showToast(context, '重置失败: $e');
      }
    }
  }

  void _showNewSearch() {
    Navigator.of(context).pop({'selectText': true});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _getAllEntriesInOrder();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // item 0: 词形关系横幅（始终占一个位置，无结果时 FutureBuilder 返回 SizedBox.shrink()）
    const wordRelationsOffset = 1;
    // 搜索关系横幅现在内嵌在各词典的词典头部下方，不占独立 item
    final totalCount = wordRelationsOffset + entries.length;

    final content = Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  return false;
                },
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  padding: _getDynamicPadding(
                    context,
                  ).copyWith(top: 16, bottom: 100),
                  itemCount: totalCount,
                  minCacheExtent: 100,
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
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 16),
                child: _buildBottomActionBar(),
              ),
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

  Widget _buildBottomActionBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final toolbarWidgets = _toolbarActions
        .map(
          (action) => Expanded(child: _buildToolbarAction(action, colorScheme)),
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

  Widget _buildToolbarAction(String action, ColorScheme colorScheme) {
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
        final colorScheme = Theme.of(context).colorScheme;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final hadNewAnswer = _hasNewAiAnswer;
              if (mounted) setState(() => _hasNewAiAnswer = false);
              _showAiChatHistory(
                startFullscreen: hadNewAnswer,
                expandNewest: hadNewAnswer,
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: _BlinkingIcon(
                icon: Icons.auto_awesome,
                color: _hasNewAiAnswer
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                isBlinking: _hasNewAiAnswer,
              ),
            ),
          ),
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
        borderRadius: BorderRadius.circular(20),
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
    final bottomInset = mediaQuery.viewInsets.bottom;

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
    return PreferencesService.getActionLabel(action);
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
        final hadNewAnswer = _hasNewAiAnswer;
        if (mounted) setState(() => _hasNewAiAnswer = false);
        _showAiChatHistory(
          startFullscreen: hadNewAnswer,
          expandNewest: hadNewAnswer,
        );
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
        borderRadius: BorderRadius.circular(20),
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

    return Container(
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
    const Map<String, String> _colLabels = {
      'word1': '',
      'word2': '',
      'base': '原形',
      'nominal': '名词形',
      'plural': '复数',
      'past': '过去式',
      'past_part': '过去分词',
      'pres_part': '现在分词',
      'third_sing': '三单',
      'comp': '比较级',
      'superl': '最高级',
    };
    const Map<String, String> _tableLabels = {
      'spelling_variant': '变体',
      'nominalization': '名词化',
      'inflection': '屈折词',
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
              final baseLabel = _tableLabels[row.tableName] ?? row.tableName;
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
                          final colLabel = _colLabels[field.key] ?? field.key;
                          final wordVal = field.value!;
                          // 合并胶囊（如"sawn, sawed"）：拆分后检查任一分量是否命中当前词
                          final isCurrentWord = wordVal
                              .split(', ')
                              .any(
                                (v) =>
                                    v.toLowerCase() ==
                                    widget.initialWord.toLowerCase(),
                              );

                          final chip = Container(
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
                                  ...([
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
                                  ]),
                                Text(
                                  wordVal,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.2,
                                    fontWeight: isCurrentWord
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrentWord
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          );

                          // 合并值（含逗号）或"不可数"标记不可点击跳转
                          final isNavigable =
                              !isCurrentWord &&
                              !wordVal.contains(', ') &&
                              wordVal != '不可数';

                          if (!isNavigable) return chip;

                          return GestureDetector(
                            onTap: () => _navigateToWord(wordVal),
                            child: chip,
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

    final dbService = DatabaseService();
    final historyService = SearchHistoryService();

    final result = await dbService.getAllEntries(word);

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
        showToast(context, '未找到单词: $word');
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
      showToast(context, '无法编辑此元素: $e');
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _JsonEditorBottomSheet(
        entry: currentEntry,
        pathParts: pathParts,
        initialText: initialText,
        historyIndex: _historyIndex,
        pathHistory: _pathHistory,
        initialPath: startPath,
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

  Widget _buildPathNavigator(
    DictionaryEntry entry,
    List<String> pathParts,
    Function(List<String>) onPathSelected, {
    String? title,
    VoidCallback? onHomeTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onHomeTap != null)
          InkWell(
            onTap: onHomeTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 18, color: colorScheme.primary),
            ),
          ),
        ...pathParts.asMap().entries.expand((entry) {
          final index = entry.key;
          final part = entry.value;
          final currentPath = pathParts.sublist(0, index + 1);

          final widgets = <Widget>[];

          // 添加分隔符（除了第一个）
          if (index > 0) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '>',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          // 添加可点击的路径段
          final isLast = index == pathParts.length - 1;
          widgets.add(
            InkWell(
              onTap: isLast ? null : () => onPathSelected(currentPath),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  part,
                  style: TextStyle(
                    color: isLast
                        ? colorScheme.primary
                        : colorScheme.primary.withOpacity(0.8),
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );

          return widgets;
        }),
      ],
    );
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
          throw Exception('根节点必须是对象类型');
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

      final newEntry = DictionaryEntry.fromJson(fullJson);
      final success = await DatabaseService().insertOrUpdateEntry(newEntry);

      if (success) {
        _updateEntryInGroup(newEntry);
        if (mounted) {
          showToast(toastContext ?? context, '保存成功');
        }
        return newEntry;
      } else {
        throw Exception('数据库更新失败');
      }
    } catch (e) {
      if (mounted) {
        showToast(toastContext ?? context, '保存失败: $e');
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
        // 去除格式标记后再进行翻译
        final plainText = _removeFormatting(textToTranslate);
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
      showToast(context, '处理失败: $e');
    }
  }

  Future<void> _performTranslation(
    DictionaryEntry entry,
    List<String> pathParts,
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    showToast(context, '正在翻译...');

    try {
      final translation = await AIService().translate(text, targetLang);
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
        showToast(context, '翻译失败: $e');
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
        showToast(context, '切换失败: $e');
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
        showToast(context, '切换失败: $e');
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

    // 去除格式化文本中的格式标记
    if (currentValue is String) {
      currentValue = _removeFormatting(currentValue);
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
                // 路径导航栏（包含返回初始路径按钮）
                Row(
                  children: [
                    Expanded(
                      child: _buildPathNavigator(entry, pathParts, (
                        newPathParts,
                      ) {
                        Navigator.pop(context);
                        // 获取新路径对应的值
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
                            if (index != null && index < currentValue.length) {
                              currentValue = currentValue[index];
                            }
                          }
                        }
                        // 重新打开AI对话框，显示新路径的内容
                        _showAiElementDialog(
                          entry,
                          newPathParts,
                          currentValue,
                          initialPath: startPath, // 传递初始路径
                        );
                      }, title: '路径'),
                    ),
                    // 返回初始路径按钮
                    if (startPath != null &&
                        pathParts.join('.') != startPath.join('.'))
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);

                          // 获取初始路径对应的值
                          final json = entry.toJson();
                          dynamic currentValue = json;
                          for (final part in startPath) {
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

                          // 重新打开AI对话框，显示初始路径的内容
                          _showAiElementDialog(
                            entry,
                            startPath,
                            currentValue,
                            initialPath: startPath, // 保持初始路径不变
                          );
                        },
                        icon: const Icon(
                          Icons.first_page,
                        ), // 使用 first_page 图标表示返回初始位置
                        tooltip: '返回初始路径',
                        color: Theme.of(context).colorScheme.primary,
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
                    hintText: '这是词典中单词"${entry.headword}"的一部分，请解释这部分内容。',
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
                            ? '这是词典中单词"${entry.headword}"的一部分，请解释这部分内容'
                            : inputText;
                        Navigator.pop(context);
                        await _askAiAboutElement(
                          elementJson,
                          pathParts.join('.'),
                          question,
                          word: entry.headword,
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
                      child: const Text('取消'),
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

  /// 向AI询问元素
  Future<void> _askAiAboutElement(
    String elementJson,
    String path,
    String question, {
    String? word,
  }) async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final targetWord = word ?? widget.initialWord;

    // 格式化JSON为密集文本（移除换行和多余空格）
    final compactJson = _formatCompactJson(elementJson);

    // 创建加载中的记录
    final loadingRecord = AiChatRecord(
      id: requestId,
      word: targetWord,
      question: question,
      answer: '', // 空表示加载中
      timestamp: DateTime.now(),
      path: path,
      elementJson: compactJson,
    );
    _aiChatHistory.add(loadingRecord);
    _currentLoadingId = requestId;

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        word: targetWord,
        question: question,
        answer: '',
        timestamp: loadingRecord.timestamp,
        path: path,
        elementJson: compactJson,
      ),
    );

    // 立即刷新UI显示加载状态
    setState(() {});

    // 启动后台请求
    final requestFuture = _aiService.askAboutElement(
      elementJson,
      path,
      question,
    );
    _pendingAiRequests[requestId] = requestFuture;

    // 显示一个简短的提示
    showToast(context, 'AI正在思考中，您可以继续浏览...');

    // 处理请求完成
    requestFuture
        .then((answer) {
          _pendingAiRequests.remove(requestId);
          // 更新记录
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: targetWord,
              question: question,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: path,
              elementJson: compactJson,
            );
          }
          // 更新持久化存储
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: targetWord,
              question: question,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: path,
              elementJson: compactJson,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {
              _hasNewAiAnswer = true;
            });
            _modalSetState?.call(() {});
            // 显示完成提示
            showToast(context, 'AI回答已生成，请查看');
          }
        })
        .catchError((e) {
          _pendingAiRequests.remove(requestId);
          // 更新记录为错误状态
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: targetWord,
              question: question,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: path,
              elementJson: compactJson,
            );
          }
          // 更新持久化存储
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: targetWord,
              question: question,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: path,
              elementJson: compactJson,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            _modalSetState?.call(() {});
            showToast(context, 'AI请求失败: $e');
          }
        });
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

  /// 显示AI聊天记录
  void _showAiChatHistory({
    bool startFullscreen = false,
    bool expandNewest = false,
  }) async {
    // 首次打开时加载聊天记录
    if (!_isAiChatHistoryLoaded) {
      await _loadAiChatHistory();
      _isAiChatHistoryLoaded = true;
    }

    final freeChatController = TextEditingController();
    final freeChatFocusNode = FocusNode();
    bool isFullScreen = startFullscreen;
    // 提前从父级 context 获取状态栏高度，底部弹出层的 context 中 viewPadding.top 为 0
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _modalSetState = setModalState;
          final screenSize = MediaQuery.of(context).size;
          return DraggableScrollableSheet(
            initialChildSize: isFullScreen ? 1.0 : 0.7,
            minChildSize: isFullScreen ? 1.0 : 0.5,
            // 非全屏时限制最大拖动高度，确保内容不压住状态栏底部
            maxChildSize: isFullScreen
                ? 1.0
                : (screenSize.height - statusBarHeight - 8) / screenSize.height,
            expand: false,
            builder: (context, scrollController) {
              Widget content = Container(
                width: isFullScreen ? screenSize.width : null,
                padding: EdgeInsets.only(
                  top: isFullScreen ? statusBarHeight + 8 : 16,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                decoration: isFullScreen
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.zero,
                      )
                    : null,
                child: Column(
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _summarizeCurrentPage();
                            },
                            icon: Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            label: Text(
                              '总结当前页',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.6),
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const Spacer(),
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
                            tooltip: isFullScreen ? '退出全屏' : '全屏',
                          ),
                          IconButton(
                            onPressed: () {
                              _modalSetState = null;
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 聊天记录列表
                    Expanded(
                      child: _aiChatHistory.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    '暂无聊天记录',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _aiChatHistory.length,
                              itemBuilder: (context, index) {
                                final record =
                                    _aiChatHistory[_aiChatHistory.length -
                                        1 -
                                        index];
                                final isLoading =
                                    record.answer.isEmpty &&
                                    _pendingAiRequests.containsKey(record.id);
                                final isError = record.answer.startsWith(
                                  '请求失败:',
                                );

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                  child: ExpansionTile(
                                    leading: isLoading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          )
                                        : isError
                                        ? Icon(
                                            Icons.error_outline,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          )
                                        : Icon(
                                            Icons.check_circle_outline,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                    initiallyExpanded:
                                        index == 0 && expandNewest,
                                    title: Text(
                                      record.question,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${record.word} · ${_formatTimestamp(record.timestamp)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    ),
                                    // 修复深色模式下的亮色横条问题
                                    collapsedShape:
                                        const RoundedRectangleBorder(
                                          side: BorderSide.none,
                                        ),
                                    shape: const RoundedRectangleBorder(
                                      side: BorderSide.none,
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          8,
                                          12,
                                          4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 显示JSON内容（紧凑格式，最多两行）
                                            if (record.elementJson != null)
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  record.elementJson!,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'Consolas',
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            // 显示加载中、错误或回答内容
                                            if (isLoading)
                                              Row(
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'AI正在思考中...',
                                                    style: TextStyle(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.outline,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            else if (isError)
                                              Text(
                                                record.answer,
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                              )
                                            else
                                              // Markdown渲染回答 - 使用延迟加载避免卡顿
                                              _LazyMarkdownBody(
                                                data: record.answer,
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                if (!isLoading)
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: record.answer,
                                                        ),
                                                      );
                                                      showToast(
                                                        context,
                                                        '已复制到剪贴板',
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.copy,
                                                      size: 16,
                                                    ),
                                                    label: const Text('复制'),
                                                    style: TextButton.styleFrom(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  ),
                                                // 继续对话按钮
                                                if (!isLoading && !isError)
                                                  TextButton.icon(
                                                    onPressed: () {
                                                      _showContinueChatDialog(
                                                        record,
                                                        onMessageSent: () {
                                                          setModalState(() {});
                                                          setState(() {});
                                                        },
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.chat,
                                                      size: 16,
                                                    ),
                                                    label: const Text('继续'),
                                                    style: TextButton.styleFrom(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  ),
                                                // 删除单条记录按钮
                                                IconButton(
                                                  onPressed: () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (context) => AlertDialog(
                                                        title: const Text(
                                                          '删除记录',
                                                        ),
                                                        content: const Text(
                                                          '确定删除这条AI聊天记录吗？',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              '取消',
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  true,
                                                                ),
                                                            style: TextButton.styleFrom(
                                                              foregroundColor:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .error,
                                                            ),
                                                            child: const Text(
                                                              '删除',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm == true) {
                                                      await _aiChatDatabaseService
                                                          .deleteRecord(
                                                            record.id,
                                                          );
                                                      setState(() {
                                                        _aiChatHistory
                                                            .removeWhere(
                                                              (r) =>
                                                                  r.id ==
                                                                  record.id,
                                                            );
                                                      });
                                                      setModalState(() {});
                                                    }
                                                  },
                                                  icon: Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                        .withOpacity(0.7),
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  tooltip: '删除',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 6),
                    // 自由发送文本框
                    Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom > 0
                            ? MediaQuery.of(context).viewInsets.bottom
                            : 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: freeChatController,
                              focusNode: freeChatFocusNode,
                              maxLines: 3,
                              minLines: 1,
                              decoration: InputDecoration(
                                hintText: '输入任意问题...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.outline,
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
                              onSubmitted: (text) {
                                if (text.trim().isNotEmpty) {
                                  _sendFreeChatMessage(
                                    text.trim(),
                                    onMessageSent: () {
                                      freeChatController.clear();
                                      setModalState(() {});
                                      setState(() {});
                                      // 滚动到最新消息
                                      Future.delayed(
                                        const Duration(milliseconds: 300),
                                        () {
                                          if (scrollController.hasClients) {
                                            scrollController.animateTo(
                                              0,
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              curve: Curves.easeOut,
                                            );
                                          }
                                        },
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () {
                              final text = freeChatController.text.trim();
                              if (text.isNotEmpty) {
                                _sendFreeChatMessage(
                                  text,
                                  onMessageSent: () {
                                    freeChatController.clear();
                                    freeChatFocusNode.unfocus();
                                    setModalState(() {});
                                    setState(() {});
                                    // 滚动到最新消息
                                    Future.delayed(
                                      const Duration(milliseconds: 300),
                                      () {
                                        if (scrollController.hasClients) {
                                          scrollController.animateTo(
                                            0,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOut,
                                          );
                                        }
                                      },
                                    );
                                  },
                                );
                              }
                            },
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              // 全屏时使用 ClipRect 裁剪圆角，顶部 padding 已手动留起状态栏空间
              if (isFullScreen) {
                return ClipRect(child: content);
              }
              return content;
            },
          );
        },
      ),
    );
  }

  /// 发送自由聊天消息
  Future<void> _sendFreeChatMessage(
    String message, {
    required VoidCallback onMessageSent,
  }) async {
    final requestId = 'free_${DateTime.now().millisecondsSinceEpoch}';

    // 构建当前单词上下文
    final currentWord = widget.initialWord;
    final currentDict = _entryGroup.currentDictionaryGroup;
    String context = '当前查询单词: $currentWord';
    if (currentDict.dictionaryId.isNotEmpty) {
      context += '\n当前词典: ${currentDict.dictionaryId}';
    }

    // 创建加载中的记录
    final loadingRecord = AiChatRecord(
      id: requestId,
      word: currentWord,
      question: message,
      answer: '',
      timestamp: DateTime.now(),
      path: null,
      elementJson: null,
    );
    _aiChatHistory.add(loadingRecord);
    _currentLoadingId = requestId;

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        word: currentWord,
        question: message,
        answer: '',
        timestamp: loadingRecord.timestamp,
        path: null,
        elementJson: null,
      ),
    );

    onMessageSent();

    // 准备历史对话（最近5轮）
    final history = _buildChatHistory();

    // 启动后台请求
    final requestFuture = _aiService.freeChat(
      message,
      history: history,
      context: context,
    );
    _pendingAiRequests[requestId] = requestFuture;

    // 处理请求完成
    requestFuture
        .then((answer) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: currentWord,
              question: message,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
              elementJson: null,
            );
          }
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: currentWord,
              question: message,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
              elementJson: null,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            _modalSetState?.call(() {});
          }
        })
        .catchError((e) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: currentWord,
              question: message,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
              elementJson: null,
            );
          }
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: currentWord,
              question: message,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
              elementJson: null,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            _modalSetState?.call(() {});
          }
        });
  }

  /// 构建聊天历史（用于连续对话）
  List<Map<String, String>> _buildChatHistory() {
    final history = <Map<String, String>>[];
    // 取最近5轮对话（最多10条消息）
    final recentRecords = _aiChatHistory
        .where((r) => r.answer.isNotEmpty && !r.answer.startsWith('请求失败:'))
        .toList();

    final startIndex = recentRecords.length > 5 ? recentRecords.length - 5 : 0;
    for (var i = startIndex; i < recentRecords.length; i++) {
      final record = recentRecords[i];
      history.add({'role': 'user', 'content': record.question});
      history.add({'role': 'assistant', 'content': record.answer});
    }
    return history;
  }

  /// 显示继续对话对话框
  void _showContinueChatDialog(
    AiChatRecord record, {
    required VoidCallback onMessageSent,
  }) {
    final messageController = TextEditingController();
    final scrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, sheetScrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '继续对话',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),
                    // 历史消息显示
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          // 原始问题
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '原始问题',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(record.question),
                                ],
                              ),
                            ),
                          ),
                          // AI回答
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI回答',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  MarkdownBody(
                                    data: record.answer,
                                    selectable: true,
                                    styleSheet:
                                        MarkdownStyleSheet.fromTheme(
                                          Theme.of(context),
                                        ).copyWith(
                                          p: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(height: 1.6),
                                          code: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize:
                                                (Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.fontSize ??
                                                    14) *
                                                0.9,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                          codeblockDecoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withOpacity(0.5),
                                            ),
                                          ),
                                          codeblockPadding:
                                              const EdgeInsets.all(12),
                                          blockquote: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontStyle: FontStyle.italic,
                                                height: 1.6,
                                              ),
                                          blockquoteDecoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.5),
                                                width: 4,
                                              ),
                                            ),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withOpacity(0.15),
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topRight: Radius.circular(4),
                                                  bottomRight: Radius.circular(
                                                    4,
                                                  ),
                                                ),
                                          ),
                                          blockquotePadding:
                                              const EdgeInsets.fromLTRB(
                                                12,
                                                8,
                                                8,
                                                8,
                                              ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            '继续提问',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const Divider(),
                    // 输入框
                    Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom > 0
                            ? MediaQuery.of(context).viewInsets.bottom
                            : 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: messageController,
                              maxLines: 3,
                              minLines: 1,
                              decoration: InputDecoration(
                                hintText: '基于以上对话继续提问...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.outline,
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
                              onSubmitted: (text) {
                                if (text.trim().isNotEmpty) {
                                  _sendContinueChatMessage(
                                    record,
                                    text.trim(),
                                    onMessageSent: () {
                                      messageController.clear();
                                      Navigator.pop(context);
                                      onMessageSent();
                                    },
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () {
                              final text = messageController.text.trim();
                              if (text.isNotEmpty) {
                                _sendContinueChatMessage(
                                  record,
                                  text,
                                  onMessageSent: () {
                                    messageController.clear();
                                    Navigator.pop(context);
                                    onMessageSent();
                                  },
                                );
                              }
                            },
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 发送继续对话消息
  Future<void> _sendContinueChatMessage(
    AiChatRecord parentRecord,
    String message, {
    required VoidCallback onMessageSent,
  }) async {
    final requestId = 'continue_${DateTime.now().millisecondsSinceEpoch}';
    final currentWord = widget.initialWord;

    // 构建上下文信息
    String context = '当前查询单词: $currentWord\n';
    context += '原始问题: ${parentRecord.question}\n';
    context +=
        '原始回答: ${parentRecord.answer.substring(0, parentRecord.answer.length > 500 ? 500 : parentRecord.answer.length)}...';
    if (parentRecord.elementJson != null) {
      context += '\n相关词典内容: ${parentRecord.elementJson}';
    }

    // 创建加载中的记录
    final loadingRecord = AiChatRecord(
      id: requestId,
      word: currentWord,
      question: message,
      answer: '',
      timestamp: DateTime.now(),
      path: parentRecord.path,
      elementJson: parentRecord.elementJson,
    );
    _aiChatHistory.add(loadingRecord);
    _currentLoadingId = requestId;

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        word: currentWord,
        question: message,
        answer: '',
        timestamp: loadingRecord.timestamp,
        path: parentRecord.path,
        elementJson: parentRecord.elementJson,
      ),
    );

    onMessageSent();

    // 准备历史对话（包含父对话）
    final history = <Map<String, String>>[
      {'role': 'user', 'content': parentRecord.question},
      {'role': 'assistant', 'content': parentRecord.answer},
    ];

    // 启动后台请求
    final requestFuture = _aiService.freeChat(
      message,
      history: history,
      context: context,
    );
    _pendingAiRequests[requestId] = requestFuture;

    // 处理请求完成
    requestFuture
        .then((answer) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: currentWord,
              question: message,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: parentRecord.path,
              elementJson: parentRecord.elementJson,
            );
          }
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: currentWord,
              question: message,
              answer: answer,
              timestamp: _aiChatHistory[index].timestamp,
              path: parentRecord.path,
              elementJson: parentRecord.elementJson,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
          }
        })
        .catchError((e) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: currentWord,
              question: message,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: parentRecord.path,
              elementJson: parentRecord.elementJson,
            );
          }
          _aiChatDatabaseService.updateRecord(
            AiChatRecordModel(
              id: requestId,
              word: currentWord,
              question: message,
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: parentRecord.path,
              elementJson: parentRecord.elementJson,
            ),
          );
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
          }
        });
  }

  /// 格式化时间戳
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 一键总结当前词典当前页的所有entry
  Future<void> _summarizeCurrentPage() async {
    final requestId = 'summary_${DateTime.now().millisecondsSinceEpoch}';
    final currentDict = _entryGroup.currentDictionaryGroup;
    final currentPageIndex = currentDict.currentPageIndex;

    // 获取当前词典当前页的所有entries
    if (currentDict.pageGroups.isEmpty ||
        currentPageIndex >= currentDict.pageGroups.length) {
      showToast(context, '当前页没有内容');
      return;
    }

    final currentPage = currentDict.pageGroups[currentPageIndex];
    final entries = currentPage.sections.map((s) => s.entry).toList();

    if (entries.isEmpty) {
      showToast(context, '当前页没有内容');
      return;
    }

    final targetWord = entries.length == 1
        ? entries[0].headword
        : '${entries[0].headword}等${entries.length}个词条';

    // 创建加载中的记录
    final loadingRecord = AiChatRecord(
      id: requestId,
      word: targetWord,
      question: '请总结当前页的所有词典内容',
      answer: '',
      timestamp: DateTime.now(),
      path: null,
    );
    _aiChatHistory.add(loadingRecord);
    _currentLoadingId = requestId;

    // 保存到持久化存储
    _aiChatDatabaseService.addRecord(
      AiChatRecordModel(
        id: requestId,
        word: targetWord,
        question: '请总结当前页的所有词典内容',
        answer: '',
        timestamp: loadingRecord.timestamp,
        path: null,
        elementJson: null,
      ),
    );

    setState(() {});

    // 构建当前页所有entries的JSON内容
    final jsonContent = const JsonEncoder.withIndent('  ').convert({
      'dictionary': currentDict.dictionaryId,
      'page': currentPageIndex,
      'entries': entries.map((e) => e.toJson()).toList(),
    });

    final requestFuture = _aiService.summarizeDictionary(jsonContent);
    _pendingAiRequests[requestId] = requestFuture;

    showToast(context, 'AI正在分析当前页内容...');

    requestFuture
        .then((summary) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: targetWord,
              question: '当前页内容总结',
              answer: summary,
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
            );
            // 更新持久化存储
            _aiChatDatabaseService.updateRecord(
              AiChatRecordModel(
                id: requestId,
                word: targetWord,
                question: '当前页内容总结',
                answer: summary,
                timestamp: _aiChatHistory[index].timestamp,
                path: null,
                elementJson: null,
              ),
            );
          }
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {
              _hasNewAiAnswer = true;
            });
            showToast(context, 'AI回答已生成，请查看');
          }
        })
        .catchError((e) {
          _pendingAiRequests.remove(requestId);
          final index = _aiChatHistory.indexWhere((r) => r.id == requestId);
          if (index != -1) {
            _aiChatHistory[index] = AiChatRecord(
              id: requestId,
              word: targetWord,
              question: '当前页内容总结',
              answer: '请求失败: $e',
              timestamp: _aiChatHistory[index].timestamp,
              path: null,
            );
            // 更新持久化存储
            _aiChatDatabaseService.updateRecord(
              AiChatRecordModel(
                id: requestId,
                word: targetWord,
                question: '当前页内容总结',
                answer: '请求失败: $e',
                timestamp: _aiChatHistory[index].timestamp,
                path: null,
                elementJson: null,
              ),
            );
          }
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            showToast(context, 'AI总结失败: $e');
          }
        });
  }
}

/// 工具栏 AI 按鈕闪烁动画小部件
class _BlinkingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool isBlinking;

  const _BlinkingIcon({
    required this.icon,
    required this.color,
    required this.isBlinking,
  });

  @override
  State<_BlinkingIcon> createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<_BlinkingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 1.0,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isBlinking) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_BlinkingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBlinking != oldWidget.isBlinking) {
      if (widget.isBlinking) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isBlinking) {
      return Icon(widget.icon, size: 24, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Icon(widget.icon, size: 24, color: widget.color),
        );
      },
    );
  }
}

class _JsonEditorBottomSheet extends StatefulWidget {
  final DictionaryEntry entry;
  final List<String> pathParts;
  final String initialText;
  final int historyIndex;
  final List<List<String>> pathHistory;
  final List<String>? initialPath; // 新增：初始路径
  final Function(dynamic) onSave;
  final Function(List<String>, dynamic) onNavigate;

  const _JsonEditorBottomSheet({
    required this.entry,
    required this.pathParts,
    required this.initialText,
    required this.historyIndex,
    required this.pathHistory,
    this.initialPath, // 新增：初始路径
    required this.onSave,
    required this.onNavigate,
  });

  @override
  State<_JsonEditorBottomSheet> createState() => _JsonEditorBottomSheetState();
}

class _JsonEditorBottomSheetState extends State<_JsonEditorBottomSheet> {
  late TextEditingController _controller;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _hasSyntaxError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _undoStack.add(widget.initialText);
    _controller.addListener(_trackChanges);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trackChanges() {
    final currentText = _controller.text;
    if (_undoStack[_currentEditPosition] != currentText) {
      if (_currentEditPosition < _undoStack.length - 1) {
        _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
      }
      _undoStack.add(currentText);
      _currentEditPosition = _undoStack.length - 1;
      _redoStack.clear();
      _validateJson();
    }
  }

  void _undo() {
    if (_currentEditPosition > 0) {
      setState(() {
        _currentEditPosition--;
        _controller.text = _undoStack[_currentEditPosition];
        _redoStack.clear();
        _validateJson();
      });
    }
  }

  void _redo() {
    if (_currentEditPosition < _undoStack.length - 1) {
      setState(() {
        _currentEditPosition++;
        _controller.text = _undoStack[_currentEditPosition];
        _validateJson();
      });
    }
  }

  void _formatJson() {
    try {
      final json = jsonDecode(_controller.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(json);
      setState(() {
        _controller.text = formatted;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = '格式化失败: $e';
      });
    }
  }

  void _validateJson() {
    try {
      jsonDecode(_controller.text);
      setState(() {
        _hasSyntaxError = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleSave() async {
    if (_hasSyntaxError) {
      showToast(context, 'JSON 格式错误: $_errorMessage');
      return;
    }

    try {
      final newValue = jsonDecode(_controller.text);
      await widget.onSave(newValue);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showToast(context, '保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                child: _buildPathNavigator(
                  context,
                  widget.pathParts,
                  (newPathParts) {
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in newPathParts) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(newPathParts, currentValue);
                  },
                  onHomeTap: () {
                    // 跳转到根目录
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    widget.onNavigate([], json);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.initialPath != null &&
                  widget.pathParts.join('.') != widget.initialPath!.join('.'))
                _buildToolbarIconButton(
                  icon: Icons.first_page,
                  onPressed: () {
                    Navigator.pop(context);
                    final startPath = widget.initialPath!;
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in startPath) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(startPath, currentValue);
                  },
                  tooltip: '返回初始路径',
                  color: colorScheme.primary,
                ),
              _buildToolbarIconButton(
                icon: Icons.undo,
                onPressed: _currentEditPosition > 0 ? _undo : null,
                tooltip: '撤销',
              ),
              _buildToolbarIconButton(
                icon: Icons.redo,
                onPressed: _currentEditPosition < _undoStack.length - 1
                    ? _redo
                    : null,
                tooltip: '重做',
              ),
              _buildToolbarIconButton(
                icon: Icons.format_align_left,
                onPressed: _formatJson,
                tooltip: '格式化',
              ),
              _buildToolbarIconButton(
                icon: _hasSyntaxError
                    ? Icons.error
                    : Icons.check_circle_outline,
                onPressed: _validateJson,
                tooltip: _hasSyntaxError ? '语法错误' : '语法检测',
                color: _hasSyntaxError ? colorScheme.error : null,
              ),
            ],
          ),
          if (_hasSyntaxError && _errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '错误: $_errorMessage',
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: TextField(
              controller: _controller,
              maxLines: 10,
              minLines: 3,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '输入 JSON 内容',
                errorText: _hasSyntaxError ? ' ' : null,
              ),
              style: const TextStyle(fontFamily: 'Consolas'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _hasSyntaxError ? null : _handleSave,
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 16,
        color:
            color ??
            (onPressed != null ? colorScheme.primary : colorScheme.outline),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color:
              color ??
              (onPressed != null ? colorScheme.primary : colorScheme.outline),
        ),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurface,
      ),
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        color:
            color ??
            (onPressed != null ? colorScheme.primary : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _buildPathNavigator(
    BuildContext context,
    List<String> pathParts,
    Function(List<String>) onPathSelected, {
    VoidCallback? onHomeTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onHomeTap != null)
          InkWell(
            onTap: onHomeTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 18, color: colorScheme.primary),
            ),
          ),
        ...pathParts.asMap().entries.expand((entry) {
          final index = entry.key;
          final part = entry.value;
          final currentPath = pathParts.sublist(0, index + 1);

          final widgets = <Widget>[];

          if (index > 0) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '>',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          final isLast = index == pathParts.length - 1;
          widgets.add(
            InkWell(
              onTap: isLast ? null : () => onPathSelected(currentPath),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  part,
                  style: TextStyle(
                    color: isLast
                        ? colorScheme.primary
                        : colorScheme.primary.withValues(alpha: 0.8),
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );

          return widgets;
        }),
      ],
    );
  }
}

class _LazyMarkdownBody extends StatefulWidget {
  final String data;

  const _LazyMarkdownBody({required this.data});

  @override
  State<_LazyMarkdownBody> createState() => _LazyMarkdownBodyState();
}

class _LazyMarkdownBodyState extends State<_LazyMarkdownBody> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // 延迟 300ms 渲染 Markdown，避免在 ExpansionTile 展开动画期间带来卡顿
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: MarkdownBody(
        data: widget.data,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          h1: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h2: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h3: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          h1Padding: const EdgeInsets.only(top: 16, bottom: 4),
          h2Padding: const EdgeInsets.only(top: 12, bottom: 4),
          h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
          pPadding: const EdgeInsets.symmetric(vertical: 2),
          code: TextStyle(
            fontFamily: 'Consolas',
            fontSize:
                (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 0.9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            height: 1.6,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                width: 4,
              ),
            ),
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          listBullet: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(height: 1.6),
          listIndent: 20,
          strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.6,
          ),
          em: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.6,
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
          ),
          tableHead: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          tableBody: Theme.of(context).textTheme.bodyMedium,
          tableBorder: TableBorder.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
          tableColumnWidth: const FlexColumnWidth(),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          tableHeadAlign: TextAlign.left,
        ),
      ),
    );
  }
}
