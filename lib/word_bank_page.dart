import 'dart:math';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'word_bank_service.dart';
import 'models/dictionary_entry_group.dart';
import 'services/search_history_service.dart';
import 'pages/entry_detail_page.dart';
import 'utils/toast_utils.dart';

enum SortMode {
  addTimeDesc('添加顺序（新到旧）'),
  alphabetical('字母顺序'),
  random('随机排序');

  final String label;
  const SortMode(this.label);
}

class WordBankPage extends StatefulWidget {
  const WordBankPage({super.key});

  @override
  State<WordBankPage> createState() => _WordBankPageState();
}

class _WordBankPageState extends State<WordBankPage> {
  final WordBankService _wordBankService = WordBankService();
  final DatabaseService _dictionaryService = DatabaseService();
  final SearchHistoryService _historyService = SearchHistoryService();
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _originalFavorites = []; // 原始顺序
  bool _isLoading = true;
  String _searchQuery = '';
  SortMode _currentSortMode = SortMode.addTimeDesc;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    try {
      if (_searchQuery.isEmpty) {
        _originalFavorites = await _wordBankService.getAllFavorites();
      } else {
        _originalFavorites = await _wordBankService.searchFavorites(
          _searchQuery,
        );
      }
      _applySort();
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
    setState(() => _isLoading = false);
  }

  /// 应用排序
  void _applySort() {
    _favorites = List<Map<String, dynamic>>.from(_originalFavorites);
    switch (_currentSortMode) {
      case SortMode.addTimeDesc:
        // 默认就是添加顺序（数据库返回的顺序）
        break;
      case SortMode.alphabetical:
        _favorites.sort((a, b) {
          final wordA = (a['headword'] as String? ?? '').toLowerCase();
          final wordB = (b['headword'] as String? ?? '').toLowerCase();
          return wordA.compareTo(wordB);
        });
        break;
      case SortMode.random:
        _favorites.shuffle(Random());
        break;
    }
  }

  /// 切换排序模式
  void _changeSortMode(SortMode mode) {
    setState(() {
      _currentSortMode = mode;
      _applySort();
    });
  }

  Future<void> _removeFavorite(int id) async {
    await _wordBankService.removeFavoriteById(id);
    _loadFavorites();
  }

  // 使用与主界面相同的查词逻辑
  Future<void> _searchWord(String word) async {
    if (word.isEmpty) return;

    final result = await _dictionaryService.getAllEntries(word);

    if (result.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(result.entries);

      // 添加到搜索历史
      await _historyService.addSearchRecord(word);

      // 跳转到详情页面（与主界面相同）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本'),
        actions: [
          if (_favorites.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '更多选项',
              onSelected: (value) async {
                switch (value) {
                  case 'sort_alpha':
                    _changeSortMode(SortMode.alphabetical);
                    break;
                  case 'sort_time':
                    _changeSortMode(SortMode.addTimeDesc);
                    break;
                  case 'sort_random':
                    _changeSortMode(SortMode.random);
                    break;
                  case 'clear_all':
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清空生词本'),
                        content: const Text('确定要清空所有收藏的单词吗？此操作不可恢复。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      for (var fav in _originalFavorites) {
                        await _wordBankService.removeFavoriteById(
                          fav['id'] as int,
                        );
                      }
                      _loadFavorites();
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'sort_alpha',
                  child: Row(
                    children: [
                      Icon(
                        Icons.sort_by_alpha,
                        color: _currentSortMode == SortMode.alphabetical
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '按字母顺序排序',
                        style: TextStyle(
                          color: _currentSortMode == SortMode.alphabetical
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: _currentSortMode == SortMode.alphabetical
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sort_time',
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: _currentSortMode == SortMode.addTimeDesc
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '按添加顺序排序（新到旧）',
                        style: TextStyle(
                          color: _currentSortMode == SortMode.addTimeDesc
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: _currentSortMode == SortMode.addTimeDesc
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sort_random',
                  child: Row(
                    children: [
                      Icon(
                        Icons.shuffle,
                        color: _currentSortMode == SortMode.random
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '随机排序',
                        style: TextStyle(
                          color: _currentSortMode == SortMode.random
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: _currentSortMode == SortMode.random
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '清空生词本',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SearchBar(
                leading: const Icon(Icons.search),
                hintText: '搜索生词本',
                onChanged: (value) {
                  _searchQuery = value;
                  _loadFavorites();
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _favorites.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.bookmark_border,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? '生词本为空' : '未找到相关单词',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '查词时点击收藏按钮可将单词加入生词本',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final favorite = _favorites[index];
              final word = favorite['headword'] as String? ?? '';

              if (word.isEmpty) {
                return const SizedBox.shrink();
              }

              return FutureBuilder<DictionaryEntry?>(
                future: _dictionaryService.getEntry(word),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data == null) {
                    return ListTile(
                      onTap: () => _searchWord(word),
                      title: Text(
                        word,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  }

                  final entry = snapshot.data!;

                  return Dismissible(
                    key: Key('favorite_${favorite['id']}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: Theme.of(context).colorScheme.error,
                      child: Icon(
                        Icons.delete,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('取消收藏'),
                          content: Text('确定取消收藏 "${entry.headword}" 吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              child: const Text('取消收藏'),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (direction) {
                      _removeFavorite(favorite['id'] as int);
                    },
                    child: ListTile(
                      onTap: () => _searchWord(word), // 使用主界面相同的查词逻辑
                      title: Text(
                        entry.headword,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        entry.pronunciations.isNotEmpty
                            ? (entry.pronunciations.first['notation']
                                      as String?) ??
                                  ''
                            : '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 删除按钮
                          IconButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('取消收藏'),
                                  content: Text(
                                    '确定取消收藏 "${entry.headword}" 吗？',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      child: const Text('取消收藏'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                _removeFavorite(favorite['id'] as int);
                              }
                            },
                            icon: Icon(
                              Icons.bookmark_remove,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            tooltip: '取消收藏',
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  );
                },
              );
            }, childCount: _favorites.length),
          ),
        ],
      ),
    );
  }
}
