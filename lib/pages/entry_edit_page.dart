import 'package:flutter/material.dart';
import '../database_service.dart';
import '../components/json_text_editor.dart';
import '../services/entry_edit_service.dart';
import '../utils/toast_utils.dart';

class EntryEditPage extends StatefulWidget {
  final DictionaryEntry entry;

  const EntryEditPage({super.key, required this.entry});

  @override
  State<EntryEditPage> createState() => _EntryEditPageState();
}

class _EntryEditPageState extends State<EntryEditPage> {
  late final EditState _editState;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  String _searchQuery = '';
  List<int> _searchResults = [];
  int _currentResultIndex = -1;
  final GlobalKey _editorKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _editState = EditState();
    _editState.startEditing(widget.entry);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editState.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
      _searchResults = [];
      _currentResultIndex = -1;
    });

    if (query.isEmpty) return;

    final jsonText = _editState.editedEntry?.toJson().toString() ?? '';
    int index = 0;
    while (true) {
      index = jsonText.toLowerCase().indexOf(query.toLowerCase(), index);
      if (index == -1) break;
      _searchResults.add(index);
      index += query.length;
    }

    if (_searchResults.isNotEmpty) {
      setState(() {
        _currentResultIndex = 0;
      });
      // 滚动到第一个搜索结果
      _scrollToCurrentResult();
    }
  }

  void _nextSearchResult() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentResultIndex = (_currentResultIndex + 1) % _searchResults.length;
    });
    _scrollToCurrentResult();
  }

  void _previousSearchResult() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentResultIndex =
          (_currentResultIndex - 1 + _searchResults.length) %
          _searchResults.length;
    });
    _scrollToCurrentResult();
  }

  // 滚动到当前搜索结果位置
  void _scrollToCurrentResult() {
    if (_searchResults.isEmpty || _currentResultIndex < 0) return;

    // 延迟执行，等待UI更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      // 计算目标位置（根据字符位置估算行数）
      final targetIndex = _searchResults[_currentResultIndex];
      final jsonText = _editState.editedEntry?.toJson().toString() ?? '';

      // 估算行高和每行字符数
      const double lineHeight = 19.5; // 13 * 1.5
      const int charsPerLine = 80; // 估算每行字符数

      // 计算目标行号
      int lineNumber = 0;
      int currentLineChars = 0;
      for (int i = 0; i < targetIndex && i < jsonText.length; i++) {
        if (jsonText[i] == '\n') {
          lineNumber++;
          currentLineChars = 0;
        } else {
          currentLineChars++;
          if (currentLineChars >= charsPerLine) {
            lineNumber++;
            currentLineChars = 0;
          }
        }
      }

      // 计算滚动偏移量
      final targetOffset = lineNumber * lineHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final maxScrollExtent = _scrollController.position.maxScrollExtent;

      // 将目标位置滚动到视口中央
      double scrollOffset = targetOffset - viewportHeight / 2;
      scrollOffset = scrollOffset.clamp(0.0, maxScrollExtent);

      _scrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _closeSearch() {
    setState(() {
      _searchQuery = '';
      _searchResults = [];
      _currentResultIndex = -1;
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  Future<void> _saveChanges() async {
    final success = await _editState.saveChanges();
    if (mounted) {
      showToast(context, success ? '保存成功' : '保存失败');
      if (success) {
        Navigator.of(context).pop(_editState.editedEntry);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 主内容区域
          AnimatedBuilder(
            animation: _editState,
            builder: (context, child) {
              if (_editState.editedEntry == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: JsonTextEditor(
                  key: _editorKey,
                  entry: _editState.editedEntry!,
                  editState: _editState,
                  searchQuery: _searchQuery.trim(),
                  currentResultIndex: _currentResultIndex,
                  searchResults: _searchResults,
                  // 搜索栏放在编辑器内部
                  searchBar: _buildSearchBar(colorScheme),
                  onSave: _saveChanges,
                  hasChanges: _editState.hasChanges,
                  scrollController: _scrollController,
                ),
              );
            },
          ),
          // 左上角悬浮返回按钮
          Positioned(
            top: 16,
            left: 16,
            child: Material(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back, color: colorScheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建搜索栏
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // 搜索图标
          Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          // 搜索输入框
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: '搜索...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
              onChanged: _performSearch,
            ),
          ),
          // 搜索结果计数和导航
          if (_searchResults.isNotEmpty) ...[
            Text(
              '${_currentResultIndex + 1}/${_searchResults.length}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              tooltip: '上一个',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _previousSearchResult,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              tooltip: '下一个',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _nextSearchResult,
            ),
          ],
          // 关闭搜索按钮
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '清除搜索',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _closeSearch,
            ),
        ],
      ),
    );
  }
}
