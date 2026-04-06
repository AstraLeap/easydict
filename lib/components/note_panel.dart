import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../i18n/strings.g.dart';
import '../services/note_service.dart';
import '../widgets/note_editor_bottom_sheet.dart';

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
  bool _isLoading = true;
  String _loadedWord = '';

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _loadNote();
  }

  Future<void> _loadNote() async {
    // 防止重复加载同一个单词
    if (_loadedWord == '${widget.word}_${widget.language}') {
      return;
    }

    final note = await _noteService.getNote(widget.word, widget.language);
    if (mounted) {
      setState(() {
        _note = note;
        _isLoading = false;
        _loadedWord = '${widget.word}_${widget.language}';
      });
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  Future<void> _startEditing() async {
    // 使用底部弹窗编辑
    final result = await NoteEditorBottomSheet.show(
      context,
      word: widget.word,
      language: widget.language,
    );
    if (result && mounted) {
      // 重新加载笔记
      _loadedWord = '';  // 重置以允许重新加载
      await _loadNote();
    }
  }

  void _handleLinkTap(String href) {
    // 解析链接格式: dictId/entryId/json.path
    // 检查是否是内部链接格式（包含至少两个斜杠分隔的部分）
    final parts = href.split('/');
    if (parts.length >= 2) {
      widget.onLinkTap?.call(href);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果正在加载，显示加载指示器
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    // 如果没有笔记，不显示面板
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
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: _startEditing,
                    tooltip: context.t.note.edit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
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

  @override
  void dispose() {
    super.dispose();
  }
}
