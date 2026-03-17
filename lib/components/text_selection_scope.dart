import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/logger.dart';

/// 文本段信息
class TextSegment {
  final GlobalKey key;
  final String plainText;
  final int globalStartOffset;
  final InlineSpan? textSpan;

  TextSegment({
    required this.key,
    required this.plainText,
    required this.globalStartOffset,
    this.textSpan,
  });

  int get globalEndOffset => globalStartOffset + plainText.length;
}

/// 全局文本选择管理器
/// 用于协调多个文本段的选择
class GlobalTextSelectionManager extends ChangeNotifier {
  final Map<String, TextSegment> _segments = {};

  int? _selectionStart;
  int? _selectionEnd;
  String? _selectedText;
  bool _isSelecting = false;

  /// 是否正在选择
  bool get isSelecting => _isSelecting;

  /// 是否有选择内容
  bool get hasSelection =>
      _selectionStart != null &&
      _selectionEnd != null &&
      _selectionStart != _selectionEnd;

  /// 获取选中的文本
  String? get selectedText => _selectedText;

  /// 获取选择范围
  (int, int)? get selectionRange {
    if (_selectionStart == null || _selectionEnd == null) return null;
    final start = _selectionStart! < _selectionEnd!
        ? _selectionStart!
        : _selectionEnd!;
    final end = _selectionStart! < _selectionEnd!
        ? _selectionEnd!
        : _selectionStart!;
    return (start, end);
  }

  /// 注册文本段
  void registerSegment(String id, TextSegment segment) {
    _segments[id] = segment;
  }

  /// 注销文本段
  void unregisterSegment(String id) {
    _segments.remove(id);
  }

  /// 开始选择
  void startSelection(int globalOffset) {
    _selectionStart = globalOffset;
    _selectionEnd = globalOffset;
    _isSelecting = true;
    _selectedText = null;
    notifyListeners();
  }

  /// 更新选择
  void updateSelection(int globalOffset) {
    if (!_isSelecting) return;
    _selectionEnd = globalOffset;
    _updateSelectedText();
    notifyListeners();
  }

  /// 完成选择
  void finishSelection() {
    _isSelecting = false;
    _updateSelectedText();
    notifyListeners();
  }

  void _updateSelectedText() {
    if (_selectionStart == null || _selectionEnd == null) {
      _selectedText = null;
      return;
    }

    final start = _selectionStart! < _selectionEnd!
        ? _selectionStart!
        : _selectionEnd!;
    final end = _selectionStart! < _selectionEnd!
        ? _selectionEnd!
        : _selectionStart!;

    // 收集选择范围内的所有文本
    final buffer = StringBuffer();

    // 按起始偏移量排序
    final sortedSegments = _segments.values.toList()
      ..sort((a, b) => a.globalStartOffset.compareTo(b.globalStartOffset));

    for (final segment in sortedSegments) {
      // 检查是否在选择范围内
      if (segment.globalEndOffset <= start) continue;
      if (segment.globalStartOffset >= end) break;

      // 计算该段内的选择范围
      final segStart = start > segment.globalStartOffset
          ? start - segment.globalStartOffset
          : 0;
      final segEnd = end < segment.globalEndOffset
          ? end - segment.globalStartOffset
          : segment.plainText.length;

      if (segStart < segEnd && segStart < segment.plainText.length) {
        final safeEnd = segEnd > segment.plainText.length
            ? segment.plainText.length
            : segEnd;
        buffer.write(segment.plainText.substring(segStart, safeEnd));
      }
    }

    _selectedText = buffer.toString();
  }

  /// 清除选择
  void clearSelection() {
    _selectionStart = null;
    _selectionEnd = null;
    _selectedText = null;
    _isSelecting = false;
    notifyListeners();
  }

  /// 获取指定段的选择范围（返回相对于该段的局部偏移量）
  (int, int)? getSegmentSelectionRange(String segmentId) {
    final segment = _segments[segmentId];
    if (segment == null) return null;
    if (_selectionStart == null || _selectionEnd == null) return null;

    final start = _selectionStart! < _selectionEnd!
        ? _selectionStart!
        : _selectionEnd!;
    final end = _selectionStart! < _selectionEnd!
        ? _selectionEnd!
        : _selectionStart!;

    // 检查是否与该段有交集
    if (end <= segment.globalStartOffset || start >= segment.globalEndOffset) {
      return null;
    }

    // 计算局部范围
    final localStart = start > segment.globalStartOffset
        ? start - segment.globalStartOffset
        : 0;
    final localEnd = end < segment.globalEndOffset
        ? end - segment.globalStartOffset
        : segment.plainText.length;

    return (localStart, localEnd);
  }

  /// 复制到剪贴板
  Future<void> copyToClipboard() async {
    if (_selectedText != null && _selectedText!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _selectedText!));
    }
  }
}

/// 全局文本选择作用域
/// 用于在组件树中共享选择状态
class TextSelectionScope extends InheritedWidget {
  final GlobalTextSelectionManager manager;

  const TextSelectionScope({
    super.key,
    required this.manager,
    required super.child,
  });

  static TextSelectionScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TextSelectionScope>();
  }

  static GlobalTextSelectionManager? managerOf(BuildContext context) {
    return of(context)?.manager;
  }

  @override
  bool updateShouldNotify(covariant TextSelectionScope oldWidget) {
    return manager != oldWidget.manager;
  }
}

/// 可选择的文本段组件
class SelectableTextSegment extends StatefulWidget {
  /// 段ID
  final String segmentId;

  /// 全局起始偏移量
  final int globalStartOffset;

  /// 文本内容
  final InlineSpan textSpan;

  /// 纯文本
  final String plainText;

  /// 文本样式
  final TextStyle? style;

  /// 选择颜色
  final Color selectionColor;

  const SelectableTextSegment({
    super.key,
    required this.segmentId,
    required this.globalStartOffset,
    required this.textSpan,
    required this.plainText,
    this.style,
    this.selectionColor = const Color(0x661976D2),
  });

  @override
  State<SelectableTextSegment> createState() => _SelectableTextSegmentState();
}

class _SelectableTextSegmentState extends State<SelectableTextSegment> {
  final GlobalKey _textKey = GlobalKey();
  GlobalTextSelectionManager? _manager;
  List<Rect> _selectionRects = [];

  @override
  void initState() {
    super.initState();
    _registerSegment();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager = TextSelectionScope.managerOf(context);
    _manager?.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(SelectableTextSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.segmentId != oldWidget.segmentId ||
        widget.globalStartOffset != oldWidget.globalStartOffset ||
        widget.plainText != oldWidget.plainText) {
      _registerSegment();
    }
  }

  @override
  void dispose() {
    _manager?.removeListener(_onSelectionChanged);
    _manager?.unregisterSegment(widget.segmentId);
    super.dispose();
  }

  void _registerSegment() {
    _manager?.registerSegment(
      widget.segmentId,
      TextSegment(
        key: _textKey,
        plainText: widget.plainText,
        globalStartOffset: widget.globalStartOffset,
        textSpan: widget.textSpan,
      ),
    );
  }

  void _onSelectionChanged() {
    _updateSelectionRects();
  }

  void _updateSelectionRects() {
    final manager = _manager;
    if (manager == null) return;

    final range = manager.getSegmentSelectionRange(widget.segmentId);
    if (range == null) {
      if (_selectionRects.isNotEmpty) {
        setState(() {
          _selectionRects = [];
        });
      }
      return;
    }

    final (localStart, localEnd) = range;
    final rects = _getSelectionRects(localStart, localEnd);

    if (rects.length != _selectionRects.length ||
        !_listsEqual(rects, _selectionRects)) {
      setState(() {
        _selectionRects = rects;
      });
    }
  }

  bool _listsEqual(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Rect> _getSelectionRects(int start, int end) {
    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return [];

    if (start < 0 || end > widget.plainText.length || start >= end) {
      return [];
    }

    final selection = TextSelection(baseOffset: start, extentOffset: end);

    final boxes = renderObject.getBoxesForSelection(selection);
    return boxes.map((box) => box.toRect()).toList();
  }

  int? _getGlobalOffset(Offset globalPosition) {
    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return null;

    final localPosition = renderObject.globalToLocal(globalPosition);
    final textPosition = renderObject.getPositionForOffset(localPosition);
    return widget.globalStartOffset + textPosition.offset;
  }

  bool _isDragging = false;

  void _handlePointerDown(PointerDownEvent event) {
    Logger.d(
      'PointerDown: buttons=${event.buttons}, position=${event.position}',
      tag: 'TextSelection',
    );

    // 只处理左键
    if (event.buttons != kPrimaryButton) return;

    final offset = _getGlobalOffset(event.position);
    Logger.d('PointerDown offset: $offset', tag: 'TextSelection');

    if (offset == null) return;

    _isDragging = true;
    _manager?.startSelection(offset);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragging) return;

    final offset = _getGlobalOffset(event.position);
    if (offset == null) return;
    _manager?.updateSelection(offset);
  }

  void _handlePointerUp(PointerUpEvent event) {
    Logger.d('PointerUp: _isDragging=$_isDragging', tag: 'TextSelection');

    if (!_isDragging) return;
    _isDragging = false;
    _manager?.finishSelection();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    Logger.d('PointerCancel: _isDragging=$_isDragging', tag: 'TextSelection');

    if (!_isDragging) return;
    _isDragging = false;
    _manager?.finishSelection();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Listener 监听原始指针事件，避免与外层 GestureDetector 冲突
    // 使用 HitTestBehavior.opaque 确保能接收到所有事件
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Text.rich(widget.textSpan, key: _textKey, style: widget.style),
          if (_selectionRects.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SelectionHighlightPainter(
                    rects: _selectionRects,
                    color: widget.selectionColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionHighlightPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;

  _SelectionHighlightPainter({required this.rects, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final rect in rects) {
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.0));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionHighlightPainter oldDelegate) {
    if (rects.length != oldDelegate.rects.length) return true;
    for (int i = 0; i < rects.length; i++) {
      if (rects[i] != oldDelegate.rects[i]) return true;
    }
    return color != oldDelegate.color;
  }
}
