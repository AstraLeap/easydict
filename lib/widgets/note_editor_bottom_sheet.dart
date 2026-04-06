import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/languages/markdown.dart';
import '../i18n/strings.g.dart';
import '../services/note_service.dart';

/// 笔记编辑器底部弹窗
/// 使用 flutter_code_editor 实现纯 Flutter 的 Markdown 编辑体验
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
  late CodeController _controller;
  String _initialContent = '';
  bool _isLoading = true;
  bool _isFullScreen = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _isTrackingChanges = true;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: '',
      language: markdown,
    );
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

    _initialContent = content;
    _controller.text = content;
    _undoStack.add(content);
    _controller.addListener(_trackChanges);
    setState(() {
      _isLoading = false;
    });
  }

  void _trackChanges() {
    if (!_isTrackingChanges) return;

    final currentText = _controller.text;
    if (_undoStack.isNotEmpty && _undoStack[_currentEditPosition] != currentText) {
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
        _isTrackingChanges = false;
        _controller.text = _undoStack[_currentEditPosition];
        _isTrackingChanges = true;
      });
    }
  }

  void _redo() {
    if (_currentEditPosition < _undoStack.length - 1) {
      setState(() {
        _currentEditPosition++;
        _isTrackingChanges = false;
        _controller.text = _undoStack[_currentEditPosition];
        _isTrackingChanges = true;
      });
    }
  }

  Future<void> _save() async {
    final content = _controller.text;
    final existingNote = await _noteService.getNote(
      widget.word,
      widget.language,
    );
    final note = Note(
      word: widget.word,
      language: widget.language,
      content: content,
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
    int newCursorOffset;

    if (selectedText.isEmpty) {
      // 没有选中文本，插入占位符
      final placeholder = 'text';
      newText = '$before$placeholder${after ?? ''}';
      newCursorOffset = before.length;
    } else {
      // 有选中文本，包裹选中的文本
      newText = '$before$selectedText${after ?? ''}';
      newCursorOffset = before.length + selectedText.length;
    }

    // 替换选中的文本
    final start = selection.start;
    final end = selection.end;

    _isTrackingChanges = false;
    _controller.text = text.replaceRange(start, end, newText);
    _controller.selection = TextSelection.collapsed(
      offset: start + newCursorOffset,
    );
    _isTrackingChanges = true;

    // 手动更新撤销栈
    if (_currentEditPosition < _undoStack.length - 1) {
      _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
    }
    _undoStack.add(_controller.text);
    _currentEditPosition = _undoStack.length - 1;
    _redoStack.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    // 代码编辑器
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                        child: CodeTheme(
                          data: CodeThemeData(
                            styles: isDark ? atomOneDarkTheme : githubTheme,
                          ),
                          child: CodeField(
                            controller: _controller,
                            textStyle: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                            expands: true,
                            gutterStyle: const GutterStyle(
                              showLineNumbers: false,
                              showFoldingHandles: false,
                              showErrors: false,
                            ),
                          ),
                        ),
                      ),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
