import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../core/logger.dart';
import '../i18n/strings.g.dart';
import '../core/utils/scroll_safe_utils.dart';
import '../services/note_service.dart';
import '../services/preferences_service.dart';
import 'note_markdown_media_image.dart';

/// 笔记编辑器底部弹窗
/// 使用 re_editor 实现纯 Flutter 的 Markdown 编辑体验
class NoteEditorBottomSheet extends StatefulWidget {
  final String word;
  final String language;
  final String? linkToAppend;
  final double statusBarHeight;
  final void Function(String path)? onLinkTap;

  const NoteEditorBottomSheet({
    super.key,
    required this.word,
    required this.language,
    this.linkToAppend,
    required this.statusBarHeight,
    this.onLinkTap,
  });

  /// 显示笔记编辑器底部弹窗
  static Future<bool> show(
    BuildContext context, {
    required String word,
    required String language,
    String? linkToAppend,
    void Function(String path)? onLinkTap,
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
        onLinkTap: onLinkTap,
      ),
    );
    return result ?? false;
  }

  @override
  State<NoteEditorBottomSheet> createState() => _NoteEditorBottomSheetState();
}

class _NoteEditorBottomSheetState extends State<NoteEditorBottomSheet> {
  static const String _logTag = 'NoteEditorPaste';
  final NoteService _noteService = NoteService();
  final PreferencesService _preferencesService = PreferencesService();
  late CodeLineEditingController _controller;
  bool _isLoading = true;
  bool _isFullScreen = false;
  bool _isPreviewMode = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _isTrackingChanges = true;
  bool _isPastingImage = false;
  DateTime? _lastPasteShortcutTime;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    Logger.i(
      'note editor init, platform=${Platform.operatingSystem}, supportsPaste=$_supportsClipboardImagePaste',
      tag: _logTag,
    );
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final previewMode = await _preferencesService.getNoteEditorPreviewMode();
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
      _isPreviewMode = previewMode;
      _isLoading = false;
    });
  }

  void _trackChanges() {
    if (!_isTrackingChanges) return;

    final currentText = _controller.text;
    if (_undoStack.isNotEmpty &&
        _undoStack[_currentEditPosition] != currentText) {
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

  Future<void> _togglePreviewMode() async {
    final newValue = !_isPreviewMode;
    setState(() {
      _isPreviewMode = newValue;
    });
    await _preferencesService.setNoteEditorPreviewMode(newValue);
  }

  Future<void> _insertImageFromPicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.first;
      Uint8List? bytes = pickedFile.bytes;
      final path = pickedFile.path;
      if ((bytes == null || bytes.isEmpty) && path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        _showMessage(context.t.common.error);
        return;
      }

      final fallbackName = 'image_${DateTime.now().millisecondsSinceEpoch}.png';
      final fileName = pickedFile.name.trim().isEmpty
          ? fallbackName
          : pickedFile.name.trim();

      final storedName = await _noteService.saveMedia(
        fileName: fileName,
        bytes: bytes,
      );
      final encodedName = Uri.encodeComponent(storedName);
      _insertTextAtSelection('![$storedName](media://$encodedName)');
      _showMessage(context.t.common.success);
    } catch (_) {
      _showMessage(context.t.common.error);
    }
  }

  Future<bool> _insertImageFromClipboard() async {
    if (_isPastingImage) {
      Logger.d('skip paste: already processing', tag: _logTag);
      return false;
    }
    _isPastingImage = true;
    try {
      Logger.d('reading image bytes from clipboard...', tag: _logTag);
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        Logger.w('clipboard has no image bytes', tag: _logTag);
        return false;
      }
      Logger.i('clipboard image bytes=${bytes.length}', tag: _logTag);

      final fileName = 'paste_${DateTime.now().millisecondsSinceEpoch}.png';
      final storedName = await _noteService.saveMedia(
        fileName: fileName,
        bytes: bytes,
      );
      Logger.i('clipboard image saved as $storedName', tag: _logTag);
      final encodedName = Uri.encodeComponent(storedName);
      _insertTextAtSelection('![$storedName](media://$encodedName)');
      _showMessage(context.t.common.success);
      Logger.i('markdown image inserted from clipboard', tag: _logTag);
      return true;
    } catch (e, stackTrace) {
      Logger.e(
        'clipboard image paste failed: $e',
        tag: _logTag,
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _isPastingImage = false;
    }
  }

  bool get _supportsClipboardImagePaste =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    final keyLabel = event.logicalKey.keyLabel;
    Logger.d(
      'key event: down=$isDown up=$isUp key="$keyLabel" ctrl=${HardwareKeyboard.instance.isControlPressed} meta=${HardwareKeyboard.instance.isMetaPressed}',
      tag: _logTag,
    );

    if (!_supportsClipboardImagePaste) {
      Logger.d('ignored key event: unsupported platform', tag: _logTag);
      return KeyEventResult.ignored;
    }
    // 在某些控件中，KeyDown 可能会被内部消费，只能收到 KeyUp。
    if (event is! KeyDownEvent && event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final isPasteKey = event.logicalKey == LogicalKeyboardKey.keyV;
    final isModifierPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isPasteKey || !isModifierPressed) {
      return KeyEventResult.ignored;
    }

    final now = DateTime.now();
    final tooSoon =
        _lastPasteShortcutTime != null &&
        now.difference(_lastPasteShortcutTime!).inMilliseconds < 300;
    if (tooSoon) {
      Logger.d('skip paste shortcut: debounce window', tag: _logTag);
      return KeyEventResult.ignored;
    }
    _lastPasteShortcutTime = now;

    Logger.i(
      'detected Ctrl/Cmd+V on ${isDown ? 'keydown' : 'keyup'}, trying image paste',
      tag: _logTag,
    );

    _insertImageFromClipboard().then((inserted) {
      Logger.i(
        'clipboard image paste result: inserted=$inserted',
        tag: _logTag,
      );
      if (inserted && mounted) {
        FocusScope.of(
          context,
        ).requestFocus(FocusScope.of(context).focusedChild);
      }
    });
    return KeyEventResult.ignored;
  }

  String _normalizeMarkdownLinks(String markdown) {
    final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)\r\n]+)\)');
    return markdown.replaceAllMapped(linkPattern, (match) {
      final label = match.group(1)!;
      final href = match.group(2)!;
      if (!href.contains(' ')) {
        return match.group(0)!;
      }
      final encodedHref = href.replaceAll(' ', '%20');
      return '[$label]($encodedHref)';
    });
  }

  void _handlePreviewLinkTap(String href) {
    final decoded = Uri.decodeComponent(href);
    Navigator.of(context).pop(false);
    widget.onLinkTap?.call(decoded);
  }

  Future<void> _persistImageWidthPercentInEditor(
    String mediaName,
    int widthPercent,
  ) async {
    final currentText = _controller.text;
    final updatedText = NoteService.upsertMediaWidthPercentInMarkdown(
      markdown: currentText,
      mediaName: mediaName,
      widthPercent: widthPercent,
    );
    if (updatedText == currentText) {
      return;
    }

    _isTrackingChanges = false;
    _controller.text = updatedText;
    _isTrackingChanges = true;

    if (_currentEditPosition < _undoStack.length - 1) {
      _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
    }
    _undoStack.add(updatedText);
    _currentEditPosition = _undoStack.length - 1;
    _redoStack.clear();

    if (mounted) {
      setState(() {});
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

  void _insertTextAtSelection(String insertText) {
    final selection = _controller.selection;
    final startIndex = selection.startIndex;
    final startOffset = selection.startOffset;
    final endIndex = selection.endIndex;
    final endOffset = selection.endOffset;

    _isTrackingChanges = false;

    final fullText = _controller.text;
    final globalStart = _getGlobalOffset(startIndex, startOffset);
    final globalEnd = _getGlobalOffset(endIndex, endOffset);
    _controller.text = fullText.replaceRange(
      globalStart,
      globalEnd,
      insertText,
    );

    final newGlobalOffset = globalStart + insertText.length;
    final (newLineIndex, newLineOffset) = _getLinePosition(newGlobalOffset);
    _controller.selection = CodeLineSelection.collapsed(
      index: newLineIndex,
      offset: newLineOffset,
    );

    _isTrackingChanges = true;

    if (_currentEditPosition < _undoStack.length - 1) {
      _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
    }
    _undoStack.add(_controller.text);
    _currentEditPosition = _undoStack.length - 1;
    _redoStack.clear();
    setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    return (
      codeLines.length - 1,
      codeLines.isEmpty ? 0 : codeLines.last.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noteFontSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 15;
    final previewBackground = colorScheme.surface;

    return Focus(
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: _onKeyEvent,
      child: DraggableScrollableSheet(
        initialChildSize: _isFullScreen ? 1.0 : 0.7,
        minChildSize: _isFullScreen ? 1.0 : 0.5,
        maxChildSize: _isFullScreen
            ? 1.0
            : availableHeightRatio(
                totalHeight: screenSize.height,
                reservedTop: topInsetWithMargin(widget.statusBarHeight),
              ),
        expand: false,
        builder: (context, scrollController) {
          return Container(
            width: _isFullScreen ? screenSize.width : null,
            padding: EdgeInsets.only(
              top: _isFullScreen
                  ? topInsetWithMargin(widget.statusBarHeight)
                  : 16,
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
                            onPressed:
                                _currentEditPosition < _undoStack.length - 1
                                ? _redo
                                : null,
                            tooltip: context.t.common.redo,
                          ),
                          _buildToolbarButton(
                            icon: Icons.image_outlined,
                            onPressed: _insertImageFromPicker,
                            tooltip: context.t.common.upload,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _togglePreviewMode,
                            icon: Icon(
                              _isPreviewMode ? Icons.edit_note : Icons.preview,
                              size: 20,
                            ),
                            tooltip: context.t.note.preview,
                          ),
                          // 全屏
                          IconButton(
                            onPressed: () =>
                                setState(() => _isFullScreen = !_isFullScreen),
                            icon: Icon(
                              _isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
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
                      const SizedBox(height: 8),
                      // 编辑器 / 预览
                      Expanded(
                        child: _isPreviewMode
                            ? Container(
                                decoration: BoxDecoration(
                                  color: previewBackground,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withOpacity(0.5),
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minWidth: constraints.maxWidth,
                                        ),
                                        child: _controller.text.trim().isEmpty
                                            ? SizedBox(
                                                height: 220,
                                                child: Center(
                                                  child: Text(
                                                    context.t.note.previewEmpty,
                                                    style: TextStyle(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: noteFontSize,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : MarkdownBody(
                                                data: _normalizeMarkdownLinks(
                                                  _controller.text,
                                                ),
                                                styleSheet: MarkdownStyleSheet(
                                                  p: TextStyle(
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontSize: noteFontSize,
                                                  ),
                                                  a: TextStyle(
                                                    color: colorScheme.primary,
                                                    fontSize: noteFontSize,
                                                  ),
                                                ),
                                                imageBuilder:
                                                    (
                                                      uri,
                                                      title,
                                                      alt,
                                                    ) => NoteMarkdownMediaImage(
                                                      uri: uri,
                                                      altText: alt,
                                                      onWidthPercentResolved:
                                                          _persistImageWidthPercentInEditor,
                                                    ),
                                                onTapLink: (text, href, title) {
                                                  if (href != null) {
                                                    _handlePreviewLinkTap(href);
                                                  }
                                                },
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: previewBackground,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withOpacity(0.5),
                                  ),
                                ),
                                child: CodeEditor(
                                  controller: _controller,
                                  style: CodeEditorStyle(
                                    fontSize: noteFontSize,
                                    fontFamily: 'monospace',
                                    backgroundColor: previewBackground,
                                    codeTheme: CodeHighlightTheme(
                                      languages: {
                                        'markdown': CodeHighlightThemeMode(
                                          mode: langMarkdown,
                                        ),
                                      },
                                      theme: isDark
                                          ? builtThemes['atom-one-dark']!
                                          : builtThemes['atom-one-light']!,
                                    ),
                                  ),
                                  wordWrap: true,
                                  indicatorBuilder:
                                      (
                                        context,
                                        editingController,
                                        chunkController,
                                        notifier,
                                      ) {
                                        return const SizedBox.shrink();
                                      },
                                ),
                              ),
                      ),
                    ],
                  ),
          );
        },
      ),
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
        color:
            color ??
            (onPressed != null
                ? colorScheme.onSurfaceVariant
                : colorScheme.outline),
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
