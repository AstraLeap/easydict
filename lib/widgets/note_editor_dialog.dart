import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';
import '../services/note_service.dart';

/// 笔记编辑器弹窗
class NoteEditorDialog extends StatefulWidget {
  final String word;
  final String language;
  final String? linkToAppend;

  const NoteEditorDialog({
    super.key,
    required this.word,
    required this.language,
    this.linkToAppend,
  });

  /// 显示笔记编辑器弹窗
  static Future<bool> show(
    BuildContext context, {
    required String word,
    required String language,
    String? linkToAppend,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => NoteEditorDialog(
        word: word,
        language: language,
        linkToAppend: linkToAppend,
      ),
    );
    return result ?? false;
  }

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  final NoteService _noteService = NoteService();
  late TextEditingController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
    setState(() {
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.note_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(context.t.note.title),
          const Spacer(),
          Text(
            widget.word,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              width: 400,
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: 500,
              height: 400,
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: context.t.note.placeholder,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLowest,
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: Text(context.t.common.save),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
