import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../i18n/strings.g.dart';
import '../core/utils/scroll_safe_utils.dart';
import '../core/utils/markdown_style_sheet.dart';
import '../services/note_service.dart';
import '../services/preferences_service.dart';
import 'note_markdown_media_image.dart';
import 're_editor_selection_toolbar.dart';

enum _UnsavedCloseAction { save, discard }

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
      enableDrag: false,
      showDragHandle: false,
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
  final NoteService _noteService = NoteService();
  final PreferencesService _preferencesService = PreferencesService();
  late CodeLineEditingController _controller;
  SelectionToolbarController? _toolbarController;
  String _savedText = '';
  bool _isLoading = true;
  bool _isFullScreen = false;
  bool _isPreviewMode = false;
  bool _hasSavedDuringSession = false; // 跟踪本次编辑会话是否保存过笔记
  bool _isDraggingImage = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _isTrackingChanges = true;
  late final bool Function(KeyEvent event) _keyboardSaveHandler;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _toolbarController = buildReEditorSelectionToolbarController();
    _keyboardSaveHandler = _handleGlobalKeyEvent;
    HardwareKeyboard.instance.addHandler(_keyboardSaveHandler);
    _loadInitialState();
  }

  bool _isSaveShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final isSKey = event.logicalKey == LogicalKeyboardKey.keyS;
    final keyboard = HardwareKeyboard.instance;
    final hasModifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    return isSKey && hasModifier;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (_isSaveShortcut(event)) {
      _save();
      return true;
    }

    return false;
  }

  Future<void> _handlePasteShortcut() async {
    if (_isPreviewMode) {
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final fileName =
            'clipboard_${DateTime.now().millisecondsSinceEpoch}.png';
        final storedName = await _noteService.saveMedia(
          fileName: fileName,
          bytes: imageBytes,
        );
        final encodedName = Uri.encodeComponent(storedName);
        _insertTextAtSelection('![$storedName](media://$encodedName)');
        return;
      }
    } catch (_) {
      // Ignore clipboard image errors and continue with other clipboard formats.
    }

    try {
      final filePaths = await Pasteboard.files();
      if (filePaths.isNotEmpty) {
        var insertedCount = 0;
        for (final filePath in filePaths) {
          if (!_isImageFile(filePath)) {
            continue;
          }

          final file = File(filePath);
          if (!await file.exists()) {
            continue;
          }

          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) {
            continue;
          }

          final nameFromPath = filePath.split(RegExp(r'[\\/]')).last;
          await _insertImageBytesToEditor(bytes: bytes, fileName: nameFromPath);
          insertedCount++;
        }

        if (insertedCount > 0) {
          return;
        }
      }
    } catch (_) {
      // Ignore clipboard file errors and fallback to plain text paste.
    }

    _controller.paste();
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
    _savedText = content;
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
    final previousText = _undoStack.isNotEmpty
        ? _undoStack[_currentEditPosition]
        : '';

    // 检测并自动转换新插入的图片URL
    if (currentText.length > previousText.length) {
      final insertedDiff = currentText.length - previousText.length;
      // 只有插入量合理（可能是粘贴的URL）才检查
      if (insertedDiff <= 500) {
        _autoConvertImageUrl(previousText, currentText);
      }
    }

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

  /// 检测新插入的图片URL并自动转换为Markdown格式
  void _autoConvertImageUrl(String previousText, String currentText) {
    if (previousText == currentText) {
      return;
    }

    // 仅分析本次编辑实际变更的区间，避免同 URL 多次粘贴时被旧内容误判。
    int prefixLen = 0;
    final minLength = previousText.length < currentText.length
        ? previousText.length
        : currentText.length;
    while (prefixLen < minLength &&
        previousText.codeUnitAt(prefixLen) ==
            currentText.codeUnitAt(prefixLen)) {
      prefixLen++;
    }

    int suffixLen = 0;
    while (suffixLen < (previousText.length - prefixLen) &&
        suffixLen < (currentText.length - prefixLen) &&
        previousText.codeUnitAt(previousText.length - 1 - suffixLen) ==
            currentText.codeUnitAt(currentText.length - 1 - suffixLen)) {
      suffixLen++;
    }

    final changedStart = prefixLen;
    final changedEnd = currentText.length - suffixLen;
    if (changedEnd <= changedStart) {
      return;
    }

    final changedText = currentText.substring(changedStart, changedEnd);
    final urlPattern = RegExp(r'(https?://[^\s\)]+)', caseSensitive: false);
    final matches = urlPattern.allMatches(changedText);

    for (final match in matches) {
      final url = match.group(1)!;
      // 检查是否是图片URL
      if (!_isImageUrl(url)) continue;

      final startIndex = changedStart + match.start;
      final endIndex = changedStart + match.end;

      // 检查是否已经被Markdown图片语法包裹
      // 查找匹配位置前后是否有 ![...](...)
      // 检查前面是否有 ![...](
      final beforeText = currentText.substring(0, startIndex);
      if (beforeText.contains(RegExp(r'!\[[^\]]*\]\($'))) continue;

      // 检查后面是否有 )
      final afterText = currentText.substring(endIndex);
      if (afterText.startsWith(')')) continue;

      // 找到了未被包裹的图片URL，转换为Markdown格式
      final newText = currentText.replaceRange(
        startIndex,
        endIndex,
        '![picture]($url)',
      );
      if (newText != currentText) {
        _isTrackingChanges = false;
        _controller.text = newText;
        _isTrackingChanges = true;
        // 更新撤销栈中的最新文本
        if (_undoStack.isNotEmpty) {
          _undoStack[_currentEditPosition] = newText;
        }
        setState(() {});
      }
      return; // 只处理第一个，避免多次触发
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

  Future<bool> _save({bool closeAfterSave = false}) async {
    final content = _controller.text;
    try {
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

      if (!mounted) {
        return true;
      }

      setState(() {
        _savedText = content;
        _hasSavedDuringSession = true;
      });

      if (_undoStack.isNotEmpty) {
        _undoStack[_currentEditPosition] = content;
      }

      if (closeAfterSave) {
        Navigator.of(context).pop(true);
      }
      return true;
    } catch (_) {
      if (mounted) {
        _showMessage(context.t.entry.saveFailed(error: context.t.common.error));
      }
      return false;
    }
  }

  bool get _hasUnsavedChanges => _controller.text != _savedText;

  Future<_UnsavedCloseAction?> _showUnsavedCloseDialog() {
    return showDialog<_UnsavedCloseAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(context.t.common.unsavedChangesTitle)),
              IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
                tooltip: context.t.common.continueEditing,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          content: Text(context.t.common.unsavedChangesMessage),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.discard),
              child: Text(context.t.common.discard),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedCloseAction.save),
              child: Text(context.t.common.save),
            ),
          ],
        );
      },
    );
  }

  Future<void> _attemptClose() async {
    if (!_hasUnsavedChanges) {
      if (mounted) {
        // 如果本次编辑会话曾保存过笔记，返回 true 以触发笔记面板刷新
        Navigator.pop(context, _hasSavedDuringSession);
      }
      return;
    }

    final action = await _showUnsavedCloseDialog();
    if (!mounted) return;

    if (action == _UnsavedCloseAction.save) {
      await _save(closeAfterSave: true);
      return;
    }

    if (action == _UnsavedCloseAction.discard) {
      Navigator.pop(context, _hasSavedDuringSession);
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
      await _insertImageBytesToEditor(bytes: bytes, fileName: fileName);
    } catch (_) {}
  }

  Future<void> _insertImageBytesToEditor({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final normalizedName = fileName.trim().isEmpty
        ? 'image_${DateTime.now().millisecondsSinceEpoch}.png'
        : fileName.trim();
    final storedName = await _noteService.saveMedia(
      fileName: normalizedName,
      bytes: bytes,
    );
    final encodedName = Uri.encodeComponent(storedName);
    _insertTextAtSelection('![$storedName](media://$encodedName)');
  }

  bool _isImageFile(String nameOrPath) {
    final lower = nameOrPath.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  Future<void> _handleDroppedFiles(List<DropItem> files) async {
    if (_isPreviewMode || files.isEmpty) {
      return;
    }

    var insertedCount = 0;
    try {
      for (final file in files) {
        final path = file.path;
        final candidateName = file.name.trim().isNotEmpty
            ? file.name
            : path.split(RegExp(r'[\\/]')).last;
        final imageLike =
            _isImageFile(candidateName) ||
            (path.isNotEmpty && _isImageFile(path));
        if (!imageLike) {
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          continue;
        }

        await _insertImageBytesToEditor(bytes: bytes, fileName: candidateName);
        insertedCount++;
      }
    } catch (_) {}
  }

  /// 检查文本是否是图片URL
  bool _isImageUrl(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  Widget _buildCodeEditorWithPasteOverride(
    ColorScheme colorScheme,
    Color previewBackground,
    double noteFontSize,
    bool isDark,
  ) {
    return CodeEditor(
      controller: _controller,
      toolbarController: _toolbarController,
      shortcutOverrideActions: {
        CodeShortcutPasteIntent: CallbackAction<CodeShortcutPasteIntent>(
          onInvoke: (_) {
            _handlePasteShortcut();
            return null;
          },
        ),
      },
      style: CodeEditorStyle(
        fontSize: noteFontSize,
        fontFamily: 'monospace',
        backgroundColor: previewBackground,
        codeTheme: CodeHighlightTheme(
          languages: {'markdown': CodeHighlightThemeMode(mode: langMarkdown)},
          theme: isDark
              ? builtThemes['atom-one-dark']!
              : builtThemes['atom-one-light']!,
        ),
      ),
      wordWrap: true,
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return const SizedBox.shrink();
          },
    );
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
    if (!mounted) {
      return;
    }
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
    final isDesktop = Theme.of(context).platform.isDesktopLike;
    final noteFontSize = (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 15) + 1.5;
    final previewBackground = colorScheme.surface;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _attemptClose();
      },
      child: Shortcuts(
        shortcuts: {
          // Ctrl+Z / Cmd+Z 撤销
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyZ,
          ): const _UndoIntent(),
          // Ctrl+Shift+Z / Cmd+Shift+Z 重做
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ,
          ): const _RedoIntent(),
          // Ctrl+Y / Cmd+Y 重做 (备选)
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyY,
          ): const _RedoIntent(),
          // Ctrl+S / Cmd+S 保存
          LogicalKeySet(
            Platform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyS,
          ): const _SaveIntent(),
        },
        child: Actions(
          actions: {
            _UndoIntent: CallbackAction<_UndoIntent>(
              onInvoke: (_) {
                _undo();
                return null;
              },
            ),
            _RedoIntent: CallbackAction<_RedoIntent>(
              onInvoke: (_) {
                _redo();
                return null;
              },
            ),
            _SaveIntent: CallbackAction<_SaveIntent>(
              onInvoke: (_) {
                _save();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            child: DraggableScrollableSheet(
              initialChildSize: _isFullScreen ? 1.0 : 0.7,
              minChildSize: _isFullScreen ? 1.0 : 0.5,
              maxChildSize: _isFullScreen
                  ? 1.0
                  : availableHeightRatio(
                      totalHeight: screenSize.height,
                      reservedTop: topInsetWithMargin(widget.statusBarHeight),
                    ),
              shouldCloseOnMinExtent: false,
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
                                _buildToolbarButton(
                                  icon: Icons.save_outlined,
                                  onPressed: () => _save(),
                                  tooltip: context.t.common.save,
                                  color: _hasUnsavedChanges
                                      ? null
                                      : Theme.of(context).colorScheme.outline,
                                ),
                                // 撤销
                                _buildToolbarButton(
                                  icon: Icons.undo,
                                  onPressed: _currentEditPosition > 0
                                      ? _undo
                                      : null,
                                  tooltip: context.t.common.undo,
                                ),
                                // 重做
                                _buildToolbarButton(
                                  icon: Icons.redo,
                                  onPressed:
                                      _currentEditPosition <
                                          _undoStack.length - 1
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
                                    _isPreviewMode
                                        ? Icons.edit_note
                                        : Icons.preview,
                                    size: 20,
                                  ),
                                  tooltip: context.t.note.preview,
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: isDesktop
                                      ? VisualDensity.standard
                                      : VisualDensity.compact,
                                ),
                                // 全屏
                                IconButton(
                                  onPressed: () => setState(
                                    () => _isFullScreen = !_isFullScreen,
                                  ),
                                  icon: Icon(
                                    _isFullScreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    size: 20,
                                  ),
                                  tooltip: _isFullScreen
                                      ? context.t.common.exitFullscreen
                                      : context.t.common.fullscreen,
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: isDesktop
                                      ? VisualDensity.standard
                                      : VisualDensity.compact,
                                ),
                                // 关闭
                                IconButton(
                                  onPressed: _attemptClose,
                                  icon: const Icon(Icons.close, size: 20),
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: isDesktop
                                      ? VisualDensity.standard
                                      : VisualDensity.compact,
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
                                          return _controller.text.trim().isEmpty
                                              ? Center(
                                                  child: Text(
                                                    context.t.note.previewEmpty,
                                                    style: TextStyle(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: noteFontSize,
                                                    ),
                                                  ),
                                                )
                                              : SingleChildScrollView(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      minWidth:
                                                          constraints.maxWidth,
                                                    ),
                                                    child: MarkdownBody(
                                                      data:
                                                          _normalizeMarkdownLinks(
                                                            _controller.text,
                                                          ),
                                                      styleSheet:
                                                          buildMarkdownStyleSheet(
                                                            context,
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
                                                      onTapLink:
                                                          (text, href, title) {
                                                            if (href != null) {
                                                              _handlePreviewLinkTap(
                                                                href,
                                                              );
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
                                      child: DropTarget(
                                        onDragEntered: (_) {
                                          if (!_isPreviewMode && mounted) {
                                            setState(
                                              () => _isDraggingImage = true,
                                            );
                                          }
                                        },
                                        onDragExited: (_) {
                                          if (mounted) {
                                            setState(
                                              () => _isDraggingImage = false,
                                            );
                                          }
                                        },
                                        onDragDone: (detail) async {
                                          if (mounted) {
                                            setState(
                                              () => _isDraggingImage = false,
                                            );
                                          }
                                          await _handleDroppedFiles(
                                            detail.files,
                                          );
                                        },
                                        child: Stack(
                                          children: [
                                            _buildCodeEditorWithPasteOverride(
                                              colorScheme,
                                              previewBackground,
                                              noteFontSize,
                                              isDark,
                                            ),
                                            if (_controller.text.trim().isEmpty)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: Center(
                                                    child: Text(
                                                      context.t.note.editorHint,
                                                      style: TextStyle(
                                                        color: colorScheme
                                                            .onSurfaceVariant
                                                            .withOpacity(0.5),
                                                        fontSize: noteFontSize,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (_isDraggingImage)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: colorScheme.primary
                                                          .withOpacity(0.1),
                                                      border: Border.all(
                                                        color:
                                                            colorScheme.primary,
                                                        width: 1.5,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Icon(
                                                      Icons.add_photo_alternate,
                                                      color:
                                                          colorScheme.primary,
                                                      size: 28,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
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
    final isDesktop = Theme.of(context).platform.isDesktopLike;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        color:
            color ??
            (onPressed != null ? colorScheme.primary : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      visualDensity: isDesktop ? VisualDensity.standard : VisualDensity.compact,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyboardSaveHandler);
    _controller.dispose();
    super.dispose();
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

extension on TargetPlatform {
  bool get isDesktopLike =>
      this == TargetPlatform.windows ||
      this == TargetPlatform.macOS ||
      this == TargetPlatform.linux;
}
