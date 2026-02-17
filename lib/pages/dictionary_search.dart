import 'dart:async';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'models/dictionary_entry_group.dart';
import 'services/search_history_service.dart';
import 'services/advanced_search_settings_service.dart';
import 'services/dictionary_manager.dart';
import 'services/english_db_service.dart';
import 'services/font_loader_service.dart';
import 'pages/entry_detail_page.dart';
import 'utils/toast_utils.dart';
import 'utils/language_utils.dart';
import 'utils/language_dropdown.dart';
import 'utils/dpi_utils.dart';
import 'widgets/search_bar.dart';
import 'components/english_db_download_dialog.dart';
import 'components/scale_layout_wrapper.dart';
import 'components/global_scale_wrapper.dart';
import 'logger.dart';

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
  Timer? _debounceTimer;

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FontLoaderService().reloadDictionaryContentScale();
  }

  Future<void> _initData() async {
    await Future.wait([
      _loadSearchHistory(),
      _loadAdvancedSettings(),
      _loadDictionaryGroups(),
    ]);

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 边打边搜 - 防抖搜索
  void _onSearchTextChanged(String text) {
    // 取消之前的定时器
    _debounceTimer?.cancel();

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    // 如果启用了模糊搜索，不进行边打边搜
    if (_useFuzzySearch) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    // 设置新的定时器，延迟300ms执行搜索
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await _dbService.searchByPrefix(trimmedText, limit: 10);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showSearchResults = results.isNotEmpty;
        });
      }
    });
  }

  /// 点击搜索结果项
  Future<void> _onSearchResultTap(String word) async {
    _searchController.text = word;
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
    });
    await _searchWord();
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
    String? originalWord,
  }) async {
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

    setState(() {
      _isLoading = true;
      // 历史记录始终显示，不隐藏
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

    setState(() => _isLoading = false);
  }

  Future<void> _searchWord() async {
    final word = _searchController.text.trim();
    if (word.isEmpty) return;

    Logger.d('用户开始查词: $word', tag: 'DictionarySearch');

    setState(() {
      _isLoading = true;
      // 历史记录始终显示，不隐藏
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

        await _maybeShowEnglishDbDownloadDialog(word);
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final contentScale = FontLoaderService().getDictionaryContentScale();

    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: UnifiedSearchBar.withLanguageSelector(
                controller: _searchController,
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
                    await _advancedSettingsService.setLastSelectedGroup(value);
                  }
                },
                hintText: '输入单词',
                extraSuffixIcons: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: DpiUtils.scaleIconSize(context, 18),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.tune,
                      size: 18,
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
                  ),
                ],
                onChanged: (text) {
                  setState(() {});
                  _onSearchTextChanged(text);
                },
                onSubmitted: (_) {
                  if (_exactMatch) {
                    _searchWord();
                  } else {
                    if (_showSearchResults && _searchResults.isNotEmpty) {
                      _onSearchResultTap(_searchResults.first);
                    } else {
                      _searchWord();
                    }
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
                                  _advancedSettingsService.setUseFuzzySearch(
                                    selected,
                                  );
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
                                  color: Theme.of(context).colorScheme.outline,
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
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final word = _searchResults[index];
                        final isFirst = index == 0;
                        return ListTile(
                          dense: true,
                          leading: isFirst
                              ? Icon(
                                  Icons.keyboard_return,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : const SizedBox(width: 24),
                          title: Text(word),
                          subtitle: isFirst
                              ? Text(
                                  '按回车进入',
                                  style: TextStyle(
                                    fontSize: DpiUtils.scaleFontSize(
                                      context,
                                      12,
                                    ),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                )
                              : null,
                          onTap: () => _onSearchResultTap(word),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: 12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '历史记录',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: Icon(
                  Icons.delete_outline,
                  size: DpiUtils.scaleIconSize(context, 18),
                ),
                label: const Text('清除'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _searchHistory.length,
            itemBuilder: (context, index) {
              final word = _searchHistory[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(word),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: DpiUtils.scaleIconSize(context, 18),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      await _historyService.removeSearchRecord(word);
                      await _loadSearchHistory();
                    },
                  ),
                  onTap: () => _onSearchFromHistory(word),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _detectLanguage(String text) {
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return 'zh';
    if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return 'ko';
    return 'en';
  }

  Future<void> _maybeShowEnglishDbDownloadDialog(String word) async {
    if (_detectLanguage(word) != 'en') return;

    final dbExists = await EnglishDbService().dbExists();
    if (dbExists) return;

    final shouldShow = await EnglishDbService().shouldShowDownloadDialog();
    if (!shouldShow) return;

    final result = await EnglishDbDownloadDialog.show(context);
    if (result == EnglishDbDownloadResult.downloaded) {
      if (mounted) {
        showToast(context, '下载完成，搜索 "$word" 以测试功能');
      }
    }
  }
}
