import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 自定义文本装饰类型
enum CustomDecorationType { underline, doubleUnderline, wavy, dashed }

/// 带自定义装饰位置的文本 Widget
///
/// 使用 Text.rich + TextSpan 保持手势兼容性，
/// 同时用 Stack 叠加装饰线。
class CustomDecoratedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final CustomDecorationType decorationType;
  final Color? decorationColor;
  final double underlineOffset; // 装饰线距离基线的偏移量
  final GestureRecognizer? recognizer;
  final MouseCursor? mouseCursor;
  final void Function(Offset position, String text)? onShowMenu;
  /// 双击查词回调
  final void Function(String word, Offset position)? onDoubleTapWord;
  /// 单击查词回调
  final VoidCallback? onTap;

  const CustomDecoratedText({
    super.key,
    required this.text,
    required this.style,
    required this.decorationType,
    this.decorationColor,
    this.underlineOffset = 5.0,
    this.recognizer,
    this.mouseCursor,
    this.onShowMenu,
    this.onDoubleTapWord,
    this.onTap,
  });

  @override
  State<CustomDecoratedText> createState() => _CustomDecoratedTextState();
}

class _CustomDecoratedTextState extends State<CustomDecoratedText> {
  final GlobalKey _textKey = GlobalKey();
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  @override
  Widget build(BuildContext context) {
    final effectiveDecorationColor =
        widget.decorationColor ?? widget.style.color ?? Colors.black;

    // 使用 TextPainter 测量文本尺寸
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final textWidth = textPainter.width;
    final baseline = textPainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    // 使用普通 Text widget，不使用 TextSpan.recognizer
    // 所有手势由 GestureDetector 处理
    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Text(widget.text, style: widget.style, key: _textKey),
        // 装饰线 - 使用 Positioned 定位
        Positioned(
          top: baseline + widget.underlineOffset,
          left: 0,
          child: IgnorePointer(
            ignoring: true,
            child: CustomPaint(
              size: Size(textWidth, 4),
              painter: _DecorationPainter(
                width: textWidth,
                decorationType: widget.decorationType,
                color: effectiveDecorationColor,
              ),
            ),
          ),
        ),
      ],
    );

    // 添加鼠标样式
    if (widget.mouseCursor != null) {
      content = MouseRegion(cursor: widget.mouseCursor!, child: content);
    }

    // 使用 GestureDetector 处理所有手势
    content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        _lastTapPosition = details.globalPosition;
        // 同时通知外层的 recognizer
        if (widget.recognizer != null) {
          // 对于 TapGestureRecognizer，需要调用 addPointer
          // 但这里我们使用自己的手势处理
        }
      },
      onTap: () {
        // 检测双击
        final now = DateTime.now();
        final isDoubleTap = _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300);

        if (isDoubleTap && _lastTapPosition != null) {
          _handleDoubleTap(_lastTapPosition!);
          _lastTapTime = null;
        } else {
          _lastTapTime = now;
          // 单击时触发 onTap 回调（如果有）
          widget.onTap?.call();
        }
      },
      onSecondaryTapDown: (details) {
        if (widget.onShowMenu != null) {
          widget.onShowMenu!(details.globalPosition, widget.text);
        }
      },
      onLongPress: () {
        if (widget.onShowMenu != null && _lastTapPosition != null) {
          widget.onShowMenu!(_lastTapPosition!, widget.text);
        }
      },
      child: content,
    );

    return content;
  }

  void _handleDoubleTap(Offset globalPosition) {
    if (widget.onDoubleTapWord == null) return;

    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }

    // 查找 RenderParagraph（可能被 Stack 等包装）
    RenderParagraph? renderParagraph;
    if (renderObject is RenderParagraph) {
      renderParagraph = renderObject;
    } else {
      void visitChild(RenderObject child) {
        if (child is RenderParagraph) {
          renderParagraph = child;
        } else {
          child.visitChildren(visitChild);
        }
      }
      renderObject.visitChildren(visitChild);
    }

    if (renderParagraph == null) {
      return;
    }

    // 使用 late 或强制非空，因为我们已经检查了 null
    final rp = renderParagraph!;
    final localPosition = rp.globalToLocal(globalPosition);
    final textPosition = rp.getPositionForOffset(localPosition);
    final offset = textPosition.offset;

    // 提取点击位置的单词
    final word = _extractWordAtOffset(widget.text, offset);
    if (word.isNotEmpty) {
      widget.onDoubleTapWord!(word, globalPosition);
    }
  }

  String _extractWordAtOffset(String text, int offset) {
    if (offset < 0 || offset >= text.length) return '';

    // 找到单词的起始和结束位置
    int start = offset;
    int end = offset;

    // 向左扩展
    while (start > 0 && _isWordChar(text[start - 1])) {
      start--;
    }

    // 向右扩展
    while (end < text.length && _isWordChar(text[end])) {
      end++;
    }

    return text.substring(start, end);
  }

  bool _isWordChar(String char) {
    // 检查是否是字母、数字或 CJK 字符
    final codeUnit = char.codeUnitAt(0);
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
        (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) || // CJK
        (codeUnit >= 0x3040 && codeUnit <= 0x30FF) || // 日文
        (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF); // 韩文
  }
}

class _DecorationPainter extends CustomPainter {
  final double width;
  final CustomDecorationType decorationType;
  final Color color;

  _DecorationPainter({
    required this.width,
    required this.decorationType,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    switch (decorationType) {
      case CustomDecorationType.underline:
        canvas.drawLine(Offset.zero, Offset(width, 0), paint);
        break;
      case CustomDecorationType.doubleUnderline:
        canvas.drawLine(const Offset(0, 0), Offset(width, 0), paint);
        canvas.drawLine(const Offset(0, 2), Offset(width, 2), paint);
        break;
      case CustomDecorationType.wavy:
        _drawWavy(canvas, paint, width);
        break;
      case CustomDecorationType.dashed:
        _drawDashed(canvas, paint, width);
        break;
    }
  }

  void _drawWavy(Canvas canvas, Paint paint, double width) {
    const waveHeight = 1.5;
    const waveLength = 6.0;

    final path = Path();
    path.moveTo(0, 0);

    double x = 0;
    bool up = true;

    while (x < width) {
      final nextX = math.min(x + waveLength / 2, width);
      final nextY = up ? -waveHeight : waveHeight;
      path.lineTo(nextX, nextY);
      x = nextX;
      up = !up;
    }

    canvas.drawPath(path, paint);
  }

  void _drawDashed(Canvas canvas, Paint paint, double width) {
    const dashWidth = 4.0;
    const dashGap = 2.0;
    double x = 0;
    while (x < width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DecorationPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.decorationType != decorationType ||
        oldDelegate.color != color;
  }
}
