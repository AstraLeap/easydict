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
  final int refreshVersion;  // 刷新版本号，变化时重新加载内容
  final void Function(String path)? onLinkTap;

  const NotePanel({
    super.key,
    required this.word,
    required this.language,
    this.initiallyExpanded = true,
    this.refreshVersion = 0,
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
  int _loadedRefreshVersion = -1;
  bool _hasInitializedExpanded = false;  // 标记是否已初始化展开状态

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void didUpdateWidget(NotePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 refreshVersion 变化时，重新加载笔记内容
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadedWord = '';  // 重置以允许重新加载
      _loadNote();
    }
  }

  Future<void> _loadNote() async {
    // 防止重复加载（同一个单词且同一个刷新版本）
    final loadKey = '${widget.word}_${widget.language}_${widget.refreshVersion}';
    if (_loadedWord == loadKey) {
      return;
    }

    final note = await _noteService.getNote(widget.word, widget.language);
    if (mounted) {
      setState(() {
        _note = note;
        _isLoading = false;
        _loadedWord = loadKey;
        // 只在首次加载时设置展开状态
        if (!_hasInitializedExpanded) {
          _isExpanded = widget.initiallyExpanded;
          _hasInitializedExpanded = true;
        }
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
      onLinkTap: _handleLinkTap,
    );
    if (result && mounted) {
      // 重新加载笔记
      _loadedWord = '';  // 重置以允许重新加载
      await _loadNote();
    }
  }

  void _handleLinkTap(String href) {
    widget.onLinkTap?.call(href);
  }

  /// Encode whitespace in markdown link destinations so markdown parser
  /// treats links with spaces (e.g. `More examples`) as valid hrefs.
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
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
                    Icons.sticky_note_2_outlined,
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
    final normalizedContent = _normalizeMarkdownLinks(_note?.content ?? '');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        data: normalizedContent,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: colorScheme.onSurface),
          a: TextStyle(color: colorScheme.primary),
        ),
        onTapLink: (text, href, title) {
          if (href != null) {
            _handleLinkTap(href);
          }
        },
      ),
    );
  }
}
