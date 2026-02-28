import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../services/search_history_service.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_db_service.dart';
import '../services/font_loader_service.dart';
import 'entry_detail_page.dart';
import '../core/utils/toast_utils.dart';
import '../widgets/search_bar.dart';
import '../components/english_db_download_dialog.dart';
import '../components/global_scale_wrapper.dart';
import '../core/logger.dart';

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

  bool _isLoading = false;
  List<String> _searchHistory = [];
  bool _wasFocused = false;
  bool _isHistoryEditMode = false;

  // 分组设置
  String _selectedGroup = 'auto';
  List<String> _availableGroups = ['auto'];

  // 高级搜索选项
  bool _showAdvancedOptions = false;
  bool _useFuzzySearch = false;
  bool _useAuxiliarySearch = false;
  bool _exactMatch = false;

  // 搜索结果列表
  List<String> _searchResults = [];
  bool _showSearchResults = false;
  int _selectedResultIndex = -1;
  bool _isHandlingKeyboardEnter = false;
  Timer? _debounceTimer;
  int _prefixSearchToken = 0;
  bool _isSearchingWord = false;

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
    final languages = dicts.map((d) => d.sourceLanguage).toSet().toList()
      ..sort();

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

  /// 加载高级搜索设置
  Future<void> _loadAdvancedSettings() async {
    final settings = await _advancedSettingsService.loadSettings();
    setState(() {
      _useFuzzySearch = settings['useFuzzySearch'] ?? false;
      _useAuxiliarySearch = settings['useAuxiliarySearch'] ?? false;
      _exactMatch = settings['exactMatch'] ?? false;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 边打边搜 - 立即前置匹配，无防抖
  void _onSearchTextChanged(String text) {
    if (_isSearchingWord) return;

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      _prefixSearchToken++;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _selectedResultIndex = -1;
      });
      return;
    }

    final currentToken = ++_prefixSearchToken;
    () async {
      if (currentToken != _prefixSearchToken) return;

      List<String> results;
      if (_useFuzzySearch) {
        results = await _dbService.searchByWildcard(
          trimmedText,
          limit: 20,
          sourceLanguage: _selectedGroup,
        );
      } else {
        results = await _dbService.searchByPrefix(
          trimmedText,
          limit: 30,
          sourceLanguage: _selectedGroup,
        );
        results = _sortPrefixResults(trimmedText, results);
        results = results.take(8).toList();
      }

      if (!mounted || currentToken != _prefixSearchToken) return;

      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
      });
    }();
  }

  List<String> _sortPrefixResults(String prefix, List<String> results) {
    if (results.isEmpty) return results;

    final prefixLower = prefix.toLowerCase();
    final prefixWithSpace = '${prefixLower} ';

    int getPriority(String word) {
      final wordLower = word.toLowerCase();
      if (wordLower == prefixLower) return 0;
      if (wordLower.startsWith(prefixWithSpace)) return 1;
      if (wordLower.startsWith(prefixLower)) return 2;
      return 3;
    }

    results.sort((a, b) {
      final aPriority = getPriority(a);
      final bPriority = getPriority(b);

      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      final aLen = a.length;
      final bLen = b.length;
      if (aLen != bLen) return aLen.compareTo(bLen);

      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return results;
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
    final history = await _historyService.getSearchHistory();
    setState(() {
      _searchHistory = history;
    });
  }

  Future<void> _clearHistory() async {
    await _historyService.clearHistory();
    setState(() {
      _searchHistory = [];
    });
    if (mounted) {
      showToast(context, '历史记录已清除');
    }
  }

  Future<void> _onSearchFromHistory(String word) async {
    // 直接使用搜索框的搜索方法，这样会使用相同的搜索逻辑（包括辅助搜索）
    _searchController.text = word;
    await _searchWord();
  }

  Future<void> _searchWordWithOptions({
    required bool useFuzzySearch,
    required bool exactMatch,
  }) async {
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

    _isSearchingWord = true;
    _debounceTimer?.cancel();
    _prefixSearchToken++;

    setState(() {
      _isLoading = true;
      _showSearchResults = false;
      _searchResults = [];
      _selectedResultIndex = -1;
    });

    // 使用传入的高级选项进行查询，但不添加到历史记录
    final searchResult = await _dbService.getAllEntries(
      word,
      useFuzzySearch: useFuzzySearch,
      exactMatch: exactMatch,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

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

        // 如果返回结果要求选中文本
        if (navResult != null &&
            navResult is Map &&
            navResult['selectText'] == true) {
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
    } else {
      // 查询失败时刷新历史记录显示
      final history = await _historyService.getSearchHistory();
      setState(() {
        _searchHistory = history;
        _showSearchResults = false;
      });
      if (mounted) {
        showToast(context, '未找到单词: $word');
      }
    }

    setState(() {
      _isLoading = false;
      _isSearchingWord = false;
    });
  }

  Future<void> _searchWord() async {
    _debounceTimer?.cancel();
    _prefixSearchToken++;
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

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
            showToast(context, '下载完成，搜索 "$word" 以测试功能');
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

    await _historyService.addSearchRecord(
      word,
      useFuzzySearch: _useFuzzySearch,
      exactMatch: _exactMatch,
      group: _selectedGroup,
    );
    final history = await _historyService.getSearchHistory();

    final searchResult = await _dbService.getAllEntries(
      word,
      useFuzzySearch: _useFuzzySearch,
      exactMatch: _exactMatch,
      sourceLanguage: _selectedGroup,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

      // 更新历史记录
      setState(() {
        _searchHistory = history;
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

        // 如果返回结果要求选中文本
        if (navResult != null &&
            navResult is Map &&
            navResult['selectText'] == true) {
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
    } else {
      setState(() {
        _searchHistory = history;
        _showSearchResults = false;
      });

      if (mounted) {
        showToast(context, '未找到单词: $word');
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
                          if (value != 'en' && value != 'auto') {
                            _useAuxiliarySearch = false;
                            _exactMatch = false;
                          }
                        });
                        await _advancedSettingsService.setLastSelectedGroup(
                          value,
                        );
                      }
                    },
                    hintText: '输入单词',
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
                      IconButton(
                        icon: Icon(
                          Icons.tune,
                          size: 20,
                          color: _showAdvancedOptions
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _showAdvancedOptions = !_showAdvancedOptions;
                          });
                        },
                        tooltip: '高级选项',
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
                        onPressed: _isLoading ? null : _searchWord,
                        tooltip: '查询',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ],
                    onChanged: (text) {
                      setState(() {});
                      _onSearchTextChanged(text);
                    },
                    onSubmitted: (_) {
                      if (_isHandlingKeyboardEnter) {
                        _isHandlingKeyboardEnter = false;
                        return;
                      }
                      if (_selectedResultIndex >= 0 &&
                          _selectedResultIndex < _searchResults.length) {
                        _onSearchResultTap(
                          _searchResults[_selectedResultIndex],
                        );
                      } else if (_useFuzzySearch && _searchResults.isNotEmpty) {
                        _onSearchResultTap(_searchResults.first);
                      } else {
                        _searchWord();
                      }
                    },
                  ),
                ),
                // 高级搜索选项
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _showAdvancedOptions
                      ? Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '搜索选项',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                children: [
                                  // 通配符搜索 (LIKE)
                                  FilterChip(
                                    label: const Text('通配符搜索'),
                                    selected: _useFuzzySearch,
                                    onSelected: (selected) {
                                      setState(() {
                                        _useFuzzySearch = selected;
                                      });
                                      _advancedSettingsService
                                          .setUseFuzzySearch(selected);
                                    },
                                    avatar: Icon(
                                      Icons.pattern,
                                      size: 16,
                                      color: _useFuzzySearch
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  // 区分大小写 - 仅在英语或自动模式下显示
                                  if (_selectedGroup == 'en' ||
                                      _selectedGroup == 'auto')
                                    FilterChip(
                                      label: const Text('区分大小写'),
                                      selected: _exactMatch,
                                      onSelected: (selected) {
                                        setState(() {
                                          _exactMatch = selected;
                                        });
                                        _advancedSettingsService.setExactMatch(
                                          selected,
                                        );
                                      },
                                      avatar: Icon(
                                        Icons.text_fields,
                                        size: 16,
                                        color: _exactMatch
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // 提示文本
                              Text(
                                _getAdvancedSearchHint(),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
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
                            '搜索结果',
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
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.15)
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
                // 历史记录始终显示
                Expanded(
                  child: _searchHistory.isNotEmpty
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
                                '输入单词开始查询',
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

  /// 获取高级搜索提示文本
  String _getAdvancedSearchHint() {
    if (_useFuzzySearch) {
      return '通配符搜索：使用 % 作为通配符，如 %tion% 匹配包含tion的单词';
    } else if (_useAuxiliarySearch) {
      return '辅助搜索：使用辅助字段搜索（例如用读音搜索汉字），与精确搜索互斥';
    } else if (_exactMatch) {
      return '精确搜索：精确匹配headword字段，与辅助搜索互斥';
    }
    return '选择上方选项启用高级搜索功能。默认搜索会将输入词小写化并去除音调符号后匹配';
  }

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
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '历史记录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除'),
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
              itemCount: _searchHistory.length,
              itemBuilder: (context, index) {
                final word = _searchHistory[index];
                return _buildHistoryItem(word);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String word) {
    return InkWell(
      onTap: () {
        if (_isHistoryEditMode) {
          return;
        }
        _onSearchFromHistory(word);
      },
      onLongPress: () {
        setState(() {
          _isHistoryEditMode = true;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Builder(
        builder: (context) {
          return GestureDetector(
            onSecondaryTapUp: (details) {
              setState(() {
                _isHistoryEditMode = true;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      word,
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
                      onTap: () => _deleteHistoryItem(word),
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

  Future<void> _deleteHistoryItem(String word) async {
    await _historyService.removeSearchRecord(word);
    await _loadSearchHistory();
    if (mounted) {
      showToast(context, '已删除 "$word"');
    }
  }

  String _detectLanguage(String text) {
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    return 'en';
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
