import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 文本选择区域
class TextSelectionRegion {
  final int startOffset;
  final int endOffset;
  final String selectedText;
  final List<Rect> highlightRects;

  TextSelectionRegion({
    required this.startOffset,
    required this.endOffset,
    required this.selectedText,
    required this.highlightRects,
  });

  bool get isEmpty => startOffset == endOffset;
  int get length => (endOffset - startOffset).abs();

  /// 规范化偏移量（确保 start <= end）
  TextSelectionRegion normalized() {
    if (startOffset <= endOffset) return this;
    return TextSelectionRegion(
      startOffset: endOffset,
      endOffset: startOffset,
      selectedText: selectedText,
      highlightRects: highlightRects,
    );
  }
}

/// 文本选择处理器
/// 用于处理富文本（包含 WidgetSpan）的文本选择功能
class TextSelectionHandler {
  /// 选择起始偏移量
  int? selectionStart;

  /// 选择结束偏移量
  int? selectionEnd;

  /// 当前选择区域
  TextSelectionRegion? _currentSelection;

  /// 是否正在选择
  bool get isSelecting => selectionStart != null && selectionEnd != null;

  /// 是否有有效选择
  bool get hasSelection =>
      _currentSelection != null && !_currentSelection!.isEmpty;

  /// 开始选择
  void startSelection(int offset) {
    selectionStart = offset;
    selectionEnd = offset;
    _currentSelection = null;
  }

  /// 更新选择结束位置
  void updateSelection(int offset) {
    selectionEnd = offset;
  }

  /// 完成选择
  void finishSelection(String plainText) {
    if (selectionStart == null || selectionEnd == null) {
      _currentSelection = null;
      return;
    }

    final start = selectionStart!;
    final end = selectionEnd!;

    if (start == end) {
      _currentSelection = null;
      return;
    }

    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;

    // 确保不越界
    final safeEnd = normalizedEnd > plainText.length
        ? plainText.length
        : normalizedEnd;
    final safeStart = normalizedStart > plainText.length
        ? plainText.length
        : normalizedStart;

    if (safeStart >= safeEnd) {
      _currentSelection = null;
      return;
    }

    final selectedText = plainText.substring(safeStart, safeEnd);

    _currentSelection = TextSelectionRegion(
      startOffset: safeStart,
      endOffset: safeEnd,
      selectedText: selectedText,
      highlightRects: [],
    );
  }

  /// 清除选择
  void clearSelection() {
    selectionStart = null;
    selectionEnd = null;
    _currentSelection = null;
  }

  /// 获取当前选择
  TextSelectionRegion? get currentSelection => _currentSelection;

  /// 从全局坐标获取字符偏移量
  static int? getOffsetFromPosition({
    required GlobalKey textKey,
    required Offset globalPosition,
  }) {
    final renderObject = textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return null;

    final localPosition = renderObject.globalToLocal(globalPosition);
    final textPosition = renderObject.getPositionForOffset(localPosition);
    return textPosition.offset;
  }

  /// 获取选择区域的高亮矩形
  static List<Rect> getSelectionRects({
    required GlobalKey textKey,
    required int startOffset,
    required int endOffset,
  }) {
    final renderObject = textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return [];

    final textLength = renderObject.text.toPlainText().length;
    if (startOffset < 0 || endOffset > textLength || startOffset >= endOffset) {
      return [];
    }

    final selection = TextSelection(
      baseOffset: startOffset,
      extentOffset: endOffset,
    );

    final boxes = renderObject.getBoxesForSelection(selection);
    return boxes.map((box) => box.toRect()).toList();
  }
}

/// 文本选择高亮绘制器
class TextSelectionPainter extends CustomPainter {
  final List<Rect> selectionRects;
  final Color selectionColor;
  final double borderRadius;

  TextSelectionPainter({
    required this.selectionRects,
    required this.selectionColor,
    this.borderRadius = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.fill;

    for (final rect in selectionRects) {
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant TextSelectionPainter oldDelegate) {
    if (selectionRects.length != oldDelegate.selectionRects.length) return true;
    for (int i = 0; i < selectionRects.length; i++) {
      if (selectionRects[i] != oldDelegate.selectionRects[i]) return true;
    }
    return selectionColor != oldDelegate.selectionColor;
  }
}

/// 文本选择覆盖层组件
class TextSelectionOverlay extends StatefulWidget {
  final GlobalKey textKey;
  final int? startOffset;
  final int? endOffset;
  final Color selectionColor;
  final VoidCallback? onSelectionCleared;
  final Widget child;

  const TextSelectionOverlay({
    super.key,
    required this.textKey,
    this.startOffset,
    this.endOffset,
    this.selectionColor = const Color(0x661976D2),
    this.onSelectionCleared,
    required this.child,
  });

  @override
  State<TextSelectionOverlay> createState() => _TextSelectionOverlayState();
}

class _TextSelectionOverlayState extends State<TextSelectionOverlay> {
  List<Rect> _selectionRects = [];

  @override
  void didUpdateWidget(TextSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startOffset != oldWidget.startOffset ||
        widget.endOffset != oldWidget.endOffset) {
      _updateSelectionRects();
    }
  }

  void _updateSelectionRects() {
    if (widget.startOffset == null || widget.endOffset == null) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final start = widget.startOffset!;
    final end = widget.endOffset!;

    if (start == end) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;

    final rects = TextSelectionHandler.getSelectionRects(
      textKey: widget.textKey,
      startOffset: normalizedStart,
      endOffset: normalizedEnd,
    );

    setState(() {
      _selectionRects = rects;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_selectionRects.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: TextSelectionPainter(
                  selectionRects: _selectionRects,
                  selectionColor: widget.selectionColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 选择菜单回调
typedef SelectionMenuCallback = void Function(String selectedText);

/// 文本选择控制器
class TextSelectionController extends ChangeNotifier {
  TextSelectionHandler _handler = TextSelectionHandler();
  bool _isSelecting = false;
  String _plainText = '';

  TextSelectionHandler get handler => _handler;
  bool get isSelecting => _isSelecting;
  TextSelectionRegion? get currentSelection => _handler.currentSelection;

  void setPlainText(String text) {
    _plainText = text;
  }

  void startSelection(int offset) {
    _handler.startSelection(offset);
    _isSelecting = true;
    notifyListeners();
  }

  void updateSelection(int offset) {
    _handler.updateSelection(offset);
    notifyListeners();
  }

  void finishSelection() {
    _handler.finishSelection(_plainText);
    _isSelecting = false;
    notifyListeners();
  }

  void clearSelection() {
    _handler.clearSelection();
    _isSelecting = false;
    notifyListeners();
  }

  String? getSelectedText() {
    return _handler.currentSelection?.selectedText;
  }
}
