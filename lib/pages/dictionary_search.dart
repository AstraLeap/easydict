import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/word_bank_service.dart';
import '../models/browse_list.dart';
import '../services/search_history_service.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_db_service.dart';
import '../services/english_search_service.dart';
import '../services/font_loader_service.dart';
import '../services/entry_event_bus.dart';
import '../services/daily_word_service.dart';
import '../services/entry_tab_service.dart';
import 'entry_tab_host_page.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/language_utils.dart';
import '../widgets/search_bar.dart';
import '../components/english_db_download_dialog.dart';
import '../components/global_scale_wrapper.dart';
import '../core/logger.dart';
import '../i18n/strings.g.dart';

class DictionarySearchPage extends StatefulWidget {
  const DictionarySearchPage({super.key});

  @override
  State<DictionarySearchPage> createState() => _DictionarySearchPageState();
}

class _DictionarySearchPageState extends State<DictionarySearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final DatabaseService _dbService = DatabaseService();
  final SearchHistoryService _historyService = SearchHistoryService();
  final AdvancedSearchSettingsService _advancedSettingsService =
      AdvancedSearchSettingsService();
  final DictionaryManager _dictManager = DictionaryManager();
  final DailyWordService _dailyWordService = DailyWordService();
  final WordBankService _wordBankService = WordBankService();
  final EntryTabService _entryTabService = EntryTabService();

  // 使用 ValueNotifier 优化频繁变化的状态，减少不必要的全局重建
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isHistoryEditModeNotifier = ValueNotifier(false);
  final ValueNotifier<List<String>> _dailyWordsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isLoadingDailyWordsNotifier = ValueNotifier(false);
  final ValueNotifier<List<String>> _searchResultsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _showSearchResultsNotifier = ValueNotifier(false);
  final ValueNotifier<int> _selectedResultIndexNotifier = ValueNotifier(-1);

  // Getters/setters 保持代码兼容性
  bool get _isLoading => _isLoadingNotifier.value;
  set _isLoading(bool value) => _isLoadingNotifier.value = value;
  bool get _isHistoryEditMode => _isHistoryEditModeNotifier.value;
  set _isHistoryEditMode(bool value) =>
      _isHistoryEditModeNotifier.value = value;
  List<String> get _dailyWords => _dailyWordsNotifier.value;
  set _dailyWords(List<String> value) => _dailyWordsNotifier.value = value;
  bool get _isLoadingDailyWords => _isLoadingDailyWordsNotifier.value;
  set _isLoadingDailyWords(bool value) =>
      _isLoadingDailyWordsNotifier.value = value;
  List<String> get _searchResults => _searchResultsNotifier.value;
  set _searchResults(List<String> value) =>
      _searchResultsNotifier.value = value;
  bool get _showSearchResults => _showSearchResultsNotifier.value;
  set _showSearchResults(bool value) =>
      _showSearchResultsNotifier.value = value;
  int get _selectedResultIndex => _selectedResultIndexNotifier.value;
  set _selectedResultIndex(int value) =>
      _selectedResultIndexNotifier.value = value;

  List<SearchRecord> _searchRecords = [];
  bool _wasFocused = false;

  // 分组设置
  String _selectedGroup = 'auto';
  List<String> _availableGroups = ['auto'];

  // 按语言独立存储的精确匹配设置
  Map<String, bool> _exactMatchByLanguage = {};

  // 获取当前语言的精确匹配设置
  bool get _exactMatch {
    return _exactMatchByLanguage[_selectedGroup] ?? false;
  }

  // 设置当前语言的精确匹配设置
  set _exactMatch(bool value) {
    _exactMatchByLanguage[_selectedGroup] = value;
  }

  // 每日单词
  List<String> _selectedLanguages = [];
  Map<String, List<String>> _selectedLists = {};
  Map<String, List<WordListInfo>> _availableWordListsMap = {};
  List<String> _availableWordBankLanguages = [];
  final Map<String, String> _wordLanguageCache = {};
  bool _isHandlingKeyboardEnter = false;
  Timer? _debounceTimer;
  int _prefixSearchToken = 0;
  bool _isSearchingWord = false;
  StreamSubscription<SettingsSyncedEvent>? _syncSubscription;
  StreamSubscription<DictionariesChangedEvent>? _dictsChangedSubscription;
  StreamSubscription<LanguageOrderChangedEvent>? _langOrderSubscription;
  StreamSubscription<SearchHistoryChangedEvent>? _historyChangedSubscription;
  StreamSubscription<ClipboardSearchEvent>? _clipboardSearchSubscription;

  // 从历史记录点击进入详情时，临时暂停历史组件刷新，避免先重建当前页。
  bool _pauseHistoryComponentRefresh = false;
  bool _pendingHistoryComponentRefresh = false;
  Timer? _historyRefreshTimer;
  static const Duration _historyRefreshDelay = Duration(milliseconds: 450);

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
    // 拦截方向键，阻止 TextField 默认的光标移动行为（上/下移到行首/尾）
    _searchFocusNode.onKey = (FocusNode node, RawKeyEvent event) {
      if (event is RawKeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown)) {
        // 直接在此处处理搜索结果导航（不调用 _handleKeyEvent 避免 hasFocus 防重复问题）
        if (_showSearchResults && _searchResults.isNotEmpty) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_selectedResultIndex < _searchResults.length - 1) {
              _selectedResultIndex++;
            } else {
              _selectedResultIndex = 0;
            }
          } else {
            if (_selectedResultIndex > 0) {
              _selectedResultIndex--;
            } else {
              _selectedResultIndex = _searchResults.length - 1;
            }
          }
        }
        return KeyEventResult.handled; // 始终吸收，防止 TextField 移动光标
      }
      return KeyEventResult.ignored;
    };
    _initData();
    _syncSubscription = EntryEventBus().settingsSynced.listen((event) {
      if (event.includesHistory) {
        _refreshHistoryComponent();
      }
    });
    _dictsChangedSubscription = EntryEventBus().dictionariesChanged.listen((_) {
      _loadDictionaryGroups();
    });
    _langOrderSubscription = EntryEventBus().languageOrderChanged.listen((_) {
      _loadDictionaryGroups();
    });
    _historyChangedSubscription = EntryEventBus().searchHistoryChanged.listen((
      _,
    ) {
      _refreshHistoryComponent();
    });
    // 监听剪切板搜索事件
    _clipboardSearchSubscription = EntryEventBus().clipboardSearch.listen((
      event,
    ) {
      _handleClipboardSearch(event.text);
    });
  }

  void _onFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      _wasFocused = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FontLoaderService().reloadDictionaryContentScale();
  }

  Future<void> _initData() async {
    try {
      await Future.wait([
        _loadSearchHistory(),
        _loadAdvancedSettings(),
        _loadDictionaryGroups(),
        _loadDailyWordSettings(),
      ]);

      Logger.i('DictionarySearchPage _initData 完成', tag: 'DictionarySearch');

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e, stack) {
      Logger.e(
        'DictionarySearchPage _initData 错误: $e',
        tag: 'DictionarySearch',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _loadDictionaryGroups() async {
    final dicts = await _dictManager.getEnabledDictionariesMetadata();
    final rawLanguages = dicts
        .map((d) => LanguageUtils.normalizeSourceLanguage(d.sourceLanguage))
        .toSet()
        .toList();

    final savedOrder = await _advancedSettingsService.getLanguageOrder();
    final languages = AdvancedSearchSettingsService.sortLanguagesByOrder(
      rawLanguages,
      savedOrder,
    );

    final availableGroups = ['auto', ...languages];

    final lastGroup = await _advancedSettingsService.getLastSelectedGroup();
    final selectedGroup =
        (lastGroup != null && availableGroups.contains(lastGroup))
        ? lastGroup
        : 'auto';

    if (mounted) {
      setState(() {
        _availableGroups = availableGroups;
        _selectedGroup = selectedGroup;
      });
    }
  }

  /// 加载每日单词设置
  Future<void> _loadDailyWordSettings() async {
    final languages = await _wordBankService.getSupportedLanguages();

    _selectedLanguages = await _dailyWordService.getSelectedLanguages();
    _selectedLists = await _dailyWordService.getSelectedLists();

    _selectedLanguages = _selectedLanguages
        .where((l) => languages.contains(l))
        .toList();

    if (_selectedLanguages.isNotEmpty) {
      for (final lang in _selectedLanguages) {
        await _loadWordListsForLanguage(lang);
      }
      await _loadDailyWords();
    }

    if (mounted) {
      setState(() {
        _availableWordBankLanguages = languages;
      });
    }
  }

  /// 加载指定语言的词表列表
  Future<void> _loadWordListsForLanguage(String language) async {
    final lists = await _wordBankService.getWordLists(language);
    if (mounted) {
      setState(() {
        _availableWordListsMap[language] = lists;
      });
    }
  }

  /// 加载每日单词
  Future<void> _loadDailyWords() async {
    if (_selectedLanguages.isEmpty) return;

    _isLoadingDailyWords = true;

    final words = await _dailyWordService.getDailyWords();
    _wordLanguageCache.clear();

    if (mounted) {
      _dailyWords = words;
      _isLoadingDailyWords = false;
    }
  }

  /// 刷新每日单词
  Future<void> _refreshDailyWords() async {
    if (_selectedLanguages.isEmpty) return;

    _isLoadingDailyWords = true;

    final words = await _dailyWordService.refreshDailyWords();
    _wordLanguageCache.clear();

    if (mounted) {
      _dailyWords = words;
      _isLoadingDailyWords = false;
    }
  }

  /// 从每日单词查词
  Future<void> _searchFromDailyWord(String word) async {
    if (_selectedLanguages.isEmpty) return;

    // 防止重复搜索
    if (_isSearchingWord) {
      Logger.d('_searchFromDailyWord: 跳过，正在搜索中', tag: 'DictionarySearch');
      return;
    }

    String? language = _wordLanguageCache[word];
    if (language == null) {
      language = await _dailyWordService.getWordLanguage(word);
      _wordLanguageCache[word] = language;
    }

    _isSearchingWord = true;
    _beginDeferredHistoryRefreshWindow();
    Logger.d('_searchFromDailyWord 开始: $word', tag: 'DictionarySearch');

    _isLoading = true;
    _showSearchResults = false;
    _searchResults = [];
    _selectedResultIndex = -1;

    if (_detectLanguage(word) == 'en') {
      // 每日词点击后立即并行预热顶部关系横幅数据。
      unawaited(EnglishSearchService().searchWordRelations(word));
    }

    try {
      final reusableTab = _findReusableSearchTab(word);
      if (reusableTab != null) {
        Logger.d('每日词复用已有搜索标签: $word', tag: 'DictionarySearch');

        await _historyService.addSearchRecord(word, exactMatch: false);
        await _historyService.addSearchRecord(
          word,
          exactMatch: false,
          group: language,
        );

        final records = await _historyService.getSearchRecords();
        if (mounted) {
          await _openEntryHostFromData(
            word: word,
            entryGroup: reusableTab.entryGroup,
            dictResults: reusableTab.dictResults,
            records: records,
            deferHistoryComponentUpdateUntilNavigated: false,
          );
        }
        return;
      }

      final searchResult = await _dbService.getAllEntries(
        word,
        exactMatch: false,
        sourceLanguage: language,
      );

      if (searchResult.entries.isNotEmpty) {
        final entryGroup = DictionaryEntryGroup.groupEntries(
          searchResult.entries,
        );

        // 获取语言信息并记录搜索历史
        String? group;
        final dictId = searchResult.entries.first.dictId;
        if (dictId != null) {
          final metadata = await DictionaryManager().getDictionaryMetadata(
            dictId,
          );
          group = metadata?.sourceLanguage;
        }
        await _historyService.addSearchRecord(word, group: group);

        // 重新获取历史记录以构建浏览列表
        final records = await _historyService.getSearchRecords();

        if (mounted) {
          await _openEntryHostFromData(
            word: word,
            entryGroup: entryGroup,
            dictResults: searchResult.dictResults.isNotEmpty
                ? searchResult.dictResults
                : null,
            records: records,
            deferHistoryComponentUpdateUntilNavigated: false,
          );
        }
      } else {
        if (mounted) {
          showToast(context, context.t.search.noResult(word: word));
        }
      }
    } catch (e, stack) {
      Logger.e(
        '_searchFromDailyWord 失败: $e',
        tag: 'DictionarySearch',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        showToast(context, context.t.search.noResult(word: word));
      }
    } finally {
      _isLoading = false;
      _isSearchingWord = false;
      if (_pauseHistoryComponentRefresh) {
        _resumeHistoryComponentRefresh();
      }
      Logger.d('_searchFromDailyWord 完成: $word', tag: 'DictionarySearch');
    }
  }

  /// 加载高级搜索设置
  Future<void> _loadAdvancedSettings() async {
    // 加载所有语言的精确匹配设置
    final settings = await _advancedSettingsService.getAllExactMatchSettings();
    setState(() {
      _exactMatchByLanguage = settings;
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _dictsChangedSubscription?.cancel();
    _langOrderSubscription?.cancel();
    _historyChangedSubscription?.cancel();
    _clipboardSearchSubscription?.cancel();
    _debounceTimer?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _historyRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    // 释放 ValueNotifier
    _isLoadingNotifier.dispose();
    _isHistoryEditModeNotifier.dispose();
    _dailyWordsNotifier.dispose();
    _isLoadingDailyWordsNotifier.dispose();
    _searchResultsNotifier.dispose();
    _showSearchResultsNotifier.dispose();
    _selectedResultIndexNotifier.dispose();
    super.dispose();
  }

  /// 激活搜索框：获取焦点并全选文本
  /// 用于用户在已处于查词页时再次点击查词 tab
  void activateSearchBar() {
    _searchFocusNode.requestFocus();
    if (_searchController.text.isNotEmpty) {
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    }
  }

  void _beginDeferredHistoryRefreshWindow() {
    _pauseHistoryComponentRefresh = true;
    _pendingHistoryComponentRefresh = false;
    _historyRefreshTimer?.cancel();
  }

  void _scheduleHistoryComponentRefresh({
    List<SearchRecord>? records,
    Duration? delay,
  }) {
    _historyRefreshTimer?.cancel();
    _historyRefreshTimer = Timer(delay ?? _historyRefreshDelay, () {
      if (!mounted) return;
      if (records != null) {
        setState(() {
          _searchRecords = records;
        });
      } else {
        _loadSearchHistory();
      }
    });
  }

  /// 判断当前语言是否需要至少输入2个字符才启动边打边搜（字母文字）。
  /// auto 模式且含表意文字单字符时不需要；其余字母文字需要 2 个字符。
  bool _prefixSearchNeedsMinTwoChars(String text) {
    if (_selectedGroup == 'auto') {
      // 含汉字/假名/谚文时，1 个字符就足够触发搜索
      if (DatabaseService.containsIdeographic(text)) return false;
      return true;
    }
    const logographic = {'zh', 'jp', 'ko'};
    return !logographic.contains(_selectedGroup);
  }

  /// 边打边搜 - 立即前置匹配，无防抖
  void _onSearchTextChanged(String text) {
    if (_isSearchingWord) return;

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      _prefixSearchToken++;
      _searchResults = [];
      _showSearchResults = false;
      _selectedResultIndex = -1;
      return;
    }

    // 字母文字 / auto 模式：至少2个字符才触发（表意文字单字符除外）
    final needsMinTwo = _prefixSearchNeedsMinTwoChars(trimmedText);
    if (needsMinTwo && trimmedText.length < 2) {
      _prefixSearchToken++;
      _searchResults = [];
      _showSearchResults = false;
      _selectedResultIndex = -1;
      return;
    }

    final currentToken = ++_prefixSearchToken;

    () async {
      if (currentToken != _prefixSearchToken) return;

      // 传入原始文本（含大小写、尾部空格），供 Dart 层 startsWith 比较；
      // DatabaseService 内部会 trim 后再用于 SQL 查询。
      final results = await _dbService.getPreSearchCandidates(
        text,
        sourceLanguage: _selectedGroup,
        exactMatch: _exactMatch,
        biaoyiExactMatch: _exactMatch,
        limit: 8,
      );

      if (!mounted || currentToken != _prefixSearchToken) return;

      _searchResults = results;
      _showSearchResults = results.isNotEmpty;
      _selectedResultIndex = -1;
    }();
  }

  /// 点击搜索结果项
  Future<void> _onSearchResultTap(String word) async {
    _searchController.text = word;
    _searchResults = [];
    _showSearchResults = false;
    _selectedResultIndex = -1;
    await _searchWord();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (!_showSearchResults || _searchResults.isEmpty) {
        return;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        // 当搜索框有焦点时，该事件已由 _searchFocusNode.onKey 处理，这里跳过避免重复触发
        if (_searchFocusNode.hasFocus) return;
        if (_selectedResultIndex < _searchResults.length - 1) {
          _selectedResultIndex++;
        } else {
          _selectedResultIndex = 0;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_searchFocusNode.hasFocus) return;
        if (_selectedResultIndex > 0) {
          _selectedResultIndex--;
        } else {
          _selectedResultIndex = _searchResults.length - 1;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_selectedResultIndex >= 0 &&
            _selectedResultIndex < _searchResults.length) {
          _isHandlingKeyboardEnter = true;
          _onSearchResultTap(_searchResults[_selectedResultIndex]);
        }
      }
    }
  }

  Future<void> _loadSearchHistory() async {
    final records = await _historyService.getSearchRecords();
    setState(() {
      _searchRecords = records;
    });
  }

  void _refreshHistoryComponent() {
    if (_pauseHistoryComponentRefresh || _isSearchingWord) {
      _pendingHistoryComponentRefresh = true;
      return;
    }
    _scheduleHistoryComponentRefresh();
  }

  void _resumeHistoryComponentRefresh() {
    _pauseHistoryComponentRefresh = false;
    if (_pendingHistoryComponentRefresh) {
      _pendingHistoryComponentRefresh = false;
      _scheduleHistoryComponentRefresh();
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.search.historyClearConfirmTitle),
        content: Text(context.t.search.historyClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _historyService.clearHistory();
    setState(() {
      _searchRecords = [];
    });
    if (mounted) {
      showToast(context, context.t.search.historyCleared);
    }
  }

  Future<void> _onSearchFromHistory(SearchRecord record) async {
    // 恢复搜索记录中保存的高级选项和成功搜索时的语言
    _searchController.text = record.word;
    _exactMatch = record.exactMatch;
    if (record.group != null) {
      _selectedGroup = record.group!;
    }
    await _searchWord(deferHistoryComponentUpdateUntilNavigated: true);
  }

  /// 处理剪切板搜索事件
  void _handleClipboardSearch(String text) {
    Logger.i(
      '收到剪切板搜索事件: $text, _isSearchingWord=$_isSearchingWord',
      tag: 'DictionarySearch',
    );
    // 设置搜索框文本
    _searchController.text = text;
    // 执行搜索
    _searchWord();
  }

  EntryTabItem? _findReusableSearchTab(String word) {
    final normalized = word.trim().toLowerCase();
    for (final tab in _entryTabService.tabs) {
      if (tab.word.trim().toLowerCase() != normalized) continue;
      final source = tab.browseList?.source;
      if (source == null || source == BrowseListSource.searchHistory) {
        return tab;
      }
    }
    return null;
  }

  BrowseList? _buildHistoryBrowseList(List<SearchRecord> records, String word) {
    final historyWords = records.map((r) => r.word).toList();
    if (historyWords.isEmpty) return null;
    final currentIndex = historyWords.indexOf(word);
    return BrowseList(
      source: BrowseListSource.searchHistory,
      words: historyWords,
      initialIndex: currentIndex >= 0 ? currentIndex : 0,
    );
  }

  Future<void> _openEntryHostFromData({
    required String word,
    required DictionaryEntryGroup entryGroup,
    required List<SearchRecord> records,
    List<DictSearchResult>? dictResults,
    required bool deferHistoryComponentUpdateUntilNavigated,
  }) async {
    if (!mounted) return;

    final navResultFuture = EntryTabHostPage.open(
      context,
      entryGroup: entryGroup,
      initialWord: word,
      dictResults: dictResults,
      browseList: _buildHistoryBrowseList(records, word),
    );

    final navResult = await navResultFuture;

    // 查词完成后再延迟刷新历史组件，避免查词动作触发立刻重建。
    _scheduleHistoryComponentRefresh(
      records: records,
      delay: deferHistoryComponentUpdateUntilNavigated
          ? const Duration(milliseconds: 520)
          : _historyRefreshDelay,
    );

    if (navResult == null) return;

    if (navResult is String) {
      _searchController.text = navResult;
      await _searchWord();
      return;
    }

    if (navResult is Map && navResult['selectText'] == true) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _searchFocusNode.requestFocus();
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        }
      });
    }
  }

  Future<void> _searchWord({
    bool deferHistoryComponentUpdateUntilNavigated = false,
  }) async {
    // 防止重复搜索
    if (_isSearchingWord) {
      Logger.d('_searchWord: 跳过，正在搜索中', tag: 'DictionarySearch');
      return;
    }

    _debounceTimer?.cancel();
    _prefixSearchToken++;
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

    if (_detectLanguage(word) == 'en') {
      // 用户点击查词瞬间即预热顶部关系横幅数据。
      unawaited(EnglishSearchService().searchWordRelations(word));
    }

    // LIKE/GLOB 通配符模式下禁止直接查词，必须从候选词列表点击进入
    if (_isWildcardMode(word)) {
      if (mounted) {
        showToast(context, context.t.search.wildcardNoEntry);
      }
      return;
    }

    _isSearchingWord = true;
    _beginDeferredHistoryRefreshWindow();

    Logger.d(
      '用户开始查词: $word, _isSearchingWord 已设置为 true',
      tag: 'DictionarySearch',
    );

    // 首次查英语词且 en.db 不存在时，直接弹出下载推荐（不等待查询结果）
    if (_detectLanguage(word) == 'en') {
      final dbExists = await EnglishDbService().dbExists();
      if (!dbExists) {
        final cloudUrl = (await _dictManager.onlineSubscriptionUrl).trim();
        final cloudUri = Uri.tryParse(cloudUrl);
        final hasCloudServer =
            cloudUri != null && cloudUri.hasScheme && cloudUri.host.isNotEmpty;

        if (!hasCloudServer) {
          Logger.i('未设置有效服务器地址，跳过 en.db 下载提示', tag: 'EnglishDB');
        } else {
          final shouldShow = await EnglishDbService()
              .shouldShowDownloadDialog();
          if (shouldShow && mounted) {
            final result = await EnglishDbDownloadDialog.show(context);
            if (result == EnglishDbDownloadResult.downloaded && mounted) {
              showToast(context, context.t.search.dbDownloaded(word: word));
            }
            // 下载弹窗关闭后继续执行查词
          }
        }
      }
    }

    _isLoading = true;
    _showSearchResults = false;
    _searchResults = [];
    _selectedResultIndex = -1;

    try {
      final reusableTab = _findReusableSearchTab(word);
      if (reusableTab != null) {
        Logger.d('复用已有搜索标签，跳过数据库查询: $word', tag: 'DictionarySearch');

        await _historyService.addSearchRecord(word, exactMatch: _exactMatch);
        await _historyService.addSearchRecord(
          word,
          exactMatch: _exactMatch,
          group: _selectedGroup,
        );

        final records = await _historyService.getSearchRecords();
        await _openEntryHostFromData(
          word: word,
          entryGroup: reusableTab.entryGroup,
          dictResults: reusableTab.dictResults,
          records: records,
          deferHistoryComponentUpdateUntilNavigated:
              deferHistoryComponentUpdateUntilNavigated,
        );
        return;
      }

      final searchResult = await _dbService.getAllEntries(
        word,
        exactMatch: _exactMatch,
        sourceLanguage: _selectedGroup,
      );

      if (searchResult.entries.isNotEmpty) {
        final entryGroup = DictionaryEntryGroup.groupEntries(
          searchResult.entries,
        );

        // 搜索成功时才记录到搜索历史
        await _historyService.addSearchRecord(
          word,
          exactMatch: _exactMatch,
          group: _selectedGroup,
        );
        final records = await _historyService.getSearchRecords();
        await _openEntryHostFromData(
          word: word,
          entryGroup: entryGroup,
          dictResults: searchResult.dictResults.isNotEmpty
              ? searchResult.dictResults
              : null,
          records: records,
          deferHistoryComponentUpdateUntilNavigated:
              deferHistoryComponentUpdateUntilNavigated,
        );
      } else {
        final records = await _historyService.getSearchRecords();
        _scheduleHistoryComponentRefresh(records: records);
        _showSearchResults = false;

        if (mounted) {
          showToast(context, context.t.search.noResult(word: word));
        }
      }
    } catch (e, stack) {
      Logger.e(
        '_searchWord 失败: $e',
        tag: 'DictionarySearch',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        showToast(context, context.t.search.noResult(word: word));
      }
    } finally {
      _isLoading = false;
      _isSearchingWord = false;
      if (_pauseHistoryComponentRefresh) {
        _resumeHistoryComponentRefresh();
      }
      Logger.d(
        '_searchWord 完成: $word, _isSearchingWord 已重置为 false',
        tag: 'DictionarySearch',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final contentScale = FontLoaderService().getDictionaryContentScale();

    return Scaffold(
      body: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: _handleKeyEvent,
        child: PageScaleWrapper(
          scale: contentScale,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: 12,
                  ),
                  child: UnifiedSearchBarFactory.withLanguageSelector(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    selectedLanguage: _selectedGroup,
                    availableLanguages: _availableGroups,
                    onLanguageSelected: (value) async {
                      if (value != null) {
                        setState(() {
                          _selectedGroup = value;
                        });
                        await _advancedSettingsService.setLastSelectedGroup(
                          value,
                        );
                        // 语言切换后立即更新边打边搜预览列表
                        _onSearchTextChanged(_searchController.text);
                      }
                    },
                    hintText: context.t.search.hint,
                    onTap: () {
                      if (!_wasFocused && _searchController.text.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _searchController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _searchController.text.length,
                          );
                        });
                      }
                      _wasFocused = true;
                    },
                    extraSuffixIcons: [
                      // 精确匹配状态图标按钮
                      IconButton(
                        icon: Icon(
                          _exactMatch ? Icons.filter_alt : Icons.filter_alt_off,
                          size: 20,
                          color: _exactMatch
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _exactMatch = !_exactMatch;
                            _advancedSettingsService.setExactMatchForLanguage(
                              _selectedGroup,
                              _exactMatch,
                            );
                          });
                          _onSearchTextChanged(_searchController.text);
                        },
                        tooltip: _isLogographicLang(_selectedGroup)
                            ? context.t.search.toneExact
                            : context.t.search.exactMatch,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.arrow_forward,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          if (_isLoading) return;
                          // 通配符模式或有搜索结果时，查询第一个候选词；否则直接查词
                          if (_searchResults.isNotEmpty) {
                            _onSearchResultTap(_searchResults.first);
                          } else if (!_isWildcardMode(
                            _searchController.text.trim(),
                          )) {
                            _searchWord();
                          }
                        },
                        tooltip: context.t.search.searchBtn,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ],
                    onChanged: (text) {
                      _onSearchTextChanged(text);
                    },
                    onSubmitted: (_) {
                      if (_isHandlingKeyboardEnter) {
                        _isHandlingKeyboardEnter = false;
                        return;
                      }
                      if (_selectedResultIndex >= 0 &&
                          _selectedResultIndex < _searchResults.length) {
                        // 用户用方向键选择了候选词，使用选中的词
                        _onSearchResultTap(
                          _searchResults[_selectedResultIndex],
                        );
                      } else if (!_isWildcardMode(
                        _searchController.text.trim(),
                      )) {
                        // 用户直接按回车，使用输入框中的原始词进行搜索
                        // 而不是自动选择第一个候选词，避免大小写变化问题
                        _searchWord();
                      }
                    },
                  ),
                ),
                // 搜索结果列表 - 使用 ValueListenableBuilder 实现局部重建
                ValueListenableBuilder<bool>(
                  valueListenable: _showSearchResultsNotifier,
                  builder: (context, showResults, child) {
                    if (!showResults) return const SizedBox.shrink();
                    return ValueListenableBuilder<List<String>>(
                      valueListenable: _searchResultsNotifier,
                      builder: (context, results, _) {
                        if (results.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  context.t.search.searchResults,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ),
                              const Divider(height: 1),
                              ValueListenableBuilder<int>(
                                valueListenable: _selectedResultIndexNotifier,
                                builder: (context, selectedIndex, _) {
                                  return ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: results.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final word = results[index];
                                      final isSelected = index == selectedIndex;
                                      return Container(
                                        color: isSelected
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withOpacity(0.15)
                                            : null,
                                        child: ListTile(
                                          dense: true,
                                          title: Text(
                                            word,
                                            style: isSelected
                                                ? TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                  )
                                                : null,
                                          ),
                                          onTap: () => _onSearchResultTap(word),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                // 每日单词
                _buildDailyWordsSection(),
                // 历史记录始终显示
                Expanded(
                  child: _searchRecords.isNotEmpty
                      ? _buildHistoryView()
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.t.search.startHint,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
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

  /// 构建每日单词区域 - 使用 ValueListenableBuilder 实现局部重建
  Widget _buildDailyWordsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.primary.withOpacity(0.4);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 边框容器
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _selectedLanguages.isEmpty
                ? _buildDailyWordsEmptyState()
                : ValueListenableBuilder<List<String>>(
                    valueListenable: _dailyWordsNotifier,
                    builder: (context, dailyWords, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _isLoadingDailyWordsNotifier,
                        builder: (context, isLoadingDailyWords, _) {
                          if (dailyWords.isEmpty && !isLoadingDailyWords) {
                            return Text(
                              context.t.search.dailyWordsNoWords,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colorScheme.outline),
                            );
                          }
                          return Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: dailyWords.map((word) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _searchFromDailyWord(word),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    word,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  ),
          ),
          // 左上角标题（骑在边框线上）
          Positioned(
            top: -10,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.t.search.dailyWords,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右上角按钮（骑在边框线上）- 使用 ValueListenableBuilder
          if (_selectedLanguages.isNotEmpty)
            Positioned(
              top: -10,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isLoadingDailyWordsNotifier,
                  builder: (context, isLoadingDailyWords, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: isLoadingDailyWords
                              ? null
                              : _refreshDailyWords,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: isLoadingDailyWords
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _showDailyWordsSettingsDialog(),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.settings_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建每日单词空状态（未选择语言）
  Widget _buildDailyWordsEmptyState() {
    return Row(
      children: [
        Text(
          context.t.search.dailyWordsLanguage,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showDailyWordsSettingsDialog(),
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.t.search.dailyWordsSettings),
        ),
      ],
    );
  }

  /// 显示每日单词设置对话框
  Future<void> _showDailyWordsSettingsDialog() async {
    var currentWordCount = await _dailyWordService.getWordCount();

    final selectedLanguages = List<String>.from(_selectedLanguages);
    final selectedLists = Map<String, List<String>>.from(_selectedLists);
    final dialogWordListsMap = <String, List<WordListInfo>>{};

    for (final lang in _availableWordBankLanguages) {
      final lists = await _wordBankService.getWordLists(lang);
      dialogWordListsMap[lang] = lists;
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            title: Text(
              context.t.search.dailyWordsSettings,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.search.dailyWordsLanguage,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableWordBankLanguages.map((lang) {
                        final isSelected = selectedLanguages.contains(lang);
                        return ChoiceChip(
                          label: Text(_langDisplayName(lang)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              selectedLanguages.add(lang);
                            } else {
                              selectedLanguages.remove(lang);
                              selectedLists.remove(lang);
                            }
                            dialogSetState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedLanguages.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        context.t.search.dailyWordsList,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...selectedLanguages.map((lang) {
                        final lists = dialogWordListsMap[lang] ?? [];
                        final selectedListNames = selectedLists[lang] ?? [];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _langDisplayName(lang),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    selectedListNames.isEmpty
                                        ? context.t.search.dailyWordsAllLists
                                        : '${selectedListNames.length}/${lists.length}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colorScheme.outline),
                                  ),
                                ],
                              ),
                              if (lists.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    context.t.search.dailyWordsNoList,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: colorScheme.outline,
                                        ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ChoiceChip(
                                        label: Text(
                                          context.t.search.dailyWordsAllLists,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        selected: selectedListNames.isEmpty,
                                        visualDensity: VisualDensity.compact,
                                        onSelected: (selected) {
                                          selectedLists[lang] = [];
                                          dialogSetState(() {});
                                        },
                                      ),
                                      ...lists.map((list) {
                                        final isSelected = selectedListNames
                                            .contains(list.name);
                                        return ChoiceChip(
                                          label: Text(
                                            list.displayName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          selected: isSelected,
                                          visualDensity: VisualDensity.compact,
                                          onSelected: (s) {
                                            selectedLists.putIfAbsent(
                                              lang,
                                              () => [],
                                            );
                                            if (s) {
                                              selectedLists[lang]!.add(
                                                list.name,
                                              );
                                            } else {
                                              selectedLists[lang]!.remove(
                                                list.name,
                                              );
                                            }
                                            dialogSetState(() {});
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      context.t.search.dailyWordsCount,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: currentWordCount.toDouble(),
                            min: 1,
                            max: 20,
                            divisions: 19,
                            label: currentWordCount.toString(),
                            onChanged: (value) async {
                              await _dailyWordService.setWordCount(
                                value.round(),
                              );
                              currentWordCount = value.round();
                              dialogSetState(() {});
                            },
                          ),
                        ),
                        Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            currentWordCount.toString(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t.common.close),
              ),
              FilledButton(
                onPressed: () async {
                  await _dailyWordService.setSelectedLanguages(
                    selectedLanguages,
                  );
                  await _dailyWordService.setSelectedLists(selectedLists);
                  _selectedLanguages = selectedLanguages;
                  _selectedLists = selectedLists;
                  for (final lang in selectedLanguages) {
                    await _loadWordListsForLanguage(lang);
                  }
                  // 强制刷新每日单词
                  await _refreshDailyWords();
                  if (mounted) {
                    setState(() {});
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: Text(context.t.common.save),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 语言代码 → 显示名称
  String _langDisplayName(String lang) {
    final names = context.t.langNames;
    switch (lang) {
      case 'zh':
        return names.zh;
      case 'jp':
        return names.jp;
      case 'ko':
        return names.ko;
      case 'en':
        return names.en;
      case 'fr':
        return names.fr;
      case 'de':
        return names.de;
      case 'es':
        return names.es;
      case 'it':
        return names.it;
      case 'ru':
        return names.ru;
      case 'pt':
        return names.pt;
      case 'ar':
        return names.ar;
      default:
        return lang.toUpperCase();
    }
  }

  bool _isLogographicLang(String lang) =>
      lang == 'zh' || lang == 'jp' || lang == 'ko';

  Widget _buildHistoryView() {
    return AnimatedBuilder(
      animation: _entryTabService,
      builder: (context, _) {
        final activeWords = _entryTabService.activeWords;
        return GestureDetector(
          onTap: () {
            if (_isHistoryEditMode) {
              _isHistoryEditMode = false;
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 16, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t.search.historyTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _clearHistory,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(context.t.search.historyClear),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      cacheExtent: 200,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 42,
                      ),
                      itemCount: _searchRecords.length,
                      itemBuilder: (context, index) {
                        final record = _searchRecords[index];
                        final isTabActive = activeWords.contains(record.word);
                        return _buildHistoryItem(
                          record,
                          isTabActive: isTabActive,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(SearchRecord record, {required bool isTabActive}) {
    final platform = Theme.of(context).platform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final colorScheme = Theme.of(context).colorScheme;

    final historyCard = Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isTabActive
            ? colorScheme.primaryContainer.withOpacity(0.78)
            : colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isTabActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              record.word,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          // 使用 ValueListenableBuilder 实现删除按钮的局部重建
          ValueListenableBuilder<bool>(
            valueListenable: _isHistoryEditModeNotifier,
            builder: (context, isEditMode, _) {
              if (!isEditMode) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => _deleteHistoryItem(record),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _ShakingDeleteIcon(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              );
            },
          ),
          if (isTabActive)
            GestureDetector(
              onTap: () {
                _entryTabService.closeByWord(record.word);
              },
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.95),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );

    return InkWell(
      onTap: () {
        if (_isHistoryEditMode) {
          return;
        }
        _onSearchFromHistory(record);
      },
      onLongPress: isMobile
          ? () {
              _isHistoryEditMode = !_isHistoryEditMode;
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Builder(
        builder: (context) {
          return GestureDetector(
            onSecondaryTapUp: (details) {
              _isHistoryEditMode = !_isHistoryEditMode;
            },
            child: isTabActive
                ? CustomPaint(
                    foregroundPainter: _DashedRoundedBorderPainter(
                      color: colorScheme.primary,
                      strokeWidth: 1.0,
                      radius: 12,
                    ),
                    child: historyCard,
                  )
                : historyCard,
          );
        },
      ),
    );
  }

  Future<void> _deleteHistoryItem(SearchRecord record) async {
    await _historyService.removeSearchRecord(record.word);
    await _loadSearchHistory();
    if (mounted) {
      showToast(context, context.t.search.historyDeleted(word: record.word));
    }
  }

  String _detectLanguage(String text) {
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'jp';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    return 'en';
  }

  /// 检测输入文本是否为 LIKE/GLOB 通配符模式。
  /// 含 % 或 _ → LIKE；含 * ? [ ] ^ → GLOB。
  bool _isWildcardMode(String text) {
    if (text.contains('%') || text.contains('_')) return true;
    if (text.contains('*') ||
        text.contains('?') ||
        text.contains('[') ||
        text.contains(']') ||
        text.contains('^')) {
      return true;
    }
    return false;
  }
}

class _ShakingDeleteIcon extends StatefulWidget {
  final Color? color;

  const _ShakingDeleteIcon({this.color});

  @override
  State<_ShakingDeleteIcon> createState() => _ShakingDeleteIconState();
}

class _ShakingDeleteIconState extends State<_ShakingDeleteIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: -0.1,
      end: 0.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.rotate(angle: _animation.value, child: child);
      },
      child: Icon(Icons.close, size: 14, color: widget.color),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashWidth;
  final double dashGap;

  const _DashedRoundedBorderPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.radius = 12,
    this.dashWidth = 4,
    this.dashGap = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final inset = strokeWidth / 2;
    final rect =
        Offset(inset, inset) &
        Size(
          math.max(0, size.width - strokeWidth),
          math.max(0, size.height - strokeWidth),
        );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius ||
        dashWidth != oldDelegate.dashWidth ||
        dashGap != oldDelegate.dashGap;
  }
}
