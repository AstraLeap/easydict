import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database_service.dart';
import '../services/entry_edit_service.dart';

/// JSON 文本编辑器
class JsonTextEditor extends StatefulWidget {
  final DictionaryEntry entry;
  final EditState editState;
  final String searchQuery;
  final int currentResultIndex;
  final List<int> searchResults;
  final Widget? searchBar;
  final VoidCallback? onSave;
  final bool hasChanges;
  final ScrollController? scrollController;

  const JsonTextEditor({
    super.key,
    required this.entry,
    required this.editState,
    this.searchQuery = '',
    this.currentResultIndex = -1,
    this.searchResults = const [],
    this.searchBar,
    this.onSave,
    this.hasChanges = false,
    this.scrollController,
  });

  @override
  State<JsonTextEditor> createState() => _JsonTextEditorState();
}

class _JsonTextEditorState extends State<JsonTextEditor> {
  late TextEditingController _jsonController;
  String? _errorMessage;
  bool _isValid = true;
  late final ScrollController _scrollController;
  final GlobalKey _textFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _jsonController = TextEditingController(
      text: _formatJson(widget.entry.toJson()),
    );
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(JsonTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _jsonController.text = _formatJson(widget.entry.toJson());
      _errorMessage = null;
      _isValid = true;
    }
  }

  @override
  void dispose() {
    _jsonController.dispose();
    // 只有当 scrollController 是内部创建的时候才需要 dispose
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  String _formatJson(Map<String, dynamic> json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  void _validateAndUpdate() {
    try {
      final json = jsonDecode(_jsonController.text) as Map<String, dynamic>;
      final newEntry = DictionaryEntry.fromJson(json);

      // 更新编辑状态
      widget.editState.updateEntry(newEntry);

      setState(() {
        _errorMessage = null;
        _isValid = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'JSON 格式错误: $e';
        _isValid = false;
      });
    }
  }

  void _formatDocument() {
    try {
      final json = jsonDecode(_jsonController.text);
      final formatted = _formatJson(json);
      _jsonController.text = formatted;
      _validateAndUpdate();
    } catch (e) {
      // 格式错误时不进行格式化
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 合并的顶部栏（搜索栏 + 工具栏）
        _buildCombinedToolbar(colorScheme),
        // 错误提示
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade100,
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
            ),
          ),
        // JSON 编辑器
        Expanded(
          child: Container(
            color: colorScheme.surface,
            child: _buildEditor(colorScheme),
          ),
        ),
      ],
    );
  }

  // 合并的顶部栏（搜索栏 + 工具栏）
  Widget _buildCombinedToolbar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // 搜索区域（如果提供）
          if (widget.searchBar != null)
            Expanded(flex: 3, child: widget.searchBar!),
          if (widget.searchBar != null) const SizedBox(width: 16),
          // 工具按钮区域
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 格式化按钮
                _buildToolbarButton(
                  icon: Icons.auto_fix_high,
                  tooltip: '格式化 JSON',
                  onPressed: _formatDocument,
                ),
                // 验证状态指示
                _buildToolbarButton(
                  icon: _isValid ? Icons.check_circle : Icons.error,
                  tooltip: _isValid ? 'JSON 格式正确' : 'JSON 格式错误',
                  onPressed: null,
                  color: _isValid ? Colors.green : Colors.red,
                ),
                // 查看 Schema 按钮
                _buildToolbarButton(
                  icon: Icons.help_outline,
                  tooltip: '查看 JSON 格式说明',
                  onPressed: _showSchemaHelp,
                ),
                // 保存按钮
                if (widget.hasChanges && widget.onSave != null)
                  _buildToolbarButton(
                    icon: Icons.save,
                    tooltip: '保存修改',
                    onPressed: widget.onSave,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      color: color,
      onPressed: onPressed,
    );
  }

  void _showSchemaHelp() {
    showDialog(
      context: context,
      builder: (context) => const JsonSchemaHelpDialog(),
    );
  }

  Widget _buildEditor(ColorScheme colorScheme) {
    // 使用单层 TextField，搜索高亮通过自定义实现
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: _buildRichTextEditor(colorScheme),
      ),
    );
  }

  Widget _buildRichTextEditor(ColorScheme colorScheme) {
    final text = _jsonController.text;

    // 如果没有搜索词，显示普通文本
    if (widget.searchQuery.isEmpty) {
      return TextField(
        controller: _jsonController,
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 13,
          height: 1.5,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        maxLines: null,
        onChanged: (_) => _validateAndUpdate(),
      );
    }

    // 有搜索词时，使用 RichText 显示高亮
    // 但保持 TextField 用于编辑
    return Stack(
      children: [
        // 底层：透明编辑框（用于输入）
        TextField(
          controller: _jsonController,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 13,
            height: 1.5,
            color: Colors.transparent, // 隐藏文字，只显示光标
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          maxLines: null,
          onChanged: (_) => _validateAndUpdate(),
          cursorColor: colorScheme.primary,
        ),
        // 上层：高亮显示（只读）
        Positioned.fill(
          child: IgnorePointer(child: _buildHighlightedText(colorScheme)),
        ),
      ],
    );
  }

  Widget _buildHighlightedText(ColorScheme colorScheme) {
    final text = _jsonController.text;
    if (text.isEmpty || widget.searchQuery.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 13,
          height: 1.5,
        ),
      );
    }

    final spans = <TextSpan>[];
    int currentIndex = 0;
    final queryLower = widget.searchQuery.toLowerCase();

    while (currentIndex < text.length) {
      final matchIndex = text.toLowerCase().indexOf(queryLower, currentIndex);

      if (matchIndex == -1) {
        // 没有更多匹配，添加剩余文本
        spans.add(
          TextSpan(
            text: text.substring(currentIndex),
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 13,
              height: 1.5,
              color: colorScheme.onSurface,
            ),
          ),
        );
        break;
      }

      // 添加匹配前的文本
      if (matchIndex > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, matchIndex),
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 13,
              height: 1.5,
              color: colorScheme.onSurface,
            ),
          ),
        );
      }

      // 检查是否是当前选中的结果
      final isCurrentResult =
          widget.searchResults.isNotEmpty &&
          widget.searchResults[widget.currentResultIndex.clamp(
                0,
                widget.searchResults.length - 1,
              )] ==
              matchIndex;

      // 添加匹配的文本（高亮）
      spans.add(
        TextSpan(
          text: text.substring(
            matchIndex,
            matchIndex + widget.searchQuery.length,
          ),
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 13,
            height: 1.5,
            backgroundColor: isCurrentResult
                ? Colors.orange.withOpacity(0.6) // 当前选中结果用橙色
                : Colors.yellow.withOpacity(0.4), // 其他结果用黄色
            color: colorScheme.onSurface,
            fontWeight: isCurrentResult ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );

      currentIndex = matchIndex + widget.searchQuery.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      softWrap: true,
      locale: const Locale('zh', 'CN'),
    );
  }
}

/// JSON Schema 帮助对话框
class JsonSchemaHelpDialog extends StatelessWidget {
  const JsonSchemaHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Text('JSON 格式说明'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSection(
                '基本结构',
                '''
{
  "entry_id": "唯一标识",
  "headword": "词条词",
  "entry_type": "word/phrase",
  "page": "页码",
  "section": "章节",
  ...
}
                '''
                    .trim(),
                colorScheme,
                isDark,
              ),
              const SizedBox(height: 16),
              _buildSection(
                '主要字段',
                '''
• entry_id - 条目的唯一标识符
• headword - 词条的主词
• entry_type - 条目类型: "word" 或 "phrase"
• page - 页码（可选）
• section - 章节名称（可选）
• tags - 标签数组
• certifications - 认证等级数组
• frequency - 词频信息对象
• etymology - 词源信息
• inflections - 词形变化数组
• pronunciations - 发音数组
• senses - 释义数组
• boards - 板块数组
• collocations - 搭配信息
• phrases - 短语信息
• theasaruses - 同义词信息
• sense_groups - 释义分组
                '''
                    .trim(),
                colorScheme,
                isDark,
              ),
              const SizedBox(height: 16),
              _buildSection(
                '示例',
                '''
{
  "entry_id": "example_001",
  "headword": "example",
  "entry_type": "word",
  "page": "123",
  "section": "A",
  "tags": ["common", "formal"],
  "pronunciations": [
    {
      "ipa": "/ɪɡˈzæmpəl/",
      "audio": "example.mp3"
    }
  ],
  "senses": [
    {
      "definition": "A thing characteristic of its kind",
      "example": ["This is an example sentence."]
    }
  ]
}
                '''
                    .trim(),
                colorScheme,
                isDark,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildSection(
    String title,
    String content,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              color: colorScheme.onSurface,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
