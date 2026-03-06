import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/database_service.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';

/// 表示 JSON 编辑器中可折叠的行范围。
class _FoldRange {
  final int startLine;
  final int endLine;
  const _FoldRange(this.startLine, this.endLine);
}

/// 解析 JSON 文本中匹配括号对形成的折叠范围。
List<_FoldRange> _computeFoldRanges(String text) {
  final lines = text.split('\n');
  final ranges = <_FoldRange>[];
  final stack = <int>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    bool inString = false;
    bool escaped = false;
    for (int j = 0; j < line.length; j++) {
      final ch = line[j];
      if (escaped) { escaped = false; continue; }
      if (ch == '\\' && inString) { escaped = true; continue; }
      if (ch == '"') { inString = !inString; continue; }
      if (inString) continue;
      if (ch == '{' || ch == '[') {
        stack.add(i);
      } else if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty) {
          final startLine = stack.removeLast();
          if (i > startLine + 1) {
            ranges.add(_FoldRange(startLine, i));
          }
        }
      }
    }
  }
  return ranges;
}

/// JSON 编辑器底部弹出面板，用于在词条详情页中直接编辑 JSON 元素
class JsonEditorBottomSheet extends StatefulWidget {
  final DictionaryEntry entry;
  final List<String> pathParts;
  final String initialText;
  final int historyIndex;
  final List<List<String>> pathHistory;
  final List<String>? initialPath;
  final Function(dynamic) onSave;
  final Function(List<String>, dynamic) onNavigate;

  const JsonEditorBottomSheet({
    super.key,
    required this.entry,
    required this.pathParts,
    required this.initialText,
    required this.historyIndex,
    required this.pathHistory,
    this.initialPath,
    required this.onSave,
    required this.onNavigate,
  });

  @override
  State<JsonEditorBottomSheet> createState() => _JsonEditorBottomSheetState();
}

class _JsonEditorBottomSheetState extends State<JsonEditorBottomSheet> {
  late TextEditingController _controller;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  int _currentEditPosition = 0;
  bool _hasSyntaxError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _undoStack.add(widget.initialText);
    _controller.addListener(_trackChanges);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trackChanges() {
    final currentText = _controller.text;
    if (_undoStack[_currentEditPosition] != currentText) {
      if (_currentEditPosition < _undoStack.length - 1) {
        _undoStack.removeRange(_currentEditPosition + 1, _undoStack.length);
      }
      _undoStack.add(currentText);
      _currentEditPosition = _undoStack.length - 1;
      _redoStack.clear();
      _validateJson();
    }
  }

  void _undo() {
    if (_currentEditPosition > 0) {
      setState(() {
        _currentEditPosition--;
        _controller.text = _undoStack[_currentEditPosition];
        _redoStack.clear();
        _validateJson();
      });
    }
  }

  void _redo() {
    if (_currentEditPosition < _undoStack.length - 1) {
      setState(() {
        _currentEditPosition++;
        _controller.text = _undoStack[_currentEditPosition];
        _validateJson();
      });
    }
  }

  void _formatJson() {
    try {
      final json = jsonDecode(_controller.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(json);
      setState(() {
        _controller.text = formatted;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = context.t.entry.jsonFormatFailed(error: e);
      });
    }
  }

  void _validateJson() {
    try {
      jsonDecode(_controller.text);
      setState(() {
        _hasSyntaxError = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _hasSyntaxError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleSave() async {
    if (_hasSyntaxError) {
      showToast(context, context.t.entry.jsonSyntaxError(error: _errorMessage ?? ''));
      return;
    }

    try {
      final newValue = jsonDecode(_controller.text);
      await widget.onSave(newValue);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showToast(context, context.t.entry.saveFailed(error: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildPathNavigator(
                  context,
                  widget.pathParts,
                  (newPathParts) {
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in newPathParts) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(newPathParts, currentValue);
                  },
                  onHomeTap: () {
                    Navigator.pop(context);
                    final json = widget.entry.toJson();
                    widget.onNavigate([], json);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.initialPath != null &&
                  widget.pathParts.join('.') != widget.initialPath!.join('.'))
                _buildToolbarIconButton(
                  icon: Icons.first_page,
                  onPressed: () {
                    Navigator.pop(context);
                    final startPath = widget.initialPath!;
                    final json = widget.entry.toJson();
                    dynamic currentValue = json;
                    for (final part in startPath) {
                      if (currentValue is Map) {
                        currentValue = currentValue[part];
                      } else if (currentValue is List) {
                        int? index = int.tryParse(part);
                        if (index != null) currentValue = currentValue[index];
                      }
                    }
                    widget.onNavigate(startPath, currentValue);
                  },
                  tooltip: context.t.entry.returnToStart,
                  color: colorScheme.primary,
                ),
              _buildToolbarIconButton(
                icon: Icons.undo,
                onPressed: _currentEditPosition > 0 ? _undo : null,
                tooltip: context.t.common.undo,
              ),
              _buildToolbarIconButton(
                icon: Icons.redo,
                onPressed: _currentEditPosition < _undoStack.length - 1
                    ? _redo
                    : null,
                tooltip: context.t.common.redo,
              ),
              _buildToolbarIconButton(
                icon: Icons.format_align_left,
                onPressed: _formatJson,
                tooltip: context.t.entry.formatJson,
              ),
              _buildToolbarIconButton(
                icon: _hasSyntaxError
                    ? Icons.error
                    : Icons.check_circle_outline,
                onPressed: _validateJson,
                tooltip: _hasSyntaxError ? context.t.entry.syntaxError : context.t.entry.syntaxCheck,
                color: _hasSyntaxError ? colorScheme.error : null,
              ),
            ],
          ),
          if (_hasSyntaxError && _errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.t.entry.jsonErrorLabel(error: _errorMessage!),
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _FoldableCodeEditor(
            controller: _controller,
            hasSyntaxError: _hasSyntaxError,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t.common.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _hasSyntaxError ? null : _handleSave,
                child: Text(context.t.common.save),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFoldView(BuildContext context) {
    // Kept for compatibility — no longer used directly.
    return const SizedBox.shrink();
  }

  Widget _buildFoldLine(
    BuildContext context, {
    required int lineIndex,
    required String lineText,
    required int? foldEndLine,
    required bool isFolded,
    required int hiddenCount,
    required ColorScheme colorScheme,
  }) {
    return const SizedBox.shrink();
  }

  Widget _buildToolbarIconButton({
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
            (onPressed != null ? colorScheme.primary : colorScheme.outline),
        size: 20,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  Widget _buildPathNavigator(
    BuildContext context,
    List<String> pathParts,
    Function(List<String>) onPathSelected, {
    VoidCallback? onHomeTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onHomeTap != null)
          InkWell(
            onTap: onHomeTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 18, color: colorScheme.primary),
            ),
          ),
        ...pathParts.asMap().entries.expand((entry) {
          final index = entry.key;
          final part = entry.value;
          final currentPath = pathParts.sublist(0, index + 1);

          final widgets = <Widget>[];

          if (index > 0) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '>',
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          final isLast = index == pathParts.length - 1;
          widgets.add(
            InkWell(
              onTap: isLast ? null : () => onPathSelected(currentPath),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  part,
                  style: TextStyle(
                    color: isLast
                        ? colorScheme.primary
                        : colorScheme.primary.withValues(alpha: 0.8),
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );

          return widgets;
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// VS Code-like foldable code editor
// ─────────────────────────────────────────────────────────────────

/// A single node in the editor's logical line list.
/// When [folded] is non-null this is a fold anchor and [folded] contains the
/// hidden lines (in order) that were collapsed beneath it.
class _LineNode {
  String content;
  List<String>? folded;
  _LineNode(this.content);
  bool get isFolded => folded != null;
}

class _FoldableCodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool hasSyntaxError;

  const _FoldableCodeEditor({
    required this.controller,
    required this.hasSyntaxError,
  });

  @override
  State<_FoldableCodeEditor> createState() => _FoldableCodeEditorState();
}

class _FoldableCodeEditorState extends State<_FoldableCodeEditor> {
  // Logical line list (visible lines only; folded content lives in _LineNode.folded).
  final List<_LineNode> _nodes = [];

  // Single TextField controller – enables native multi-line selection.
  late TextEditingController _displayCtrl;

  // Scroll controller: manages editor scrolling.
  final ScrollController _textScrollCtrl = ScrollController();

  // Foldable ranges computed from the current display text: startLine -> endLine.
  Map<int, int> _foldRanges = {};

  bool _syncing = false;

  static const double _lineHeight = 21.0; // fontSize(14) × height(1.5)
  static const TextStyle _lineStyle = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 14,
    height: 1.5,
  );

  // ── Life-cycle ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadText(widget.controller.text);
    _displayCtrl = TextEditingController(text: _displayText);
    _displayCtrl.addListener(_onDisplayChanged);
    _recomputeFoldRanges();
    widget.controller.addListener(_onParentChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParentChanged);
    _displayCtrl.removeListener(_onDisplayChanged);
    _displayCtrl.dispose();
    _textScrollCtrl.dispose();
    super.dispose();
  }

  // ── State helpers ───────────────────────────────────────────────

  void _loadText(String text) {
    _nodes.clear();
    for (final l in text.split('\n')) _nodes.add(_LineNode(l));
    if (_nodes.isEmpty) _nodes.add(_LineNode(''));
  }

  /// Text shown in the TextField (visible lines only).
  String get _displayText => _nodes.map((n) => n.content).join('\n');

  /// Full text including all folded content (used for widget.controller).
  String get _fullText {
    final parts = <String>[];
    for (final node in _nodes) {
      parts.add(node.content);
      if (node.folded != null) parts.addAll(node.folded!);
    }
    return parts.join('\n');
  }

  void _recomputeFoldRanges() {
    final ranges = _computeFoldRanges(_displayText);
    _foldRanges = {for (final r in ranges) r.startLine: r.endLine};
  }

  // ── Sync: display → parent ──────────────────────────────────────

  void _onDisplayChanged() {
    if (_syncing) return;
    _reconcileNodes(_displayCtrl.text.split('\n'));
    _syncing = true;
    widget.controller.text = _fullText;
    _syncing = false;
    // Recompute fold ranges after the current frame so we don't call setState
    // inside a listener callback.
    final ranges = _computeFoldRanges(_displayText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _foldRanges = {for (final r in ranges) r.startLine: r.endLine};
        });
      }
    });
  }

  // ── Sync: parent → display ──────────────────────────────────────

  void _onParentChanged() {
    if (_syncing) return;
    final newFull = widget.controller.text;
    if (newFull == _fullText) return;
    _loadText(newFull);
    _syncing = true;
    _displayCtrl.text = _displayText;
    _syncing = false;
    _recomputeFoldRanges();
    if (mounted) setState(() {});
  }

  // ── Text reconciliation ─────────────────────────────────────────

  /// Merges [newLines] (from the display TextField) back into [_nodes],
  /// preserving fold anchors where possible.
  void _reconcileNodes(List<String> newLines) {
    if (newLines.length == _nodes.length) {
      for (int i = 0; i < _nodes.length; i++) _nodes[i].content = newLines[i];
      return;
    }
    // Find first differing position from start.
    int start = 0;
    while (start < _nodes.length &&
        start < newLines.length &&
        _nodes[start].content == newLines[start]) {
      start++;
    }
    // Find first differing position from end.
    int oldEnd = _nodes.length - 1;
    int newEnd = newLines.length - 1;
    while (oldEnd > start &&
        newEnd > start &&
        _nodes[oldEnd].content == newLines[newEnd]) {
      oldEnd--;
      newEnd--;
    }
    // Replace the differing range.
    final replacement =
        newLines.sublist(start, newEnd + 1).map(_LineNode.new).toList();
    _nodes.replaceRange(start, oldEnd + 1, replacement);
  }

  // ── Fold / unfold ───────────────────────────────────────────────

  void _toggleFold(int i) {
    final node = _nodes[i];
    if (node.isFolded) {
      // Unfold: restore hidden lines as plain nodes.
      final hidden = node.folded!;
      node.folded = null;
      _nodes.insertAll(i + 1, hidden.map(_LineNode.new).toList());
    } else {
      // Fold: collapse nodes[i+1..endLine] under node[i].
      final endLine = _foldRanges[i];
      if (endLine == null) return;
      final hidden = <String>[];
      for (int k = i + 1; k <= endLine; k++) {
        hidden.add(_nodes[k].content);
        if (_nodes[k].folded != null) hidden.addAll(_nodes[k].folded!);
      }
      node.folded = hidden;
      _nodes.removeRange(i + 1, endLine + 1);
    }
    _syncing = true;
    _displayCtrl.text = _displayText;
    widget.controller.text = _fullText;
    _syncing = false;
    _recomputeFoldRanges();
    setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300, minHeight: 60),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color:
                widget.hasSyntaxError ? colorScheme.error : colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SingleChildScrollView(
          controller: _textScrollCtrl,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gutter: fold icons
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    for (int i = 0; i < _nodes.length; i++)
                      _buildGutterCell(i, colorScheme),
                  ],
                ),
              ),
              // Single TextField – supports native cursor + multi-line selection.
              Expanded(
                child: TextField(
                  controller: _displayCtrl,
                  style: _lineStyle,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGutterCell(int i, ColorScheme colorScheme) {
    final node = _nodes[i];
    final isFoldable = _foldRanges.containsKey(i) || node.isFolded;
    return SizedBox(
      height: _lineHeight,
      width: 20,
      child: isFoldable
          ? InkWell(
              onTap: () => _toggleFold(i),
              child: Center(
                child: Icon(
                  node.isFolded ? Icons.chevron_right : Icons.expand_more,
                  size: 14,
                  color: colorScheme.primary,
                ),
              ),
            )
          : null,
    );
  }
}

