import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/database_service.dart';
import '../core/utils/toast_utils.dart';
import '../i18n/strings.g.dart';
import '../widgets/path_navigator.dart';

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
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
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
  bool _isFullScreen = false;
  List<String> _currentPath = [];
  final GlobalKey<_FoldableCodeEditorState> _editorKey = GlobalKey();
  final GlobalKey<PathNavigatorState> _pathNavigatorKey = GlobalKey();

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
      showToast(
        context,
        context.t.entry.jsonSyntaxError(error: _errorMessage ?? ''),
      );
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

  void _scrollToPathLine(List<String> cursorPath) {
    _editorKey.currentState?.scrollToPath(cursorPath);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;
    final screenSize = MediaQuery.of(context).size;

    return DraggableScrollableSheet(
      initialChildSize: _isFullScreen ? 1.0 : 0.7,
      minChildSize: _isFullScreen ? 1.0 : 0.5,
      maxChildSize: _isFullScreen
          ? 1.0
          : (screenSize.height - statusBarHeight - 8) / screenSize.height,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          width: _isFullScreen ? screenSize.width : null,
          padding: EdgeInsets.only(
            top: _isFullScreen ? statusBarHeight + 8 : 16,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PathNavigator(
                      key: _pathNavigatorKey,
                      pathParts: widget.pathParts,
                      cursorPath: _currentPath.isNotEmpty ? _currentPath : null,
                      onNavigate: (newPathParts) {
                        Navigator.pop(context);
                        dynamic currentValue;
                        try {
                          currentValue = jsonDecode(_controller.text);
                        } catch (_) {
                          final json = widget.entry.toJson();
                          currentValue = json;
                        }
                        for (final part in newPathParts) {
                          if (currentValue is Map) {
                            currentValue = currentValue[part];
                          } else if (currentValue is List) {
                            final index = int.tryParse(part);
                            if (index != null) {
                              currentValue = currentValue[index];
                            }
                          }
                        }
                        widget.onNavigate(newPathParts, currentValue);
                      },
                      onHomeTap: () {
                        Navigator.pop(context);
                        final json = widget.entry.toJson();
                        widget.onNavigate([], json);
                      },
                      onCursorPathTap: (cursorPath) {
                        _scrollToPathLine(cursorPath);
                      },
                      showReturnToStart:
                          widget.initialPath != null &&
                          widget.pathParts.join('.') !=
                              widget.initialPath!.join('.'),
                      onReturnToStart:
                          widget.initialPath != null &&
                              widget.pathParts.join('.') !=
                                  widget.initialPath!.join('.')
                          ? () {
                              Navigator.pop(context);
                              final startPath = widget.initialPath!;
                              final json = widget.entry.toJson();
                              dynamic currentValue = json;
                              for (final part in startPath) {
                                if (currentValue is Map) {
                                  currentValue = currentValue[part];
                                } else if (currentValue is List) {
                                  int? index = int.tryParse(part);
                                  if (index != null)
                                    currentValue = currentValue[index];
                                }
                              }
                              widget.onNavigate(startPath, currentValue);
                            }
                          : null,
                      validatePath: (newPath) {
                        final json = widget.entry.toJson();
                        dynamic currentValue = json;

                        for (final part in newPath) {
                          if (currentValue is Map) {
                            if (currentValue.containsKey(part)) {
                              currentValue = currentValue[part];
                            } else {
                              return context.t.entry.pathNotFound;
                            }
                          } else if (currentValue is List) {
                            final index = int.tryParse(part);
                            if (index != null &&
                                index >= 0 &&
                                index < currentValue.length) {
                              currentValue = currentValue[index];
                            } else {
                              return context.t.entry.pathNotFound;
                            }
                          } else {
                            return context.t.entry.pathNotFound;
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildToolbarIconButton(
                    icon: Icons.save,
                    onPressed: _hasSyntaxError ? null : _handleSave,
                    tooltip: context.t.common.save,
                    color: _hasSyntaxError ? null : colorScheme.primary,
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
                    tooltip: _hasSyntaxError
                        ? context.t.entry.syntaxError
                        : context.t.entry.syntaxCheck,
                    color: _hasSyntaxError ? colorScheme.error : null,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isFullScreen = !_isFullScreen;
                      });
                    },
                    icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _isFullScreen
                        ? context.t.common.exitFullscreen
                        : context.t.common.fullscreen,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
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
              Expanded(
                child: _FoldableCodeEditor(
                  key: _editorKey,
                  controller: _controller,
                  hasSyntaxError: _hasSyntaxError,
                  onTopLinePathChanged: (path) {
                    setState(() {
                      _currentPath = path;
                    });
                  },
                  onTap: () {
                    _pathNavigatorKey.currentState?.stopEditing();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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

class _PathStackEntry {
  final String key;
  final String bracket;
  int arrayIndex;

  _PathStackEntry({
    required this.key,
    required this.bracket,
    this.arrayIndex = 0,
  });
}

class _FoldableCodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool hasSyntaxError;
  final void Function(List<String> path)? onTopLinePathChanged;
  final VoidCallback? onTap;

  const _FoldableCodeEditor({
    super.key,
    required this.controller,
    required this.hasSyntaxError,
    this.onTopLinePathChanged,
    this.onTap,
  });

  @override
  State<_FoldableCodeEditor> createState() => _FoldableCodeEditorState();
}

class _FoldableCodeEditorState extends State<_FoldableCodeEditor> {
  final List<_LineNode> _nodes = [];

  late TextEditingController _displayCtrl;

  final ScrollController _textScrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();

  Map<int, int> _foldRanges = {};

  bool _syncing = false;
  List<String> _currentPath = [];
  int _cursorLine = -1;
  bool _isProgrammaticScrolling = false;

  static const double _lineHeight = 21.0;
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
    _textScrollCtrl.addListener(_onScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cursorLine = 0;
      _displayCtrl.selection = const TextSelection.collapsed(offset: 0);
      _updateCurrentPath();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParentChanged);
    _displayCtrl.removeListener(_onDisplayChanged);
    _displayCtrl.dispose();
    _textScrollCtrl.removeListener(_onScrollChanged);
    _textScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
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
    final ranges = _computeFoldRanges(_displayText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _foldRanges = {for (final r in ranges) r.startLine: r.endLine};
        });
        _onSelectionChanged();
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
    if (mounted) {
      _updateCurrentPath();
    }
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
    final replacement = newLines
        .sublist(start, newEnd + 1)
        .map(_LineNode.new)
        .toList();
    _nodes.replaceRange(start, oldEnd + 1, replacement);
  }

  void _onScrollChanged() {
    if (!mounted) return;
    _updateCurrentPath();
    _keepCursorInView();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final selection = _displayCtrl.selection;
    if (selection.isValid) {
      final cursorPos = selection.baseOffset;
      final textBeforeCursor = _displayCtrl.text.substring(0, cursorPos);
      final newCursorLine = '\n'.allMatches(textBeforeCursor).length;
      if (newCursorLine != _cursorLine) {
        _cursorLine = newCursorLine;
        _updateCurrentPath();
      }
    } else if (_cursorLine != -1) {
      _cursorLine = -1;
      _updateCurrentPath();
    }
  }

  void _keepCursorInView() {
    if (!_textScrollCtrl.hasClients ||
        _cursorLine < 0 ||
        _nodes.isEmpty ||
        _isProgrammaticScrolling) {
      return;
    }

    final viewportHeight = _textScrollCtrl.position.viewportDimension;
    final currentOffset = _textScrollCtrl.offset;
    const topPadding = 8.0;

    final firstFullyVisibleLine =
        ((currentOffset - topPadding + _lineHeight - 0.1) / _lineHeight)
            .ceil()
            .clamp(0, _nodes.length - 1);
    final lastFullyVisibleLine =
        ((currentOffset + viewportHeight - topPadding - _lineHeight) /
                _lineHeight)
            .floor()
            .clamp(0, _nodes.length - 1);

    if (firstFullyVisibleLine > lastFullyVisibleLine) {
      return;
    }

    if (_cursorLine < firstFullyVisibleLine) {
      _setCursorToLineStart(firstFullyVisibleLine);
    } else if (_cursorLine > lastFullyVisibleLine) {
      _setCursorToLineStart(lastFullyVisibleLine);
    }
  }

  void _setCursorToLineStart(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= _nodes.length) return;

    int offset = 0;
    for (int i = 0; i < lineIndex; i++) {
      offset += _nodes[i].content.length + 1;
    }

    _displayCtrl.selection = TextSelection.collapsed(offset: offset);
    _cursorLine = lineIndex;
    _updateCurrentPath();
  }

  void scrollToPath(List<String> targetPath) {
    if (targetPath.isEmpty || _nodes.isEmpty) return;

    final targetLine = _findLineForPath(targetPath);
    if (targetLine < 0) return;

    const topPadding = 8.0;
    final targetOffset = topPadding + targetLine * _lineHeight;

    if (_textScrollCtrl.hasClients) {
      _isProgrammaticScrolling = true;
      _textScrollCtrl
          .animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (mounted) {
              _isProgrammaticScrolling = false;
              _setCursorToLineStart(targetLine);
            }
          });
    } else {
      _setCursorToLineStart(targetLine);
    }
  }

  int _findLineForPath(List<String> targetPath) {
    if (targetPath.isEmpty) return -1;

    final path = <String>[];
    final stack = <_PathStackEntry>[];

    for (int i = 0; i < _nodes.length; i++) {
      final node = _nodes[i];
      final line = node.content;

      _parseLineForPath(line, stack, path, false);

      if (_pathEquals(path, targetPath)) {
        return i;
      }

      if (node.isFolded && node.folded != null) {
        for (final hiddenLine in node.folded!) {
          _parseLineForPath(hiddenLine, stack, path, false);
          if (_pathEquals(path, targetPath)) {
            return i;
          }
        }
      }
    }

    return -1;
  }

  void _updateCurrentPath() {
    final newPath = _computePathForLine(_cursorLine);
    if (!_pathEquals(newPath, _currentPath)) {
      _currentPath = newPath;
      widget.onTopLinePathChanged?.call(newPath);
    }
  }

  bool _pathEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _computePathForLine(int? targetLine) {
    final offset = _textScrollCtrl.hasClients ? _textScrollCtrl.offset : 0.0;
    const topPadding = 8.0;
    final topLineIndex = ((offset - topPadding) / _lineHeight).floor().clamp(
      0,
      _nodes.length - 1,
    );

    final lineToCompute = targetLine ?? topLineIndex;
    if (lineToCompute < 0 || _nodes.isEmpty) return [];

    final path = <String>[];
    final stack = <_PathStackEntry>[];

    for (int i = 0; i <= lineToCompute && i < _nodes.length; i++) {
      final node = _nodes[i];
      final line = node.content;

      _parseLineForPath(line, stack, path, i == lineToCompute);

      if (node.isFolded && node.folded != null) {
        for (final hiddenLine in node.folded!) {
          _parseLineForPath(hiddenLine, stack, path, false);
        }
      }
    }

    return path;
  }

  void _parseLineForPath(
    String line,
    List<_PathStackEntry> stack,
    List<String> path,
    bool isTargetLine,
  ) {
    bool inString = false;
    bool escaped = false;
    String? currentKey;
    bool afterColon = false;
    int charIndex = 0;

    void processOpenBracket(String bracket) {
      if (bracket == '{') {
        if (currentKey != null) {
          stack.add(_PathStackEntry(key: currentKey!, bracket: '{'));
          path.add(currentKey!);
        } else if (stack.isNotEmpty && stack.last.bracket == '[') {
          final idx = stack.last.arrayIndex;
          stack.add(_PathStackEntry(key: '$idx', bracket: '{'));
          path.add('$idx');
        }
      } else {
        if (currentKey != null) {
          stack.add(
            _PathStackEntry(key: currentKey!, bracket: '[', arrayIndex: 0),
          );
          path.add(currentKey!);
        } else if (stack.isNotEmpty && stack.last.bracket == '[') {
          final idx = stack.last.arrayIndex;
          stack.add(_PathStackEntry(key: '$idx', bracket: '[', arrayIndex: 0));
          path.add('$idx');
        } else if (stack.isEmpty) {
          stack.add(_PathStackEntry(key: '', bracket: '[', arrayIndex: 0));
        }
      }
      currentKey = null;
      afterColon = false;
    }

    void processCloseBracket() {
      if (stack.isNotEmpty) {
        stack.removeLast();
        if (path.isNotEmpty) {
          path.removeLast();
        }
        if (stack.isNotEmpty && stack.last.bracket == '[') {
          stack.last.arrayIndex++;
        }
      }
    }

    void processCloseBracketForTargetLine() {
      if (stack.isNotEmpty) {
        stack.removeLast();
        if (stack.isNotEmpty && stack.last.bracket == '[') {
          stack.last.arrayIndex++;
        }
      }
    }

    void processValue() {
      if (isTargetLine && stack.isNotEmpty) {
        if (currentKey != null && stack.last.bracket == '{') {
          path.add(currentKey!);
        } else if (currentKey == null && stack.last.bracket == '[') {
          path.add('${stack.last.arrayIndex}');
        }
      }
      if (stack.isNotEmpty && stack.last.bracket == '[' && currentKey == null) {
        stack.last.arrayIndex++;
      }
      currentKey = null;
      afterColon = false;
    }

    while (charIndex < line.length) {
      final ch = line[charIndex];

      if (escaped) {
        escaped = false;
        charIndex++;
        continue;
      }

      if (ch == '\\' && inString) {
        escaped = true;
        charIndex++;
        continue;
      }

      if (ch == '"') {
        if (!inString && !afterColon) {
          if (stack.isNotEmpty && stack.last.bracket == '[') {
            processValue();
          } else {
            final keyStart = charIndex + 1;
            int keyEnd = keyStart;
            bool keyEscaped = false;
            while (keyEnd < line.length) {
              final keyCh = line[keyEnd];
              if (keyEscaped) {
                keyEscaped = false;
              } else if (keyCh == '\\') {
                keyEscaped = true;
              } else if (keyCh == '"') {
                break;
              }
              keyEnd++;
            }
            if (keyEnd > keyStart) {
              final keyBuilder = StringBuffer();
              bool kEscaped = false;
              for (int k = keyStart; k < keyEnd; k++) {
                final keyCh = line[k];
                if (kEscaped) {
                  keyBuilder.write(keyCh);
                  kEscaped = false;
                } else if (keyCh == '\\') {
                  kEscaped = true;
                } else {
                  keyBuilder.write(keyCh);
                }
              }
              currentKey = keyBuilder.toString();
            }
          }
        } else if (inString && afterColon) {
          processValue();
        }
        inString = !inString;
        charIndex++;
        continue;
      }

      if (inString) {
        charIndex++;
        continue;
      }

      if (ch == ':') {
        afterColon = true;
        charIndex++;
        continue;
      }

      if (ch == '{') {
        processOpenBracket('{');
        charIndex++;
        continue;
      }

      if (ch == '[') {
        processOpenBracket('[');
        charIndex++;
        continue;
      }

      if (ch == '}') {
        if (isTargetLine) {
          processCloseBracketForTargetLine();
        } else {
          processCloseBracket();
        }
        charIndex++;
        continue;
      }

      if (ch == ']') {
        if (isTargetLine) {
          processCloseBracketForTargetLine();
        } else {
          processCloseBracket();
        }
        charIndex++;
        continue;
      }

      if (ch == ',') {
        currentKey = null;
        afterColon = false;
        charIndex++;
        continue;
      }

      if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') {
        if (afterColon) {
          if (ch == 'n' &&
              charIndex + 3 < line.length &&
              line.substring(charIndex, charIndex + 4) == 'null') {
            processValue();
            charIndex += 4;
            continue;
          }
          if (ch == 't' &&
              charIndex + 3 < line.length &&
              line.substring(charIndex, charIndex + 4) == 'true') {
            processValue();
            charIndex += 4;
            continue;
          }
          if (ch == 'f' &&
              charIndex + 4 < line.length &&
              line.substring(charIndex, charIndex + 5) == 'false') {
            processValue();
            charIndex += 5;
            continue;
          }
          final code = ch.codeUnitAt(0);
          if (ch == '-' || (code >= 48 && code <= 57)) {
            processValue();
            int endIdx = charIndex + 1;
            while (endIdx < line.length) {
              final numCh = line[endIdx];
              final numCode = numCh.codeUnitAt(0);
              if ((numCode >= 48 && numCode <= 57) ||
                  numCh == '.' ||
                  numCh == 'e' ||
                  numCh == 'E' ||
                  numCh == '+' ||
                  numCh == '-') {
                endIdx++;
              } else {
                break;
              }
            }
            charIndex = endIdx;
            continue;
          }
        }
      }

      charIndex++;
    }
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
      // Fold: collapse nodes[i+1..endLine-1] under node[i].
      // Keep the closing bracket line (endLine) visible.
      final endLine = _foldRanges[i];
      if (endLine == null) return;
      final hidden = <String>[];
      for (int k = i + 1; k < endLine; k++) {
        hidden.add(_nodes[k].content);
        if (_nodes[k].folded != null) hidden.addAll(_nodes[k].folded!);
      }
      node.folded = hidden;
      _nodes.removeRange(i + 1, endLine);
    }
    _syncing = true;
    _displayCtrl.text = _displayText;
    widget.controller.text = _fullText;
    _syncing = false;
    _recomputeFoldRanges();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScrollChanged();
    });
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300, minHeight: 60),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(
            color: widget.hasSyntaxError
                ? colorScheme.error
                : colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SingleChildScrollView(
            controller: _textScrollCtrl,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      for (int i = 0; i < _nodes.length; i++)
                        _buildGutterCell(i, colorScheme),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 5000,
                      child: Stack(
                        children: [
                          if (_cursorLine >= 0 && _cursorLine < _nodes.length)
                            Positioned(
                              top: _cursorLine * _lineHeight + 5.0,
                              left: 0,
                              right: 0,
                              height: _lineHeight,
                              child: Container(
                                color: colorScheme.primaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          TextField(
                            controller: _displayCtrl,
                            style: _lineStyle,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            onTap: () {
                              widget.onTap?.call();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _onSelectionChanged();
                              });
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              isDense: true,
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
