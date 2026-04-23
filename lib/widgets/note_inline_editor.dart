import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../i18n/strings.g.dart';
import '../core/utils/markdown_style_sheet.dart';
import '../core/theme/app_theme.dart';
import '../services/note_service.dart';
import '../services/preferences_service.dart';
import 'note_markdown_media_image.dart';

/// 内嵌笔记编辑器
/// 支持编辑/预览模式切换，复用 NoteEditorBottomSheet 的核心逻辑
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
  late TextEditingController _controller;
  String _savedText = '';
  bool _isPreviewMode = false;
  bool _isLoading = true;
  bool _isDraggingImage = false;

  // 撤销/重做栈
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _isTrackingChanges = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
    _redoStack.clear();
    setState(() {});
  }

  void _undo() {
    if (_currentEditPosition > 0) {
      setState(() {
        _currentEditPosition--;
        _isTrackingChanges = false;
        _controller.text = _undoStack[_currentEditPosition];
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
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
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
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
    _redoStack.clear();
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
    final insertText = '![$storedName](media://$encodedName)';

    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      insertText,
    );
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: selection.start + insertText.length,
    );
    setState(() {});
  }

  Future<void> _handlePaste() async {
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
        _insertText('![$storedName](media://$encodedName)');
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
  }

  void _insertText(String insertText) {
    final text = _controller.text;
    final selection = _controller.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      insertText,
    );
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: selection.start + insertText.length,
    );
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

  @override
  void dispose() {
    _controller.removeListener(_trackChanges);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteFontSize = (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 15) + 1.5;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Shortcuts(
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
                const SizedBox(width: 8),
                _buildToolbarButton(
                  icon: Icons.undo,
                  onPressed: _currentEditPosition > 0 ? _undo : null,
                  tooltip: context.t.common.undo,
                ),
                const SizedBox(width: 8),
                _buildToolbarButton(
                  icon: Icons.redo,
                  onPressed:
                      _currentEditPosition < _undoStack.length - 1
                          ? _redo
                          : null,
                  tooltip: context.t.common.redo,
                ),
                const SizedBox(width: 8),
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
                                  styleSheet: buildMarkdownStyleSheet(context),
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
                        TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.all(12),
                            border: InputBorder.none,
                            hintText: context.t.note.placeholder,
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant
                                  .withOpacity(0.5),
                              fontSize: noteFontSize,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: noteFontSize,
                            fontFamily: 'monospace',
                            fontFamilyFallback: AppTheme.fontFamilyFallback,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_isDraggingImage)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withOpacity(0.1),
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
        color: color ?? (onPressed != null ? colorScheme.primary : colorScheme.outline),
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
