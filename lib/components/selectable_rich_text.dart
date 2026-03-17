import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'text_selection_handler.dart';

/// 可选择的富文本组件
/// 支持包含 WidgetSpan 的富文本选择
class SelectableRichText extends StatefulWidget {
  /// 富文本内容
  final InlineSpan textSpan;

  /// 纯文本内容（用于选择操作）
  final String plainText;

  /// 文本样式
  final TextStyle? style;

  /// 选择颜色
  final Color selectionColor;

  /// 选择变化回调
  final void Function(String selectedText)? onSelectionChanged;

  /// 选择完成回调（松手时触发）
  final void Function(String selectedText)? onSelectionComplete;

  const SelectableRichText({
    super.key,
    required this.textSpan,
    required this.plainText,
    this.style,
    this.selectionColor = const Color(0x661976D2),
    this.onSelectionChanged,
    this.onSelectionComplete,
  });

  @override
  State<SelectableRichText> createState() => SelectableRichTextState();
}

class SelectableRichTextState extends State<SelectableRichText> {
  final GlobalKey _textKey = GlobalKey();
  final TextSelectionController _controller = TextSelectionController();

  int? _startOffset;
  int? _endOffset;
  List<Rect> _selectionRects = [];
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller.setPlainText(widget.plainText);
    _controller.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(SelectableRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.plainText != oldWidget.plainText) {
      _controller.setPlainText(widget.plainText);
      clearSelection();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final selection = _controller.currentSelection;
    if (selection != null) {
      widget.onSelectionChanged?.call(selection.selectedText);
    }
  }

  /// 清除选择
  void clearSelection() {
    setState(() {
      _startOffset = null;
      _endOffset = null;
      _selectionRects = [];
      _isDragging = false;
    });
    _controller.clearSelection();
  }

  /// 获取选中的文本
  String? getSelectedText() {
    return _controller.getSelectedText();
  }

  /// 复制选中文本到剪贴板
  Future<void> copySelection() async {
    final text = getSelectedText();
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  int? _getOffsetFromPosition(Offset globalPosition) {
    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) return null;

    final localPosition = renderObject.globalToLocal(globalPosition);
    final textPosition = renderObject.getPositionForOffset(localPosition);
    return textPosition.offset;
  }

  void _updateSelectionRects() {
    if (_startOffset == null || _endOffset == null) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final start = _startOffset!;
    final end = _endOffset!;

    if (start == end) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;

    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final textLength = renderObject.text.toPlainText().length;
    if (normalizedStart < 0 ||
        normalizedEnd > textLength ||
        normalizedStart >= normalizedEnd) {
      setState(() {
        _selectionRects = [];
      });
      return;
    }

    final selection = TextSelection(
      baseOffset: normalizedStart,
      extentOffset: normalizedEnd,
    );

    final boxes = renderObject.getBoxesForSelection(selection);
    setState(() {
      _selectionRects = boxes.map((box) => box.toRect()).toList();
    });
  }

  void _handlePanStart(DragStartDetails details) {
    final offset = _getOffsetFromPosition(details.globalPosition);
    if (offset == null) return;

    setState(() {
      _startOffset = offset;
      _endOffset = offset;
      _isDragging = true;
      _selectionRects = [];
    });
    _controller.startSelection(offset);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final offset = _getOffsetFromPosition(details.globalPosition);
    if (offset == null) return;

    setState(() {
      _endOffset = offset;
    });
    _controller.updateSelection(offset);
    _updateSelectionRects();
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_isDragging) return;

    setState(() {
      _isDragging = false;
    });

    _controller.finishSelection();
    final selectedText = _controller.getSelectedText();
    if (selectedText != null && selectedText.isNotEmpty) {
      widget.onSelectionComplete?.call(selectedText);
      _showSelectionMenu();
    }
  }

  void _showSelectionMenu() {
    // 显示选择菜单（复制等）
    // 这里可以通过 Overlay 或 PopupMenuButton 实现
    // 暂时使用简单的回调方式
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Stack(
        children: [
          Text.rich(widget.textSpan, key: _textKey, style: widget.style),
          if (_selectionRects.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SelectionPainter(
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

class _SelectionPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;

  _SelectionPainter({required this.rects, required this.color});

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
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) {
    if (rects.length != oldDelegate.rects.length) return true;
    for (int i = 0; i < rects.length; i++) {
      if (rects[i] != oldDelegate.rects[i]) return true;
    }
    return color != oldDelegate.color;
  }
}

/// 选择菜单组件
class SelectionMenu extends StatelessWidget {
  final String selectedText;
  final Offset position;
  final VoidCallback? onCopy;
  final VoidCallback? onSearch;
  final VoidCallback? onClose;

  const SelectionMenu({
    super.key,
    required this.selectedText,
    required this.position,
    this.onCopy,
    this.onSearch,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: position.dx,
      top: position.dy - 48,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onCopy != null)
              _MenuButton(icon: Icons.copy, label: '复制', onPressed: onCopy!),
            if (onSearch != null)
              _MenuButton(
                icon: Icons.search,
                label: '查词',
                onPressed: onSearch!,
              ),
            if (onClose != null)
              _MenuButton(icon: Icons.close, label: '关闭', onPressed: onClose!),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
