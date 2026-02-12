import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../database_service.dart';
import '../models/dictionary_entry_group.dart';
import '../models/dictionary_metadata.dart';
import '../components/dictionary_navigation_panel.dart';
import '../component_renderer.dart';
import '../word_bank_service.dart';
import '../services/search_history_service.dart';
import '../services/ai_service.dart';
import '../services/ai_chat_history_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_search_service.dart';
import '../logger.dart';
import '../services/preferences_service.dart';
import '../utils/toast_utils.dart';
import '../utils/word_list_dialog.dart';
import '../utils/language_utils.dart';

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
  final Function(DictionaryEntry) onNavigateToEntry;
  final bool initialIsRight;
  final double initialDy;

  const _DraggableNavPanel({
    required this.entryGroup,
    required this.onDictionaryChanged,
    required this.onPageChanged,
    required this.onSectionChanged,
    required this.onNavigateToEntry,
    required this.initialIsRight,
    required this.initialDy,
  });

  @override
  State<_DraggableNavPanel> createState() => _DraggableNavPanelState();
}

class _DraggableNavPanelState extends State<_DraggableNavPanel> {
  late bool _isRight;
  late double _dy;
  Offset? _dragOffset;

  @override
  void initState() {
    super.initState();
    _isRight = widget.initialIsRight;
    _dy = widget.initialDy;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    double top;
    double? left;
    double? right;

    if (_dragOffset != null) {
      top = _dragOffset!.dy;
      left = _dragOffset!.dx;
    } else {
      top = screenSize.height * _dy;
      // 确保不超出屏幕底部
      if (top > screenSize.height - 100) {
        top = screenSize.height - 100;
      }
      if (_isRight) {
        right = 16;
      } else {
        left = 16;
      }
    }

    return Positioned(
      top: top,
      left: left,
      right: right,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            // 初始化拖动位置
            final currentLeft = _isRight ? (screenSize.width - 16 - 52) : 16.0;
            _dragOffset = Offset(currentLeft, screenSize.height * _dy);
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _dragOffset = _dragOffset! + details.delta;
          });
        },
        onPanEnd: (details) {
          // 计算停靠
          final centerX = _dragOffset!.dx + 52 / 2;
          final isRight = centerX > screenSize.width / 2;
          final newDy = (_dragOffset!.dy / screenSize.height).clamp(0.1, 0.8);

          setState(() {
            _isRight = isRight;
            _dy = newDy;
            _dragOffset = null;
          });
          PreferencesService().setNavPanelPosition(_isRight, _dy);
        },
        child: DictionaryNavigationPanel(
          entryGroup: widget.entryGroup,
          onDictionaryChanged: widget.onDictionaryChanged,
          onPageChanged: widget.onPageChanged,
          onSectionChanged: widget.onSectionChanged,
          onNavigateToEntry: widget.onNavigateToEntry,
          isRight: _isRight,
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
  final ScrollController _contentScrollController = ScrollController();

  /// 显示兼容夜间模式的SnackBar
  void _showSnackBar(
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    if (action != null) {
      final colorScheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: colorScheme.onSurface),
          ),
          backgroundColor: colorScheme.surfaceContainerHighest,
          duration: duration ?? const Duration(seconds: 2),
          action: action,
        ),
      );
    } else {
      showToast(context, message);
    }
  }

  final Map<String, GlobalKey> _entryKeys = {};
  final WordBankService _wordBankService = WordBankService();
  final AIService _aiService = AIService();
  final AiChatHistoryService _aiChatHistoryService = AiChatHistoryService();
  late DictionaryEntryGroup _entryGroup;
  bool _isFavorite = false;

  /// 路径历史栈，用于撤回功能
  final List<List<String>> _pathHistory = [];
  int _historyIndex = -1;

  /// AI聊天记录
  final List<AiChatRecord> _aiChatHistory = [];

  /// 正在进行的AI请求
  final Map<String, Future<String>> _pendingAiRequests = {};

  /// 当前正在加载的AI请求ID
  String? _currentLoadingId;

  // 导航栏位置状态
  bool _isNavPanelRight = true;
  double _navPanelDy = 0.7; // 相对屏幕高度的比例
  bool _isNavPanelLoaded = false;

  // 非目标语言显示状态 - 延迟初始化
  bool? _areNonTargetLanguagesVisible;

  // 用于访问 ComponentRenderer 的状态
  final GlobalKey<ComponentRendererState> _componentRendererKey =
      GlobalKey<ComponentRendererState>();

  @override
  void initState() {
    super.initState();
    _entryGroup = widget.entryGroup;
    _loadFavoriteStatus();
    _loadAiChatHistory();
    _loadNavPanelPosition();
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

      // 根据全局状态设置显示/隐藏
      final pathsToHide = visible ? <String>[] : languagePaths.toList();
      final pathsToShow = visible ? languagePaths.toList() : <String>[];
      _componentRendererKey.currentState?.batchToggleHiddenLanguages(
        pathsToHide: pathsToHide,
        pathsToShow: pathsToShow,
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
        _isNavPanelRight = position['isRight'] == 1.0;
        _navPanelDy = position['dy']!;
        _isNavPanelLoaded = true;
      });
    }
  }

  /// 加载AI聊天记录
  Future<void> _loadAiChatHistory() async {
    final records = await _aiChatHistoryService.getAllRecords();
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

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

  /// 构建搜索关系信息横幅
  Widget _buildSearchRelationBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final relations = widget.searchRelations!;
    final dynamicPadding = _getDynamicPadding(context);

    return Padding(
      padding: EdgeInsets.only(bottom: dynamicPadding.bottom),
      child: Card(
        color: colorScheme.primaryContainer.withOpacity(0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: colorScheme.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
        margin: EdgeInsets.symmetric(
          horizontal: dynamicPadding.horizontal / 2,
          vertical: dynamicPadding.top / 2,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
              Text(
                '${widget.initialWord}',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              Icon(
                Icons.arrow_forward,
                size: 14,
                color: colorScheme.onPrimaryContainer,
              ),
              ...relations.entries.expand((entry) {
                final mappedWord = entry.key;
                final relationList = entry.value;
                return relationList.map((relation) {
                  return Text(
                    '${mappedWord}（${relation.description ?? relation.relationType}）',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                });
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 更新_entryGroup中对应的entry
  void _updateEntryInGroup(
    DictionaryEntry updatedEntry, {
    bool shouldSetState = true,
  }) {
    final updateLogic = () {
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
    };

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

  void _scrollToEntry(DictionaryEntry entry) async {
    final targetKey = _entryKeys[entry.id];
    if (targetKey == null) return;

    if (targetKey.currentContext != null) {
      await _ensureVisible(targetKey.currentContext!);
      return;
    }

    final entries = _getAllEntriesInOrder();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      await _jumpToIndex(index, targetKey);
    }
  }

  Future<void> _jumpToIndex(int index, GlobalKey targetKey) async {
    const itemHeight = 600.0;
    var offset = index * itemHeight;

    for (int i = 0; i < 5; i++) {
      final maxExtent = _contentScrollController.position.maxScrollExtent;
      _contentScrollController.jumpTo(offset.clamp(0.0, maxExtent));

      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 30));

      if (targetKey.currentContext != null) {
        await _ensureVisible(targetKey.currentContext!);
        return;
      }
      offset += itemHeight;
    }

    final maxExtent = _contentScrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      _contentScrollController.jumpTo(maxExtent);
      await WidgetsBinding.instance.endOfFrame;
      if (targetKey.currentContext != null) {
        await _ensureVisible(targetKey.currentContext!);
      }
    }
  }

  Future<void> _ensureVisible(BuildContext context) async {
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  void _onDictionaryChanged() {
    // 清空 entry keys，因为 entries 列表会改变
    _entryKeys.clear();
    setState(() {});
  }

  void _onPageChanged() {
    _entryKeys.clear();
    setState(() {});
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
        _showSnackBar('已将 "$word" 从单词本移除');
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
        _showSnackBar('已更新 "$word" 的词表归属');
      }
    } else {
      if (selectedLists.isEmpty) {
        if (mounted) {
          _showSnackBar('请至少选择一个词表');
        }
      } else {
        final success = await _wordBankService.addWord(
          word,
          language,
          lists: selectedLists,
        );
        if (mounted) {
          if (success) {
            _showSnackBar('已将 "$word" 加入单词本');
            setState(() => _isFavorite = true);
          } else {
            _showSnackBar('添加失败');
          }
        }
      }
    }
  }

  void _showNewSearch() {
    Navigator.of(context).pop({'selectText': true});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _getAllEntriesInOrder();

    for (final entry in entries) {
      _entryKeys.putIfAbsent(entry.id, () => GlobalKey());
    }

    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    final hasRelations =
        widget.searchRelations != null && widget.searchRelations!.isNotEmpty;
    final totalCount = entries.length + (hasRelations ? 1 : 0);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListView.builder(
            controller: _contentScrollController,
            padding: _getDynamicPadding(context).copyWith(bottom: 100),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              if (hasRelations && index == 0) {
                return _buildSearchRelationBanner();
              }
              final entryIndex = hasRelations ? index - 1 : index;
              final entry = entries[entryIndex];
              return Container(
                key: _entryKeys[entry.id],
                child: _buildEntryContent(entry),
              );
            },
          ),
          if (_entryGroup.dictionaryGroups.isNotEmpty && _isNavPanelLoaded)
            _DraggableNavPanel(
              entryGroup: _entryGroup,
              onDictionaryChanged: _onDictionaryChanged,
              onPageChanged: _onPageChanged,
              onSectionChanged: _onSectionChanged,
              onNavigateToEntry: _scrollToEntry,
              initialIsRight: _isNavPanelRight,
              initialDy: _navPanelDy,
            ),
          // 浮动底部功能栏
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding > 0 ? bottomPadding : 16,
            child: _buildBottomActionBar(),
          ),
        ],
      ),
    );
  }

  // 构建底部功能栏（与主页面 NavigationBar 区分，使用卡片样式）
  Widget _buildBottomActionBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;

    return Container(
      margin: _getDynamicPadding(
        context,
      ).copyWith(top: 0, bottom: bottomPadding > 0 ? bottomPadding / 2 : 0),
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
              // 返回按钮（最左边）
              Expanded(
                child: _buildActionButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                  onLongPress: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ),
              // 收藏按钮
              Expanded(
                child: _buildActionButton(
                  icon: _isFavorite ? Icons.bookmark : Icons.bookmark_outline,
                  isActive: _isFavorite,
                  onPressed: _toggleFavorite,
                ),
              ),
              // 一键显示/隐藏非目标语言
              Expanded(
                child: _buildActionButton(
                  icon: _isNonTargetLanguagesVisible
                      ? Icons.translate
                      : Icons.translate_outlined,
                  isActive: _isNonTargetLanguagesVisible,
                  onPressed: _toggleAllNonTargetLanguages,
                ),
              ),
              // 大模型历史记录
              Expanded(
                child: _buildActionButton(
                  icon: Icons.auto_awesome,
                  onPressed: _showAiChatHistory,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 600) {
      return const EdgeInsets.symmetric(horizontal: 4, vertical: 6);
    } else if (screenWidth < 900) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    } else {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 6);
    }
  }

  Widget _buildEntryContent(DictionaryEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Padding(
                padding: _getDynamicPadding(context),
                child: ComponentRenderer(
                  key: _componentRendererKey,
                  entry: entry,
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
                    _componentRendererKey.currentState?.handleTranslationInsert(
                      path,
                      newEntry,
                    );
                  },
                ),
              ),
            ],
          ),
          _buildNominalizationLink(entry),
        ],
      ),
    );
  }

  Widget _buildNominalizationLink(DictionaryEntry entry) {
    final headword = entry.headword;
    if (headword.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<String?>(
      future: EnglishSearchService().searchNominalizationBase(headword),
      builder: (context, snapshot) {
        final baseWord = snapshot.data;
        if (baseWord == null) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: _getDynamicPadding(context).copyWith(top: 0),
          child: Row(
            children: [
              Icon(Icons.translate, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  locale: const Locale('zh', 'CN'),
                  text: TextSpan(
                    text: '可以通过名词化还原为单词 ',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      TextSpan(
                        text: baseWord,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            _handleNominalizationTap(baseWord);
                          },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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

  void _handleNominalizationTap(String word) async {
    _navigateToWord(word);
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
      _showSnackBar('无法编辑此元素: $e');
    }
  }

  void _showJsonElementEditor(
    DictionaryEntry entry,
    List<String> pathParts,
    dynamic initialValue, {
    bool isFromHistory = false,
    List<String>? initialPath, // 新增：初始路径
  }) async {
    // 如果不是从历史记录导航过来的，添加新路径到历史
    if (!isFromHistory) {
      if (_historyIndex < _pathHistory.length - 1) {
        _pathHistory.removeRange(_historyIndex + 1, _pathHistory.length);
      }
      _pathHistory.add(List<String>.from(pathParts));
      _historyIndex = _pathHistory.length - 1;
    }

    // 记录初始路径（如果是第一次打开）
    final startPath =
        initialPath ?? (isFromHistory ? null : List<String>.from(pathParts));

    final initialText = const JsonEncoder.withIndent(
      '  ',
    ).convert(initialValue);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _JsonEditorBottomSheet(
        entry: entry,
        pathParts: pathParts,
        initialText: initialText,
        historyIndex: _historyIndex,
        pathHistory: _pathHistory,
        initialPath: startPath, // 传递初始路径
        onSave: (newValue) async {
          await _saveElementChange(entry, pathParts, newValue);
          if (mounted) {
            setState(() {});
          }
        },
        onNavigate: (newPathParts, newValue) {
          _showJsonElementEditor(
            entry,
            newPathParts,
            newValue,
            isFromHistory: true,
            initialPath: startPath, // 传递初始路径
          );
        },
      ),
    );
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

  Future<void> _saveElementChange(
    DictionaryEntry entry,
    List<String> pathParts,
    dynamic newValue,
  ) async {
    try {
      final fullJson = entry.toJson();
      dynamic current = fullJson;

      // 遍历到倒数第二个节点
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

      // 更新最后一个节点
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

      final newEntry = DictionaryEntry.fromJson(fullJson);
      final success = await DatabaseService().updateEntry(newEntry);

      if (success) {
        _updateEntryInGroup(newEntry);
        if (mounted) {
          _showSnackBar('保存成功');
        }
      } else {
        throw Exception('数据库更新失败');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('保存失败: $e');
      }
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
      _showSnackBar('处理失败: $e');
    }
  }

  Future<void> _performTranslation(
    DictionaryEntry entry,
    List<String> pathParts,
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    _showSnackBar('正在翻译...', duration: const Duration(seconds: 1));

    try {
      final translation = await AIService().translate(text, targetLang);

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
        current[targetLang] = translation;

        final newEntry = DictionaryEntry.fromJson(json);
        await DatabaseService().updateEntry(newEntry);

        final hiddenPath = targetPath.join('.');
        final hiddenKey = '$hiddenPath.$targetLang';

        // 确保新翻译的内容显示出来（只更新本地状态，不保存到数据库的 hidden_languages）
        _componentRendererKey.currentState?.handleTranslationInsert(
          hiddenKey,
          newEntry,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('翻译失败: $e');
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

      // 通知 ComponentRenderer 更新本地隐藏状态
      _componentRendererKey.currentState?.toggleHiddenLanguage(hiddenKey);
    } catch (e) {
      Logger.d('Error in _toggleTranslationVisibility: $e', tag: 'Translation');
      if (mounted) {
        _showSnackBar('切换失败: $e');
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

      // 更新 ComponentRenderer 的本地隐藏状态
      final pathsToHide = newVisibility ? <String>[] : languagePaths.toList();
      final pathsToShow = newVisibility ? languagePaths.toList() : <String>[];
      _componentRendererKey.currentState?.batchToggleHiddenLanguages(
        pathsToHide: pathsToHide,
        pathsToShow: pathsToShow,
      );

      _showSnackBar(newVisibility ? '已显示所有语言' : '已隐藏非目标语言');
    } catch (e) {
      Logger.d('Error in _toggleAllNonTargetLanguages: $e', tag: 'Translation');
      if (mounted) {
        _showSnackBar('切换失败: $e');
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
    _aiChatHistoryService.addRecord(
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
    _showSnackBar('AI正在思考中，您可以继续浏览...', duration: const Duration(seconds: 2));

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
          _aiChatHistoryService.updateRecord(
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
            setState(() {});
            // 显示完成提示
            _showSnackBar(
              'AI回答已就绪',
              action: SnackBarAction(
                label: '查看',
                onPressed: () {
                  // 先关闭SnackBar
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _showAiResponseDialog(
                    question,
                    answer,
                    record: _aiChatHistory[index],
                  );
                },
              ),
            );
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
          _aiChatHistoryService.updateRecord(
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
            _showSnackBar('AI请求失败: $e');
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

  /// 显示AI回答对话框
  void _showAiResponseDialog(
    String question,
    String answer, {
    AiChatRecord? record,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text('AI回答'),
            // 查看历史按钮
            IconButton(
              onPressed: () {
                Navigator.pop(context);
                _showAiChatHistory();
              },
              icon: const Icon(Icons.history),
              tooltip: '查看历史记录',
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '问题: $question',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (record?.path != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.home,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        record!.path!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              // 使用Markdown渲染回答
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: answer,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: Theme.of(context).textTheme.bodyMedium,
                      h1: Theme.of(context).textTheme.headlineMedium,
                      h2: Theme.of(context).textTheme.headlineSmall,
                      h3: Theme.of(context).textTheme.titleLarge,
                      code: TextStyle(
                        fontFamily: 'Consolas',
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquote: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                            width: 4,
                          ),
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              // 复制到剪贴板
              Clipboard.setData(ClipboardData(text: answer));
              Navigator.pop(context);
              _showSnackBar('已复制到剪贴板');
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  /// 显示AI聊天记录
  void _showAiChatHistory() {
    final freeChatController = TextEditingController();
    final freeChatFocusNode = FocusNode();
    bool isFullScreen = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: isFullScreen ? 0.95 : 0.7,
            minChildSize: isFullScreen ? 0.95 : 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _summarizeCurrentPage();
                          },
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('总结当前页'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
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
                          ),
                          tooltip: isFullScreen ? '退出全屏' : '全屏',
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),
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
                                  margin: const EdgeInsets.only(bottom: 12),
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
                                        padding: const EdgeInsets.all(16),
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
                                              // Markdown渲染回答
                                              MarkdownBody(
                                                data: record.answer,
                                                selectable: true,
                                                styleSheet: MarkdownStyleSheet(
                                                  p: Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium,
                                                  code: TextStyle(
                                                    fontFamily: 'Consolas',
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest,
                                                  ),
                                                  blockquote: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                  blockquoteDecoration:
                                                      BoxDecoration(
                                                        border: Border(
                                                          left: BorderSide(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .outline,
                                                            width: 4,
                                                          ),
                                                        ),
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest
                                                            .withOpacity(0.5),
                                                      ),
                                                ),
                                              ),
                                            const SizedBox(height: 8),
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
                                                      _showSnackBar('已复制到剪贴板');
                                                    },
                                                    icon: const Icon(
                                                      Icons.copy,
                                                      size: 18,
                                                    ),
                                                    label: const Text('复制回答'),
                                                  ),
                                                const SizedBox(width: 8),
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
                                                      size: 18,
                                                    ),
                                                    label: const Text('继续对话'),
                                                  ),
                                                const SizedBox(width: 8),
                                                // 删除单条记录按钮
                                                TextButton.icon(
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
                                                      await _aiChatHistoryService
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
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                  ),
                                                  label: Text(
                                                    '删除',
                                                    style: TextStyle(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                    ),
                                                  ),
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
                    const Divider(),
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
                                hintText: '输入任意问题，AI将结合当前单词上下文回答...',
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
    _aiChatHistoryService.addRecord(
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
          _aiChatHistoryService.updateRecord(
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
          _aiChatHistoryService.updateRecord(
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
                                    styleSheet: MarkdownStyleSheet(
                                      p: Theme.of(context).textTheme.bodyMedium,
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
    _aiChatHistoryService.addRecord(
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
          _aiChatHistoryService.updateRecord(
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
          _aiChatHistoryService.updateRecord(
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
      _showSnackBar('当前页没有内容');
      return;
    }

    final currentPage = currentDict.pageGroups[currentPageIndex];
    final entries = currentPage.sections.map((s) => s.entry).toList();

    if (entries.isEmpty) {
      _showSnackBar('当前页没有内容');
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

    setState(() {});

    // 构建当前页所有entries的JSON内容
    final jsonContent = const JsonEncoder.withIndent('  ').convert({
      'dictionary': currentDict.dictionaryId,
      'page': currentPageIndex,
      'entries': entries.map((e) => e.toJson()).toList(),
    });

    final requestFuture = _aiService.summarizeDictionary(jsonContent);
    _pendingAiRequests[requestId] = requestFuture;

    _showSnackBar('AI正在分析当前页内容...', duration: const Duration(seconds: 2));

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
          }
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            _showSnackBar(
              'AI总结已就绪',
              action: SnackBarAction(
                label: '查看',
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _showAiResponseDialog(
                    '当前页内容总结',
                    summary,
                    record: _aiChatHistory[index],
                  );
                },
              ),
            );
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
          }
          if (_currentLoadingId == requestId) {
            _currentLoadingId = null;
          }
          if (mounted) {
            setState(() {});
            _showSnackBar('AI总结失败: $e');
          }
        });
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
