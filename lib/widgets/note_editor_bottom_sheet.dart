import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../i18n/strings.g.dart';
import '../services/note_service.dart';

/// 笔记编辑器底部弹窗
/// 使用 re_editor 实现纯 Flutter 的 Markdown 编辑体验
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
  late CodeLineEditingController _controller;
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
    _controller = CodeLineEditingController();
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
    final selection = _controller.selection;
    final selectedText = _controller.selectedText;

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

    // 获取选区的起始和结束位置
    final startIndex = selection.startIndex;
    final startOffset = selection.startOffset;
    final endIndex = selection.endIndex;
    final endOffset = selection.endOffset;

    _isTrackingChanges = false;

    // 获取文本并替换
    final fullText = _controller.text;
    // 计算全局偏移量
    int globalStart = _getGlobalOffset(startIndex, startOffset);
    int globalEnd = _getGlobalOffset(endIndex, endOffset);

    _controller.text = fullText.replaceRange(globalStart, globalEnd, newText);

    // 设置新选区（光标位置）
    int newGlobalOffset = globalStart + newCursorOffset;
    var (newLineIndex, newLineOffset) = _getLinePosition(newGlobalOffset);
    _controller.selection = CodeLineSelection.collapsed(
      index: newLineIndex,
      offset: newLineOffset,
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

  /// 计算全局字符偏移量
  int _getGlobalOffset(int lineIndex, int lineOffset) {
    final codeLines = _controller.codeLines;
    int offset = 0;
    for (int i = 0; i < lineIndex && i < codeLines.length; i++) {
      offset += codeLines[i].text.length + 1; // +1 for newline
    }
    return offset + lineOffset;
  }

  /// 从全局偏移量计算行索引和行内偏移
  (int lineIndex, int lineOffset) _getLinePosition(int globalOffset) {
    final codeLines = _controller.codeLines;
    int offset = 0;
    for (int i = 0; i < codeLines.length; i++) {
      final lineLength = codeLines[i].text.length;
      if (offset + lineLength >= globalOffset) {
        return (i, globalOffset - offset);
      }
      offset += lineLength + 1; // +1 for newline
    }
    return (codeLines.length - 1, codeLines.isEmpty ? 0 : codeLines.last.text.length);
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
                        Icon(Icons.sticky_note_2_outlined, color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.word,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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
                        const Spacer(),
                        // 全屏
                        IconButton(
                          onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
                          icon: Icon(
                            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            size: 20,
                          ),
                          tooltip: _isFullScreen
                              ? context.t.common.exitFullscreen
                              : context.t.common.fullscreen,
                        ),
                        // 关闭
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 代码编辑器
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                        child: CodeEditor(
                          controller: _controller,
                          style: CodeEditorStyle(
                            fontSize: 15,
                            fontFamily: 'monospace',
                            backgroundColor: isDark
                                ? colorScheme.primaryContainer.withOpacity(0.05)
                                : colorScheme.primaryContainer.withOpacity(0.08),
                            codeTheme: CodeHighlightTheme(
                              languages: {
                                'markdown': CodeHighlightThemeMode(mode: langMarkdown)
                              },
                              theme: isDark
                                  ? builtThemes['atom-one-dark']!
                                  : builtThemes['atom-one-light']!,
                            ),
                          ),
                          wordWrap: true,
                          indicatorBuilder: (context, editingController, chunkController, notifier) {
                            // 不显示行号和折叠指示器
                            return const SizedBox.shrink();
                          },
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
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
