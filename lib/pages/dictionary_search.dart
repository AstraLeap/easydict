import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/word_bank_service.dart';
import '../services/search_history_service.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_db_service.dart';
import '../services/font_loader_service.dart';
import '../services/entry_event_bus.dart';
import '../services/daily_word_service.dart';
import 'entry_detail_page.dart';
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

  bool _isLoading = false;
  List<SearchRecord> _searchRecords = [];
  bool _wasFocused = false;
  bool _isHistoryEditMode = false;

  // 分组设置
  String _selectedGroup = 'auto';
  List<String> _availableGroups = ['auto'];

  // 高级搜索选项
  bool _usePhoneticSearch = false;

  // 按语言独立存储的精确匹配设置
  Map<String, bool> _exactMatchByLanguage = {};

  // 获取当前语言的精确匹配设置
  bool get _exactMatch {
    if (_selectedGroup == 'auto') return false;
    return _exactMatchByLanguage[_selectedGroup] ?? false;
  }

  // 设置当前语言的精确匹配设置
  set _exactMatch(bool value) {
    if (_selectedGroup != 'auto') {
      _exactMatchByLanguage[_selectedGroup] = value;
    }
  }

  // 表意文字的精确匹配（简繁区分）也使用同一套逻辑
  bool get _biaoyiExactMatch => _exactMatch;
  set _biaoyiExactMatch(bool value) {
    _exactMatch = value;
  }

  // 每日单词
  List<String> _dailyWords = [];
  List<String> _selectedLanguages = [];
  Map<String, List<String>> _selectedLists = {};
  Map<String, List<WordListInfo>> _availableWordListsMap = {};
  List<String> _availableWordBankLanguages = [];
  bool _isLoadingDailyWords = false;
  final Map<String, String> _wordLanguageCache = {};

  // 搜索结果列表
  List<String> _searchResults = [];
  bool _showSearchResults = false;
  int _selectedResultIndex = -1;
  bool _isHandlingKeyboardEnter = false;
  Timer? _debounceTimer;
  int _prefixSearchToken = 0;
  bool _isSearchingWord = false;
  StreamSubscription<SettingsSyncedEvent>? _syncSubscription;
  StreamSubscription<DictionariesChangedEvent>? _dictsChangedSubscription;
  StreamSubscription<LanguageOrderChangedEvent>? _langOrderSubscription;
  StreamSubscription<SearchHistoryChangedEvent>? _historyChangedSubscription;

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    Logger.i('DictionarySearchPage initState', tag: 'DictionarySearch');
    _searchFocusNode.addListener(_onFocusChange);
    // 拦截方向键，阻止 TextField 默认的光标移动行为（上/下移到行首/尾）
    _searchFocusNode.onKey = (FocusNode node, RawKeyEvent event) {
      if (event is RawKeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown)) {
        // 直接在此处处理搜索结果导航（不调用 _handleKeyEvent 避免 hasFocus 防重复问题）
        if (_showSearchResults && _searchResults.isNotEmpty) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              if (_selectedResultIndex < _searchResults.length - 1) {
                _selectedResultIndex++;
              } else {
                _selectedResultIndex = 0;
              }
            });
          } else {
            setState(() {
              if (_selectedResultIndex > 0) {
                _selectedResultIndex--;
              } else {
                _selectedResultIndex = _searchResults.length - 1;
              }
            });
          }
        }
        return KeyEventResult.handled; // 始终吸收，防止 TextField 移动光标
      }
      return KeyEventResult.ignored;
    };
    _initData();
    _syncSubscription = EntryEventBus().settingsSynced.listen((event) {
      if (event.includesHistory) _loadSearchHistory();
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
      _loadSearchHistory();
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
    Logger.i(
      'DictionarySearchPage didChangeDependencies',
      tag: 'DictionarySearch',
    );
    FontLoaderService().reloadDictionaryContentScale();
  }

  Future<void> _initData() async {
    Logger.i('DictionarySearchPage _initData 开始', tag: 'DictionarySearch');
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

    setState(() {
      _isLoadingDailyWords = true;
    });

    final words = await _dailyWordService.getDailyWords();
    _wordLanguageCache.clear();

    if (mounted) {
      setState(() {
        _dailyWords = words;
        _isLoadingDailyWords = false;
      });
    }
  }

  /// 刷新每日单词
  Future<void> _refreshDailyWords() async {
    if (_selectedLanguages.isEmpty) return;

    setState(() {
      _isLoadingDailyWords = true;
    });

    final words = await _dailyWordService.refreshDailyWords();
    _wordLanguageCache.clear();

    if (mounted) {
      setState(() {
        _dailyWords = words;
        _isLoadingDailyWords = false;
      });
    }
  }

  /// 从每日单词查词
  Future<void> _searchFromDailyWord(String word) async {
    if (_selectedLanguages.isEmpty) return;

    String? language = _wordLanguageCache[word];
    if (language == null) {
      language = await _dailyWordService.getWordLanguage(word);
      _wordLanguageCache[word] = language;
    }

    setState(() {
      _isLoading = true;
      _showSearchResults = false;
      _searchResults = [];
      _selectedResultIndex = -1;
    });

    final searchResult = await _dbService.getAllEntries(
      word,
      exactMatch: false,
      usePhoneticSearch: false,
      sourceLanguage: language,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

      await _historyService.addSearchRecord(
        word,
        exactMatch: false,
        biaoyiExactMatch: false,
        usePhoneticSearch: false,
        group: language,
      );

      final records = await _historyService.getSearchRecords();
      setState(() {
        _searchRecords = records;
      });

      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => EntryDetailPage(
              entryGroup: entryGroup,
              initialWord: word,
              searchRelations: searchResult.hasRelations
                  ? searchResult.relations
                  : null,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        showToast(context, context.t.search.noResult(word: word));
      }
    }

    setState(() {
      _isLoading = false;
    });
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
    _debounceTimer?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 判断当前语言是否需要至少输入2个字符才启动边打边搜（字母文字）。
  /// auto 模式且含表意文字单字符时不需要；其余字母文字需要 2 个字符。
  bool _prefixSearchNeedsMinTwoChars(String text) {
    if (_selectedGroup == 'auto') {
      // 含汉字/假名/谚文时，1 个字符就足够触发搜索
      if (DatabaseService.containsIdeographic(text)) return false;
      return true;
    }
    const logographic = {'zh', 'ja', 'ko'};
    return !logographic.contains(_selectedGroup);
  }

  /// 边打边搜 - 立即前置匹配，无防抖
  void _onSearchTextChanged(String text) {
    Logger.d(
      '_onSearchTextChanged called: text=|$text| _isSearchingWord=$_isSearchingWord',
      tag: 'PrefixSearch',
    );

    if (_isSearchingWord) {
      Logger.d('_onSearchTextChanged: 跳过，正在搜索中', tag: 'PrefixSearch');
      return;
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      Logger.d('_onSearchTextChanged: 空文本，清空结果', tag: 'PrefixSearch');
      _prefixSearchToken++;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _selectedResultIndex = -1;
      });
      return;
    }

    // 字母文字 / auto 模式：至少2个字符才触发（表意文字单字符除外）
    final needsMinTwo = _prefixSearchNeedsMinTwoChars(trimmedText);
    Logger.d(
      '_onSearchTextChanged: trimmedText=|$trimmedText| length=${trimmedText.length} needsMinTwo=$needsMinTwo selectedGroup=$_selectedGroup',
      tag: 'PrefixSearch',
    );

    if (needsMinTwo && trimmedText.length < 2) {
      Logger.d('_onSearchTextChanged: 字母文字需要至少2个字符，跳过', tag: 'PrefixSearch');
      _prefixSearchToken++;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _selectedResultIndex = -1;
      });
      return;
    }

    final currentToken = ++_prefixSearchToken;
    Logger.i(
      '_onSearchTextChanged → getPreSearchCandidates text=|$text| lang=$_selectedGroup exactMatch=$_exactMatch token=$currentToken',
      tag: 'PrefixSearch',
    );

    () async {
      if (currentToken != _prefixSearchToken) {
        Logger.d(
          '_onSearchTextChanged: token不匹配，跳过 (current=$currentToken, latest=$_prefixSearchToken)',
          tag: 'PrefixSearch',
        );
        return;
      }

      // 传入原始文本（含大小写、尾部空格），供 Dart 层 startsWith 比较；
      // DatabaseService 内部会 trim 后再用于 SQL 查询。
      final stopwatch = Stopwatch()..start();
      final results = await _dbService.getPreSearchCandidates(
        text,
        sourceLanguage: _selectedGroup,
        exactMatch: _exactMatch,
        usePhoneticSearch: _usePhoneticSearch,
        biaoyiExactMatch: _biaoyiExactMatch,
        limit: 8,
      );
      stopwatch.stop();

      Logger.i(
        '_onSearchTextChanged ← getPreSearchCandidates 返回 ${results.length} 条结果，耗时 ${stopwatch.elapsedMilliseconds}ms: $results',
        tag: 'PrefixSearch',
      );

      if (!mounted || currentToken != _prefixSearchToken) {
        Logger.d(
          '_onSearchTextChanged: 组件已卸载或token不匹配，跳过更新UI',
          tag: 'PrefixSearch',
        );
        return;
      }

      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
        _selectedResultIndex = -1;
      });

      Logger.d(
        '_onSearchTextChanged: UI已更新，showSearchResults=$_showSearchResults',
        tag: 'PrefixSearch',
      );
    }();
  }

  /// 点击搜索结果项
  Future<void> _onSearchResultTap(String word) async {
    _searchController.text = word;
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
      _selectedResultIndex = -1;
    });
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
        setState(() {
          if (_selectedResultIndex < _searchResults.length - 1) {
            _selectedResultIndex++;
          } else {
            _selectedResultIndex = 0;
          }
        });
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_searchFocusNode.hasFocus) return;
        setState(() {
          if (_selectedResultIndex > 0) {
            _selectedResultIndex--;
          } else {
            _selectedResultIndex = _searchResults.length - 1;
          }
        });
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

  Future<void> _clearHistory() async {
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
    setState(() {
      _exactMatch = record.exactMatch;
      _biaoyiExactMatch = record.biaoyiExactMatch;
      _usePhoneticSearch = record.usePhoneticSearch;
      if (record.group != null) {
        _selectedGroup = record.group!;
      }
    });
    await _searchWord();
  }

  Future<void> _searchWord() async {
    _debounceTimer?.cancel();
    _prefixSearchToken++;
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

    // LIKE/GLOB 通配符模式下禁止直接查词，必须从候选词列表点击进入
    if (_isWildcardMode(word)) {
      if (mounted) {
        showToast(context, context.t.search.wildcardNoEntry);
      }
      return;
    }

    _isSearchingWord = true;

    Logger.d('用户开始查词: $word', tag: 'DictionarySearch');

    // 首次查英语词且 en.db 不存在时，直接弹出下载推荐（不等待查询结果）
    if (_detectLanguage(word) == 'en') {
      final dbExists = await EnglishDbService().dbExists();
      if (!dbExists) {
        final shouldShow = await EnglishDbService().shouldShowDownloadDialog();
        if (shouldShow && mounted) {
          final result = await EnglishDbDownloadDialog.show(context);
          if (result == EnglishDbDownloadResult.downloaded && mounted) {
            showToast(context, context.t.search.dbDownloaded(word: word));
          }
          // 下载弹窗关闭后继续执行查词
        }
      }
    }

    setState(() {
      _isLoading = true;
      _showSearchResults = false;
      _searchResults = [];
      _selectedResultIndex = -1;
    });

    // 总是更新排序位置，保留已记录的语言；仅在搜索成功后再更新语言
    await _historyService.addSearchRecord(
      word,
      exactMatch: _exactMatch,
      biaoyiExactMatch: _biaoyiExactMatch,
      usePhoneticSearch: _usePhoneticSearch,
    );

    final searchResult = await _dbService.getAllEntries(
      word,
      exactMatch: _exactMatch,
      usePhoneticSearch: _usePhoneticSearch,
      sourceLanguage: _selectedGroup,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

      // 搜索成功时才记录当前语言及所有高级选项
      await _historyService.addSearchRecord(
        word,
        exactMatch: _exactMatch,
        biaoyiExactMatch: _biaoyiExactMatch,
        usePhoneticSearch: _usePhoneticSearch,
        group: _selectedGroup,
      );
      // 更新历史记录
      final records = await _historyService.getSearchRecords();
      setState(() {
        _searchRecords = records;
      });

      // 跳转到详情页面
      if (mounted) {
        final navResult = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => EntryDetailPage(
              entryGroup: entryGroup,
              initialWord: word,
              searchRelations: searchResult.hasRelations
                  ? searchResult.relations
                  : null,
            ),
          ),
        );

        // 处理返回结果
        if (navResult != null) {
          // 如果返回的是字符串，表示新的搜索词
          if (navResult is String) {
            // 设置搜索词并执行搜索
            _searchController.text = navResult;
            await _searchWord();
          }
          // 如果返回结果要求选中文本
          else if (navResult is Map && navResult['selectText'] == true) {
            // 延迟执行，确保页面已完全返回
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                // 先请求焦点
                _searchFocusNode.requestFocus();
                // 然后选中文本
                _searchController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _searchController.text.length,
                );
              }
            });
          }
        }
      }
    } else {
      final records = await _historyService.getSearchRecords();
      setState(() {
        _searchRecords = records;
        _showSearchResults = false;
      });

      if (mounted) {
        showToast(context, context.t.search.noResult(word: word));
      }
    }

    setState(() {
      _isLoading = false;
      _isSearchingWord = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Logger.i(
      'DictionarySearchPage build, _isInitializing: $_isInitializing',
      tag: 'DictionarySearch',
    );
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
                          // 表意文字（汉字、日文、韩文）：清除不适用的表音选项
                          if (_isLogographicLang(value)) {
                            _exactMatch = false;
                            _usePhoneticSearch = false;
                          } else {
                            // 表音文字：清除不适用的简繁区分和读音搜索选项
                            _biaoyiExactMatch = false;
                            _usePhoneticSearch = false;
                          }
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
                      // 精确匹配状态图标按钮，在 auto 模式下隐藏
                      if (_selectedGroup != 'auto')
                        IconButton(
                          icon: Icon(
                            _exactMatch
                                ? Icons.filter_alt
                                : Icons.filter_alt_off,
                            size: 20,
                            color: _exactMatch
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                          color: _isLoading
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withOpacity(0.38)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: _isLoading
                            ? null
                            : () {
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
                // 搜索结果列表
                if (_showSearchResults && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text(
                            _usePhoneticSearch
                                ? context.t.search.phoneticCandidates
                                : context.t.search.searchResults,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final word = _searchResults[index];
                            final isSelected = index == _selectedResultIndex;
                            return Container(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.15)
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
                        ),
                      ],
                    ),
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

  /// 构建每日单词区域
  Widget _buildDailyWordsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  context.t.search.dailyWords,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedLanguages.isNotEmpty) ...[
                  IconButton(
                    onPressed: _isLoadingDailyWords ? null : _refreshDailyWords,
                    icon: _isLoadingDailyWords
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t.search.dailyWordsRefresh,
                  ),
                  IconButton(
                    onPressed: () => _showDailyWordsSettingsDialog(),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t.search.dailyWordsSettings,
                  ),
                ],
              ],
            ),
          ),
          if (_selectedLanguages.isEmpty)
            _buildDailyWordsEmptyState()
          else if (_dailyWords.isEmpty && !_isLoadingDailyWords)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                context.t.search.dailyWordsNoWords,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: _dailyWords.map((word) {
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建每日单词空状态（未选择语言）
  Widget _buildDailyWordsEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
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
      ),
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
                onPressed: selectedLanguages.isEmpty
                    ? null
                    : () async {
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
      case 'ja':
        return names.ja;
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
      lang == 'zh' || lang == 'ja' || lang == 'ko';

  Widget _buildHistoryView() {
    return GestureDetector(
      onTap: () {
        if (_isHistoryEditMode) {
          setState(() {
            _isHistoryEditMode = false;
          });
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
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 10,
                mainAxisExtent: 40,
              ),
              itemCount: _searchRecords.length,
              itemBuilder: (context, index) {
                final record = _searchRecords[index];
                return _buildHistoryItem(record);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(SearchRecord record) {
    return InkWell(
      onTap: () {
        if (_isHistoryEditMode) {
          return;
        }
        _onSearchFromHistory(record);
      },
      onLongPress: () {
        setState(() {
          _isHistoryEditMode = !_isHistoryEditMode;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Builder(
        builder: (context) {
          return GestureDetector(
            onSecondaryTapUp: (details) {
              setState(() {
                _isHistoryEditMode = !_isHistoryEditMode;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
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
                  if (_isHistoryEditMode)
                    GestureDetector(
                      onTap: () => _deleteHistoryItem(record),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _ShakingDeleteIcon(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';
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
