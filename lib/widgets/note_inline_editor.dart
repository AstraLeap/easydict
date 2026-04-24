import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/styles/all.dart' show builtThemes;
import '../i18n/strings.g.dart';
import '../core/utils/markdown_style_sheet.dart';
import '../core/theme/app_theme.dart';
import '../services/note_service.dart';
import '../services/preferences_service.dart';
import 'note_markdown_media_image.dart';
import 're_editor_selection_toolbar.dart';

/// 内嵌笔记编辑器
/// 使用 re_editor 实现 Markdown 语法高亮编辑 + 预览模式切换
class NoteInlineEditor extends StatefulWidget {
  final String word;
  final String language;
  final String? initialContent;
  final VoidCallback? onSaved;
  final void Function(String path)? onLinkTap;

  const NoteInlineEditor({
    super.key,
    required this.word,
    required this.language,
    this.initialContent,
    this.onSaved,
    this.onLinkTap,
  });

  @override
  State<NoteInlineEditor> createState() => _NoteInlineEditorState();
}

class _NoteInlineEditorState extends State<NoteInlineEditor> {
  final NoteService _noteService = NoteService();
  final PreferencesService _preferencesService = PreferencesService();
  late CodeLineEditingController _controller;
  SelectionToolbarController? _toolbarController;
  String _savedText = '';
  bool _isPreviewMode = false;
  bool _isLoading = true;
  bool _isDraggingImage = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  int _currentEditPosition = 0;
  bool _isTrackingChanges = true;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _toolbarController = buildReEditorSelectionToolbarController();
    _controller.addListener(_trackChanges);
    _loadContent();
  }

  @override
  void didUpdateWidget(covariant NoteInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word ||
        oldWidget.language != widget.language) {
      _loadContent();
    }
  }

  void _trackChanges() {
    if (!_isTrackingChanges) return;

    final currentText = _controller.text;
    if (_undoStack.isNotEmpty &&
        _undoStack[_currentEditPosition] == currentText) {
      return;
    }

    if (_currentEditPosition < _undoStack.length - 1) {
      _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
    }
    _undoStack.add(currentText);
    _currentEditPosition = _undoStack.length - 1;
    setState(() {});
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

  Future<void> _loadContent() async {
    final previewMode = await _preferencesService.getNoteEditorPreviewMode();
    final note = await _noteService.getNote(widget.word, widget.language);
    final content = note?.content ?? widget.initialContent ?? '';

    _controller.text = content;
    _savedText = content;
    _undoStack.clear();
    _undoStack.add(content);
    _currentEditPosition = 0;
    if (mounted) {
      setState(() {
        _isPreviewMode = previewMode;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
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

      if (!mounted) return;
      setState(() {
        _savedText = content;
      });
      widget.onSaved?.call();
    } catch (_) {
      // ignore
    }
  }

  bool get _hasUnsavedChanges => _controller.text != _savedText;

  Future<void> _togglePreviewMode() async {
    final newValue = !_isPreviewMode;
    setState(() {
      _isPreviewMode = newValue;
    });
    await _preferencesService.setNoteEditorPreviewMode(newValue);
    if (!_isPreviewMode) {
      await _save();
    }
  }

  Future<void> _insertImageFromPicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      Uint8List? bytes = pickedFile.bytes;
      final path = pickedFile.path;
      if ((bytes == null || bytes.isEmpty) && path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) return;

      final fallbackName = 'image_${DateTime.now().millisecondsSinceEpoch}.png';
      final fileName = pickedFile.name.trim().isEmpty
          ? fallbackName
          : pickedFile.name.trim();
      await _insertImageBytes(bytes: bytes, fileName: fileName);
    } catch (_) {}
  }

  Future<void> _insertImageBytes({
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

  Future<void> _handlePaste() async {
    if (_isPreviewMode) return;

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
    } catch (_) {}

    try {
      final filePaths = await Pasteboard.files();
      if (filePaths.isNotEmpty) {
        for (final filePath in filePaths) {
          if (!_isImageFile(filePath)) continue;
          final file = File(filePath);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) continue;
          final nameFromPath = filePath.split(RegExp(r'[\/]')).last;
          await _insertImageBytes(bytes: bytes, fileName: nameFromPath);
        }
        return;
      }
    } catch (_) {}

    _controller.paste();
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
    setState(() {});
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
    if (_isPreviewMode || files.isEmpty) return;
    for (final file in files) {
      final path = file.path;
      final candidateName = file.name.trim().isNotEmpty
          ? file.name
          : path.split(RegExp(r'[\/]')).last;
      final imageLike = _isImageFile(candidateName) ||
          (path.isNotEmpty && _isImageFile(path));
      if (!imageLike) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      await _insertImageBytes(bytes: bytes, fileName: candidateName);
    }
    if (mounted) {
      setState(() => _isDraggingImage = false);
    }
  }

  String _normalizeMarkdownLinks(String markdown) {
    final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)\r\n]+)\)');
    return markdown.replaceAllMapped(linkPattern, (match) {
      final label = match.group(1)!;
      final href = match.group(2)!;
      if (!href.contains(' ')) return match.group(0)!;
      final encodedHref = href.replaceAll(' ', '%20');
      return '[$label]($encodedHref)';
    });
  }

  void _handlePreviewLinkTap(String href) {
    final decoded = Uri.decodeComponent(href);
    widget.onLinkTap?.call(decoded);
  }

  Future<void> _persistImageWidthPercent(
    String mediaName,
    int widthPercent,
  ) async {
    final currentText = _controller.text;
    final updatedText = NoteService.upsertMediaWidthPercentInMarkdown(
      markdown: currentText,
      mediaName: mediaName,
      widthPercent: widthPercent,
    );
    if (updatedText == currentText) return;
    _controller.text = updatedText;
    setState(() {});
    await _save();
  }

  int _getGlobalOffset(int lineIndex, int lineOffset) {
    final codeLines = _controller.codeLines;
    int offset = 0;
    for (int i = 0; i < lineIndex && i < codeLines.length; i++) {
      offset += codeLines[i].text.length + 1; // +1 for newline
    }
    return offset + lineOffset;
  }

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
  void dispose() {
    _controller.removeListener(_trackChanges);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noteFontSize =
        (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 15) + 1.5;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(
          Platform.isMacOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyZ,
        ): const _UndoIntent(),
        LogicalKeySet(
          Platform.isMacOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ): const _RedoIntent(),
        LogicalKeySet(
          Platform.isMacOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyY,
        ): const _RedoIntent(),
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
        },
        child: Column(
          children: [
            // 工具栏
            Row(
              children: [
                _buildToolbarButton(
                  icon: Icons.save_outlined,
                  onPressed: _save,
                  tooltip: context.t.common.save,
                  color: _hasUnsavedChanges
                      ? null
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                _buildToolbarButton(
                  icon: Icons.undo,
                  onPressed: _currentEditPosition > 0 ? _undo : null,
                  tooltip: context.t.common.undo,
                ),
                const SizedBox(width: 4),
                _buildToolbarButton(
                  icon: Icons.redo,
                  onPressed: _currentEditPosition < _undoStack.length - 1
                      ? _redo
                      : null,
                  tooltip: context.t.common.redo,
                ),
                const SizedBox(width: 4),
                _buildToolbarButton(
                  icon: Icons.image_outlined,
                  onPressed: _insertImageFromPicker,
                  tooltip: context.t.common.upload,
                ),
                const Spacer(),
                _buildToolbarButton(
                  icon: _isPreviewMode ? Icons.edit_note : Icons.preview,
                  onPressed: _togglePreviewMode,
                  tooltip: _isPreviewMode
                      ? context.t.note.editorHint
                      : context.t.note.preview,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 编辑器 / 预览
            Expanded(
              child: _isPreviewMode
                  ? Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return _controller.text.trim().isEmpty
                              ? Center(
                                  child: Text(
                                    context.t.note.previewEmpty,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: noteFontSize,
                                    ),
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: MarkdownBody(
                                      data: _normalizeMarkdownLinks(
                                        _controller.text,
                                      ),
                                      styleSheet: buildMarkdownStyleSheet(
                                        context,
                                        fontSize: noteFontSize,
                                      ),
                                      imageBuilder: (uri, title, alt) =>
                                          NoteMarkdownMediaImage(
                                        uri: uri,
                                        altText: alt,
                                        onWidthPercentResolved:
                                            _persistImageWidthPercent,
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
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: DropTarget(
                        onDragEntered: (_) {
                          if (!_isPreviewMode && mounted) {
                            setState(() => _isDraggingImage = true);
                          }
                        },
                        onDragExited: (_) {
                          if (mounted) {
                            setState(() => _isDraggingImage = false);
                          }
                        },
                        onDragDone: (detail) async {
                          await _handleDroppedFiles(detail.files);
                        },
                        child: Stack(
                          children: [
                            CodeEditor(
                              controller: _controller,
                              toolbarController: _toolbarController,
                              shortcutOverrideActions: {
                                CodeShortcutPasteIntent:
                                    CallbackAction<CodeShortcutPasteIntent>(
                                  onInvoke: (_) {
                                    _handlePaste();
                                    return null;
                                  },
                                ),
                              },
                              style: CodeEditorStyle(
                                fontSize: noteFontSize,
                                fontFamily: 'monospace',
                                fontFamilyFallback:
                                    AppTheme.fontFamilyFallback,
                                backgroundColor: colorScheme.surface,
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
                              padding: const EdgeInsets.all(12),
                              wordWrap: true,
                              indicatorBuilder:
                                  (context, editingController,
                                      chunkController, notifier) {
                                return const SizedBox.shrink();
                              },
                            ),
                            if (_controller.text.trim().isEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        context.t.note.placeholder,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant
                                              .withOpacity(0.5),
                                          fontSize: noteFontSize,
                                        ),
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
                                        color: colorScheme.primary,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.add_photo_alternate,
                                      color: colorScheme.primary,
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
        color: color ??
            (onPressed != null
                ? colorScheme.primary
                : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: const EdgeInsets.all(8),
      visualDensity: VisualDensity.standard,
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}
