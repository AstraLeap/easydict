import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/logger.dart';

/// WidgetSpan 占位符映射
/// 记录 \uFFFC 在文本中的位置和对应的实际内容
class WidgetSpanMapping {
  /// \uFFFC 在 plainText 中的位置
  final int placeholderIndex;

  /// WidgetSpan 内的实际文本内容
  final String content;

  WidgetSpanMapping({required this.placeholderIndex, required this.content});
}

/// 文本段信息
class TextSegmentInfo {
  final GlobalKey key;

  /// 用于偏移量计算的文本（WidgetSpan 用 \uFFFC 表示）
  final String plainText;

  /// WidgetSpan 占位符映射列表
  /// 用于将 \uFFFC 替换为实际内容
  final List<WidgetSpanMapping> widgetSpanMappings;
  final int globalStartOffset;

  TextSegmentInfo({
    required this.key,
    required this.plainText,
    this.widgetSpanMappings = const [],
    required this.globalStartOffset,
  });

  int get globalEndOffset => globalStartOffset + plainText.length;

  /// 根据偏移量范围获取显示文本
  /// 将 \uFFFC 替换为实际内容
  String getDisplayTextInRange(int localStart, int localEnd) {
    if (widgetSpanMappings.isEmpty) {
      return plainText.substring(localStart, localEnd);
    }

    final buffer = StringBuffer();
    int lastEnd = localStart;

    // 按位置排序
    final sortedMappings = List<WidgetSpanMapping>.from(widgetSpanMappings)
      ..sort((a, b) => a.placeholderIndex.compareTo(b.placeholderIndex));

    for (final mapping in sortedMappings) {
      // 如果占位符在范围之前，跳过
      if (mapping.placeholderIndex < localStart) continue;
      // 如果占位符在范围之后，结束
      if (mapping.placeholderIndex >= localEnd) break;

      // 添加占位符之前的文本
      if (mapping.placeholderIndex > lastEnd) {
        buffer.write(plainText.substring(lastEnd, mapping.placeholderIndex));
      }
      // 添加 WidgetSpan 的实际内容
      buffer.write(mapping.content);
      lastEnd = mapping.placeholderIndex + 1; // 跳过 \uFFFC
    }
    // 添加最后剩余的文本
    if (localEnd > lastEnd) {
      buffer.write(plainText.substring(lastEnd, localEnd));
    }

    return buffer.toString();
  }
}

/// 全局文本选择管理器
/// 用于协调多个文本段的选择
class GlobalTextSelectionManager extends ChangeNotifier {
  final Map<String, TextSegmentInfo> _segments = {};

  int? _selectionStart;
  int? _selectionEnd;
  String? _selectedText;
  bool _isSelecting = false;

  /// 获取已注册的文本段数量
  int get segmentCount => _segments.length;

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
  void registerSegment(String id, TextSegmentInfo segment) {
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

    final buffer = StringBuffer();

    final sortedSegments = _segments.values.toList()
      ..sort((a, b) => a.globalStartOffset.compareTo(b.globalStartOffset));

    for (final segment in sortedSegments) {
      if (segment.globalEndOffset <= start) continue;
      if (segment.globalStartOffset >= end) break;

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
        // 使用 getDisplayTextInRange 将 \uFFFC 替换为实际内容
        buffer.write(segment.getDisplayTextInRange(segStart, safeEnd));
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

    if (end <= segment.globalStartOffset || start >= segment.globalEndOffset) {
      return null;
    }

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

  /// 根据全局坐标获取全局字符偏移量
  int? getOffsetFromGlobalPosition(Offset globalPosition) {
    Logger.d(
      'getOffsetFromGlobalPosition: position=$globalPosition, segments=${_segments.length}',
      tag: 'TextSelection',
    );

    // 按起始偏移量排序
    final sortedSegments = _segments.values.toList()
      ..sort((a, b) => a.globalStartOffset.compareTo(b.globalStartOffset));

    for (final segment in sortedSegments) {
      final renderObject = segment.key.currentContext?.findRenderObject();
      Logger.d(
        '  segment ${segment.key}: renderObject=$renderObject',
        tag: 'TextSelection',
      );

      if (renderObject is! RenderParagraph) {
        Logger.d('  skipping: not RenderParagraph', tag: 'TextSelection');
        continue;
      }

      // 获取该段的边界
      final bounds =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      Logger.d('  bounds=$bounds', tag: 'TextSelection');

      // 检查点击是否在该段范围内
      if (!bounds.contains(globalPosition)) {
        Logger.d('  position not in bounds', tag: 'TextSelection');
        continue;
      }

      // 转换为本地坐标
      final localPosition = renderObject.globalToLocal(globalPosition);
      final textPosition = renderObject.getPositionForOffset(localPosition);
      Logger.d(
        '  localPosition=$localPosition, textOffset=${textPosition.offset}',
        tag: 'TextSelection',
      );

      return segment.globalStartOffset + textPosition.offset;
    }

    Logger.d(
      'getOffsetFromGlobalPosition: no matching segment found',
      tag: 'TextSelection',
    );
    return null;
  }
}

/// 全局文本选择作用域
/// 在顶层包裹，使用 Listener 监听所有指针事件
class GlobalTextSelectionScope extends StatefulWidget {
  final GlobalTextSelectionManager manager;
  final Widget child;

  const GlobalTextSelectionScope({
    super.key,
    required this.manager,
    required this.child,
  });

  @override
  State<GlobalTextSelectionScope> createState() =>
      _GlobalTextSelectionScopeState();
}

class _GlobalTextSelectionScopeState extends State<GlobalTextSelectionScope> {
  bool _isDragging = false;

  void _handlePointerDown(PointerDownEvent event) {
    Logger.d('=== PointerDown START ===', tag: 'TextSelection');
    Logger.d(
      'PointerDown: buttons=${event.buttons}, position=${event.position}',
      tag: 'TextSelection',
    );
    Logger.d(
      'PointerDown: kPrimaryButton=$kPrimaryButton',
      tag: 'TextSelection',
    );
    Logger.d(
      'PointerDown: registered segments count=${widget.manager.segmentCount}',
      tag: 'TextSelection',
    );

    // 只处理左键
    if (event.buttons != kPrimaryButton) {
      Logger.d(
        'PointerDown: not primary button, ignoring',
        tag: 'TextSelection',
      );
      return;
    }

    final offset = widget.manager.getOffsetFromGlobalPosition(event.position);
    if (offset == null) {
      Logger.d(
        'PointerDown: no segment found at ${event.position}',
        tag: 'TextSelection',
      );
      return;
    }

    Logger.d(
      'PointerDown: offset=$offset at ${event.position}',
      tag: 'TextSelection',
    );
    _isDragging = true;
    widget.manager.startSelection(offset);
    Logger.d('=== PointerDown END ===', tag: 'TextSelection');
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDragging) return;

    final offset = widget.manager.getOffsetFromGlobalPosition(event.position);
    if (offset == null) return;

    widget.manager.updateSelection(offset);
  }

  void _handlePointerUp(PointerUpEvent event) {
    Logger.d('PointerUp: _isDragging=$_isDragging', tag: 'TextSelection');

    if (!_isDragging) return;
    _isDragging = false;
    widget.manager.finishSelection();
    Logger.d(
      'PointerUp: selected="${widget.manager.selectedText}"',
      tag: 'TextSelection',
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    Logger.d('PointerCancel: _isDragging=$_isDragging', tag: 'TextSelection');

    if (!_isDragging) return;
    _isDragging = false;
    widget.manager.finishSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.translucent,
      child: _InheritedTextSelectionScope(
        manager: widget.manager,
        child: widget.child,
      ),
    );
  }
}

class _InheritedTextSelectionScope extends InheritedWidget {
  final GlobalTextSelectionManager manager;

  const _InheritedTextSelectionScope({
    required this.manager,
    required super.child,
  });

  static GlobalTextSelectionManager? managerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedTextSelectionScope>()
        ?.manager;
  }

  @override
  bool updateShouldNotify(covariant _InheritedTextSelectionScope oldWidget) {
    return manager != oldWidget.manager;
  }
}

/// 可选择的文本段组件
/// 只负责显示文本和选择高亮，不处理手势
class SelectableTextSegment extends StatefulWidget {
  final String segmentId;
  final int globalStartOffset;
  final InlineSpan textSpan;

  /// 用于偏移量计算的文本（WidgetSpan 用 \uFFFC 表示）
  final String plainText;

  /// WidgetSpan 占位符映射列表
  /// 用于将 \uFFFC 替换为实际内容
  /// 例如：[(placeholderIndex: 7, content: 'WidgetSpan')]
  final List<WidgetSpanMapping> widgetSpanMappings;
  final TextStyle? style;
  final Color selectionColor;

  const SelectableTextSegment({
    super.key,
    required this.segmentId,
    required this.globalStartOffset,
    required this.textSpan,
    required this.plainText,
    this.widgetSpanMappings = const [],
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
    // 延迟注册，确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerSegment();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manager = _InheritedTextSelectionScope.managerOf(context);
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
    Logger.d(
      'Registering segment: id=${widget.segmentId}, offset=${widget.globalStartOffset}, text="${widget.plainText.substring(0, widget.plainText.length > 20 ? 20 : widget.plainText.length)}..."',
      tag: 'TextSelection',
    );

    _manager?.registerSegment(
      widget.segmentId,
      TextSegmentInfo(
        key: _textKey,
        plainText: widget.plainText,
        widgetSpanMappings: widget.widgetSpanMappings,
        globalStartOffset: widget.globalStartOffset,
      ),
    );

    Logger.d(
      'Segment registered. Total segments: ${_manager?.segmentCount}',
      tag: 'TextSelection',
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

  @override
  Widget build(BuildContext context) {
    return Stack(
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
