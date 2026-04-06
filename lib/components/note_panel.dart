import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../i18n/strings.g.dart';
import '../services/note_service.dart';

/// 笔记面板组件
class NotePanel extends StatefulWidget {
  final String word;
  final String language;
  final bool initiallyExpanded;
  final void Function(String path)? onLinkTap;

  const NotePanel({
    super.key,
    required this.word,
    required this.language,
    this.initiallyExpanded = true,
    this.onLinkTap,
  });

  @override
  State<NotePanel> createState() => _NotePanelState();
}

class _NotePanelState extends State<NotePanel> {
  final NoteService _noteService = NoteService();
  Note? _note;
  bool _isExpanded = true;
  bool _isEditing = false;
  late TextEditingController _editingController;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _editingController = TextEditingController();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final note = await _noteService.getNote(widget.word, widget.language);
    if (mounted) {
      setState(() {
        _note = note;
        if (note != null) {
          _editingController.text = note.content;
        }
      });
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editingController.text = _note?.content ?? '';
    });
  }

  Future<void> _saveNote() async {
    final content = _editingController.text;
    final note = Note(
      word: widget.word,
      language: widget.language,
      content: content,
      createdAt: _note?.createdAt,
    );
    await _noteService.saveNote(note);
    setState(() {
      _note = note;
      _isEditing = false;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingController.text = _note?.content ?? '';
    });
  }

  void _handleLinkTap(String href) {
    // 解析 entry://dictId/entryId/json.path
    if (href.startsWith('entry://')) {
      final path = href.substring(8); // 移除 "entry://" 前缀
      widget.onLinkTap?.call(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有笔记且未编辑，不显示面板
    if (_note == null || _note!.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.note_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.t.note.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (!_isEditing) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _startEditing,
                      tooltip: context.t.note.edit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // 内容区域
          if (_isExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withOpacity(0.3),
            ),
            if (_isEditing)
              _buildEditingView(colorScheme)
            else
              _buildMarkdownView(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkdownView(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        data: _note?.content ?? '',
        onTapLink: (text, href, title) {
          if (href != null) {
            _handleLinkTap(href);
          }
        },
      ),
    );
  }

  Widget _buildEditingView(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _editingController,
            maxLines: null,
            minLines: 3,
            decoration: InputDecoration(
              hintText: context.t.note.placeholder,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: colorScheme.surface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelEditing,
                child: Text(context.t.common.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveNote,
                child: Text(context.t.common.save),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }
}
