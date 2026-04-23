import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../data/database_service.dart';
import '../data/word_bank_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../models/browse_list.dart';
import 'entry_tab_host_page.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/word_list_dialog.dart';
import '../core/utils/language_utils.dart';
import '../widgets/search_bar.dart';
import '../widgets/note_inline_editor.dart';
import '../services/note_service.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/dictionary_manager.dart';
import '../services/entry_event_bus.dart';
import '../services/font_loader_service.dart';
import '../components/global_scale_wrapper.dart';
import '../core/logger.dart';
import '../i18n/strings.g.dart';

const double _kNotesWideLayoutThreshold = 800.0;

enum SortMode {
  addTimeDesc,
  alphabetical,
  random;

  String label(BuildContext context) {
    switch (this) {
      case SortMode.addTimeDesc:
        return context.t.wordBank.sortAddTimeDesc;
      case SortMode.alphabetical:
        return context.t.wordBank.sortAlphabetical;
      case SortMode.random:
        return context.t.wordBank.sortRandom;
    }
  }
}

class WordBankPage extends StatefulWidget {
  const WordBankPage({super.key});

  @override
  State<WordBankPage> createState() => _WordBankPageState();
}

class _WordBankPageState extends State<WordBankPage> {
  final WordBankService _wordBankService = WordBankService();
  final DatabaseService _dictionaryService = DatabaseService();
  final AdvancedSearchSettingsService _advancedSettingsService =
      AdvancedSearchSettingsService();

  // 使用 ValueNotifier 优化频繁变化的状态，减少不必要的全局重建
  final ValueNotifier<bool> _isLoadingWordsNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isLoadingMoreNotifier = ValueNotifier(false);
  final ValueNotifier<SortMode> _currentSortModeNotifier = ValueNotifier(
    SortMode.addTimeDesc,
  );
  final ValueNotifier<String?> _selectedListNotifier = ValueNotifier(null);

  // Getters/setters 保持代码兼容性
  bool get _isLoadingWords => _isLoadingWordsNotifier.value;
  set _isLoadingWords(bool value) => _isLoadingWordsNotifier.value = value;
  bool get _isLoadingMore => _isLoadingMoreNotifier.value;
  set _isLoadingMore(bool value) => _isLoadingMoreNotifier.value = value;
  SortMode get _currentSortMode => _currentSortModeNotifier.value;
  set _currentSortMode(SortMode value) =>
      _currentSortModeNotifier.value = value;
  String? get _selectedList => _selectedListNotifier.value;
  set _selectedList(String? value) => _selectedListNotifier.value = value;

  // 数据
  List<String> _languages = [];
  String? _selectedLanguage; // null 表示"全部"
  Map<String, List<Map<String, dynamic>>> _wordsByList = {};
  List<Map<String, dynamic>> _allWords = [];
  Map<String, int> _languageWordCounts = {};

  bool _isInitialLoading = true;
  bool _wordsLoaded = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _wasFocused = false;
  StreamSubscription<DictionariesChangedEvent>? _dictsChangedSubscription;
  StreamSubscription<LanguageOrderChangedEvent>? _langOrderSubscription;

  // 分页相关
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMoreData = true;

  // 笔记相关
  Map<String, dynamic>? _selectedNote;
  // 使用文件级别常量 _kNotesWideLayoutThreshold

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
    _dictsChangedSubscription = EntryEventBus().dictionariesChanged.listen((_) {
      _reloadLanguages();
    });
    _langOrderSubscription = EntryEventBus().languageOrderChanged.listen((_) {
      _reloadLanguages();
    });
  }

  void _onFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      _wasFocused = false;
    }
  }

  @override
  void dispose() {
    _dictsChangedSubscription?.cancel();
    _langOrderSubscription?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    // 释放 ValueNotifier
    _isLoadingWordsNotifier.dispose();
    _isLoadingMoreNotifier.dispose();
    _currentSortModeNotifier.dispose();
    _selectedListNotifier.dispose();
    super.dispose();
  }

  Future<void> loadWordsIfNeeded() async {
    if (_wordsLoaded) return;
    _wordsLoaded = true;
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 获取所有支持的语言（已有单词的语言 + 已启用词典的源语言）
      final languages = await _getMergedLanguages();

      // 加载上次选择的语言
      String? selectedLanguage;
      if (_selectedLanguage == null) {
        final lastLanguage = await _wordBankService.getLastSelectedLanguage();
        if (lastLanguage != null && languages.contains(lastLanguage)) {
          selectedLanguage = lastLanguage;
        } else if (languages.isNotEmpty) {
          selectedLanguage = languages.first;
        }
      } else {
        selectedLanguage = _selectedLanguage;
      }

      if (mounted) {
        setState(() {
          _languages = languages;
          _selectedLanguage = selectedLanguage;
          _isInitialLoading = false;
        });
      }

      await _loadWords();
    } catch (e) {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  /// 获取合并后的语言列表（已有单词的语言 + 启用词典的源语言）
  Future<List<String>> _getMergedLanguages() async {
    final wordBankLangs = (await _wordBankService.getSupportedLanguages())
        .map(LanguageUtils.normalizeSourceLanguage)
        .where((l) => l.isNotEmpty)
        .toSet();
    final enabledDicts = await DictionaryManager()
        .getEnabledDictionariesMetadata();
    final dictLangs = enabledDicts
        .map((d) => LanguageUtils.normalizeSourceLanguage(d.sourceLanguage))
        .where((l) => l.isNotEmpty)
        .toSet();
    final merged = {...wordBankLangs, ...dictLangs}.toList();
    final savedOrder = await _advancedSettingsService.getLanguageOrder();
    final sorted = AdvancedSearchSettingsService.sortLanguagesByOrder(
      merged,
      savedOrder,
    );
    // 如果存在笔记，添加用户笔记选项
    final notesCount = await _wordBankService.getNotesCount();
    if (notesCount > 0) {
      sorted.add('NOTES');
    }
    return sorted;
  }

  /// 词典启用状态变化时，重新加载语言列表
  Future<void> _reloadLanguages() async {
    if (!mounted) return;
    final languages = await _getMergedLanguages();
    if (!mounted) return;
    setState(() {
      _languages = languages;
      // 如果当前选中的语言已不在列表中，重置为 null（全部）
      if (_selectedLanguage != null &&
          _selectedLanguage != 'NOTES' &&
          !languages.contains(_selectedLanguage)) {
        _selectedLanguage = null;
      }
    });
  }

  Future<void> _loadWords() async {
    final startTime = DateTime.now();
    Logger.d('_loadWords 开始', tag: 'WordBank');

    _isLoadingWords = true;

    // 重置分页状态
    _currentPage = 0;
    _hasMoreData = true;
    _allWords = [];
    _wordsByList = {};
    _languageWordCounts = {};
    _selectedNote = null;

    // 直接加载单词，不使用 _loadMoreWords 以避免触发分页加载状态
    try {
      final int offset = 0;

      if (_selectedLanguage == 'NOTES') {
        // 用户笔记模式
        Logger.d('加载用户笔记', tag: 'WordBank');
        await _loadNotes(offset: offset, limit: _pageSize);
      } else if (_selectedLanguage == null) {
        // 显示所有语言的单词
        Logger.d('加载所有语言的单词: ${_languages.join(", ")}', tag: 'WordBank');
        for (final lang in _languages) {
          if (lang == 'NOTES') continue;
          await _loadWordsForLanguage(
            lang,
            addToAll: true,
            offset: offset,
            limit: _pageSize,
          );
        }
      } else {
        // 只显示特定语言的单词
        Logger.d('加载特定语言的单词: $_selectedLanguage', tag: 'WordBank');
        await _loadWordsForLanguage(
          _selectedLanguage!,
          addToAll: false,
          offset: offset,
          limit: _pageSize,
        );
      }

      _applySort();

      // 检查是否还有更多数据
      if (_allWords.length < _pageSize) {
        _hasMoreData = false;
      } else {
        _currentPage = 1;
      }
    } catch (e) {
      Logger.e('_loadWords 错误: $e', tag: 'WordBank');
    }

    _isLoadingWords = false;

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadWords 完成: 耗时 ${duration.inMilliseconds}ms, 总条数: ${_allWords.length}',
      tag: 'WordBank',
    );
  }

  Future<void> _loadMoreWords() async {
    if (_isLoadingMore || !_hasMoreData) return;

    final startTime = DateTime.now();
    Logger.d('_loadMoreWords 开始, 页码: $_currentPage', tag: 'WordBank');

    _isLoadingMore = true;

    try {
      final int offset = _currentPage * _pageSize;

      if (_selectedLanguage == 'NOTES') {
        // 用户笔记模式
        Logger.d('加载更多用户笔记', tag: 'WordBank');
        await _loadNotes(offset: offset, limit: _pageSize);
      } else if (_selectedLanguage == null) {
        // 显示所有语言的单词
        Logger.d('加载所有语言的单词: ${_languages.join(", ")}', tag: 'WordBank');
        for (final lang in _languages) {
          if (lang == 'NOTES') continue;
          await _loadWordsForLanguage(
            lang,
            addToAll: true,
            offset: offset,
            limit: _pageSize,
          );
        }
      } else {
        // 只显示特定语言的单词
        Logger.d('加载特定语言的单词: $_selectedLanguage', tag: 'WordBank');
        await _loadWordsForLanguage(
          _selectedLanguage!,
          addToAll: true,
          offset: offset,
          limit: _pageSize,
        );
      }

      _applySort();

      // 检查是否还有更多数据
      // 如果加载后的总数小于 (currentPage + 1) * pageSize，说明最后一页没满，没有更多数据了
      if (_allWords.length < (offset + _pageSize)) {
        _hasMoreData = false;
      } else {
        _currentPage++;
      }
    } catch (e) {
      Logger.e('_loadMoreWords 错误: $e', tag: 'WordBank');
    } finally {
      _isLoadingMore = false;
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadMoreWords 完成: 耗时 ${duration.inMilliseconds}ms, 总条数: ${_allWords.length}',
      tag: 'WordBank',
    );
  }

  /// 获取排序参数
  ({String sortBy, bool ascending}) _getSortParams() {
    switch (_currentSortMode) {
      case SortMode.addTimeDesc:
        // 笔记模式按更新时间排序，单词模式按创建时间排序
        final sortBy = _selectedLanguage == 'NOTES' ? 'updated_at' : 'created_at';
        return (sortBy: sortBy, ascending: false);
      case SortMode.alphabetical:
        return (sortBy: 'word', ascending: true);
      case SortMode.random:
        return (sortBy: 'random', ascending: true);
    }
  }

  Future<void> _loadWordsForLanguage(
    String language, {
    required bool addToAll,
    int offset = 0,
    int? limit,
  }) async {
    final startTime = DateTime.now();
    Logger.d(
      '_loadWordsForLanguage 开始: $language, offset=$offset, limit=$limit',
      tag: 'WordBank',
    );

    List<Map<String, dynamic>> words;
    final sortParams = _getSortParams();
    if (_searchQuery.isNotEmpty) {
      // 搜索时暂不支持数据库排序，仍需内存排序
      Logger.d('执行搜索: $_searchQuery', tag: 'WordBank');
      words = await _wordBankService.searchWords(_searchQuery, language);
    } else {
      Logger.d(
        '从数据库加载单词: sortBy=${sortParams.sortBy}, ascending=${sortParams.ascending}, offset=$offset, limit=$limit',
        tag: 'WordBank',
      );
      words = await _wordBankService.getWordsByLanguage(
        language,
        sortBy: sortParams.sortBy,
        ascending: sortParams.ascending,
        offset: offset,
        limit: limit,
      );
    }
    Logger.d('加载到 ${words.length} 个单词', tag: 'WordBank');

    // 复制列表，避免只读列表问题
    // 为每个单词添加 language 字段，以便在 UI 中区分不同语言的单词
    words = words.map((w) {
      final wordWithLang = Map<String, dynamic>.from(w);
      wordWithLang['language'] = language;
      return wordWithLang;
    }).toList();

    Logger.d('获取语言单词总数', tag: 'WordBank');
    _languageWordCounts[language] = (await _wordBankService.getWordsByLanguage(
      language,
    )).length;
    Logger.d(
      '语言 $language 共有 ${_languageWordCounts[language]} 个单词',
      tag: 'WordBank',
    );

    if (addToAll) {
      _allWords.addAll(words);
    } else {
      _allWords = words;
    }

    // 按词表分组
    Logger.d('获取词表列表', tag: 'WordBank');
    final wordLists = await _wordBankService.getWordLists(language);
    Logger.d('获取到 ${wordLists.length} 个词表', tag: 'WordBank');

    for (final list in wordLists) {
      final listKey = '${language}_${list.name}';
      _wordsByList[listKey] = [];
    }

    // 将单词分配到各个词表
    for (final word in words) {
      for (final list in wordLists) {
        if (word[list.name] == 1) {
          final listKey = '${language}_${list.name}';
          _wordsByList[listKey]!.add(word);
        }
      }
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadWordsForLanguage 完成: $language, 耗时 ${duration.inMilliseconds}ms',
      tag: 'WordBank',
    );
  }

  /// 加载用户笔记
  Future<void> _loadNotes({int offset = 0, int? limit}) async {
    final startTime = DateTime.now();
    Logger.d('_loadNotes 开始, offset=$offset, limit=$limit', tag: 'WordBank');

    List<Map<String, dynamic>> notes;
    final sortParams = _getSortParams();
    if (_searchQuery.isNotEmpty) {
      Logger.d('搜索笔记: $_searchQuery', tag: 'WordBank');
      notes = await _wordBankService.searchNotes(_searchQuery);
    } else {
      Logger.d(
        '从数据库加载笔记: sortBy=${sortParams.sortBy}, ascending=${sortParams.ascending}, offset=$offset, limit=$limit',
        tag: 'WordBank',
      );
      notes = await _wordBankService.getAllNotes(
        sortBy: sortParams.sortBy,
        ascending: sortParams.ascending,
        offset: offset,
        limit: limit,
      );
    }
    Logger.d('加载到 ${notes.length} 个笔记', tag: 'WordBank');

    // 复制列表，为每个笔记添加 language 字段（用于 UI 区分）
    notes = notes.map((n) {
      final noteWithLang = Map<String, dynamic>.from(n);
      noteWithLang['language'] = n['language'] ?? 'unknown';
      return noteWithLang;
    }).toList();

    if (offset == 0) {
      _allWords = notes;
    } else {
      _allWords.addAll(notes);
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadNotes 完成: 耗时 ${duration.inMilliseconds}ms',
      tag: 'WordBank',
    );
  }

  /// 应用排序（仅在搜索模式下需要，因为搜索时数据库排序不支持）
  void _applySort() {
    // 非搜索模式下，数据已从数据库按正确顺序加载，无需内存排序
    if (_searchQuery.isEmpty) {
      return;
    }

    // 搜索模式下需要在内存中排序
    switch (_currentSortMode) {
      case SortMode.addTimeDesc:
        // 按添加/更新时间排序（最新的在前），时间相同则按字母排序
        final timeField = _selectedLanguage == 'NOTES' ? 'updated_at' : 'created_at';
        _wordsByList = _wordsByList.map((listName, words) {
          final sorted = List<Map<String, dynamic>>.from(words)
            ..sort((a, b) {
              final timeA = a[timeField] as int? ?? 0;
              final timeB = b[timeField] as int? ?? 0;
              final timeCompare = timeB.compareTo(timeA);
              if (timeCompare != 0) return timeCompare;
              // 时间相同则按字母排序
              final wordA = (a['word'] as String? ?? '').toLowerCase();
              final wordB = (b['word'] as String? ?? '').toLowerCase();
              return wordA.compareTo(wordB);
            });
          return MapEntry(listName, sorted);
        });
        _allWords.sort((a, b) {
          final timeA = a[timeField] as int? ?? 0;
          final timeB = b[timeField] as int? ?? 0;
          final timeCompare = timeB.compareTo(timeA);
          if (timeCompare != 0) return timeCompare;
          // 时间相同则按字母排序
          final wordA = (a['word'] as String? ?? '').toLowerCase();
          final wordB = (b['word'] as String? ?? '').toLowerCase();
          return wordA.compareTo(wordB);
        });
        break;
      case SortMode.alphabetical:
        _wordsByList = _wordsByList.map((listName, words) {
          final sorted = List<Map<String, dynamic>>.from(words)
            ..sort((a, b) {
              final wordA = (a['word'] as String? ?? '').toLowerCase();
              final wordB = (b['word'] as String? ?? '').toLowerCase();
              return wordA.compareTo(wordB);
            });
          return MapEntry(listName, sorted);
        });
        _allWords.sort((a, b) {
          final wordA = (a['word'] as String? ?? '').toLowerCase();
          final wordB = (b['word'] as String? ?? '').toLowerCase();
          return wordA.compareTo(wordB);
        });
        break;
      case SortMode.random:
        _wordsByList = _wordsByList.map((listName, words) {
          final shuffled = List<Map<String, dynamic>>.from(words)
            ..shuffle(Random());
          return MapEntry(listName, shuffled);
        });
        _allWords.shuffle(Random());
        break;
    }
  }

  /// 切换排序模式
  void _changeSortMode(SortMode mode) {
    _currentSortMode = mode;
    // 重新加载数据以应用新的排序（从数据库按新顺序获取）
    _loadWords();
  }

  Future<void> _removeWordFromList(String word, String listName) async {
    if (_selectedLanguage == null) {
      // 在"全部"模式下，需要找到单词所属的语言
      for (final lang in _languages) {
        final isInBank = await _wordBankService.isInWordBank(word, lang);
        if (isInBank) {
          await _wordBankService.removeWordFromList(word, lang, listName);
          break;
        }
      }
    } else {
      await _wordBankService.removeWordFromList(
        word,
        _selectedLanguage!,
        listName,
      );
    }
    await _loadWords();
  }

  /// 显示调整词表对话框
  Future<void> _showEditWordListsDialog(String word) async {
    // 在"全部"模式下，需要找到单词所属的语言
    String? targetLanguage = _selectedLanguage;
    if (targetLanguage == null) {
      for (final lang in _languages) {
        final isInBank = await _wordBankService.isInWordBank(word, lang);
        if (isInBank) {
          targetLanguage = lang;
          break;
        }
      }
    }

    if (targetLanguage == null) return;

    final selectedLists = await WordListDialog.show(
      context,
      language: targetLanguage,
      word: word,
      isNewWord: false,
      wordBankService: _wordBankService,
    );

    if (selectedLists == null) return;

    if (selectedLists.contains('__REMOVE__')) {
      await _wordBankService.removeWord(word, targetLanguage);
      await _loadWords();
      if (mounted) {
        showToast(context, context.t.wordBank.wordRemoved);
      }
      return;
    }

    final listChanges = <String, int>{};
    final currentLists = await _wordBankService.getWordLists(targetLanguage);
    for (final list in currentLists) {
      listChanges[list.name] = selectedLists.contains(list.name) ? 1 : 0;
    }
    await _wordBankService.updateWordLists(word, targetLanguage, listChanges);
    await _loadWords();
    if (mounted) {
      showToast(context, context.t.wordBank.wordListUpdated);
    }
  }

  Future<void> _showImportWordsDialogForLanguage(String language) async {
    String listName = '';
    String? selectedFilePath;
    List<String> previewWords = [];
    bool isImporting = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.file_download,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.wordBank.importToLanguage(
                        language: LanguageUtils.getDisplayName(
                          language,
                          context.t,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 词表名称输入
                    Text(
                      context.t.wordBank.listNameLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: context.t.wordBank.listNameHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        listName = value.trim();
                      },
                    ),
                    const SizedBox(height: 16),

                    // 文件选择按钮
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['txt', 'text', 'csv'],
                          allowMultiple: false,
                        );

                        if (result != null &&
                            result.files.single.path != null) {
                          final filePath = result.files.single.path!;
                          final file = File(filePath);
                          final content = await file.readAsString();

                          // 解析单词（支持逗号或回车分割）
                          final words = content
                              .split(RegExp(r'[,，\n\r]+'))
                              .map((w) => w.trim())
                              .where((w) => w.isNotEmpty)
                              .toList();

                          setState(() {
                            selectedFilePath = filePath;
                            // 显示前10个单词作为预览
                            previewWords = words.take(10).toList();
                          });
                        }
                      },
                      icon: const Icon(Icons.file_open),
                      label: Text(context.t.wordBank.pickFile),
                    ),
                    const SizedBox(height: 8),

                    // 预览区域
                    if (previewWords.isNotEmpty) ...[
                      Text(
                        context.t.wordBank.previewWords,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: previewWords
                              .map(
                                (word) => Chip(
                                  label: Text(word),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t.wordBank.previewCount(
                          count: previewWords.length,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t.common.cancel),
                ),
                ElevatedButton(
                  onPressed:
                      isImporting ||
                          listName.isEmpty ||
                          selectedFilePath == null
                      ? null
                      : () async {
                          setState(() {
                            isImporting = true;
                          });

                          try {
                            // 读取文件并解析所有单词
                            final file = File(selectedFilePath!);
                            final content = await file.readAsString();
                            final words = content
                                .split(RegExp(r'[,，\n\r]+'))
                                .map((w) => w.trim())
                                .where((w) => w.isNotEmpty)
                                .toList();

                            // 导入词表
                            final count = await _wordBankService
                                .importWordsToList(language, listName, words);

                            if (mounted) {
                              Navigator.pop(context, true);
                              showToast(
                                context,
                                context.t.wordBank.importSuccess(
                                  count: count,
                                  list: listName,
                                ),
                              );

                              // 刷新数据
                              await _loadData();
                            }
                          } catch (e) {
                            if (mounted) {
                              String errorMessage =
                                  context.t.wordBank.importFailed;
                              if (e.toString().contains('已存在')) {
                                errorMessage = context.t.wordBank
                                    .importListExists(list: listName);
                              } else if (e.toString().contains(
                                'No such file',
                              )) {
                                errorMessage =
                                    context.t.wordBank.importFileError;
                              }
                              showToast(context, errorMessage);
                            }
                          } finally {
                            setState(() {
                              isImporting = false;
                            });
                          }
                        },
                  child: isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.t.common.import),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      // 导入成功，刷新数据
      await _loadData();
    }
  }

  /// 显示管理词表对话框（编辑词表本身）
  Future<void> _showManageWordListsDialog() async {
    if (_selectedLanguage == null) return;

    final wordLists = await _wordBankService.getWordLists(_selectedLanguage!);

    List<EditableWordList> editableLists = wordLists
        .map((l) => EditableWordList(originalName: l.name, currentName: l.name))
        .toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.playlist_play,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.wordBank.editListsTitle(
                        language: LanguageUtils.getDisplayName(
                          _selectedLanguage!,
                          context.t,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SizedBox(
                width: 550,
                height: 450,
                child: Column(
                  children: [
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: editableLists.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            final item = editableLists.removeAt(oldIndex);
                            editableLists.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final list = editableLists[index];
                          return Card(
                            key: ValueKey(list.originalName),
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              title: Text(
                                list.currentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    tooltip: context.t.common.rename,
                                    onPressed: () async {
                                      final controller = TextEditingController(
                                        text: list.currentName,
                                      );
                                      final newName = await showDialog<String>(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: Text(
                                              context.t.wordBank.renameList,
                                            ),
                                            content: TextField(
                                              controller: controller,
                                              decoration: InputDecoration(
                                                labelText: context
                                                    .t
                                                    .wordBank
                                                    .listNameFieldLabel,
                                                hintText: context
                                                    .t
                                                    .wordBank
                                                    .listNameFieldHint,
                                              ),
                                              autofocus: true,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: Text(
                                                  context.t.common.cancel,
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  controller.text.trim(),
                                                ),
                                                child: Text(
                                                  context.t.common.ok,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (newName != null &&
                                          newName.isNotEmpty &&
                                          newName != list.currentName) {
                                        setState(() {
                                          editableLists[index].currentName =
                                              newName;
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    tooltip: context.t.common.delete,
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  context.t.wordBank.deleteList,
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              context.t.wordBank
                                                  .deleteListConfirm(
                                                    name: list.currentName,
                                                  ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: Text(
                                                  context.t.common.cancel,
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                                child: Text(
                                                  context.t.common.delete,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confirmed == true) {
                                        setState(() {
                                          editableLists.removeAt(index);
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context, false);
                        await _showImportWordsDialogForLanguage(
                          _selectedLanguage!,
                        );
                      },
                      icon: const Icon(Icons.file_download),
                      label: Text(context.t.wordBank.importListBtn),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(context.t.common.cancel),
                    ),
                    FilledButton(
                      onPressed: () async {
                        try {
                          final orderedNames = <String>[];

                          for (final originalList in wordLists) {
                            if (!editableLists.any(
                              (l) => l.originalName == originalList.name,
                            )) {
                              await _wordBankService.removeWordList(
                                _selectedLanguage!,
                                originalList.name,
                              );
                            }
                          }

                          for (final editable in editableLists) {
                            orderedNames.add(editable.currentName);

                            if (editable.originalName != editable.currentName) {
                              await _wordBankService.renameWordList(
                                _selectedLanguage!,
                                editable.originalName,
                                editable.currentName,
                              );
                            }
                          }

                          await _wordBankService.reorderWordLists(
                            _selectedLanguage!,
                            orderedNames,
                          );

                          if (mounted) {
                            Navigator.pop(context, true);
                            showToast(context, context.t.wordBank.listSaved);
                            await _loadData();
                          }
                        } catch (e) {
                          if (mounted) {
                            String errorMsg = context.t.wordBank.listOpFailed;
                            if (e.toString().contains('已存在')) {
                              errorMsg = context.t.wordBank.listNameExists;
                            }
                            showToast(context, errorMsg);
                          }
                        }
                      },
                      child: Text(context.t.common.save),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await _loadData();
    }
  }

  /// 构建词表筛选器
  Widget _buildListFilter() {
    if (_selectedLanguage == 'NOTES') {
      // 用户笔记模式不需要词表筛选栏
      return const SizedBox.shrink();
    }

    if (_selectedLanguage == null) {
      // "全部"模式下，显示所有语言的词表
      final List<Widget> chips = [];

      // "全部"选项
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            selected: _selectedList == null,
            label: Text(
              context.t.common.all,
              style: const TextStyle(fontSize: 13),
            ),
            onSelected: (selected) {
              setState(() {
                _selectedList = null;
              });
            },
          ),
        ),
      );

      for (final lang in _languages) {
        final wordLists = _wordBankService.getWordListsSync(lang);
        for (final list in wordLists) {
          final listKey = '${lang}_${list.name}';
          final isSelected = _selectedList == listKey;

          chips.add(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                label: Text(
                  '${LanguageUtils.getDisplayName(lang, context.t)}-${list.displayName}',
                  style: const TextStyle(fontSize: 13),
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedList = selected ? listKey : null;
                  });
                },
              ),
            ),
          );
        }
      }

      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            cacheExtent: 500, // 添加缓存优化
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            clipBehavior: Clip.none,
            children: chips,
          ),
        ),
      );
    }

    // 特定语言模式
    final wordLists = _wordBankService.getWordListsSync(_selectedLanguage!);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                cacheExtent: 500, // 添加缓存优化
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                clipBehavior: Clip.none,
                itemCount: wordLists.length + 1, // +1 for "全部"
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // "全部" 选项
                    final isSelected = _selectedList == null;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          context.t.common.all,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _selectedList = null;
                          });
                        },
                      ),
                    );
                  }

                  final list = wordLists[index - 1];
                  final isSelected = _selectedList == list.name;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(
                        list.displayName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedList = selected ? list.name : null;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 圆形按钮：轮廓线以内不透明，轮廓线向外渐变至透明，遮住底部词表 chip
          Tooltip(
            message: context.t.wordBank.manageLists,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 渐变光晕层：以按钮半径为不透明区，按钮轮廓线外侧 8px 线性渐变至透明
                  // 使用矩形 Container（不裁圆），让渐变自然覆盖按钮四周
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.5,
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context).colorScheme.surface,
                          Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.0),
                        ],
                        // stop 0.714 ≈ 20/28，对应直径 40 内切圆半径 20px 与外层 28px 之比
                        stops: const [0.0, 0.714, 1.0],
                      ),
                    ),
                  ),
                  // 圆形按钮本体（带 1px 轮廓线）
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.35),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _showManageWordListsDialog(),
                      hoverColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.6),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.playlist_add_check, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个单词列表项
  Widget _buildWordListItem({
    required Map<String, dynamic> wordData,
    required String language,
    required VoidCallback onRemove,
    List<String>? browseWords,
    int? browseIndex,
  }) {
    final word = wordData['word'] as String? ?? '';
    if (word.isEmpty) return const SizedBox.shrink();

    return InkWell(
      onTap: () => _searchWord(
        word,
        language,
        browseWords: browseWords,
        browseIndex: browseIndex,
      ),
      onLongPress: () => _showEditWordListsDialog(word),
      onSecondaryTap: () => _showEditWordListsDialog(word),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                word,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(child: _buildWordListTags(wordData, language)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单词列表
  List<Widget> _buildWordList() {
    final List<Widget> widgets = [];

    if (_selectedLanguage == null) {
      // "全部"模式：按语言分组显示
      for (final lang in _languages) {
        // 从 _allWords 中获取该语言的单词
        final words = _allWords.where((w) => w['language'] == lang).toList();

        // 根据选择的词表筛选
        final selectedList = _selectedList;
        final filteredWords = selectedList != null
            ? words.where((w) => w[selectedList.split('_').last] == 1).toList()
            : words;

        if (filteredWords.isEmpty) continue;

        // 添加语言标题
        widgets.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                LanguageUtils.getDisplayName(lang, context.t),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );

        // 单词列表
        widgets.add(
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final useGrid = constraints.crossAxisExtent >= 800;
              if (!useGrid) {
                return SliverList(
                  key: ValueKey(
                    '${lang}_${_selectedList}_${_currentSortMode.name}',
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final wordData = filteredWords[index];
                    final word = wordData['word'] as String? ?? '';
                    final browseWords = filteredWords
                        .map((w) => w['word'] as String? ?? '')
                        .where((w) => w.isNotEmpty)
                        .toList();

                    return _buildWordListItem(
                      wordData: wordData,
                      language: lang,
                      browseWords: browseWords,
                      browseIndex: index,
                      onRemove: () {
                        _wordBankService.removeWord(word, lang);
                        setState(() {
                          filteredWords.removeAt(index);
                        });
                      },
                    );
                  }, childCount: filteredWords.length),
                );
              }
              return SliverGrid(
                key: ValueKey(
                  '${lang}_${_selectedList}_${_currentSortMode.name}_grid',
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 56,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final wordData = filteredWords[index];
                  final word = wordData['word'] as String? ?? '';
                  final browseWords = filteredWords
                      .map((w) => w['word'] as String? ?? '')
                      .where((w) => w.isNotEmpty)
                      .toList();

                  return _buildWordListItem(
                    wordData: wordData,
                    language: lang,
                    browseWords: browseWords,
                    browseIndex: index,
                    onRemove: () {
                      _wordBankService.removeWord(word, lang);
                      setState(() {
                        filteredWords.removeAt(index);
                      });
                    },
                  );
                }, childCount: filteredWords.length),
              );
            },
          ),
        );
      }
    } else {
      // 特定语言模式
      // 从 _allWords 中获取该语言的单词
      final words = _allWords
          .where((w) => w['language'] == _selectedLanguage)
          .toList();

      // 根据选择的词表筛选
      final filteredWords = _selectedList != null
          ? words.where((w) => w[_selectedList] == 1).toList()
          : words;

      if (filteredWords.isEmpty) {
        widgets.add(
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(context.t.wordBank.noWordsFound),
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final useGrid = constraints.crossAxisExtent >= 800;
              if (!useGrid) {
                return SliverList(
                  key: ValueKey(
                    '${_selectedLanguage}_${_selectedList}_${_currentSortMode.name}',
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final wordData = filteredWords[index];
                    final word = wordData['word'] as String? ?? '';
                    final browseWords = filteredWords
                        .map((w) => w['word'] as String? ?? '')
                        .where((w) => w.isNotEmpty)
                        .toList();

                    return _buildWordListItem(
                      wordData: wordData,
                      language: _selectedLanguage!,
                      browseWords: browseWords,
                      browseIndex: index,
                      onRemove: () {
                        _wordBankService.removeWord(word, _selectedLanguage!);
                        setState(() {
                          filteredWords.removeAt(index);
                        });
                      },
                    );
                  }, childCount: filteredWords.length),
                );
              }
              return SliverGrid(
                key: ValueKey(
                  '${_selectedLanguage}_${_selectedList}_${_currentSortMode.name}_grid',
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 56,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final wordData = filteredWords[index];
                  final word = wordData['word'] as String? ?? '';
                  final browseWords = filteredWords
                      .map((w) => w['word'] as String? ?? '')
                      .where((w) => w.isNotEmpty)
                      .toList();

                  return _buildWordListItem(
                    wordData: wordData,
                    language: _selectedLanguage!,
                    browseWords: browseWords,
                    browseIndex: index,
                    onRemove: () {
                      _wordBankService.removeWord(word, _selectedLanguage!);
                      setState(() {
                        filteredWords.removeAt(index);
                      });
                    },
                  );
                }, childCount: filteredWords.length),
              );
            },
          ),
        );
      }
    }

    return widgets;
  }

  /// 构建单词所属词表标签
  Widget _buildWordListTags(Map<String, dynamic> wordData, String language) {
    final wordLists = _wordBankService.getWordListsSync(language);
    final List<String> belongingLists = [];

    for (final list in wordLists) {
      if (wordData[list.name] == 1) {
        belongingLists.add(list.displayName);
      }
    }

    if (belongingLists.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Text(
        belongingLists.join(', '),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.outline,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  /// 搜索单词
  /// [browseWords] 浏览列表单词（可选，用于在详情页前进/后退）
  /// [browseIndex] 当前单词在浏览列表中的索引
  Future<void> _searchWord(
    String word,
    String language, {
    List<String>? browseWords,
    int? browseIndex,
  }) async {
    // 获取当前语言的默认搜索选项
    final advancedSettingsService = AdvancedSearchSettingsService();
    final defaultOptions = advancedSettingsService.getDefaultOptionsForLanguage(
      language == 'auto' ? null : language,
    );

    // 查询词典，使用默认高级选项
    final searchResult = await _dictionaryService.getAllEntries(
      word,
      exactMatch: defaultOptions.exactMatch,
      sourceLanguage: language == 'auto' ? null : language,
    );

    if (mounted && searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );
      if (!mounted) return;
      EntryTabHostPage.open(
        context,
        entryGroup: entryGroup,
        initialWord: word,
        dictResults: searchResult.dictResults.isNotEmpty
            ? searchResult.dictResults
            : null,
        browseList: browseWords != null
            ? BrowseList(
                source: BrowseListSource.wordBank,
                words: browseWords,
                initialIndex: browseIndex ?? 0,
                language: language,
                listName: _selectedList,
              )
            : null,
      );
    } else if (mounted) {
      showToast(context, context.t.wordBank.wordNotFound(word: word));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (_languages.isEmpty) {
      return Scaffold(body: SafeArea(child: _buildEmptyState()));
    }

    final contentScale = FontLoaderService().getDictionaryContentScale();

    // 用户笔记模式使用独立的布局
    if (_selectedLanguage == 'NOTES') {
      return _buildNotesScaffold(contentScale);
    }

    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: 12,
                      ),
                      child: UnifiedSearchBarFactory.withLanguageSelector(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        selectedLanguage: _selectedLanguage ?? 'ALL',
                        availableLanguages: _languages
                            .where((l) => l != 'NOTES')
                            .toList(),
                        onLanguageSelected: (value) async {
                          setState(() {
                            _selectedLanguage = value == 'ALL' ? null : value;
                            _selectedList = null;
                          });
                          if (value == null || value == 'ALL') {
                            await _wordBankService.saveLastSelectedLanguage(
                              'ALL',
                            );
                          } else {
                            await _wordBankService.saveLastSelectedLanguage(
                              value,
                            );
                          }
                          await _loadWords();
                        },
                        extraLanguageOptions: {
                          if (_languages.contains('NOTES'))
                            'NOTES': context.t.wordBank.notes,
                        },
                        hintText: context.t.search.hintWordBank,
                        showAllOption: true,
                        onTap: () {
                          if (!_wasFocused &&
                              _searchController.text.isNotEmpty) {
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
                          PopupMenuButton<SortMode>(
                            tooltip: context.t.wordBank.sortTooltip,
                            offset: const Offset(0, 40),
                            icon: Icon(
                              Icons.swap_vert,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onSelected: (mode) => _changeSortMode(mode),
                            itemBuilder: (context) => SortMode.values
                                .map(
                                  (mode) => PopupMenuItem<SortMode>(
                                    value: mode,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _currentSortMode == mode
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(mode.label(context)),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            onPressed: () {
                              _loadWords();
                            },
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          _searchQuery = value;
                        },
                        onSubmitted: (value) {
                          _searchQuery = value;
                          _loadWords();
                        },
                      ),
                    ),
                    // 词表筛选器
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildListFilter(),
                    ),
                  ],
                ),
              ),
              // 可滚动的单词列表 - 使用 ValueListenableBuilder 实现局部重建
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isLoadingWordsNotifier,
                  builder: (context, isLoadingWords, _) {
                    if (isLoadingWords) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification scrollInfo) {
                        if (!_isLoadingMore &&
                            _hasMoreData &&
                            scrollInfo.metrics.pixels >=
                                scrollInfo.metrics.maxScrollExtent - 200) {
                          _loadMoreWords();
                        }
                        return false;
                      },
                      child: CustomScrollView(
                        cacheExtent: 500, // 添加缓存优化
                        slivers: [
                          // 单词列表
                          ..._buildWordList(),
                          // 加载更多指示器 - 使用 ValueListenableBuilder
                          ValueListenableBuilder<bool>(
                            valueListenable: _isLoadingMoreNotifier,
                            builder: (context, isLoadingMore, _) {
                              if (!isLoadingMore) {
                                return const SliverToBoxAdapter(
                                  child: SizedBox.shrink(),
                                );
                              }
                              return const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              );
                            },
                          ),
                          // 底部留白
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 用户笔记相关方法
  // ─────────────────────────────────────────────

  Widget _buildNotesScaffold(double contentScale) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideLayout = screenWidth >= _kNotesWideLayoutThreshold;

    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: 12,
                      ),
                      child: UnifiedSearchBarFactory.withLanguageSelector(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        selectedLanguage: 'NOTES',
                        availableLanguages: _languages
                            .where((l) => l != 'NOTES')
                            .toList(),
                        onLanguageSelected: (value) async {
                          setState(() {
                            _selectedLanguage =
                                value == 'ALL' ? null : value;
                            _selectedList = null;
                          });
                          if (value == null || value == 'ALL') {
                            await _wordBankService
                                .saveLastSelectedLanguage('ALL');
                          } else {
                            await _wordBankService
                                .saveLastSelectedLanguage(value);
                          }
                          await _loadWords();
                        },
                        extraLanguageOptions: {
                          if (_languages.contains('NOTES'))
                            'NOTES': context.t.wordBank.notes,
                        },
                        hintText: context.t.wordBank.noteKeyword,
                        showAllOption: true,
                        onTap: () {
                          if (!_wasFocused &&
                              _searchController.text.isNotEmpty) {
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
                          PopupMenuButton<SortMode>(
                            tooltip: context.t.wordBank.sortTooltip,
                            offset: const Offset(0, 40),
                            icon: Icon(
                              Icons.swap_vert,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onSelected: (mode) => _changeSortMode(mode),
                            itemBuilder: (context) => SortMode.values
                                .map(
                                  (mode) => PopupMenuItem<SortMode>(
                                    value: mode,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _currentSortMode == mode
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(mode.label(context)),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            onPressed: () {
                              _loadWords();
                            },
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          _searchQuery = value;
                        },
                        onSubmitted: (value) {
                          _searchQuery = value;
                          _loadWords();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildNotesBody(isWideLayout),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewNoteDialog,
        tooltip: context.t.wordBank.newNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNotesBody(bool isWideLayout) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoadingWordsNotifier,
      builder: (context, isLoadingWords, _) {
        if (isLoadingWords) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_allWords.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  context.t.wordBank.noNotes,
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        if (isWideLayout) {
          // 宽屏：左侧列表 + 右侧详情
          return Row(
            children: [
              SizedBox(
                width: 320,
                child: _buildNotesListView(),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withOpacity(0.5),
              ),
              Expanded(
                child: _selectedNote != null
                    ? _buildNoteDetailPanel(_selectedNote!)
                    : Center(
                        child: Text(
                          context.t.wordBank.editNote,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ],
          );
        }

        // 窄屏：只显示列表
        return _buildNotesListView();
      },
    );
  }

  Widget _buildNotesListView() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (!_isLoadingMore &&
            _hasMoreData &&
            scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200) {
          _loadMoreWords();
        }
        return false;
      },
      child: ListView.builder(
        cacheExtent: 500,
        itemCount: _allWords.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _allWords.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final note = _allWords[index];
          final isSelected = _selectedNote != null &&
              _selectedNote!['word'] == note['word'] &&
              _selectedNote!['language'] == note['language'];

          return _buildNoteListItem(note, isSelected);
        },
      ),
    );
  }

  Widget _buildNoteListItem(Map<String, dynamic> note, bool isSelected) {
    final word = note['word'] as String? ?? '';
    final language = note['language'] as String? ?? '';
    final content = note['content'] as String? ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideLayout = screenWidth >= _kNotesWideLayoutThreshold;
        if (isWideLayout) {
          setState(() {
            _selectedNote = Map<String, dynamic>.from(note);
          });
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _NoteDetailPage(
                word: word,
                language: language,
                initialContent: content,
                onDeleted: () {
                  setState(() {
                    _allWords.removeWhere(
                      (n) =>
                          n['word'] == word &&
                          n['language'] == language,
                    );
                  });
                },
                onSwitchToWide: () {
                  setState(() {
                    _selectedNote = Map<String, dynamic>.from(note);
                  });
                },
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                word,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              LanguageUtils.getDisplayName(language, context.t),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteDetailPanel(Map<String, dynamic> note) {
    final word = note['word'] as String? ?? '';
    final language = note['language'] as String? ?? '';
    final content = note['content'] as String? ?? '';

    return Column(
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  word,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                LanguageUtils.getDisplayName(language, context.t),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteNote(word, language),
                tooltip: context.t.common.delete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // 编辑器
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: NoteInlineEditor(
              word: word,
              language: language,
              initialContent: content,
              onSaved: () {
                // 刷新当前笔记内容
                _refreshNote(word, language);
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshNote(String word, String language) async {
    final noteService = NoteService();
    final note = await noteService.getNote(word, language);
    if (note != null && mounted) {
      setState(() {
        final index = _allWords.indexWhere(
          (n) =>
              n['word'].toString().toLowerCase() ==
                  word.toLowerCase() &&
              n['language'].toString().toLowerCase() ==
                  language.toLowerCase(),
        );
        if (index >= 0) {
          _allWords[index] = note.toDbMap();
          _allWords[index]['language'] = language;
        }
        if (_selectedNote != null) {
          _selectedNote = Map<String, dynamic>.from(_allWords[index]);
        }
      });
    }
  }

  Future<void> _deleteNote(String word, String language) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.common.delete),
        content: Text(
          context.t.wordBank.deleteNoteConfirm(word: word),
        ),
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

    if (confirmed == true) {
      final noteService = NoteService();
      await noteService.deleteNote(word, language);
      if (mounted) {
        showToast(context, context.t.wordBank.noteDeleted);
        setState(() {
          _allWords.removeWhere(
            (n) =>
                n['word'].toString().toLowerCase() ==
                    word.toLowerCase() &&
                n['language'].toString().toLowerCase() ==
                    language.toLowerCase(),
          );
          if (_selectedNote != null &&
              _selectedNote!['word'].toString().toLowerCase() ==
                  word.toLowerCase() &&
              _selectedNote!['language'].toString().toLowerCase() ==
                  language.toLowerCase()) {
            _selectedNote = null;
          }
        });
      }
    }
  }

  Future<void> _showNewNoteDialog() async {
    String word = '';
    String language = 'en';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(context.t.wordBank.newNote),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.t.wordBank.noteKeyword,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => word = value.trim(),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: language,
                      decoration: InputDecoration(
                        labelText: context.t.wordBank.noteLanguage,
                        border: const OutlineInputBorder(),
                      ),
                      items: _languages
                          .where((l) => l != 'NOTES')
                          .map(
                            (lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(
                                LanguageUtils.getDisplayName(
                                  lang,
                                  context.t,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => language = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t.common.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t.common.ok),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && word.isNotEmpty) {
      final noteService = NoteService();
      final existing = await noteService.getNote(word, language);
      if (existing != null && existing.isNotEmpty && mounted) {
        showToast(context, context.t.wordBank.wordListUpdated);
        return;
      }

      await noteService.saveNote(
        Note(word: word, language: language, content: ''),
      );

      if (mounted) {
        showToast(context, context.t.wordBank.noteSaved);
        await _loadWords();
        // 如果是宽屏，自动选中新笔记
        final screenWidth = MediaQuery.of(context).size.width;
        if (screenWidth >= _kNotesWideLayoutThreshold) {
          final newNote = _allWords.firstWhere(
            (n) =>
                n['word'].toString().toLowerCase() ==
                    word.toLowerCase() &&
                n['language'].toString().toLowerCase() ==
                    language.toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          if (newNote.isNotEmpty) {
            setState(() {
              _selectedNote = Map<String, dynamic>.from(newNote);
            });
          }
        }
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            context.t.wordBank.empty,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t.wordBank.emptyHint,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// 窄屏笔记详情页
class _NoteDetailPage extends StatefulWidget {
  final String word;
  final String language;
  final String? initialContent;
  final VoidCallback? onDeleted;
  final VoidCallback? onSwitchToWide;

  const _NoteDetailPage({
    required this.word,
    required this.language,
    this.initialContent,
    this.onDeleted,
    this.onSwitchToWide,
  });

  @override
  State<_NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<_NoteDetailPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    // 如果从窄屏切换到宽屏，自动返回并选中当前笔记
    if (screenWidth >= _kNotesWideLayoutThreshold) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onSwitchToWide?.call();
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.word),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              LanguageUtils.getDisplayName(widget.language, context.t),
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.outline,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteNote,
            tooltip: context.t.common.delete,
          ),
        ],
      ),
      body: NoteInlineEditor(
        word: widget.word,
        language: widget.language,
        initialContent: widget.initialContent,
      ),
    );
  }

  Future<void> _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.common.delete),
        content: Text(
          context.t.wordBank.deleteNoteConfirm(word: widget.word),
        ),
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

    if (confirmed == true) {
      final noteService = NoteService();
      await noteService.deleteNote(widget.word, widget.language);
      if (mounted) {
        showToast(context, context.t.wordBank.noteDeleted);
        widget.onDeleted?.call();
        Navigator.pop(context);
      }
    }
  }
}

// 使用一个包装类来追踪原始名称
class EditableWordList {
  final String originalName;
  String currentName;

  EditableWordList({required this.originalName, required this.currentName});

  WordListInfo toInfo() => WordListInfo(name: currentName);
}
