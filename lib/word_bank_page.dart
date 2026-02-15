import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:reorderables/reorderables.dart';
import 'database_service.dart';
import 'word_bank_service.dart';
import 'models/dictionary_entry_group.dart';
import 'pages/entry_detail_page.dart';
import 'utils/toast_utils.dart';
import 'utils/word_list_dialog.dart';
import 'utils/language_utils.dart';
import 'utils/language_dropdown.dart';
import 'utils/dpi_utils.dart';
import 'widgets/search_bar.dart';
import 'services/advanced_search_settings_service.dart';
import 'logger.dart';

enum SortMode {
  addTimeDesc('添加顺序'),
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

  // 数据
  List<String> _languages = [];
  String? _selectedLanguage; // null 表示"全部"
  Map<String, List<Map<String, dynamic>>> _wordsByList = {};
  List<Map<String, dynamic>> _allWords = [];
  Map<String, int> _languageWordCounts = {};

  bool _isInitialLoading = true;
  bool _isLoadingWords = false;
  bool _isLoadingMore = false;
  bool _wordsLoaded = false;
  String _searchQuery = '';
  SortMode _currentSortMode = SortMode.addTimeDesc;
  String? _selectedList; // 选中的词表筛选
  final TextEditingController _searchController = TextEditingController();

  // 分页相关
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadWordsIfNeeded() async {
    if (_wordsLoaded) return;
    _wordsLoaded = true;
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 获取所有支持的语言
      final languages = await _wordBankService.getSupportedLanguages();

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

  Future<void> _loadWords() async {
    final startTime = DateTime.now();
    Logger.d('_loadWords 开始', tag: 'WordBank');

    if (mounted) {
      setState(() => _isLoadingWords = true);
    }

    // 重置分页状态
    _currentPage = 0;
    _hasMoreData = true;
    _allWords = [];
    _wordsByList = {};
    _languageWordCounts = {};

    // 直接加载单词，不使用 _loadMoreWords 以避免触发分页加载状态
    try {
      final int offset = 0;

      if (_selectedLanguage == null) {
        // 显示所有语言的单词
        Logger.d('加载所有语言的单词: ${_languages.join(", ")}', tag: 'WordBank');
        for (final lang in _languages) {
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

    if (mounted) {
      setState(() => _isLoadingWords = false);
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadWords 完成: 耗时 ${duration.inMilliseconds}ms, 总单词数: ${_allWords.length}',
      tag: 'WordBank',
    );
  }

  Future<void> _loadMoreWords() async {
    if (_isLoadingMore || !_hasMoreData) return;

    final startTime = DateTime.now();
    Logger.d('_loadMoreWords 开始, 页码: $_currentPage', tag: 'WordBank');

    setState(() => _isLoadingMore = true);

    try {
      final int offset = _currentPage * _pageSize;

      if (_selectedLanguage == null) {
        // 显示所有语言的单词
        Logger.d('加载所有语言的单词: ${_languages.join(", ")}', tag: 'WordBank');
        for (final lang in _languages) {
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
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    Logger.d(
      '_loadMoreWords 完成: 耗时 ${duration.inMilliseconds}ms, 总单词数: ${_allWords.length}',
      tag: 'WordBank',
    );
  }

  /// 获取排序参数
  ({String sortBy, bool ascending}) _getSortParams() {
    switch (_currentSortMode) {
      case SortMode.addTimeDesc:
        return (sortBy: 'created_at', ascending: false);
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

  /// 应用排序（仅在搜索模式下需要，因为搜索时数据库排序不支持）
  void _applySort() {
    // 非搜索模式下，数据已从数据库按正确顺序加载，无需内存排序
    if (_searchQuery.isEmpty) {
      return;
    }

    // 搜索模式下需要在内存中排序
    switch (_currentSortMode) {
      case SortMode.addTimeDesc:
        // 按添加时间排序（最新的在前），时间相同则按字母排序
        _wordsByList = _wordsByList.map((listName, words) {
          final sorted = List<Map<String, dynamic>>.from(words)
            ..sort((a, b) {
              final timeA = a['created_at'] as int? ?? 0;
              final timeB = b['created_at'] as int? ?? 0;
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
          final timeA = a['created_at'] as int? ?? 0;
          final timeB = b['created_at'] as int? ?? 0;
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
    setState(() {
      _currentSortMode = mode;
    });
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
        showToast(context, '已移除单词');
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
      showToast(context, '已更新词表归属');
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
                      '导入到 ${LanguageUtils.getLanguageDisplayName(language)}',
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
                    const Text(
                      '词表名称：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '例如：托福、雅思、GRE',
                        contentPadding: EdgeInsets.symmetric(
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
                      label: const Text('选择文件'),
                    ),
                    const SizedBox(height: 8),

                    // 预览区域
                    if (previewWords.isNotEmpty) ...[
                      const Text(
                        '预览前10个单词：',
                        style: TextStyle(fontWeight: FontWeight.bold),
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
                        '共识别到 ${previewWords.length} 个单词预览',
                        style: TextStyle(
                          fontSize: DpiUtils.scaleFontSize(context, 12),
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
                  child: const Text('取消'),
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
                                '成功导入 $count 个单词到 "$listName"',
                              );

                              // 刷新数据
                              await _loadData();
                            }
                          } catch (e) {
                            if (mounted) {
                              String errorMessage = '导入失败';
                              if (e.toString().contains('已存在')) {
                                errorMessage = '词表 "$listName" 已存在，请使用其他名称';
                              } else if (e.toString().contains(
                                'No such file',
                              )) {
                                errorMessage = '文件读取失败';
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
                      : const Text('导入'),
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
                      '编辑 ${LanguageUtils.getLanguageDisplayName(_selectedLanguage!)} 词表',
                    ),
                  ),
                ],
              ),
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
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
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
                                    tooltip: '重命名',
                                    onPressed: () async {
                                      final controller = TextEditingController(
                                        text: list.currentName,
                                      );
                                      final newName = await showDialog<String>(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: const Text('重命名词表'),
                                            content: TextField(
                                              controller: controller,
                                              decoration: const InputDecoration(
                                                labelText: '词表名称',
                                                hintText: '输入新名称',
                                              ),
                                              autofocus: true,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  controller.text.trim(),
                                                ),
                                                child: const Text('确定'),
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
                                    tooltip: '删除',
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
                                                const Text('删除词表'),
                                              ],
                                            ),
                                            content: Text(
                                              '确定要删除词表 "${list.currentName}" 吗？\n\n这将删除该词表及其所有数据。如果一个单词不属于任何其他词表，也会被删除。',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child: const Text('取消'),
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
                                                child: const Text('删除'),
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
                      label: const Text('导入词表'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
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
                            showToast(context, '词表已更新');
                            await _loadData();
                          }
                        } catch (e) {
                          if (mounted) {
                            String errorMsg = '操作失败';
                            if (e.toString().contains('已存在')) {
                              errorMsg = '词表名称已存在，请使用其他名称';
                            }
                            showToast(context, errorMsg);
                          }
                        }
                      },
                      child: const Text('保存'),
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
    if (_selectedLanguage == null) {
      // "全部"模式下，显示所有语言的词表
      final List<Widget> chips = [];

      // "全部"选项
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            selected: _selectedList == null,
            label: const Text('全部'),
            onSelected: (selected) {
              setState(() {
                _selectedList = null;
              });
            },
          ),
        ),
      );

      // 每个语言的词表
      for (final lang in _languages) {
        final wordLists = _wordBankService.getWordListsSync(lang);
        for (final list in wordLists) {
          final listKey = '${lang}_${list.name}';
          final isSelected = _selectedList == listKey;
          final count = _wordsByList[listKey]?.length ?? 0;

          if (count > 0) {
            chips.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(
                    '${LanguageUtils.getLanguageDisplayName(lang)}-${list.displayName}',
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
                        label: const Text('全部'),
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
                      label: Text(list.displayName),
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
          IconButton(
            onPressed: () => _showManageWordListsDialog(),
            icon: const Icon(Icons.playlist_add_check),
            tooltip: '管理词表',
            iconSize: 28,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              hoverColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1,
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
  }) {
    final word = wordData['word'] as String? ?? '';
    if (word.isEmpty) return const SizedBox.shrink();

    return InkWell(
      onTap: () => _searchWord(word, language),
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
                  fontSize: 18,
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
                LanguageUtils.getLanguageDisplayName(lang),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );

        // 单词列表
        widgets.add(
          SliverList(
            key: ValueKey('${lang}_${_selectedList}_${_currentSortMode.name}'),
            delegate: SliverChildBuilderDelegate((context, index) {
              final wordData = filteredWords[index];
              final word = wordData['word'] as String? ?? '';

              return _buildWordListItem(
                wordData: wordData,
                language: lang,
                onRemove: () {
                  _wordBankService.removeWord(word, lang);
                  setState(() {
                    filteredWords.removeAt(index);
                  });
                },
              );
            }, childCount: filteredWords.length),
          ),
        );
      }
    } else {
      // 特定语言模式
      // 从 _allWords 中获取该语言的单词
      final words =
          _allWords.where((w) => w['language'] == _selectedLanguage).toList() ??
          [];

      // 根据选择的词表筛选
      final filteredWords = _selectedList != null
          ? words.where((w) => w[_selectedList] == 1).toList()
          : words;

      if (filteredWords.isEmpty) {
        widgets.add(
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有找到单词'),
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          SliverList(
            key: ValueKey(
              '${_selectedLanguage}_${_selectedList}_${_currentSortMode.name}',
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final wordData = filteredWords[index];
              final word = wordData['word'] as String? ?? '';

              return _buildWordListItem(
                wordData: wordData,
                language: _selectedLanguage!,
                onRemove: () {
                  _wordBankService.removeWord(word, _selectedLanguage!);
                  setState(() {
                    filteredWords.removeAt(index);
                  });
                },
              );
            }, childCount: filteredWords.length),
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

    // 显示所有词表标签，超出部分自动省略
    return Container(
      margin: EdgeInsets.only(right: DpiUtils.scale(context, 8)),
      child: Text(
        belongingLists.join(', '),
        style: TextStyle(
          fontSize: DpiUtils.scaleFontSize(context, 11),
          color: Theme.of(context).colorScheme.outline,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  /// 搜索单词
  Future<void> _searchWord(String word, String language) async {
    // 获取当前语言的默认搜索选项
    final advancedSettingsService = AdvancedSearchSettingsService();
    final defaultOptions = advancedSettingsService.getDefaultOptionsForLanguage(
      language == 'auto' ? null : language,
    );

    // 查询词典，使用默认高级选项
    final searchResult = await _dictionaryService.getAllEntries(
      word,
      useFuzzySearch: defaultOptions.useFuzzySearch,
      exactMatch: defaultOptions.exactMatch,
      sourceLanguage: language == 'auto' ? null : language,
    );

    if (mounted && searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );
      Navigator.push(
        context,
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
    } else if (mounted) {
      showToast(context, '未找到单词: $word');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_languages.isEmpty) {
      return Scaffold(body: _buildEmptyState());
    }

    return Scaffold(
      body: Column(
        children: [
          // 固定的搜索栏和词表筛选器
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                // 搜索栏
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: UnifiedSearchBar.withLanguageSelector(
                    controller: _searchController,
                    selectedLanguage: _selectedLanguage ?? 'ALL',
                    availableLanguages: _languages,
                    onLanguageSelected: (value) async {
                      setState(() {
                        _selectedLanguage = value == 'ALL' ? null : value;
                        _selectedList = null;
                      });
                      if (value == null || value == 'ALL') {
                        await _wordBankService.saveLastSelectedLanguage('ALL');
                      } else {
                        await _wordBankService.saveLastSelectedLanguage(value);
                      }
                      await _loadWords();
                    },
                    hintText: '搜索单词本',
                    showAllOption: true,
                    extraSuffixIcons: [
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: DpiUtils.scaleIconSize(context, 18),
                          ),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                            _loadWords();
                          },
                        ),
                      PopupMenuButton<SortMode>(
                        tooltip: '排序方式',
                        icon: Icon(
                          Icons.swap_vert,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    Text(mode.label),
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
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    onSubmitted: (value) {
                      _loadWords();
                    },
                  ),
                ),
                // 词表筛选器
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: _buildListFilter(),
                ),
              ],
            ),
          ),
          // 可滚动的单词列表
          Expanded(
            child: _isLoadingWords
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
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
                      slivers: [
                        // 单词列表
                        ..._buildWordList(),
                        // 加载更多指示器
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                        // 底部留白
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
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
            '单词本还是空的',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在查词时点击收藏按钮添加单词',
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

// 使用一个包装类来追踪原始名称
class EditableWordList {
  final String originalName;
  String currentName;

  EditableWordList({required this.originalName, required this.currentName});

  WordListInfo toInfo() => WordListInfo(name: currentName);
}
