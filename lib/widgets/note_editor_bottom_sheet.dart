import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';
import '../services/note_service.dart';

/// 笔记编辑器底部弹窗
/// 支持底部弹出、全屏切换、实时 Markdown 预览
class NoteEditorBottomSheet extends StatefulWidget {
  final String word;
  final String language;
  final String? linkToAppend;
  final double statusBarHeight;

  const NoteEditorBottomSheet({
    super.key,
    required this.word,
    required this.language,
    this.linkToAppend,
    required this.statusBarHeight,
  });

  /// 显示笔记编辑器底部弹窗
  static Future<bool> show(
    BuildContext context, {
    required String word,
    required String language,
    String? linkToAppend,
  }) async {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteEditorBottomSheet(
        word: word,
        language: language,
        linkToAppend: linkToAppend,
        statusBarHeight: statusBarHeight,
      ),
    );
    return result ?? false;
  }

  @override
  State<NoteEditorBottomSheet> createState() => _NoteEditorBottomSheetState();
}

class _NoteEditorBottomSheetState extends State<NoteEditorBottomSheet> {
  final NoteService _noteService = NoteService();
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isLoading = true;
  bool _isFullScreen = false;
  bool _isPreviewMode = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final note = await _noteService.getNote(widget.word, widget.language);
    String content = note?.content ?? '';

    // 如果有要追加的链接
    if (widget.linkToAppend != null) {
      if (content.isNotEmpty) {
        content = '$content\n\n${widget.linkToAppend}';
      } else {
        content = widget.linkToAppend!;
      }
    }

    _controller.text = content;
    _undoStack.add(content);
    _controller.addListener(_trackChanges);
    setState(() {
      _isLoading = false;
    });
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
      setState(() {});
    }
  }

  void _undo() {
    if (_currentEditPosition > 0) {
      setState(() {
        _currentEditPosition--;
        _controller.removeListener(_trackChanges);
        _controller.text = _undoStack[_currentEditPosition];
        _controller.addListener(_trackChanges);
      });
    }
  }

  void _redo() {
    if (_currentEditPosition < _undoStack.length - 1) {
      setState(() {
        _currentEditPosition++;
        _controller.removeListener(_trackChanges);
        _controller.text = _undoStack[_currentEditPosition];
        _controller.addListener(_trackChanges);
      });
    }
  }

  Future<void> _save() async {
    final existingNote = await _noteService.getNote(
      widget.word,
      widget.language,
    );
    final note = Note(
      word: widget.word,
      language: widget.language,
      content: _controller.text,
      createdAt: existingNote?.createdAt,
    );
    await _noteService.saveNote(note);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _insertMarkdownSyntax(String before, [String? after]) {
    final text = _controller.text;
    final selection = _controller.selection;
    final selectedText = selection.textInside(text);

    String newText;
    TextPosition newCursorPos;

    if (selectedText.isEmpty) {
      // 没有选中文本，插入占位符
      final placeholder = after != null ? 'text' : 'text';
      newText = text.replaceRange(
        selection.start,
        selection.end,
        '$before$placeholder${after ?? ''}',
      );
      newCursorPos = TextPosition(
        offset: selection.start + before.length,
      );
    } else {
      // 有选中文本，包裹选中的文本
      newText = text.replaceRange(
        selection.start,
        selection.end,
        '$before$selectedText${after ?? ''}',
      );
      newCursorPos = TextPosition(
        offset: selection.start + before.length + selectedText.length + (after?.length ?? 0),
      );
    }

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos.offset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return DraggableScrollableSheet(
      initialChildSize: _isFullScreen ? 1.0 : 0.7,
      minChildSize: _isFullScreen ? 1.0 : 0.5,
      maxChildSize: _isFullScreen
          ? 1.0
          : (screenSize.height - widget.statusBarHeight - 8) / screenSize.height,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          width: _isFullScreen ? screenSize.width : null,
          padding: EdgeInsets.only(
            top: _isFullScreen ? widget.statusBarHeight + 8 : 16,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: _isFullScreen
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: _isFullScreen ? Clip.none : Clip.antiAlias,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Icon(Icons.note_outlined, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.t.note.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          widget.word,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 工具栏
                    Row(
                      children: [
                        // 保存
                        _buildToolbarButton(
                          icon: Icons.save,
                          onPressed: _save,
                          tooltip: context.t.common.save,
                          color: colorScheme.primary,
                        ),
                        // 撤销
                        _buildToolbarButton(
                          icon: Icons.undo,
                          onPressed: _currentEditPosition > 0 ? _undo : null,
                          tooltip: context.t.common.undo,
                        ),
                        // 重做
                        _buildToolbarButton(
                          icon: Icons.redo,
                          onPressed: _currentEditPosition < _undoStack.length - 1 ? _redo : null,
                          tooltip: context.t.common.redo,
                        ),
                        const SizedBox(width: 8),
                        // 分隔线
                        Container(
                          width: 1,
                          height: 24,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 8),
                        // 加粗
                        _buildToolbarButton(
                          icon: Icons.format_bold,
                          onPressed: () => _insertMarkdownSyntax('**', '**'),
                          tooltip: context.t.note.bold,
                        ),
                        // 斜体
                        _buildToolbarButton(
                          icon: Icons.format_italic,
                          onPressed: () => _insertMarkdownSyntax('*', '*'),
                          tooltip: context.t.note.italic,
                        ),
                        // 链接
                        _buildToolbarButton(
                          icon: Icons.link,
                          onPressed: () => _insertMarkdownSyntax('[', '](url)'),
                          tooltip: context.t.note.link,
                        ),
                        // 代码
                        _buildToolbarButton(
                          icon: Icons.code,
                          onPressed: () => _insertMarkdownSyntax('`', '`'),
                          tooltip: context.t.note.code,
                        ),
                        const Spacer(),
                        // 预览切换
                        _buildToolbarButton(
                          icon: _isPreviewMode ? Icons.edit : Icons.visibility,
                          onPressed: () => setState(() => _isPreviewMode = !_isPreviewMode),
                          tooltip: _isPreviewMode ? context.t.note.edit : context.t.note.preview,
                        ),
                        // 全屏
                        IconButton(
                          onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
                          icon: Icon(
                            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            size: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                          tooltip: _isFullScreen
                              ? context.t.common.exitFullscreen
                              : context.t.common.fullscreen,
                        ),
                        // 关闭
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 编辑区域
                    Expanded(
                      child: _isPreviewMode
                          ? _buildPreview(colorScheme)
                          : _buildEditor(colorScheme),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildToolbarButton({
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
        color: color ??
            (onPressed != null ? colorScheme.onSurfaceVariant : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEditor(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: context.t.note.placeholder,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme colorScheme) {
    // 使用简单的文本显示，保留换行
    final text = _controller.text;
    if (text.isEmpty) {
      return Center(
        child: Text(
          context.t.note.previewEmpty,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: SingleChildScrollView(
        child: _buildMarkdownPreview(text, colorScheme),
      ),
    );
  }

  /// 简单的 Markdown 预览渲染
  Widget _buildMarkdownPreview(String text, ColorScheme colorScheme) {
    final lines = text.split('\n');
    final spans = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      spans.addAll(_parseLine(line, colorScheme));
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(
      text: TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 解析单行文本，返回 InlineSpan 列表
  List<InlineSpan> _parseLine(String line, ColorScheme colorScheme) {
    final spans = <InlineSpan>[];
    var remaining = line;

    while (remaining.isNotEmpty) {
      // 检查链接格式 [text](url)
      final linkMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(remaining);
      if (linkMatch != null) {
        // 添加链接前的普通文本
        if (linkMatch.start > 0) {
          spans.add(TextSpan(text: remaining.substring(0, linkMatch.start)));
        }
        // 添加链接
        spans.add(TextSpan(
          text: linkMatch.group(1),
          style: TextStyle(
            color: colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ));
        remaining = remaining.substring(linkMatch.end);
        continue;
      }

      // 检查加粗 **text**
      final boldMatch = RegExp(r'\*\*([^*]+)\*\*').firstMatch(remaining);
      if (boldMatch != null) {
        if (boldMatch.start > 0) {
          spans.add(TextSpan(text: remaining.substring(0, boldMatch.start)));
        }
        spans.add(TextSpan(
          text: boldMatch.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
        remaining = remaining.substring(boldMatch.end);
        continue;
      }

      // 检查斜体 *text*
      final italicMatch = RegExp(r'\*([^*]+)\*').firstMatch(remaining);
      if (italicMatch != null) {
        if (italicMatch.start > 0) {
          spans.add(TextSpan(text: remaining.substring(0, italicMatch.start)));
        }
        spans.add(TextSpan(
          text: italicMatch.group(1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
        remaining = remaining.substring(italicMatch.end);
        continue;
      }

      // 检查行内代码 `code`
      final codeMatch = RegExp(r'`([^`]+)`').firstMatch(remaining);
      if (codeMatch != null) {
        if (codeMatch.start > 0) {
          spans.add(TextSpan(text: remaining.substring(0, codeMatch.start)));
        }
        spans.add(TextSpan(
          text: codeMatch.group(1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ));
        remaining = remaining.substring(codeMatch.end);
        continue;
      }

      // 没有匹配，添加剩余文本
      spans.add(TextSpan(text: remaining));
      break;
    }

    return spans;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
