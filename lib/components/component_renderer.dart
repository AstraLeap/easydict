import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:visibility_detector/visibility_detector.dart';

import '../core/constants/entry_keys.dart' show kExcludedEntryKeys;
import '../core/logger.dart';
import 'rendering/custom_text_decoration.dart';
import 'rendering/formatted_text_parser.dart'
    show
        parseFormattedText,
        FormattedTextResult,
        kRubySpacingRatio,
        TypeParser,
        CustomDecoration;
import 'rendering/ruby_layout.dart';
import '../core/utils/dict_typography.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/responsive_utils.dart';
import '../core/utils/toast_utils.dart';
import '../data/database_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../i18n/strings.g.dart';
import '../pages/entry_detail_page.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/ai_service.dart';
import '../services/dictionary_manager.dart';
import '../services/entry_event_bus.dart';
import '../services/font_loader_service.dart';
import '../services/media_kit_manager.dart';
import '../services/preferences_service.dart';
import '../services/search_history_service.dart';
import '../models/browse_list.dart';
import '../services/tts_cache_service.dart';
import 'board_widget.dart';
import 'dictionary_interaction_scope.dart';
import 'global_scale_wrapper.dart';
import 'hidden_languages_scope.dart';
import 'path_scope.dart';

// 颜色映射表
const Map<String, Color> _colorMap = {
  'red': Colors.red,
  'green': Colors.green,
  'blue': Colors.blue,
  'yellow': Colors.yellow,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'grey': Colors.grey,
  'gray': Colors.grey,
  'black': Colors.black,
  'white': Colors.white,
};

class _PathData {
  final List<String> path;
  final String label;

  _PathData(this.path, this.label);
}

/// 待处理的滚动请求
class _PendingScrollRequest {
  final String path;
  final int retryCount;

  _PendingScrollRequest(this.path, this.retryCount);
}

/// 支持多种手势的识别器，继承自 TapGestureRecognizer 以兼容无障碍系统
class _MultiGestureRecognizer extends TapGestureRecognizer {
  final TapGestureRecognizer tapRecognizer;
  final _SecondaryTapGestureRecognizer secondaryTapRecognizer;
  final LongPressGestureRecognizer? longPressRecognizer;
  final DoubleTapGestureRecognizer? doubleTapRecognizer;

  // 跟踪是否是右键操作
  bool _isSecondaryButton = false;

  _MultiGestureRecognizer({
    required this.tapRecognizer,
    required this.secondaryTapRecognizer,
    this.longPressRecognizer,
    this.doubleTapRecognizer,
  });

  @override
  void addPointer(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      _isSecondaryButton = true;
      secondaryTapRecognizer.addPointer(event);
    } else {
      _isSecondaryButton = false;
      tapRecognizer.addPointer(event);
      longPressRecognizer?.addPointer(event);
      doubleTapRecognizer?.addPointer(event);
    }
  }

  @override
  String get debugDescription => '_MultiGestureRecognizer';

  @override
  void handleEvent(PointerEvent event) {
    // 使用 _isSecondaryButton 标志来判断是否是右键操作
    // 因为 PointerUpEvent 时 buttons 已经是 0
    if (_isSecondaryButton) {
      secondaryTapRecognizer.handleEvent(event);
    } else {
      tapRecognizer.handleEvent(event);
      longPressRecognizer?.handleEvent(event);
    }
  }
}

/// 自定义右键手势识别器
class _SecondaryTapGestureRecognizer extends OneSequenceGestureRecognizer {
  GestureTapUpCallback? onSecondaryTapUp;

  PointerDeviceKind? _kind;

  @override
  void addPointer(PointerDownEvent event) {
    Logger.d(
      '_SecondaryTapGestureRecognizer.addPointer: buttons=${event.buttons}, kSecondaryMouseButton=$kSecondaryMouseButton',
      tag: 'DoubleTapWord',
    );
    if (event.buttons == kSecondaryMouseButton) {
      startTrackingPointer(event.pointer);
      _kind = event.kind;
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    Logger.d(
      '_SecondaryTapGestureRecognizer.handleEvent: ${event.runtimeType}, buttons=${event.buttons}',
      tag: 'DoubleTapWord',
    );
    if (event is PointerUpEvent && event.buttons == 0) {
      Logger.d(
        '_SecondaryTapGestureRecognizer: calling onSecondaryTapUp',
        tag: 'DoubleTapWord',
      );
      if (onSecondaryTapUp != null) {
        onSecondaryTapUp!(
          TapUpDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
            kind: _kind ?? PointerDeviceKind.mouse,
          ),
        );
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => '_SecondaryTapGestureRecognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {
    _kind = null;
  }
}

/// 高亮闪烁包装器 - 用于滚动到目标元素时显示闪烁效果
class _HighlightWrapper extends StatefulWidget {
  final bool isHighlighting;
  final Widget child;

  const _HighlightWrapper({required this.isHighlighting, required this.child});

  @override
  State<_HighlightWrapper> createState() => _HighlightWrapperState();
}

class _HighlightWrapperState extends State<_HighlightWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInQuart)),
        weight: 3,
      ),
    ]).animate(_controller);

    if (widget.isHighlighting) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_HighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighting != oldWidget.isHighlighting) {
      if (widget.isHighlighting) {
        _controller.forward(from: 0.0);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = colorScheme.primary.withValues(alpha: 0.10);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: widget.isHighlighting
                ? Color.lerp(
                    Colors.transparent,
                    highlightColor,
                    _animation.value,
                  )
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _TappableWrapper extends SingleChildRenderObjectWidget {
  final _PathData pathData;

  const _TappableWrapper({required this.pathData, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTappable(pathData);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTappable renderObject) {
    renderObject.pathData = pathData;
  }
}

class _RenderTappable extends RenderProxyBox {
  _PathData pathData;

  _RenderTappable(this.pathData);
}

/// 自动缩放字体文本组件
/// 当文本超出可用宽度时，自动缩小字体以适应一行显示
class _AutoScalingText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final DictElementType elementType;
  final Map<String, Map<String, double>> fontScales;
  final String? sourceLanguage;
  final double maxWidth;
  final bool isBold;
  final List<InlineSpan>? spans;

  const _AutoScalingText({
    required this.text,
    required this.baseStyle,
    required this.elementType,
    required this.fontScales,
    this.sourceLanguage,
    required this.maxWidth,
    this.isBold = false,
    this.spans,
  });

  @override
  Widget build(BuildContext context) {
    // 获取缩放后的样式
    final scaledStyle = DictTypography.getScaledStyle(
      elementType,
      language: sourceLanguage,
      fontScales: fontScales,
      color: baseStyle.color,
    );

    // 合并基础样式和缩放样式
    final effectiveStyle = scaledStyle.merge(
      TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
    );

    // 使用传入的spans或创建纯文本span
    final textSpans = spans ?? [TextSpan(text: text, style: effectiveStyle)];

    // 检查是否包含 WidgetSpan
    // WidgetSpan 使用 PlaceholderAlignment.baseline 时，TextPainter.layout() 会失败
    // 因为此时 widget 尺寸（dimensions）未知
    final hasWidgetSpan = textSpans.any((span) => span is WidgetSpan);

    // 如果包含 WidgetSpan，跳过宽度计算，直接返回 Text.rich
    // 因为 TextPainter 无法正确处理带有 baseline 对齐的 WidgetSpan
    if (hasWidgetSpan) {
      return Text.rich(
        TextSpan(children: textSpans, style: effectiveStyle),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // 计算文本宽度
    final textPainter = TextPainter(
      text: TextSpan(children: textSpans, style: effectiveStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final textWidth = textPainter.width;
    final availableWidth = maxWidth;

    // 如果文本宽度超过可用宽度，使用FittedBox进行缩放
    if (textWidth > availableWidth && textWidth > 0) {
      // 使用FittedBox确保文本在一行内完整显示
      return SizedBox(
        width: availableWidth,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: textSpans, style: effectiveStyle),
            maxLines: 1,
          ),
        ),
      );
    }

    // 文本宽度足够，正常显示
    return Text.rich(
      TextSpan(children: textSpans, style: effectiveStyle),
      maxLines: 1,
    );
  }
}

// 预编译的正则表达式常量，避免每次调用时重新创建对象
final RegExp _removeFormattingPattern = RegExp(r'\[([^\]]*?)\]\([^\)]*?\)');

const int _maxNestingDepth = 10;

class _ParseContext {
  final String text;
  int pos = 0;
  final int maxDepth;
  int currentDepth = 0;

  _ParseContext(this.text, {this.maxDepth = _maxNestingDepth});

  bool get isAtEnd => pos >= text.length;
  String get currentChar => isAtEnd ? '' : text[pos];
  String get peekNext => pos + 1 >= text.length ? '' : text[pos + 1];
}

class _ParsedSegment {
  final String? plainText;
  final String? formattedText;
  final String? typesStr;
  final List<_ParsedSegment>? children;
  // Ruby 支持
  final bool isRuby;
  final String? rubyText;

  _ParsedSegment.plain(this.plainText)
    : formattedText = null,
      typesStr = null,
      children = null,
      isRuby = false,
      rubyText = null;

  _ParsedSegment.formatted(this.formattedText, this.typesStr, this.children)
    : plainText = null,
      isRuby = false,
      rubyText = null;

  _ParsedSegment.ruby(this.formattedText, this.rubyText)
    : plainText = null,
      typesStr = null,
      children = null,
      isRuby = true;

  bool get isPlain => plainText != null;
  bool get isFormatted => formattedText != null;
}

List<_ParsedSegment> _parseSegments(_ParseContext ctx) {
  final segments = <_ParsedSegment>[];
  final buffer = StringBuffer();

  while (!ctx.isAtEnd) {
    if (ctx.currentChar == '[') {
      if (buffer.isNotEmpty) {
        segments.add(_ParsedSegment.plain(buffer.toString()));
        buffer.clear();
      }

      final segment = _tryParseFormattedSegment(ctx);
      if (segment != null) {
        segments.add(segment);
      } else {
        buffer.write('[');
        ctx.pos++;
      }
    } else {
      buffer.write(ctx.currentChar);
      ctx.pos++;
    }
  }

  if (buffer.isNotEmpty) {
    segments.add(_ParsedSegment.plain(buffer.toString()));
  }

  return segments;
}

_ParsedSegment? _tryParseFormattedSegment(_ParseContext ctx) {
  if (ctx.currentChar != '[') return null;

  final startPos = ctx.pos;
  ctx.pos++;

  final contentBuffer = StringBuffer();
  int bracketDepth = 1;

  while (!ctx.isAtEnd && bracketDepth > 0) {
    final ch = ctx.currentChar;

    if (ch == '[') {
      bracketDepth++;
      contentBuffer.write(ch);
      ctx.pos++;
    } else if (ch == ']') {
      bracketDepth--;
      if (bracketDepth > 0) {
        contentBuffer.write(ch);
      }
      ctx.pos++;
    } else {
      contentBuffer.write(ch);
      ctx.pos++;
    }
  }

  if (ctx.isAtEnd || ctx.currentChar != '(') {
    ctx.pos = startPos;
    return null;
  }

  ctx.pos++;

  final typesBuffer = StringBuffer();
  int parenDepth = 1;

  while (!ctx.isAtEnd && parenDepth > 0) {
    final ch = ctx.currentChar;

    if (ch == '(') {
      parenDepth++;
      typesBuffer.write(ch);
      ctx.pos++;
    } else if (ch == ')') {
      parenDepth--;
      if (parenDepth > 0) {
        typesBuffer.write(ch);
      }
      ctx.pos++;
    } else {
      typesBuffer.write(ch);
      ctx.pos++;
    }
  }

  if (parenDepth != 0) {
    ctx.pos = startPos;
    return null;
  }

  final content = contentBuffer.toString();
  final typesStr = typesBuffer.toString();

  // 检测 Ruby 语法: [漢](:かん) - typesStr 以冒号开头表示振假名
  if (typesStr.startsWith(':') && content.isNotEmpty) {
    final rubyText = typesStr.substring(1);
    if (rubyText.isNotEmpty) {
      return _ParsedSegment.ruby(content, rubyText);
    }
  }

  if (content.contains('[') && content.contains('](')) {
    if (ctx.currentDepth >= ctx.maxDepth) {
      return _ParsedSegment.formatted(content, typesStr, null);
    }

    ctx.currentDepth++;
    final nestedCtx = _ParseContext(content, maxDepth: ctx.maxDepth)
      ..currentDepth = ctx.currentDepth;
    final children = _parseSegments(nestedCtx);
    ctx.currentDepth--;

    return _ParsedSegment.formatted(content, typesStr, children);
  }

  return _ParsedSegment.formatted(content, typesStr, null);
}

String _removeFormatting(String text) {
  return text.replaceAllMapped(
    _removeFormattingPattern,
    (match) => match.group(1) ?? '',
  );
}

String? _extractTextToCopy(dynamic value) {
  final result = _extractTextRecursive(value);
  return result.isNotEmpty ? result : null;
}

/// 递归提取文本内容，移除格式标记
String _extractTextRecursive(dynamic value) {
  if (value == null) return '';
  if (value is String) {
    return _removeFormatting(value);
  }
  if (value is Map) {
    // 优先使用常见的文本字段
    final textKeys = ['text', 'word', 'content'];
    for (final key in textKeys) {
      if (value.containsKey(key)) {
        final text = value[key];
        if (text is String && text.isNotEmpty) {
          return _removeFormatting(text);
        }
      }
    }
    // 如果没有直接的文本字段，递归提取所有值
    final parts = <String>[];
    for (final entry in value.entries) {
      final extracted = _extractTextRecursive(entry.value);
      if (extracted.isNotEmpty) {
        parts.add(extracted);
      }
    }
    return parts.join(' ');
  }
  if (value is List) {
    final parts = <String>[];
    for (final item in value) {
      final extracted = _extractTextRecursive(item);
      if (extracted.isNotEmpty) {
        parts.add(extracted);
      }
    }
    return parts.join(' ');
  }
  return value.toString();
}

String _convertPathToString(List<String> path) {
  return path.join('.');
}

/// 判断字符串是否为已知语言代码（非路径组件）
bool _isKnownLanguageCode(String key) {
  const known = {
    'en',
    'zh',
    'jp',
    'ko',
    'fr',
    'de',
    'es',
    'it',
    'ru',
    'pt',
    'ar',
  };
  return known.contains(key) ||
      key.startsWith('zh_') ||
      key.startsWith('jp_') ||
      key.startsWith('ko_');
}

String? _determineEffectiveLanguage({
  String? language,
  List<String>? path,
  String? sourceLanguage,
}) {
  if (language != null && language.isNotEmpty) {
    return language;
  } else if (path != null && path.isNotEmpty) {
    final firstKey = path.first;
    // 仅当 path.first 是真正的语言代码时才用它（路径通常以 'entry'、'sense' 等开头）
    if (_isKnownLanguageCode(firstKey)) {
      return firstKey;
    } else {
      return sourceLanguage;
    }
  } else {
    return sourceLanguage;
  }
}

class _StyleInfo {
  TextStyle style;
  List<TextDecoration> decorations;
  bool isSup;
  bool isSub;
  bool aiTextMark;
  bool isWordLabel;
  bool isLabelType;
  Color? customColor;
  String? linkTarget;
  String? exactJumpTarget;
  List<CustomDecoration> customDecorations;

  _StyleInfo({
    required this.style,
    this.decorations = const [],
    this.isSup = false,
    this.isSub = false,
    this.aiTextMark = false,
    this.isWordLabel = false,
    this.isLabelType = false,
    this.customColor,
    this.linkTarget,
    this.exactJumpTarget,
    this.customDecorations = const [],
  });

  bool get hasCustomDecorations => customDecorations.isNotEmpty;
}

_StyleInfo _parseTypes(
  String typesStr,
  TextStyle baseStyle,
  BuildContext? context,
) {
  final types = typesStr.split(',').map((t) => t.trim()).toList();

  TextStyle style = baseStyle;
  List<TextDecoration> decorations = [];
  List<CustomDecoration> customDecorations = [];
  bool isSup = false;
  bool isSub = false;
  bool aiTextMark = false;
  bool isWordLabel = false;
  Color? customColor;
  String? linkTarget;
  String? exactJumpTarget;

  for (final type in types) {
    if (_colorMap.containsKey(type.toLowerCase())) {
      customColor = _colorMap[type.toLowerCase()];
      continue;
    }

    if (type.startsWith('->')) {
      linkTarget = type.substring(2).trim();
      continue;
    }

    if (type.startsWith('==')) {
      exactJumpTarget = type.substring(2).trim();
      continue;
    }

    switch (type) {
      case 'strike':
        decorations.add(TextDecoration.lineThrough);
        break;
      case 'underline':
        customDecorations.add(CustomDecoration.underline);
        break;
      case 'double_underline':
        customDecorations.add(CustomDecoration.doubleUnderline);
        break;
      case 'wavy':
        customDecorations.add(CustomDecoration.wavy);
        break;
      case 'dashed':
        customDecorations.add(CustomDecoration.dashed);
        break;
      case 'bold':
        style = style.copyWith(
          fontWeight: types.contains('label')
              ? FontWeight.w600
              : FontWeight.bold,
        );
        break;
      case 'italic':
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'sup':
        isSup = true;
        break;
      case 'sub':
        isSub = true;
        break;
      case 'special':
        style = style.copyWith(
          fontStyle: FontStyle.italic,
          color: context != null ? Theme.of(context).colorScheme.primary : null,
        );
        break;
      case 'ai':
        aiTextMark = true;
        break;
      case 'label':
        isSup = false;
        style = style.copyWith(fontWeight: FontWeight.w500);
        break;
      case 'word':
        isWordLabel = true;
        style = style.copyWith(fontWeight: FontWeight.w700);
        break;
    }
  }

  final isLabelType = types.contains('label');

  if (decorations.isNotEmpty) {
    style = style.copyWith(
      decoration: TextDecoration.combine(decorations),
      decorationColor: baseStyle.color,
    );
  }

  if (customColor != null) {
    style = style.copyWith(color: customColor);
  }

  return _StyleInfo(
    style: style,
    decorations: decorations,
    isSup: isSup,
    isSub: isSub,
    aiTextMark: aiTextMark,
    isWordLabel: isWordLabel,
    isLabelType: isLabelType,
    customColor: customColor,
    linkTarget: linkTarget,
    exactJumpTarget: exactJumpTarget,
    customDecorations: customDecorations,
  );
}

void _processSegments({
  required List<_ParsedSegment> segments,
  required TextStyle baseStyle,
  required BuildContext? context,
  required GestureRecognizer? recognizer,
  required MouseCursor? mouseCursor,
  required String? effectiveLanguage,
  required List<InlineSpan> spans,
  required List<String> plainTexts,
  void Function(Offset position, String text)? onShowMenu,
  GlobalKey? textKey,
  void Function(String word, Offset position)? onDoubleTapWord,
}) {
  for (final segment in segments) {
    if (segment.isPlain) {
      final text = segment.plainText!;
      spans.add(
        TextSpan(
          text: text,
          style: baseStyle,
          recognizer: recognizer,
          mouseCursor: mouseCursor,
        ),
      );
      plainTexts.add(text);
    } else if (segment.isRuby) {
      // 处理 Ruby 文本
      _processRubySegment(
        segment: segment,
        baseStyle: baseStyle,
        context: context,
        recognizer: recognizer,
        mouseCursor: mouseCursor,
        spans: spans,
        plainTexts: plainTexts,
        onShowMenu: onShowMenu,
      );
    } else if (segment.isFormatted) {
      _processFormattedSegment(
        segment: segment,
        baseStyle: baseStyle,
        context: context,
        recognizer: recognizer,
        mouseCursor: mouseCursor,
        effectiveLanguage: effectiveLanguage,
        spans: spans,
        plainTexts: plainTexts,
        onShowMenu: onShowMenu,
        textKey: textKey,
        onDoubleTapWord: onDoubleTapWord,
      );
    }
  }
}

/// 处理 Ruby（振假名）段落
void _processRubySegment({
  required _ParsedSegment segment,
  required TextStyle baseStyle,
  required BuildContext? context,
  required GestureRecognizer? recognizer,
  required MouseCursor? mouseCursor,
  required List<InlineSpan> spans,
  required List<String> plainTexts,
  void Function(Offset position, String text)? onShowMenu,
}) {
  final baseText = segment.formattedText ?? '';
  final rubyText = segment.rubyText ?? '';

  if (baseText.isEmpty) return;

  // Ruby 文本的基础字体大小
  final baseFontSize = baseStyle.fontSize ?? 14.0;
  // 振假名字体大小为基础字体的 50%
  final rubyFontSize = baseFontSize * 0.5;
  // 假名与汉字之间的间距（基于字体大小动态计算）
  final rubySpacing = baseFontSize * kRubySpacingRatio;

  spans.add(
    WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _RubyTextLayout(
        rubyFontSize: rubyFontSize,
        rubySpacing: rubySpacing,
        baseText: baseText,
        baseStyle: baseStyle,
        rubyText: rubyText,
        onShowMenu: onShowMenu,
      ),
    ),
  );

  plainTexts.add(baseText);
}

/// Ruby 文本布局组件
/// 使用共享的 RubyLayout 组件正确处理基线对齐
class _RubyTextLayout extends StatelessWidget {
  final double rubyFontSize;
  final double rubySpacing;
  final String baseText;
  final TextStyle baseStyle;
  final String rubyText;
  final void Function(Offset position, String text)? onShowMenu;

  const _RubyTextLayout({
    required this.rubyFontSize,
    required this.rubySpacing,
    required this.baseText,
    required this.baseStyle,
    required this.rubyText,
    this.onShowMenu,
  });

  @override
  Widget build(BuildContext context) {
    final rubyColor = Theme.of(context).colorScheme.primary;
    Widget rubyWidget = RubyLayout(
      rubyFontSize: rubyFontSize,
      rubySpacing: rubySpacing,
      baseText: baseText,
      baseStyle: baseStyle,
      rubyText: rubyText,
      rubyColor: rubyColor,
    );

    if (onShowMenu != null) {
      rubyWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            onShowMenu!(event.position, baseText);
          }
        },
        child: rubyWidget,
      );
    }

    return rubyWidget;
  }
}

void _processFormattedSegment({
  required _ParsedSegment segment,
  required TextStyle baseStyle,
  required BuildContext? context,
  required GestureRecognizer? recognizer,
  required MouseCursor? mouseCursor,
  required String? effectiveLanguage,
  required List<InlineSpan> spans,
  required List<String> plainTexts,
  void Function(Offset position, String text)? onShowMenu,
  GlobalKey? textKey,
  void Function(String word, Offset position)? onDoubleTapWord,
}) {
  final typesStr = segment.typesStr ?? '';
  final styleInfo = _parseTypes(typesStr, baseStyle, context);

  if (segment.children != null && segment.children!.isNotEmpty) {
    final childSpans = <InlineSpan>[];
    final childPlainTexts = <String>[];

    _processSegments(
      segments: segment.children!,
      baseStyle: styleInfo.style,
      context: context,
      recognizer: recognizer,
      mouseCursor: mouseCursor,
      effectiveLanguage: effectiveLanguage,
      spans: childSpans,
      plainTexts: childPlainTexts,
      onShowMenu: onShowMenu,
      onDoubleTapWord: onDoubleTapWord,
    );

    spans.add(
      TextSpan(
        children: childSpans,
        style: styleInfo.style,
        recognizer: recognizer,
        mouseCursor: mouseCursor,
      ),
    );
    plainTexts.addAll(childPlainTexts);
    return;
  }

  final formattedText = segment.formattedText ?? '';

  if (styleInfo.linkTarget != null && context != null) {
    var style = styleInfo.style.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    spans.add(
      TextSpan(
        text: formattedText,
        style: style,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            _handleLinkTap(context, styleInfo.linkTarget!);
          },
      ),
    );
  } else if (styleInfo.exactJumpTarget != null && context != null) {
    var style = styleInfo.style.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );
    spans.add(
      TextSpan(
        text: formattedText,
        style: style,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            _handleExactJump(context, styleInfo.exactJumpTarget!);
          },
      ),
    );
  } else if (styleInfo.isLabelType && context != null) {
    final labelBaseSize = baseStyle.fontSize ?? 12.0;
    var labelStyle = styleInfo.style.copyWith(fontSize: labelBaseSize * 0.85);
    if (styleInfo.isWordLabel) {
      final serifFontInfo = FontLoaderService().getFontInfo(
        effectiveLanguage ?? '',
        isSerif: true,
      );
      if (serifFontInfo != null) {
        labelStyle = labelStyle.copyWith(fontFamily: serifFontInfo.fontFamily);
      }
    }
    final borderColor = Theme.of(context).colorScheme.outline.withAlpha(140);
    final bgColor = Theme.of(context).colorScheme.onSurface.withAlpha(13);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(formattedText, style: labelStyle),
        ),
      ),
    );
  } else if (styleInfo.isSup) {
    // 使用 FontFeature.superscripts 实现上标
    // 这是 TextSpan 样式，不是 WidgetSpan，所以文本选择功能可以正常工作
    spans.add(
      TextSpan(
        text: formattedText,
        style: styleInfo.style.copyWith(
          fontSize: baseStyle.fontSize != null
              ? baseStyle.fontSize! * 0.7
              : null,
          fontFeatures: [FontFeature.superscripts()],
        ),
        recognizer: recognizer,
        mouseCursor: mouseCursor,
      ),
    );
  } else if (styleInfo.isSub) {
    // 使用 FontFeature.subscripts 实现下标
    // 这是 TextSpan 样式，不是 WidgetSpan，所以文本选择功能可以正常工作
    spans.add(
      TextSpan(
        text: formattedText,
        style: styleInfo.style.copyWith(
          fontSize: baseStyle.fontSize != null
              ? baseStyle.fontSize! * 0.7
              : null,
          fontFeatures: [FontFeature.subscripts()],
        ),
        recognizer: recognizer,
        mouseCursor: mouseCursor,
      ),
    );
  } else {
    var style = styleInfo.style;
    if (styleInfo.aiTextMark && context != null) {
      final bgColor = Theme.of(context).colorScheme.primaryContainer;
      style = style.copyWith(backgroundColor: bgColor.withAlpha(115));
    }

    // 如果有自定义装饰，使用 CustomDecoratedText
    if (styleInfo.hasCustomDecorations) {
      final customDec = styleInfo.customDecorations.first;
      CustomDecorationType decType;
      switch (customDec) {
        case CustomDecoration.underline:
          decType = CustomDecorationType.underline;
          break;
        case CustomDecoration.doubleUnderline:
          decType = CustomDecorationType.doubleUnderline;
          break;
        case CustomDecoration.wavy:
          decType = CustomDecorationType.wavy;
          break;
        case CustomDecoration.dashed:
          decType = CustomDecorationType.dashed;
          break;
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: CustomDecoratedText(
            text: formattedText,
            style: style,
            decorationType: decType,
            decorationColor: style.color,
            recognizer: recognizer,
            mouseCursor: mouseCursor,
            onShowMenu: onShowMenu,
            onDoubleTapWord: onDoubleTapWord,
          ),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: formattedText,
          style: style,
          recognizer: recognizer,
          mouseCursor: mouseCursor,
        ),
      );
    }
  }
  plainTexts.add(formattedText);
}

Future<void> _handleLinkTap(BuildContext context, String word) async {
  if (word.isEmpty) return;

  final dbService = DatabaseService();
  final historyService = SearchHistoryService();

  final result = await dbService.getAllEntries(word);

  if (result.entries.isNotEmpty) {
    final entryGroup = DictionaryEntryGroup.groupEntries(result.entries);

    // 获取语言信息
    String? group;
    final dictId = result.entries.first.dictId;
    if (dictId != null) {
      final metadata = await DictionaryManager().getDictionaryMetadata(dictId);
      group = metadata?.sourceLanguage;
    }
    await historyService.addSearchRecord(word, group: group);

    // 获取历史记录构建浏览列表
    final records = await historyService.getSearchRecords();
    final historyWords = records.map((r) => r.word).toList();
    final currentIndex = historyWords.indexOf(word);

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EntryDetailPage(
            entryGroup: entryGroup,
            initialWord: word,
            browseList: historyWords.isNotEmpty
                ? BrowseList(
                    source: BrowseListSource.searchHistory,
                    words: historyWords,
                    initialIndex: currentIndex >= 0 ? currentIndex : 0,
                  )
                : null,
          ),
        ),
      );
    }
  } else {
    if (context.mounted) {
      showToast(context, context.t.entry.wordNotFound(word: word));
    }
  }
}

Future<void> _handleExactJump(
  BuildContext context,
  String target, {
  String? currentDictId,
}) async {
  // target format: entry_id 或 entry_id:path (e.g., 25153 或 25153:sense.0)
  Logger.d(
    '_handleExactJump: target=$target, currentDictId=$currentDictId',
    tag: 'ExactJump',
  );

  if (target.isEmpty) {
    if (context.mounted) {
      showToast(context, context.t.entry.entryNotFound(entryId: target));
    }
    return;
  }

  // 使用新的解析方法，支持 : 和 . 分隔符
  final (:entryId, :path) = TypeParser.parseExactJumpTarget(target);

  final dictManager = DictionaryManager();

  DictionaryEntry? targetEntry;

  // 1. 优先在当前词典中查找
  if (currentDictId != null && currentDictId.isNotEmpty) {
    Logger.d(
      '_handleExactJump: searching in current dict $currentDictId',
      tag: 'ExactJump',
    );
    targetEntry = await _findEntryInDict(dictManager, currentDictId, entryId);
    if (targetEntry != null) {
      Logger.d('_handleExactJump: found in current dict', tag: 'ExactJump');
    }
  }

  // 2. 如果当前词典没找到，在所有启用词典中查找
  if (targetEntry == null) {
    Logger.d(
      '_handleExactJump: searching in all enabled dicts',
      tag: 'ExactJump',
    );
    final enabledDicts = await dictManager.getEnabledDictionariesMetadata();
    for (final metadata in enabledDicts) {
      if (currentDictId != null && metadata.id == currentDictId)
        continue; // 已查询过
      targetEntry = await _findEntryInDict(dictManager, metadata.id, entryId);
      if (targetEntry != null) {
        Logger.d(
          '_handleExactJump: found in dict ${metadata.id}',
          tag: 'ExactJump',
        );
        break;
      }
    }
  }

  if (targetEntry != null) {
    if (context.mounted) {
      final entryGroup = DictionaryEntryGroup.groupEntries([targetEntry]);
      final word = targetEntry.headword;

      // 获取语言信息并记录搜索历史
      String? group;
      final dictId = targetEntry.dictId;
      if (dictId != null) {
        final metadata = await DictionaryManager().getDictionaryMetadata(
          dictId,
        );
        group = metadata?.sourceLanguage;
      }
      final historyService = SearchHistoryService();
      await historyService.addSearchRecord(word, group: group);

      // 获取历史记录构建浏览列表
      final records = await historyService.getSearchRecords();
      final historyWords = records.map((r) => r.word).toList();
      final currentIndex = historyWords.indexOf(word);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EntryDetailPage(
            entryGroup: entryGroup,
            initialWord: word,
            browseList: historyWords.isNotEmpty
                ? BrowseList(
                    source: BrowseListSource.searchHistory,
                    words: historyWords,
                    initialIndex: currentIndex >= 0 ? currentIndex : 0,
                  )
                : null,
          ),
        ),
      );
    }
  } else {
    Logger.d('_handleExactJump: entry not found: $entryId', tag: 'ExactJump');
    if (context.mounted) {
      showToast(context, context.t.entry.entryNotFound(entryId: entryId));
    }
  }
}

Future<DictionaryEntry?> _findEntryInDict(
  DictionaryManager dictManager,
  String dictId,
  String entryId,
) async {
  try {
    final db = await dictManager.openDictionaryDatabase(dictId);
    final zstdDict = await dictManager.getZstdDictionary(dictId);
    final entryIdInt = int.tryParse(entryId);
    if (entryIdInt != null) {
      final results = await db.query(
        'entries',
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
        limit: 1,
      );
      Logger.d(
        '_findEntryInDict: dictId=$dictId, entryId=$entryId, results=${results.length}',
        tag: 'ExactJump',
      );
      if (results.isNotEmpty) {
        final jsonStr = extractJsonFromFieldWithDict(
          results.first['json_data'],
          zstdDict,
        );
        if (jsonStr != null) {
          final jsonData = Map<String, dynamic>.from(
            jsonDecode(jsonStr) as Map<String, dynamic>,
          );
          String fullId = jsonData['id']?.toString() ?? '';
          if (fullId.isEmpty) {
            fullId = '${dictId}_$entryId';
            jsonData['id'] = fullId;
          } else if (!fullId.startsWith('${dictId}_')) {
            fullId = '${dictId}_$fullId';
            jsonData['id'] = fullId;
          }
          await db.close();
          return DictionaryEntry.fromJson(jsonData);
        } else {
          Logger.e('_findEntryInDict: jsonStr is null', tag: 'ExactJump');
        }
      }
    }
    await db.close();
  } catch (e, stackTrace) {
    Logger.e(
      '_findEntryInDict error: $e',
      tag: 'ExactJump',
      stackTrace: stackTrace,
    );
  }
  return null;
}

/// Intent for copying selected text (Ctrl+C / Cmd+C)
class _CopySelectionIntent extends Intent {
  const _CopySelectionIntent();
}

/// Action for copying selected text
class _CopySelectionAction extends Action<_CopySelectionIntent> {
  final VoidCallback onCopy;

  _CopySelectionAction({required this.onCopy});

  @override
  Object? invoke(_CopySelectionIntent intent) {
    onCopy();
    return null;
  }
}

/// 用于管理隐藏语言状态的通知器

class ComponentRenderer extends StatefulWidget {
  final DictionaryEntry entry;
  final void Function(String path, String label)? onElementTap;
  final void Function(String path, String label)? onEditElement;
  final void Function(String path, String label)? onAiAsk;
  final void Function(String path, DictionaryEntry newEntry)?
  onTranslationInsert;
  final bool enableElementActions;

  /// 自定义顶部内边距。如果为 -1（默认），则自动加上状态栏高度和 16px。
  /// 嵌入 ScrollablePositionedList 时应传 0。
  final double topPadding;

  /// 自定义底部内边距。如果为 -1（默认），则使用 16px。
  final double bottomPadding;

  /// 自定义左侧内边距。如果为 -1（默认），则使用 16px。
  final double leftPadding;

  /// 自定义右侧内边距。如果为 -1（默认），则使用 16px。
  final double rightPadding;

  /// 是否启用文本选择功能。默认为 true。
  /// 当 ComponentRenderer 被嵌入到另一个可滚动组件中时，
  /// 应设置为 false 以避免 SelectionArea 和 SingleChildScrollView 的嵌套冲突。
  final bool enableSelection;

  /// 分组跳转回调，点击 [text](=>group_id) 格式的链接时触发
  final void Function(String groupId, BuildContext context)? onGroupJump;

  /// 精确跳转回调，点击 [text](==entryid::path) 格式的链接时触发
  final void Function(String target, BuildContext context)? onExactJump;

  /// 路径跳转回调，点击 [text](::path) 格式的链接时触发
  final void Function(String path, BuildContext context)? onPathJump;

  /// 添加到笔记回调，参数：(word, language, link)
  final void Function(String word, String language, String link)? onAddToNote;

  /// 外部提供的隐藏语言通知器。如果提供，则使用此通知器而不是内部创建。
  /// 这允许多个 ComponentRenderer 共享同一个隐藏状态。
  final HiddenLanguagesNotifier? hiddenLanguagesNotifier;

  const ComponentRenderer({
    super.key,
    required this.entry,
    this.onElementTap,
    this.onEditElement,
    this.onAiAsk,
    this.onTranslationInsert,
    this.enableElementActions = true,
    this.topPadding = -1,
    this.bottomPadding = -1,
    this.leftPadding = -1,
    this.rightPadding = -1,
    this.enableSelection = true,
    this.onGroupJump,
    this.onExactJump,
    this.onPathJump,
    this.onAddToNote,
    this.hiddenLanguagesNotifier,
  });

  @override
  State<ComponentRenderer> createState() => ComponentRendererState();
}

class ComponentRendererState extends State<ComponentRenderer> {
  final List<GestureRecognizer> _recognizers = [];
  final List<StreamSubscription> _streamSubscriptions = [];
  DateTime? _lastTapTime;
  int? _lastTapButton;
  Offset? _lastTapPosition;
  Timer? _longPressTimer;
  bool _longPressHandled = false;
  DateTime? _lastTtsTime; // TTS防抖时间戳
  late HiddenLanguagesNotifier _hiddenLanguagesNotifier;
  late DictionaryEntry _localEntry;

  /// 路径前缀，格式为 "dictId.entryId"
  /// 用于隐藏语言功能，但对外暴露路径时需要剥离
  String get _pathPrefix =>
      '${widget.entry.dictId ?? ''}.${widget.entry.entryIdAsInt}';

  /// 剥离路径前缀，用于对外暴露路径（如右键菜单、目录跳转等）
  /// 内部路径格式：dictId.entryId.sense.0.definition.zh
  /// 对外路径格式：sense.0.definition.zh
  String _stripPathPrefix(String path) {
    final prefix = _pathPrefix;
    if (path.startsWith('$prefix.')) {
      return path.substring(prefix.length + 1);
    }
    return path;
  }

  // headword 音节显示状态：true 表示显示音节形式，false 表示显示原始形式
  // null 表示尚未初始化，会从设置中加载
  bool? _showHeadwordSyllable;

  // 当前选择的文本（用于选择完成后触发查词）
  SelectedContent? _currentSelection;

  // 长按/选择开始时的触摸位置（用于定位菜单）
  Offset? _selectionStartPosition;

  // 展开的 example comment 路径集合
  Set<String> _expandedCommentPaths = {};

  // 折叠的 child_xxxx 条目路径集合（默认展开，点击后折叠）
  Set<String> _collapsedChildPaths = {};

  /// ASCII 字母判断助手（替代循环内 RegExp 创建）
  static bool _isAsciiLetter(int cu) =>
      (cu >= 65 && cu <= 90) || (cu >= 97 && cu <= 122);

  // 用于存储元素 Key 的 Map，用于精确滚动
  final Map<String, GlobalKey> _elementKeys = {};
  // 待处理的滚动请求队列
  final List<_PendingScrollRequest> _pendingScrollRequests = [];

  StreamSubscription? _scrollSubscription;
  StreamSubscription? _translationInsertSubscription;
  StreamSubscription? _toggleHiddenSubscription;
  StreamSubscription? _batchToggleHiddenSubscription;

  // 用于存储正在闪烁的元素路径
  final Set<String> _highlightingPaths = {};
  // 闪烁动画控制器
  final Map<String, AnimationController> _highlightControllers = {};

  // 懒加载相关
  bool _isVisible = false;
  bool _hasBeenVisible = false;

  // 菜单重建计数器（用于强制重建 SelectionArea 的 contextMenuBuilder）
  int _menuRebuildCounter = 0;

  // 缩放指示器相关（桌面端 Ctrl+滚轮缩放）
  bool _showScaleIndicator = false;
  Timer? _scaleIndicatorTimer;
  OverlayEntry? _scaleOverlayEntry;
  // 局部临时缩放（仅影响当前 ComponentRenderer，不进入全局状态）
  double _tempContentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _localEntry = widget.entry;
    // 如果提供了外部的通知器，则使用它；否则创建内部的
    _hiddenLanguagesNotifier = widget.hiddenLanguagesNotifier ?? HiddenLanguagesNotifier([]);
    _initSourceLanguage();
    _loadClickAction();
    _loadHeadwordSyllableSetting();
    _fontScales = FontLoaderService().getFontScales();
    _listenToEvents();
  }

  /// 滚动结束后重新定位菜单
  void _onScrollEnded() {
    // 只有手机端且有选择菜单时才需要重新定位
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop) return;

    // 如果有当前选择，触发菜单重建
    // 手机端菜单通过 SelectionArea 的 contextMenuBuilder 构建，
    // 需要通过增加计数器并 setState 触发重建来更新菜单位置
    if (_currentSelection != null && _currentSelection!.plainText.isNotEmpty) {
      Logger.d('_onScrollEnded: triggering menu rebuild', tag: 'ContextMenu');
      // 触发重建以更新菜单位置
      if (mounted) {
        setState(() {
          _menuRebuildCounter++;
        });
      }
    }
  }

  /// Renders the content for a 'clob' element.
  /// Only renders clob at root level (path.length == 1) as plain text.
  /// Nested clob elements are not displayed.
  /// Supports both plain string value and object with 'text' field.
  Widget _buildClobContent(
    BuildContext context,
    dynamic clob,
    List<String> path,
  ) {
    if (path.length != 1) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final String text;
    if (clob is String) {
      text = clob;
    } else if (clob is Map<String, dynamic>) {
      text = clob['text'] as String? ?? '';
    } else {
      text = '';
    }

    if (text.isEmpty) return const SizedBox.shrink();

    final clobPath = path;
    final pathStr = _convertPathToString(clobPath);
    final clobStyle = DictTypography.getBaseStyle(
      DictElementType.clob,
      color: colorScheme.onSurface,
    );
    final clobTextKey = GlobalKey();

    final recognizer = _createGestureRecognizer(
      pathKey: pathStr,
      label: 'Clob',
      path: clobPath,
      context: context,
      text: text,
      textStyle: clobStyle,
      textKey: clobTextKey,
    );

    final formattedResult = _parseFormattedText(
      text,
      clobStyle,
      context: context,
      elementType: DictElementType.clob,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.text,
      onShowMenu: (position, text) {
        _handleElementSecondaryTap(pathStr, 'Clob', context, position);
      },
    );

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(clobPath, 'clob'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(
          TextSpan(children: formattedResult.spans),
          key: clobTextKey,
        ),
      ),
    );
  }

  /// Renders the content for a 'text' element.
  /// Only renders text at root level (path.length == 1) as formatted text.
  /// Nested text elements are not displayed.
  Widget _buildTextContent(
    BuildContext context,
    dynamic textValue,
    List<String> path,
  ) {
    if (path.length != 1) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final String text;
    if (textValue is String) {
      text = textValue;
    } else if (textValue is Map<String, dynamic>) {
      text = textValue['text'] as String? ?? '';
    } else {
      text = '';
    }

    if (text.isEmpty) return const SizedBox.shrink();

    final textPath = path;
    final pathStr = _convertPathToString(textPath);
    final textStyle = DictTypography.getBaseStyle(
      DictElementType.text,
      color: colorScheme.onSurface,
    );
    final textTextKey = GlobalKey();

    final recognizer = _createGestureRecognizer(
      pathKey: pathStr,
      label: 'Text',
      path: textPath,
      context: context,
      text: text,
      textStyle: textStyle,
      textKey: textTextKey,
    );

    final formattedResult = _parseFormattedText(
      text,
      textStyle,
      context: context,
      elementType: DictElementType.text,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.text,
      onShowMenu: (position, text) {
        _handleElementSecondaryTap(pathStr, 'Text', context, position);
      },
    );

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(textPath, 'text'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(
          TextSpan(children: formattedResult.spans),
          key: textTextKey,
        ),
      ),
    );
  }

  /// 构建表格组件
  Widget _buildTable(
    BuildContext context,
    Map<String, dynamic> value,
    List<String> path,
  ) {
    final columns = value['column'] as List<dynamic>?;
    final data = value['content'] as List<dynamic>?;

    if (columns == null || data == null) {
      return const SizedBox.shrink();
    }

    final columnList = columns.cast<String>();
    final dataList = data.cast<List<dynamic>>();

    return _buildTableWidget(
      context: context,
      columns: columnList,
      data: dataList,
      path: path,
    );
  }

  /// 构建表格 Widget
  Widget _buildTableWidget({
    required BuildContext context,
    required List<String> columns,
    required List<List<dynamic>> data,
    required List<String> path,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 13,
      color: colorScheme.onSurface,
    );
    final headerStyle = textStyle.copyWith(
      fontWeight: FontWeight.bold,
    );

    // 动态生成列宽
    final columnWidths = <int, TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      columnWidths[i] = const FlexColumnWidth(1);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Table(
          border: TableBorder.symmetric(
            inside: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          columnWidths: columnWidths,
          children: [
            // 表头
            TableRow(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              children: columns.asMap().entries.map((entry) {
                final colIndex = entry.key;
                final col = entry.value;
                final headerPath = [...path, 'column', '$colIndex'];
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildTableCellText(
                    context,
                    col,
                    headerPath,
                    headerStyle,
                    label: 'Table Header',
                  ),
                );
              }).toList(),
            ),
            // 数据行
            ...data.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;
              return TableRow(
                children: row.asMap().entries.map((cell) {
                  final cellPath = [...path, 'content', '$rowIndex', '${cell.key}'];
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildTableCell(
                      context,
                      cell.value,
                      cellPath,
                      textStyle,
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建表格单元格
  Widget _buildTableCell(
    BuildContext context,
    dynamic value,
    List<String> path,
    TextStyle baseStyle,
  ) {
    if (value is String) {
      return _buildTableCellText(context, value, path, baseStyle);
    }
    if (value is num) {
      return _buildTableCellText(context, value.toString(), path, baseStyle);
    }
    if (value is Map<String, dynamic> || value is List) {
      // 嵌套内容递归渲染
      return renderJsonElement(context, 'cell', value, path);
    }
    return _buildTableCellText(context, value?.toString() ?? '', path, baseStyle);
  }

  /// 构建表格单元格文本，支持双击查词和右键菜单
  Widget _buildTableCellText(
    BuildContext context,
    String text,
    List<String> path,
    TextStyle style, {
    String label = 'Table Cell',
  }) {
    if (text.isEmpty) return const SizedBox.shrink();

    final pathData = _PathData(path, label);
    final textKey = GlobalKey();

    // 创建手势识别器以支持点击和右键菜单
    final tapRecognizer = TapGestureRecognizer()
      ..onTapDown = (details) {
        _lastTapPosition = details.globalPosition;
        _currentSelectionPathData = pathData;
      }
      ..onTap = () {
        // 单击立即生效
        _handleElementTap(_convertPathToString(path), pathData.label);

        // 检测双击
        final now = DateTime.now();
        final isDoubleTap =
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
            _lastTapButton == 0;

        if (isDoubleTap && _lastTapPosition != null) {
          Logger.d('Table cell 双击触发', tag: 'DoubleTapWord');
          _handleDoubleTapOnText(
            _lastTapPosition!,
            text,
            style,
            textKey,
            context,
          );
          _lastTapTime = null;
          _lastTapButton = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapButton = 0;
        }
      };

    // 添加右键菜单支持
    final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
      ..onSecondaryTapUp = (details) {
        _lastTapPosition = details.globalPosition;
        _handleElementSecondaryTap(
          _convertPathToString(path),
          pathData.label,
          context,
          details.globalPosition,
        );
      };

    _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

    // 使用 MultiGestureRecognizer 支持点击和右键
    final recognizer = _MultiGestureRecognizer(
      tapRecognizer: tapRecognizer,
      secondaryTapRecognizer: secondaryTapRecognizer,
      longPressRecognizer: null,
      doubleTapRecognizer: null,
    );

    // 解析文本，添加手势识别器
    final result = _parseFormattedText(
      text,
      style,
      context: context,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.text,
    );

    return Text.rich(TextSpan(children: result.spans), key: textKey);
  }

  void _initSourceLanguage() {
    final dictId = _localEntry.dictId;
    if (dictId != null && dictId.isNotEmpty) {
      final cachedMetadata = DictionaryManager().getCachedMetadata(dictId);
      if (cachedMetadata != null) {
        _sourceLanguage = LanguageUtils.normalizeForFontLookup(
          cachedMetadata.sourceLanguage,
        );
        _targetLanguages = cachedMetadata.targetLanguages;
      }
    }
    _loadSourceLanguage();
  }

  void _listenToEvents() {
    final eventBus = EntryEventBus();
    _scrollSubscription = eventBus.scrollToElement.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        scrollToElement(event.path);
      }
    });
    _translationInsertSubscription = eventBus.translationInsert.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        handleTranslationInsert(
          event.path,
          DictionaryEntry.fromJson(event.newEntry),
        );
      }
    });
    _toggleHiddenSubscription = eventBus.toggleHiddenLanguage.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        toggleHiddenLanguage(event.languageKey);
      }
    });
    _batchToggleHiddenSubscription = eventBus.batchToggleHidden.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        batchToggleHiddenLanguages(
          pathsToHide: event.pathsToHide,
          pathsToShow: event.pathsToShow,
        );
      }
    });
  }

  @override
  void didUpdateWidget(ComponentRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _localEntry = widget.entry;
      // 只有在使用内部通知器时才重置
      if (widget.hiddenLanguagesNotifier == null) {
        _hiddenLanguagesNotifier.value = [];
      }
      _elementKeys.clear();
      _pendingScrollRequests.clear();
      _isVisible = false;
      _hasBeenVisible = false;
      _initSourceLanguage();
    } else if (!identical(oldWidget.entry, widget.entry)) {
      // 同一条目内容被更新（如编辑 JSON 后），同步 _localEntry 但保留其余是态
      setState(() {
        _localEntry = widget.entry;
      });
    }
  }

  /// 滚动到指定路径的元素
  void scrollToElement(String path, {int retryCount = 0}) {
    // 如果组件还没有可见，将请求加入队列等待处理
    if (!_hasBeenVisible) {
      Logger.d(
        'Component not visible yet, queuing scroll request for path: $path',
        tag: 'ComponentRenderer',
      );
      _pendingScrollRequests.add(_PendingScrollRequest(path, retryCount));
      return;
    }

    // 外部传入的路径不带前缀，需要加上前缀才能在 _elementKeys 中找到
    final prefixedPath = '$_pathPrefix.$path';
    // 直接执行滚动，GlobalKey 会在 _getElementKey 中按需创建
    _executeScrollToElement(prefixedPath, retryCount: retryCount);
  }

  /// 执行实际的滚动操作
  /// 从最深路径开始逐层向上尝试，直到找到可滚动的元素
  void _executeScrollToElement(String path, {int retryCount = 0}) {
    // 尝试从当前路径开始，逐层向上查找可滚动的元素
    String? foundPath = _findScrollablePath(path);

    if (foundPath != null) {
      final key = _elementKeys[foundPath];
      if (key != null && key.currentContext != null) {
        // 如果找到的路径与原始路径不同，记录日志
        if (foundPath != path) {
          Logger.d(
            'Scrolling to parent path: $foundPath (original: $path)',
            tag: 'ComponentRenderer',
          );
          // 更新 anchor 映射
          _updateResolvedAnchor(path, foundPath);
        }

        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.1,
        ).then((_) {
          // 滚动完成后触发闪烁效果
          if (mounted) {
            _triggerHighlight(foundPath);
          }
        });
        return;
      }
    }

    // 如果重试次数小于3次，延迟重试
    if (retryCount < 3) {
      Logger.d(
        'Element key not found or context null for path: $path, retrying... ($retryCount)',
        tag: 'ComponentRenderer',
      );
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _executeScrollToElement(path, retryCount: retryCount + 1);
        }
      });
    } else {
      Logger.w(
        'Element key not found or context null for path: $path after $retryCount retries',
        tag: 'ComponentRenderer',
      );
    }
  }

  /// 从给定路径开始，逐层向上查找可滚动的元素路径
  /// 返回第一个存在于 _elementKeys 中的路径，如果都找不到则返回 null
  String? _findScrollablePath(String path) {
    // 首先检查当前路径是否存在
    if (_elementKeys.containsKey(path) &&
        _elementKeys[path]?.currentContext != null) {
      return path;
    }

    // 逐层向上查找
    final parts = path.split('.');
    for (int i = parts.length - 1; i > 0; i--) {
      final parentPath = parts.sublist(0, i).join('.');
      if (_elementKeys.containsKey(parentPath) &&
          _elementKeys[parentPath]?.currentContext != null) {
        return parentPath;
      }
    }

    return null;
  }

  /// 存储原始 anchor 到实际滚动路径的映射
  final Map<String, String> _resolvedAnchorMap = {};

  /// 更新 anchor 映射，同时更新 entry.matchedAnchors
  void _updateResolvedAnchor(String originalPath, String resolvedPath) {
    if (originalPath != resolvedPath) {
      _resolvedAnchorMap[originalPath] = resolvedPath;
      Logger.d(
        'Updated anchor mapping: $originalPath -> $resolvedPath',
        tag: 'ComponentRenderer',
      );

      // 更新 entry.matchedAnchors 中的 anchor 值
      // 由于 record 是不可变的，需要找到并替换
      final anchors = widget.entry.matchedAnchors;
      for (int i = 0; i < anchors.length; i++) {
        if (anchors[i].$2 == originalPath) {
          // 创建新的 record 替换旧的
          anchors[i] = (anchors[i].$1, resolvedPath);
          Logger.d(
            'Updated matchedAnchor: ${anchors[i].$1} -> $resolvedPath',
            tag: 'ComponentRenderer',
          );
          break;
        }
      }
    }
  }

  /// 处理待处理的滚动请求
  void _processPendingScrollRequests() {
    if (_pendingScrollRequests.isEmpty) return;

    Logger.d(
      'Processing ${_pendingScrollRequests.length} pending scroll requests',
      tag: 'ComponentRenderer',
    );

    // 只处理最后一个请求（最新的）
    final lastRequest = _pendingScrollRequests.last;
    _pendingScrollRequests.clear();

    scrollToElement(lastRequest.path, retryCount: lastRequest.retryCount);
  }

  /// 触发元素的闪烁效果
  void _triggerHighlight(String path) {
    setState(() {
      _highlightingPaths.add(path);
    });

    // 2秒后移除闪烁效果
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightingPaths.remove(path);
        });
      }
    });
  }

  /// 检查元素是否正在闪烁
  bool _isHighlighting(String path) {
    return _highlightingPaths.contains(path);
  }

  /// 判断路径是否需要生成 GlobalKey（只有释义条目、phrase、board和child_xxxx需要）
  bool _shouldGenerateGlobalKey(String path) {
    // 释义条目路径: sense_group.x.sense.y 或 sense.x
    if (path.contains('sense_group') && path.contains('sense')) return true;
    if (RegExp(r'^sense\.\d+$').hasMatch(path)) return true;

    // phrase
    if (path == 'phrase') return true;

    // child_xxxx 元素（顶层 child_xxxx key 或 child_xxxx.0, child_xxxx.1 等索引路径）
    final parts = path.split('.');
    if (parts.isNotEmpty && _isChildKey(parts[0])) {
      // 支持 child_xxxx 或 child_xxxx.n 格式
      if (parts.length == 1) return true; // 单个 Map 格式
      if (parts.length == 2 && int.tryParse(parts[1]) != null) return true; // List 格式的索引
    }

    // board 元素（不在 _renderedKeys 中的顶层 key）
    // board 路径通常是直接的 key 名，如 "etymology", "notes" 等
    if (parts.length == 1 && !_isRenderedKey(parts[0]) && !_isChildKey(parts[0])) return true;

    return false;
  }

  /// 检查 key 是否是已单独渲染的 key
  bool _isRenderedKey(String key) {
    return _renderedKeys.contains(key);
  }

  /// 获取或创建元素的 GlobalKey - 只为需要滚动的元素创建
  /// 策略：组件可见后直接创建，无需状态控制
  GlobalKey? _getElementKey(String path) {
    // 检查是否需要为此路径生成 GlobalKey
    if (!_shouldGenerateGlobalKey(path)) {
      return null;
    }

    // 组件可见后直接创建 GlobalKey，无需等待 setState
    if (!_hasBeenVisible) {
      return null;
    }

    return _elementKeys.putIfAbsent(path, () => GlobalKey());
  }

  Widget _buildTappableWidget({
    required BuildContext context,
    required _PathData pathData,
    required Widget child,
    String? text,
    TextStyle? textStyle,
    GlobalKey? customTextKey,
  }) {
    final textKey = customTextKey ?? GlobalKey();
    final pathStr = _convertPathToString(pathData.path);

    // 延迟加载 GlobalKey：只有在需要精确滚动时才创建
    final elementKey = _getElementKey(pathStr);

    // 检查是否正在闪烁
    final isHighlighting = _isHighlighting(pathStr);

    // 使用 Listener 包装以支持手机端文本选择菜单
    // onPointerDown 记录路径数据，用于菜单操作
    return _HighlightWrapper(
      isHighlighting: isHighlighting,
      child: _TappableWrapper(
        pathData: pathData,
        child: Listener(
          onPointerDown: (_) {
            // 记录当前路径数据，用于手机端文本选择菜单
            _currentSelectionPathData = pathData;
          },
          child: customTextKey != null
              ? child
              : Builder(key: textKey, builder: (context) => child),
        ),
      ),
    );
  }

  void _handleDoubleTapOnText(
    Offset globalPosition,
    String text,
    TextStyle textStyle,
    GlobalKey textKey,
    BuildContext context, {
    int startOffset = 0,
  }) {
    final renderObject = textKey.currentContext?.findRenderObject();

    // 查找 RenderParagraph（可能被 MouseRegion 等包装）
    RenderParagraph? renderParagraph;
    if (renderObject is RenderParagraph) {
      renderParagraph = renderObject;
    } else if (renderObject != null) {
      // 遍历子节点查找 RenderParagraph
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
      Logger.d('未找到 RenderParagraph', tag: 'DoubleTapWord');
      return;
    }

    final localPosition = renderParagraph!.globalToLocal(globalPosition);

    // 直接使用 RenderParagraph 获取点击位置的全局字符偏移量
    final textPosition = renderParagraph!.getPositionForOffset(localPosition);
    final globalOffset = textPosition.offset;
    Logger.d('全局字符偏移量: $globalOffset', tag: 'DoubleTapWord');

    // 使用 parseFormattedText 解析文本，以获取纯文本内容
    final result = _parseFormattedText(text, textStyle, context: context);
    final plainText = result.spans.fold<String>(
      '',
      (prev, span) => prev + span.toPlainText(),
    );

    // 计算相对于当前文本段的局部偏移量
    final localOffset = globalOffset - startOffset;
    Logger.d('局部字符偏移量: $localOffset', tag: 'DoubleTapWord');

    // 检查偏移量是否在当前文本段范围内
    if (localOffset >= 0 && localOffset < plainText.length) {
      final tappedWord = _extractWordAtOffset(plainText, localOffset);

      if (tappedWord.isNotEmpty) {
        Logger.d('双击识别的单词: $tappedWord', tag: 'DoubleTapWord');
        // 执行查词
        _performDoubleTapSearch(tappedWord, context);
      } else {
        Logger.d('未识别到单词', tag: 'DoubleTapWord');
      }
    } else {
      Logger.d('点击位置超出当前文本段范围', tag: 'DoubleTapWord');
    }
  }

  /// 执行双击查词
  Future<void> _performDoubleTapSearch(
    String word,
    BuildContext context,
  ) async {
    Logger.d('双击查词: $word', tag: 'DoubleTapWord');
    // 若双击的词与当前词条相同，不执行查词
    if (word.toLowerCase() == (_localEntry.headword).toLowerCase()) return;

    // 获取当前语言的默认搜索选项
    final advancedSettingsService = AdvancedSearchSettingsService();
    final defaultOptions = advancedSettingsService.getDefaultOptionsForLanguage(
      _sourceLanguage,
    );

    // 查询词典
    final dbService = DatabaseService();
    final searchResult = await dbService.getAllEntries(
      word,
      exactMatch: defaultOptions.exactMatch,
      sourceLanguage: _sourceLanguage,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

      // 获取语言信息并记录搜索历史
      String? group;
      final dictId = searchResult.entries.first.dictId;
      if (dictId != null) {
        final metadata = await DictionaryManager().getDictionaryMetadata(
          dictId,
        );
        group = metadata?.sourceLanguage;
      }
      final historyService = SearchHistoryService();
      await historyService.addSearchRecord(word, group: group);

      // 获取历史记录构建浏览列表
      final records = await historyService.getSearchRecords();
      final historyWords = records.map((r) => r.word).toList();
      final currentIndex = historyWords.indexOf(word);

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EntryDetailPage(
              entryGroup: entryGroup,
              initialWord: word,
              dictResults: searchResult.dictResults.isNotEmpty
                  ? searchResult.dictResults
                  : null,
              browseList: historyWords.isNotEmpty
                  ? BrowseList(
                      source: BrowseListSource.searchHistory,
                      words: historyWords,
                      initialIndex: currentIndex >= 0 ? currentIndex : 0,
                    )
                  : null,
            ),
          ),
        );
      }
    } else {
      if (context.mounted) {
        showToast(context, context.t.entry.wordNotFound(word: word));
      }
    }
  }

  void handleTranslationInsert(String path, DictionaryEntry newEntry) {
    // 确保该路径不被隐藏（即显示）
    if (_hiddenLanguagesNotifier.value.contains(path)) {
      _hiddenLanguagesNotifier.toggle(path);
    }

    setState(() {
      _localEntry = newEntry;
    });

    // 触发 HiddenLanguagesNotifier 通知监听器，强制重建 HiddenLanguagesSelector
    // 这对于 AI 翻译后显示新添加的翻译是必要的
    _hiddenLanguagesNotifier.forceNotify();
  }

  /// 切换指定路径的隐藏状态（仅本地状态，不保存到数据库）
  void toggleHiddenLanguage(String path) {
    _hiddenLanguagesNotifier.toggle(path);
  }

  /// 批量设置隐藏状态（仅本地状态，不保存到数据库）
  /// [pathsToHide] 要隐藏的路径列表
  /// [pathsToShow] 要显示的路径列表
  void batchToggleHiddenLanguages({
    required List<String> pathsToHide,
    required List<String> pathsToShow,
  }) {
    final currentHidden = List<String>.from(_hiddenLanguagesNotifier.value);

    // 移除要显示的路径
    for (final path in pathsToShow) {
      currentHidden.remove(path);
    }

    // 添加要隐藏的路径
    for (final path in pathsToHide) {
      if (!currentHidden.contains(path)) {
        currentHidden.add(path);
      }
    }

    _hiddenLanguagesNotifier.value = currentHidden;
  }

  String _extractWordAtOffset(String text, int offset) {
    if (offset < 0 || offset >= text.length) return '';

    // 如果当前字符是 CJK 汉字，直接返回单个汉字（词语识别待后续实现）
    final cu = text.codeUnitAt(offset);
    if (_isCjkCodeUnit(cu)) {
      return text[offset];
    }

    int start = offset;
    int end = offset;

    while (start > 0 && _isAsciiLetter(text.codeUnitAt(start - 1))) {
      start--;
    }

    while (end < text.length && _isAsciiLetter(text.codeUnitAt(end))) {
      end++;
    }

    return text.substring(start, end);
  }

  /// 判断一个 UTF-16 code unit 是否属于 CJK 范围
  /// （仅判断基本区 + 扩展A，足够覆盖常用充字）
  static bool _isCjkCodeUnit(int cu) {
    return (cu >= 0x4E00 && cu <= 0x9FFF) || // CJK 基本区
        (cu >= 0x3400 && cu <= 0x4DBF) || // CJK 扩展A
        (cu >= 0xF900 && cu <= 0xFAFF) || // CJK 兼容区
        (cu >= 0x2E80 && cu <= 0x2EFF) || // CJK 部首拓展
        (cu >= 0x3000 && cu <= 0x303F); // CJK 标点符号
  }

  Widget _buildExampleItem({
    required BuildContext context,
    required List<MapEntry<String, String>> texts,
    required String usage,
    double leftMargin = 0,
    required List<String> basePath,
    required void Function(String path, String label) onElementTap,
    void Function(String path, String label, Offset position)?
    onElementSecondaryTapWithPosition,
    Map<String, Map<String, double>>? fontScales,
    String? sourceLanguage,
    List<Map<String, dynamic>> audios = const [],
    Map<String, dynamic>? source,
    String? dictId,
    dynamic comment,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final spans = <InlineSpan>[];
    int currentTextOffset = 0;

    final usageStyle = DictTypography.getScaledStyle(
      DictElementType.exampleUsage,
      language: sourceLanguage,
      fontScales: fontScales ?? {},
      color: colorScheme.onSecondaryContainer,
    );

    // 在例句之前渲染音频图标
    if (audios.isNotEmpty) {
      // 根据region数量决定颜色策略
      final regions = audios
          .map((a) => a['region'] as String? ?? '')
          .where((r) => r.isNotEmpty)
          .toSet()
          .toList();
      final hasMultipleRegions = regions.length > 1;

      for (int i = 0; i < audios.length; i++) {
        final audio = audios[i];
        final region = audio['region'] as String? ?? '';
        final audioFile = audio['audio_file'] as String? ?? '';

        if (audioFile.isNotEmpty && dictId != null && dictId.isNotEmpty) {
          final audioPath = [...basePath, 'audios.$i'];
          final audioPathData = _PathData(audioPath, 'Example Audio');

          // 根据region决定颜色
          Color iconColor;
          final regionUpper = region.toUpperCase();
          if (!hasMultipleRegions) {
            // 只有一种region或没有region，使用主题色（浅一点）
            iconColor = colorScheme.primary.withValues(alpha: 0.8);
          } else {
            // 多种region，使用不同颜色区分
            if (regionUpper == 'UK' || regionUpper == 'GB') {
              iconColor = colorScheme.tertiary.withValues(
                alpha: 0.8,
              ); // UK/GB用第三色
            } else if (regionUpper == 'US') {
              iconColor = colorScheme.primary.withValues(alpha: 0.8); // US用主题色
            } else {
              // 其他region用次要色
              iconColor = colorScheme.secondary.withValues(alpha: 0.8);
            }
          }

          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Transform.translate(
                offset: const Offset(0, 1),
                child: GestureDetector(
                  onSecondaryTapUp: (details) {
                    if (onElementSecondaryTapWithPosition != null) {
                      onElementSecondaryTapWithPosition(
                        audioPath.join('.'),
                        audioPathData.label,
                        details.globalPosition,
                      );
                    }
                  },
                  child: InkWell(
                    onTap: () {
                      _playAudio(dictId, audioFile);
                    },
                    onLongPress: () {
                      if (onElementSecondaryTapWithPosition != null) {
                        onElementSecondaryTapWithPosition(
                          audioPath.join('.'),
                          audioPathData.label,
                          Offset.zero,
                        );
                      }
                    },
                    mouseCursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.volume_up, size: 14, color: iconColor),
                    ),
                  ),
                ),
              ),
            ),
          );
          currentTextOffset += 1;
        }
      }
    }

    if (usage.isNotEmpty) {
      final usagePath = [...basePath, 'usage'];
      final usagePathData = _PathData(usagePath, 'Example Usage');

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              if (onElementSecondaryTapWithPosition != null) {
                onElementSecondaryTapWithPosition(
                  usagePath.join('.'),
                  usagePathData.label,
                  details.globalPosition,
                );
              }
            },
            child: InkWell(
              onTap: () {
                onElementTap(usagePath.join('.'), usagePathData.label);
              },
              onLongPress: () {
                if (onElementSecondaryTapWithPosition != null) {
                  onElementSecondaryTapWithPosition(
                    usagePath.join('.'),
                    usagePathData.label,
                    Offset.zero,
                  );
                }
              },
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(usage, style: usageStyle),
              ),
            ),
          ),
        ),
      );
      currentTextOffset += 1;
    }

    final exampleTextKey = GlobalKey();

    // 记录是否有 CJK 语言的例句文本（用于决定 source 的字体样式）
    bool hasCJKText = false;

    for (int i = 0; i < texts.length; i++) {
      final textEntry = texts[i];
      final text = textEntry.value;
      final key = textEntry.key;

      // 不同语言的 example 之间添加间距
      if (i > 0) {
        spans.add(WidgetSpan(child: SizedBox(width: 12)));
        currentTextOffset += 1; // WidgetSpan 占 1 个字符
      } else if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: ' '));
        currentTextOffset += 1; // 空格占 1 个字符
      }

      final startOffset = currentTextOffset;
      currentTextOffset += text.length;

      final path = key.isEmpty ? basePath : [...basePath, key];
      final pathData = _PathData(path, 'Example Text');

      final hiddenPath = path.join('.');
      // 使用 notifier 的当前值，这样当状态变化时会重建
      final hidden = _hiddenLanguagesNotifier.value.contains(hiddenPath);

      // 判断是否为 CJK（日语或中文）
      final isCJK =
          key == 'jp' ||
          key == 'zh' ||
          key.startsWith('zh_') ||
          key.startsWith('zh-') ||
          key.startsWith('jp_') ||
          key.startsWith('jp-');

      // 记录是否有 CJK 文本
      if (isCJK) {
        hasCJKText = true;
      }

      // 使用 DictTypography 获取 example 基础样式（字体族和缩放由 _parseFormattedText 处理）
      final exampleTextStyle = DictTypography.getBaseStyle(
        DictElementType.example,
        color: colorScheme.onSurface.withValues(alpha: 0.85),
        // CJK 不使用斜体，非-CJK 使用斜体
        fontStyleOverride: isCJK ? FontStyle.normal : FontStyle.italic,
      );

      // 创建手势识别器以支持点击和右键菜单
      final tapRecognizer = TapGestureRecognizer()
        ..onTapDown = (details) {
          _lastTapPosition = details.globalPosition;
          // 记录当前路径数据，用于手机端文本选择菜单
          _currentSelectionPathData = pathData;
        }
        ..onTap = () {
          // 单击立即生效
          onElementTap(_convertPathToString(path), pathData.label);

          // 检测双击
          final now = DateTime.now();
          final isDoubleTap =
              _lastTapTime != null &&
              now.difference(_lastTapTime!) <
                  const Duration(milliseconds: 300) &&
              _lastTapButton == 0;

          if (isDoubleTap && _lastTapPosition != null) {
            Logger.d('双击触发', tag: 'DoubleTapWord');
            _handleDoubleTapOnText(
              _lastTapPosition!,
              text,
              exampleTextStyle,
              exampleTextKey,
              context,
              startOffset: startOffset,
            );
            _lastTapTime = null;
            _lastTapButton = null;
            _lastTapPosition = null;
          } else {
            _lastTapTime = now;
            _lastTapButton = 0;
          }
        };

      // 恢复 SecondaryTapGestureRecognizer 用于电脑端右键菜单
      // 长按选择由 SelectionArea 处理
      final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
        ..onSecondaryTapUp = (details) {
          _lastTapPosition = details.globalPosition;
          if (onElementSecondaryTapWithPosition != null) {
            onElementSecondaryTapWithPosition(
              _convertPathToString(path),
              pathData.label,
              details.globalPosition,
            );
          }
        };

      _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

      // 使用 MultiGestureRecognizer 支持点击和右键
      final recognizer = _MultiGestureRecognizer(
        tapRecognizer: tapRecognizer,
        secondaryTapRecognizer: secondaryTapRecognizer,
        longPressRecognizer: null,
        doubleTapRecognizer: null,
      );

      final result = _parseFormattedText(
        text,
        exampleTextStyle,
        context: context,
        path: path,
        language: key.isEmpty ? null : key,
        label: 'Example Text ($key)',
        recognizer: recognizer,
        hidden: hidden,
        elementType: DictElementType.example,
        mouseCursor: SystemMouseCursors.text,
        onShowMenu: (position, text) {
          _handleElementSecondaryTap(
            _convertPathToString(path),
            pathData.label,
            context,
            position,
          );
        },
        onDoubleTapWord: (word, position) {
          _performDoubleTapSearch(word, context);
        },
      );

      // 直接使用 TextSpan 而不是 WidgetSpan，以实现文本接着换行的效果
      spans.addAll(result.spans);
    }

    // 构建来源引用组件（右对齐）
    Widget? sourceWidget;
    if (source != null && source.isNotEmpty) {
      final (sourceText, isChinese) = _buildSourceText(source);

      if (sourceText.isNotEmpty) {
        final displayText = '— $sourceText';
        final sourcePath = [...basePath, 'source'];
        final sourcePathData = _PathData(sourcePath, 'Example Source');

        sourceWidget = GestureDetector(
          onSecondaryTapUp: (details) {
            if (onElementSecondaryTapWithPosition != null) {
              onElementSecondaryTapWithPosition(
                sourcePath.join('.'),
                sourcePathData.label,
                details.globalPosition,
              );
            }
          },
          child: InkWell(
            onTap: () {
              onElementTap(sourcePath.join('.'), sourcePathData.label);
            },
            onLongPress: () {
              if (onElementSecondaryTapWithPosition != null) {
                onElementSecondaryTapWithPosition(
                  sourcePath.join('.'),
                  sourcePathData.label,
                  Offset.zero,
                );
              }
            },
            mouseCursor: SystemMouseCursors.click,
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                // 中文 source 不使用斜体
                fontStyle: isChinese ? FontStyle.normal : FontStyle.italic,
                fontFamily: 'SourceSans3',
              ),
            ),
          ),
        );
      }
    }

    // 检查是否有 comment
    final hasComment =
        comment != null &&
        ((comment is String && comment.isNotEmpty) ||
            (comment is Map<String, dynamic> && comment.isNotEmpty) ||
            (comment is List && comment.isNotEmpty));

    // 如果有 comment，在句尾添加圆形的 i 折叠符号
    if (hasComment) {
      final commentPath = basePath.join('.');
      final isExpanded = _expandedCommentPaths.contains(commentPath);

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedCommentPaths.remove(commentPath);
                  } else {
                    _expandedCommentPaths.add(commentPath);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  isExpanded ? Icons.expand_less : Icons.info_outline,
                  size: 15,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 构建 comment 内容 Widget
    Widget? commentWidget;
    if (hasComment && _expandedCommentPaths.contains(basePath.join('.'))) {
      final commentPath = [...basePath, 'comment'];

      // comment 可以是 map 或 list of map
      Widget commentContent;
      if (comment is List) {
        // list of map：每个元素单独渲染
        commentContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < comment.length; i++)
              _buildExample(
                context,
                comment[i],
                leftMargin: 0,
                path: [...commentPath, i.toString()],
              ),
          ],
        );
      } else {
        // map：直接渲染
        commentContent = _buildExample(
          context,
          comment,
          leftMargin: 0,
          path: commentPath,
        );
      }

      // 整行宽度的 comment 容器
      commentWidget = Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: commentContent,
      );
    }

    // 如果有来源引用或 comment，使用 Column 布局
    if (sourceWidget != null || commentWidget != null) {
      return Container(
        margin: EdgeInsets.only(bottom: 6, left: leftMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(children: spans), key: exampleTextKey),
            if (sourceWidget != null) ...[
              const SizedBox(height: 2),
              Align(alignment: Alignment.centerRight, child: sourceWidget),
            ],
            if (commentWidget != null) commentWidget,
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6, left: leftMargin),
      child: Text.rich(TextSpan(children: spans), key: exampleTextKey),
    );
  }

  /// Check if the source contains Chinese characters
  bool _containsChinese(Map<String, dynamic> source) {
    final chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    for (final value in source.values) {
      if (value is String && chineseRegex.hasMatch(value)) {
        return true;
      }
    }
    return false;
  }

  /// Build source text with recursive support for cited_in
  /// Returns (formattedText, isChinese)
  (String, bool) _buildSourceText(Map<String, dynamic> source) {
    // Check if Chinese content (contains Chinese characters in any field)
    final isChinese = _containsChinese(source);

    final parts = <String>[];

    // 1. cited_in - recursively render using same logic (all fields)
    if (source['cited_in'] != null) {
      final citedIn = source['cited_in'] as Map<String, dynamic>;
      final (citedText, _) = _buildSourceText(citedIn);
      parts.add(citedText);
    }

    // 2. head (放在 cited_in 右边)
    if (source['head'] != null) {
      parts.add(source['head'].toString());
    }

    // 收集中间字段
    final middleParts = <String>[];

    // 3. year (already Chinese text like '清', '唐')
    if (source['year'] != null) {
      middleParts.add(source['year'].toString());
    }

    // 4. author
    if (source['author'] != null) {
      middleParts.add(source['author'].toString());
    }

    // 5. title (don't add extra 《》, title may already contain it)
    if (source['title'] != null) {
      middleParts.add(source['title'].toString());
    }

    // 6. publisher
    if (source['publisher'] != null) {
      middleParts.add(source['publisher'].toString());
    }

    // 7. page
    if (source['page'] != null) {
      middleParts.add(
        isChinese ? '第${source['page']}页' : 'p.${source['page']}',
      );
    }

    // 8. edition
    if (source['edition'] != null) {
      middleParts.add(
        isChinese ? '${source['edition']}版' : '${source['edition']} ed.',
      );
    }

    // 9. tail (放在最尾端)
    if (source['tail'] != null) {
      middleParts.add(source['tail'].toString());
    }

    final separator = isChinese ? ' · ' : ', ';
    final middleText = middleParts.join(separator);

    // 如果有 cited_in/head 且有其他字段，用连接符 ∷ 连接
    if (parts.isNotEmpty && middleText.isNotEmpty) {
      return ('${parts.join(separator)} ∷ $middleText', isChinese);
    } else if (parts.isNotEmpty) {
      return (parts.join(separator), isChinese);
    } else {
      return (middleText, isChinese);
    }
  }

  final Map<int, GlobalKey> _sectionKeys = {};
  String? _sourceLanguage;
  Map<String, Map<String, double>> _fontScales = {};
  List<String> _targetLanguages = [];
  String _clickAction = PreferencesService.actionAiTranslate;

  OverlayEntry? _currentOverlayEntry;
  OverlayEntry? _currentBarrierEntry;
  OverlayEntry? _phraseOverlayEntry;
  OverlayEntry? _phraseBarrierEntry;

  // 标志：是否正在显示上下文菜单（用于防止重复显示）
  bool _isShowingContextMenu = false;

  // 标志：是否正在关闭菜单（用于防止菜单重建）
  bool _isClosingContextMenu = false;

  // 当前选择的路径数据（用于手机端文本选择菜单）
  _PathData? _currentSelectionPathData;

  Future<void> _loadClickAction() async {
    final action = await PreferencesService().getClickAction();
    if (mounted) {
      setState(() {
        _clickAction = action;
      });
    }
  }

  Future<void> _loadHeadwordSyllableSetting() async {
    final showByDefault = await PreferencesService().getShowHeadwordSyllableByDefault();
    if (mounted) {
      setState(() {
        _showHeadwordSyllable = showByDefault;
      });
    }
  }

  Future<void> _loadSourceLanguage() async {
    final dictId = _localEntry.dictId;
    if (dictId != null && dictId.isNotEmpty) {
      final metadata = await DictionaryManager().getDictionaryMetadata(dictId);
      if (mounted && metadata != null) {
        setState(() {
          _sourceLanguage = LanguageUtils.normalizeForFontLookup(
            metadata.sourceLanguage,
          );
          _targetLanguages = metadata.targetLanguages;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _scrollToSection(int sectionIndex) {
    final key = _sectionKeys[sectionIndex];
    if (key == null) return;
    final elementContext = key.currentContext;
    if (elementContext == null) return;

    final renderBox = elementContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final scrollableState = Scrollable.maybeOf(elementContext);
    if (scrollableState == null) return;

    final scrollRenderBox =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollRenderBox == null) return;

    // dy = current distance from element's top to the scrollable viewport's top edge
    final elementOffset = renderBox.localToGlobal(
      Offset.zero,
      ancestor: scrollRenderBox,
    );

    final position = scrollableState.position;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    // Scroll so the element's top sits exactly at statusBarHeight below the
    // screen's physical top (i.e. just below the status bar).
    final targetPixels = (position.pixels + elementOffset.dy - statusBarHeight)
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    position.animateTo(
      targetPixels,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  FormattedTextResult _parseFormattedText(
    String text,
    TextStyle baseStyle, {
    BuildContext? context,
    List<String>? path,
    String? label,
    void Function(String path, String label)? onElementTap,
    void Function(String path, String label)? onElementSecondaryTap,
    void Function(Offset position, String text)? onShowMenu,
    GestureRecognizer? recognizer,
    bool hidden = false,
    String? language,
    bool isSerif = false,
    bool isBold = false,
    DictElementType? elementType,
    MouseCursor? mouseCursor,
    bool useCustomFont = true,
    void Function(String word, BuildContext context)? onLinkTap,
    void Function(String target, BuildContext context)? onExactJump,
    void Function(String path, BuildContext context)? onPathJump,
    void Function(String groupId, BuildContext context)? onGroupJump,
    void Function(String word, Offset position)? onDoubleTapWord,
  }) {
    final effectiveOnLinkTap =
        onLinkTap ?? ((word, ctx) => _handleLinkTap(ctx, word));
    final effectiveOnExactJump =
        onExactJump ??
        widget.onExactJump ??
        ((target, ctx) =>
            _handleExactJump(ctx, target, currentDictId: _localEntry.dictId));
    final effectiveOnPathJump =
        onPathJump ??
        widget.onPathJump ??
        ((path, ctx) => _handlePathJump(ctx, path));
    final effectiveOnGroupJump = onGroupJump ?? widget.onGroupJump;
    final effectiveOnDoubleTapWord =
        onDoubleTapWord ??
        ((word, position) => _performDoubleTapSearch(word, context!));

    return parseFormattedText(
      text,
      baseStyle,
      context: context,
      path: path,
      label: label,
      onElementTap: onElementTap,
      onElementSecondaryTap: onElementSecondaryTap,
      onShowMenu: onShowMenu,
      recognizer: recognizer,
      hidden: hidden,
      language: language,
      sourceLanguage: _sourceLanguage,
      fontScales: _fontScales,
      isSerif: isSerif,
      isBold: isBold,
      elementType: elementType,
      mouseCursor: mouseCursor,
      useCustomFont: useCustomFont,
      onLinkTap: effectiveOnLinkTap,
      onExactJump: effectiveOnExactJump,
      onPathJump: effectiveOnPathJump,
      onGroupJump: effectiveOnGroupJump,
      dictId: _localEntry.dictId,
      onLoadImage: _loadInlineImage,
      onDoubleTapWord: effectiveOnDoubleTapWord,
    );
  }

  void _handlePathJump(BuildContext context, String path) {
    scrollToElement(path);
  }

  Future<Uint8List?> _loadInlineImage(String dictId, String imageFile) async {
    Logger.d(
      '_loadInlineImage: dictId=$dictId, imageFile=$imageFile',
      tag: 'InlineImage',
    );
    final bytes = await DictionaryManager().getImageBytes(dictId, imageFile);
    Logger.d(
      '_loadInlineImage: got ${bytes?.length ?? 0} bytes for $imageFile',
      tag: 'InlineImage',
    );
    return bytes;
  }

  dynamic _getValueByPath(dynamic json, List<String> pathParts) {
    dynamic currentValue = json;
    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return currentValue;
  }

  /// 执行 AI 翻译/切换翻译显示
  /// 这是原来的单击功能，现在提取为可复用方法
  void _performAiTranslate(String path, String label) {
    Logger.d(
      '_performAiTranslate: path=$path, label=$label',
      tag: 'ContextMenu',
    );
    // 检查是否是语言切换操作（路径以语言代码结尾）
    final pathParts = path.split('.');
    if (pathParts.isNotEmpty) {
      final lastKey = pathParts.last;
      final isLanguageCode =
          LanguageUtils.getLanguageDisplayName(lastKey) !=
          lastKey.toUpperCase();
      if (isLanguageCode) {
        Logger.d(
          '点击语言代码: path=$path, lastKey=$lastKey, sourceLanguage=$_sourceLanguage',
          tag: 'LanguageToggle',
        );

        final parentPath = pathParts.sublist(0, pathParts.length - 1);
        final parentValue = _getValueByPath(_localEntry.toJson(), parentPath);

        String? currentSourceLang = _sourceLanguage;

        // 如果未加载源语言，尝试推断
        if (currentSourceLang == null && parentValue is Map) {
          if (parentValue.containsKey('en')) {
            currentSourceLang = 'en';
          } else if (parentValue.containsKey('jp')) {
            currentSourceLang = 'jp';
          } else if (parentValue.containsKey('zh')) {
            currentSourceLang = 'zh';
          }
        }

        // 如果点击的是源语言
        if (currentSourceLang != null && lastKey == currentSourceLang) {
          if (parentValue is Map) {
            // 无论是否有翻译，都通知父组件
            // 如果有翻译，父组件会切换显示状态
            // 如果没有翻译，父组件会触发翻译
            widget.onElementTap?.call(_stripPathPrefix(path), label);
            return;
          }
        } else {
          // 点击的是非源语言（目标语言），通知父组件切换显示状态
          widget.onElementTap?.call(_stripPathPrefix(path), label);
          return;
        }
      }
    }

    // 非语言代码路径，直接调用 onElementTap
    widget.onElementTap?.call(_stripPathPrefix(path), label);
  }

  /// 根据点击动作设置执行对应的动作
  void _handleElementTap(String path, String label) {
    if (!widget.enableElementActions) {
      return;
    }

    // 剥离路径前缀，对外暴露不带 dictId.entryId 的路径
    final strippedPath = _stripPathPrefix(path);

    // 使用缓存的点击动作，避免异步延迟
    final action = _clickAction;

    switch (action) {
      case PreferencesService.actionAiTranslate:
        _performAiTranslate(strippedPath, label);
        break;
      case PreferencesService.actionCopy:
        _performCopy(strippedPath, label);
        break;
      case PreferencesService.actionAskAi:
        widget.onAiAsk?.call(strippedPath, label);
        break;
      case PreferencesService.actionEdit:
        widget.onEditElement?.call(strippedPath, label);
        break;
      case PreferencesService.actionSpeak:
        _performSpeak(strippedPath, label);
        break;
      default:
        _performAiTranslate(strippedPath, label);
    }
  }

  /// 从指定路径提取文本（复用逻辑）
  String? _getTextFromPath(String path) {
    final pathParts = path.split('.');
    final json = _localEntry.toJson();
    dynamic currentValue = json;

    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          currentValue = null;
          break;
        }
      } else {
        currentValue = null;
        break;
      }
    }

    final textToCopy = _extractTextToCopy(currentValue);
    return textToCopy != null ? _substituteHeadword(textToCopy) : null;
  }

  void _performCopy(String path, String label) {
    final textToCopy = _getTextFromPath(path);
    if (textToCopy != null) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      showToast(context, context.t.entry.copiedToClipboard);
    } else {
      showToast(context, context.t.entry.extractFailed);
    }
  }

  /// 处理添加到笔记
  void _handleAddToNote(_PathData pathData, {String? selectedText}) {
    final entry = widget.entry;
    final word = entry.headword;
    final language = _sourceLanguage ?? 'en';

    // 构建链接格式：[label](dictId/entryId/json.path)
    final dictId = entry.dictId ?? '';
    // entry.entryIdAsInt 返回纯数字的 entry_id
    final entryId = entry.entryIdAsInt;
    final jsonPath = pathData.path.join('.');

    // 获取标签：
    // 1. 如果有选中文本，使用选中文本
    // 2. 否则从 JSON 值中提取实际文本（与复制文本逻辑一致）
    final label = (selectedText != null && selectedText.isNotEmpty)
        ? selectedText
        : _getTextFromPath(jsonPath) ?? pathData.label;

    // 格式: [label](dictId/entryId/json.path)
    final link = '[$label]($dictId/$entryId/$jsonPath)';

    // 调用外部提供的回调来处理笔记
    widget.onAddToNote?.call(word, language, link);
  }

  void _performSpeak(String path, String label) async {
    // TTS防抖：每秒最多调用1次
    final now = DateTime.now();
    if (_lastTtsTime != null &&
        now.difference(_lastTtsTime!) < const Duration(seconds: 1)) {
      showToast(context, context.t.common.retryLater);
      return;
    }
    _lastTtsTime = now;

    final pathParts = path.split('.');
    Logger.d('TTS path: $path, parts: $pathParts', tag: '_performSpeak');

    final json = _localEntry.toJson();
    dynamic currentValue = json;

    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          currentValue = null;
          break;
        }
      } else {
        currentValue = null;
        break;
      }
    }

    final textToSpeakRaw = _extractTextToCopy(currentValue);
    if (textToSpeakRaw == null || textToSpeakRaw.isEmpty) {
      showToast(context, context.t.entry.extractFailed);
      return;
    }
    final textToSpeak = _substituteHeadword(textToSpeakRaw);

    // 尝试从路径中提取语言代码（路径的最后一部分通常是语言代码）
    String? languageCode;
    String? languageSource;
    if (pathParts.isNotEmpty) {
      final lastPart = pathParts.last;
      // 检查是否是语言代码（如 en, zh, ja 等）
      final knownLanguages = [
        'en',
        'zh',
        'jp',
        'ko',
        'fr',
        'de',
        'es',
        'it',
        'ru',
        'pt',
        'ar',
        'text',
      ];
      if (knownLanguages.contains(lastPart.toLowerCase())) {
        languageCode = lastPart.toLowerCase();
        languageSource = '路径字段 "$lastPart"';
      }
    }
    // 从路径未识别到语言时，回退到词典源语言
    if (languageCode == null && _sourceLanguage != null) {
      languageCode = _sourceLanguage;
      languageSource = '词典源语言 "$_sourceLanguage"';
    }

    try {
      final ttsCache = TtsCacheService();
      final voice = await AIService().getVoiceForLanguage(
        languageCode,
        languageSource,
        null,
      );
      List<int>? audioData = await ttsCache.getCache(
        textToSpeak,
        languageCode,
        voice,
      );

      if (audioData != null && audioData.isNotEmpty) {
        Logger.d(
          '使用 TTS 缓存音频，长度: ${audioData.length} bytes',
          tag: '_performSpeak',
        );
      } else {
        showToast(context, context.t.entry.generatingAudio);
        Logger.d(
          '开始TTS: 文本="$textToSpeak", 语言代码=$languageCode (来源: $languageSource)',
          tag: '_performSpeak',
        );

        final result = await AIService().textToSpeech(
          textToSpeak,
          languageCode: languageCode,
          languageSource: languageSource,
        );
        audioData = result.audio;

        Logger.d(
          'TTS音频生成成功，长度: ${audioData.length} bytes',
          tag: '_performSpeak',
        );

        await ttsCache.saveCache(
          textToSpeak,
          languageCode,
          result.voice,
          audioData,
        );
      }

      await _playTtsAudio(audioData);

      unawaited(ttsCache.cleanOldCache(maxAgeDays: 1));
    } catch (e) {
      Logger.e('TTS失败: $e', tag: '_performSpeak', error: e);
      showToast(context, context.t.entry.speakFailed(error: e));
    }
  }

  /// 对中文和日文词典的文本，将占位符替换为 headword 或 headline
  /// 中文：～（全角波浪线）、\u301c（波浪线）
  /// 日文：～、\u301c、―（U+2015 HORIZONTAL BAR）、—（U+2014 EM DASH）
  String _substituteHeadword(String text) {
    if (_sourceLanguage == null) return text;

    final lang = LanguageUtils.normalizeSourceLanguage(_sourceLanguage!);
    if (lang != 'zh' && lang != 'jp') return text;

    final replacement = _localEntry.headword.isNotEmpty
        ? _localEntry.headword
        : _removeFormatting(_localEntry.headline ?? '');

    return text
        .replaceAll('～', replacement)
        .replaceAll('\u301c', replacement)
        .replaceAll('\u2015', replacement)
        .replaceAll('\u2014', replacement);
  }

  Future<void> _playTtsAudio(List<int> audioData) async {
    try {
      // 取消之前的完成监听，但不停止播放
      // 让 open() 自动处理切换，避免 stop() 导致的音频管道重置
      _playbackCompletionSub?.cancel();
      _playbackCompletionSub = null;

      // 复用现有 player 或创建新实例
      Player player;
      if (_currentPlayer != null) {
        player = _currentPlayer!;
        Logger.d('复用现有播放器', tag: '_playTtsAudio');
      } else {
        player = Player();
        _currentPlayer = player;
        // 注册到管理器以便热重启时清理
        MediaKitManager().registerPlayer(player);
        Logger.d('创建新播放器', tag: '_playTtsAudio');
      }

      // 使用缓存目录存储音频文件（由 TtsCacheService 管理，1天后自动清理）
      final ttsCache = TtsCacheService();
      final tempDir = await ttsCache.getTemporaryDirectory();
      final cacheDir = Directory(path.join(tempDir.path, 'tts_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final audioFile = File(
        path.join(
          cacheDir.path,
          'tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
        ),
      );
      await audioFile.writeAsBytes(audioData, flush: true);

      Logger.d('播放TTS音频: ${audioFile.path}', tag: '_playTtsAudio');

      // 确保文件存在且有内容
      if (!await audioFile.exists()) {
        Logger.e('TTS音频文件不存在', tag: '_playTtsAudio');
        return;
      }
      final fileSize = await audioFile.length();
      Logger.d('TTS音频文件大小: $fileSize bytes', tag: '_playTtsAudio');

      // 直接打开并播放，避免 open 和 play 之间的间隙导致 Android 抖动
      // 使用 play: true 让播放器内部处理缓冲和播放的衔接
      await player.open(Media(audioFile.path), play: true);

      // 监听播放完成，稍等尾帧稳定后再清理，避免结尾被截断
      _playbackCompletionSub?.cancel();
      _playbackCompletionSub = player.stream.completed.listen((
        completed,
      ) async {
        if (!completed) return;

        Logger.d('TTS音频播放完成', tag: '_playTtsAudio');

        _playbackCompletionSub?.cancel();
        _playbackCompletionSub = null;

        await Future.delayed(const Duration(milliseconds: 500));

        if (_currentPlayer == player) {
          await _cleanupPlayer();
        }

        // 播放完成后删除临时音频文件（缓存由 TtsCacheService 统一管理）
        try {
          if (await audioFile.exists()) {
            await audioFile.delete();
            Logger.d('已删除临时 TTS 音频文件', tag: '_playTtsAudio');
          }
        } catch (_) {}
      });

      Logger.d('TTS音频播放已启动', tag: '_playTtsAudio');
    } catch (e, stackTrace) {
      Logger.e('播放TTS音频失败: $e', tag: '_playTtsAudio', error: e);
      Logger.e('堆栈跟踪: $stackTrace', tag: '_playTtsAudio', error: stackTrace);
      await _cleanupPlayer();
      rethrow;
    }
  }

  void _handleElementSecondaryTap(
    String path,
    String label,
    BuildContext context,
    Offset position,
  ) {
    if (!widget.enableElementActions) {
      return;
    }

    // 剥离路径前缀，对外暴露不带 dictId.entryId 的路径
    final strippedPath = _stripPathPrefix(path);
    Logger.d(
      'Right-click on element: path=$strippedPath, label=$label, _currentOverlayEntry=$_currentOverlayEntry',
      tag: 'ComponentRenderer._handleElementSecondaryTap',
    );

    final pathParts = strippedPath.split('.');
    final pathData = _PathData(pathParts, label);

    _showContextMenu(context, position, pathData);
  }

  void _showContextMenu(
    BuildContext context,
    Offset? position,
    _PathData? pathData,
  ) async {
    Logger.d(
      '_showContextMenu called: position=$position, pathData=$pathData',
      tag: 'ComponentRenderer._showContextMenu',
    );

    // 关闭之前的菜单
    _removeCurrentOverlay();

    // 立即设置一个标志，表示正在显示菜单
    // 这样可以防止 _buildSelectionContextMenu 在 await 期间创建另一个菜单
    _isShowingContextMenu = true;

    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    late OverlayEntry barrierEntry;

    // 全屏透明遮罩，点击外部关闭菜单
    barrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _removeCurrentOverlay();
          },
          onSecondaryTapDown: (_) {
            _removeCurrentOverlay();
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    // Ensure position is within bounds
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    double dx = position?.dx ?? screenSize.width / 2;
    double dy = position?.dy ?? screenSize.height / 2;

    final order = await PreferencesService().getClickActionOrder();

    // 检查是否有选中文本
    final selectedText = _currentSelection?.plainText ?? '';
    final hasSelection = selectedText.isNotEmpty;

    // 根据菜单项数量动态计算菜单高度，确保菜单完全在屏幕内
    // 如果有选中文本，需要额外添加"查词"菜单项
    final itemCount = order.length + (hasSelection ? 1 : 0);
    const menuWidth = 200.0;
    // 菜单高度 = 菜单项高度 + 顶部内边距(8) + 底部内边距(8)
    final menuHeight = itemCount * 48.0 + 16.0;
    dx = dx.clamp(8.0, screenSize.width - menuWidth - 8.0);
    dy = dy.clamp(topPadding + 8.0, screenSize.height - menuHeight - 8.0);

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: dx,
          top: dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildContextMenuItems(
                    context: context,
                    order: order,
                    selectedText: hasSelection ? selectedText : null,
                    pathData: pathData,
                    closeMenu: _removeCurrentOverlay,
                    selectableState: null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(barrierEntry);
    overlay.insert(overlayEntry);
    _currentOverlayEntry = overlayEntry;
    _currentBarrierEntry = barrierEntry;

    // 菜单已显示，重置标志
    _isShowingContextMenu = false;
  }

  /// 计算菜单的垂直位置
  /// 考虑光标选择区域的高度，确保菜单不会与选择区域重叠
  /// [selectionTop] 选择区域的上边界（屏幕坐标）
  /// [selectionBottom] 选择区域的下边界（屏幕坐标）
  double _calculateMenuVerticalPosition({
    required double touchY,
    required double menuHeight,
    required Size screenSize,
    required double topPadding,
    required double bottomPadding,
    double? selectionTop,
    double? selectionBottom,
  }) {
    // 菜单显示在下方时的间隙（较大，方便用户操作）
    const gapBelow = 8.0;
    // 菜单显示在上方时的间隙
    const gapAbove = 32.0;

    // 如果有选择区域信息，使用选择区域的边界来计算空间
    // 选择区域的上部高度：从选择区域顶部到屏幕顶部的距离
    // 选择区域的下部高度：从选择区域底部到屏幕底部的距离
    final effectiveTop = selectionTop ?? touchY;
    final effectiveBottom = selectionBottom ?? touchY;

    final spaceBelow = screenSize.height - effectiveBottom - bottomPadding;
    final spaceAbove = effectiveTop - topPadding;

    double dy;
    if (spaceBelow >= menuHeight + gapBelow) {
      // 下方有足够空间，显示在选择区域下方
      dy = effectiveBottom + gapBelow;
    } else if (spaceAbove >= menuHeight + gapAbove) {
      // 上方有足够空间，显示在选择区域上方
      dy = effectiveTop - menuHeight - gapAbove;
    } else {
      // 空间都不够，选择空间较大的一方
      if (spaceBelow >= spaceAbove) {
        dy = effectiveBottom + gapBelow;
      } else {
        dy = effectiveTop - menuHeight - gapAbove;
      }
    }

    return dy;
  }

  /// 计算菜单高度
  /// [itemCount] 菜单项数量（不含分隔线）
  /// [dividerCount] 分隔线数量
  /// ListTile (dense: true) 高度约 48，分隔线高度约 1
  static double _calculateMenuHeight(int itemCount, int dividerCount) {
    return itemCount * 48.0 + dividerCount * 1.0;
  }

  /// 构建统一的菜单项列表（电脑端和手机端共用）
  List<Widget> _buildContextMenuItems({
    required BuildContext context,
    required List<String> order,
    required String? selectedText,
    required _PathData? pathData,
    required VoidCallback closeMenu,
    required SelectableRegionState? selectableState,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final menuItems = <Widget>[];
    final hasSelection = selectedText != null && selectedText.isNotEmpty;

    // 如果有选中文本，在最前面显示"查词"菜单项
    if (hasSelection) {
      menuItems.add(
        ListTile(
          leading: const Icon(Icons.search, size: 20),
          title: Text(
            '${context.t.settings.actionLabel.search}："${selectedText.length > 10 ? '${selectedText.substring(0, 10)}...' : selectedText}"',
            overflow: TextOverflow.ellipsis,
          ),
          dense: true,
          onTap: () {
            closeMenu();
            if (selectableState != null) {
              selectableState.clearSelection();
            }
            _handleTextSelectionSearch(selectedText!);
          },
        ),
      );

      // 只有"查词"下方才有分隔线
      if (order.isNotEmpty) {
        menuItems.add(
          Divider(
            height: 1,
            thickness: 0.5,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        );
      }
    }

    // 添加其他菜单项（之间无分隔线）
    for (int i = 0; i < order.length; i++) {
      final action = order[i];

      Widget? menuItem = _buildActionMenuItem(
        context: context,
        action: action,
        pathData: pathData,
        closeMenu: closeMenu,
        selectableState: selectableState,
        selectedText: selectedText,
      );

      if (menuItem != null) {
        menuItems.add(menuItem);
      }
    }

    // 添加"添加到笔记"菜单项
    if (pathData != null) {
      menuItems.add(
        ListTile(
          leading: const Icon(Icons.note_add, size: 20),
          title: Text(context.t.note.addToNote),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            _handleAddToNote(pathData, selectedText: selectedText);
          },
        ),
      );
    }

    return menuItems;
  }

  /// 构建单个操作菜单项
  Widget? _buildActionMenuItem({
    required BuildContext context,
    required String action,
    required _PathData? pathData,
    required VoidCallback closeMenu,
    required SelectableRegionState? selectableState,
    required String? selectedText,
  }) {
    switch (action) {
      case PreferencesService.actionAiTranslate:
        return ListTile(
          leading: const Icon(Icons.translate, size: 20),
          title: Text(context.t.settings.actionLabel.aiTranslate),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            if (pathData != null) {
              _performAiTranslate(pathData.path.join('.'), pathData.label);
            }
          },
        );
      case PreferencesService.actionEdit:
        return ListTile(
          leading: const Icon(Icons.edit, size: 20),
          title: Text(context.t.settings.actionLabel.edit),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            if (pathData != null) {
              widget.onEditElement?.call(
                pathData.path.join('.'),
                pathData.label,
              );
            }
          },
        );
      case PreferencesService.actionAskAi:
        return ListTile(
          leading: const Icon(Icons.auto_awesome, size: 20),
          title: Text(context.t.settings.actionLabel.askAi),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            if (pathData != null) {
              widget.onAiAsk?.call(pathData.path.join('.'), pathData.label);
            }
          },
        );
      case PreferencesService.actionCopy:
        return ListTile(
          leading: const Icon(Icons.copy, size: 20),
          title: Text(context.t.settings.actionLabel.copy),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            if (selectedText != null && selectedText.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: selectedText));
            } else if (pathData != null) {
              _performCopy(pathData.path.join('.'), pathData.label);
            }
          },
        );
      case PreferencesService.actionSpeak:
        return ListTile(
          leading: const Icon(Icons.volume_up, size: 20),
          title: Text(context.t.settings.actionLabel.speak),
          dense: true,
          onTap: () {
            closeMenu();
            selectableState?.clearSelection();
            if (pathData != null) {
              _performSpeak(pathData.path.join('.'), pathData.label);
            }
          },
        );
      case PreferencesService.actionSearch:
        // 已在最前面单独处理
        return null;
      default:
        return null;
    }
  }

  /// 构建文本选择的上下文菜单
  /// 手机端：显示和电脑端一样的软件菜单，同时保留光标选择功能
  /// 桌面端：不显示菜单，右键菜单由 SecondaryTapGestureRecognizer 处理
  /// 选择手柄（光标）由 SelectionArea 自动管理
  Widget _buildSelectionContextMenu(
    BuildContext context,
    SelectableRegionState state,
  ) {
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop) {
      return const SizedBox.shrink();
    }

    // 注意：不再阻止菜单重建，以便在光标调整时实时更新菜单位置
    // _isClosingContextMenu 标志仅在关闭过程中阻止重建
    if (_isClosingContextMenu) {
      Logger.d(
        '_buildSelectionContextMenu: closing, returning empty',
        tag: 'ContextMenu',
      );
      return const SizedBox.shrink();
    }

    // 手机端：显示软件菜单，同时保留光标选择功能
    // 光标选择功能由 SelectionArea 自动管理
    final selectedText = _currentSelection?.plainText ?? '';
    Logger.d(
      '_buildSelectionContextMenu: selectedText="$selectedText"',
      tag: 'ContextMenu',
    );

    if (selectedText.isEmpty) {
      Logger.d(
        '_buildSelectionContextMenu: no selection, returning empty',
        tag: 'ContextMenu',
      );
      return const SizedBox.shrink();
    }

    // 使用记录的路径数据，如果没有则使用默认值
    final pathData =
        _currentSelectionPathData ?? _PathData(['selection'], selectedText);
    Logger.d(
      '_buildSelectionContextMenu: using pathData=${pathData.path.join('.')}, label=${pathData.label}',
      tag: 'ContextMenu',
    );

    return FutureBuilder<List<String>>(
      future: PreferencesService().getClickActionOrder(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final order = snapshot.data!;

        // 构建菜单项列表
        final colorScheme = Theme.of(context).colorScheme;
        final menuItems = _buildContextMenuItems(
          context: context,
          order: order,
          selectedText: selectedText,
          pathData: pathData,
          closeMenu: () => state.clearSelection(),
          selectableState: state,
        );

        // 获取屏幕尺寸和安全区域
        final screenSize = MediaQuery.of(context).size;
        final topPadding = MediaQuery.of(context).padding.top;
        final bottomPadding = MediaQuery.of(context).padding.bottom;

        // 计算菜单尺寸
        const menuWidth = 200.0;
        // 计算实际菜单高度：ListTile (dense: true) 高度约 48，分隔线高度约 1
        // Material 容器无额外内边距
        int normalItemCount = 0;
        int dividerCount = 0;
        for (final item in menuItems) {
          if (item is Divider) {
            dividerCount++;
          } else {
            normalItemCount++;
          }
        }
        final menuHeight = _calculateMenuHeight(normalItemCount, dividerCount);

        double dx;
        double dy;

        // 均衡的间距：菜单与选区的距离
        const gap = 12.0;

        // 获取选择区域的位置信息
        double? selectionTop;
        double? selectionBottom;
        try {
          final endpoints = state.selectionEndpoints;
          if (endpoints.isNotEmpty) {
            // selectionEndpoints 返回的坐标已经按照 Y 坐标排序
            // endpoints.first 是上面的点，endpoints.last 是下面的点
            final topPoint = endpoints.first;
            final bottomPoint = endpoints.last;

            // 使用 SelectableRegionState 的 context 来获取正确的 RenderBox
            // selectionEndpoints 返回的是相对于 SelectionArea 的本地坐标
            final stateRenderBox =
                state.context.findRenderObject() as RenderBox?;
            if (stateRenderBox != null) {
              // 将本地坐标转换为全局坐标
              final topGlobal = stateRenderBox.localToGlobal(topPoint.point);
              final bottomGlobal = stateRenderBox.localToGlobal(
                bottomPoint.point,
              );

              // 获取行高
              // startGlyphHeight 是选择起点的行高，endGlyphHeight 是选择终点的行高
              // 由于 endpoints 已经按 Y 坐标排序，我们需要确定哪个行高对应哪个端点
              // 使用较大的行高来确保菜单不会覆盖选择区域
              final startLineHeight = state.startGlyphHeight;
              final endLineHeight = state.endGlyphHeight;
              final maxLineHeight = max(startLineHeight, endLineHeight);

              // 选择区域的上边界是上面那行的顶部
              selectionTop = topGlobal.dy;
              // 选择区域的下边界是下面那行的底部
              // 使用 maxLineHeight 确保包含所有可能的行高
              selectionBottom = bottomGlobal.dy + maxLineHeight;

              Logger.d(
                '_buildSelectionContextMenu: topGlobal=$topGlobal, bottomGlobal=$bottomGlobal, selectionTop=$selectionTop, selectionBottom=$selectionBottom, startLineHeight=$startLineHeight, endLineHeight=$endLineHeight',
                tag: 'ContextMenu',
              );
            } else {
              Logger.d(
                '_buildSelectionContextMenu: stateRenderBox is null',
                tag: 'ContextMenu',
              );
            }
          } else {
            Logger.d(
              '_buildSelectionContextMenu: endpoints is empty',
              tag: 'ContextMenu',
            );
          }
        } catch (e, stackTrace) {
          Logger.d(
            '_buildSelectionContextMenu: failed to get selection endpoints: $e\n$stackTrace',
            tag: 'ContextMenu',
          );
        }

        Logger.d(
          '_buildSelectionContextMenu: _selectionStartPosition=$_selectionStartPosition, menuHeight=$menuHeight, gap=$gap',
          tag: 'ContextMenu',
        );

        // 优先使用选择区域的位置来计算菜单位置
        if (selectionTop != null && selectionBottom != null) {
          // 使用选择区域的水平中心
          dx = screenSize.width / 2 - menuWidth / 2;
          dy = _calculateMenuVerticalPosition(
            touchY: _selectionStartPosition?.dy ?? selectionTop,
            menuHeight: menuHeight,
            screenSize: screenSize,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            selectionTop: selectionTop,
            selectionBottom: selectionBottom,
          );
        } else if (_selectionStartPosition != null) {
          // 没有选择区域信息时，使用触摸位置计算菜单位置
          dx = _selectionStartPosition!.dx - menuWidth / 2;
          dy = _calculateMenuVerticalPosition(
            touchY: _selectionStartPosition!.dy,
            menuHeight: menuHeight,
            screenSize: screenSize,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
          );
        } else {
          // 没有任何位置信息，使用屏幕底部居中
          dy = screenSize.height - bottomPadding - menuHeight - 16.0;
          dx = (screenSize.width - menuWidth) / 2;
        }

        // 确保菜单在屏幕范围内
        dx = dx.clamp(8.0, screenSize.width - menuWidth - 8.0);
        dy = dy.clamp(
          topPadding + 8.0,
          screenSize.height - bottomPadding - menuHeight - 8.0,
        );

        // 计算菜单区域矩形，用于判断点击是否在菜单内
        final menuRect = Rect.fromLTWH(dx, dy, menuWidth, menuHeight);

        // 返回自定义菜单
        // 使用 Listener 监听指针事件，区分点击和拖动
        // 点击外部关闭菜单，拖动事件穿透到底层支持滚动和光标拖动
        return Stack(
          children: [
            // 全屏透明遮罩层，检测点击关闭菜单
            // 使用 Listener 而不是 GestureDetector，更精确地控制事件处理
            Positioned.fill(
              child: _SelectionDismissOverlay(
                menuRect: menuRect,
                onDismiss: () {
                  Logger.d(
                    '_buildSelectionContextMenu: tap outside menu, clearing selection',
                    tag: 'ContextMenu',
                  );
                  state.clearSelection();
                },
              ),
            ),
            // 菜单本体
            Positioned(
              left: dx,
              top: dy,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.surface,
                child: SizedBox(
                  width: menuWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: menuItems,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建菜单项
  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    Logger.d('Building menu item: $label', tag: 'ContextMenu');
    return InkWell(
      onTap: () {
        Logger.d('InkWell onTap: $label', tag: 'ContextMenu');
        onTap();
      },
      onTapDown: (details) {
        Logger.d(
          'InkWell onTapDown: $label at ${details.globalPosition}',
          tag: 'ContextMenu',
        );
      },
      onTapUp: (details) {
        Logger.d(
          'InkWell onTapUp: $label at ${details.globalPosition}',
          tag: 'ContextMenu',
        );
      },
      onTapCancel: () {
        Logger.d('InkWell onTapCancel: $label', tag: 'ContextMenu');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  /// 处理文本选择后的查词操作
  void _handleTextSelectionSearch(String selectedText) {
    if (selectedText.isEmpty) return;

    // 移除格式化标记
    final plainText = _removeFormatting(selectedText);

    // 使用 lookup: 前缀触发查词导航
    // _handleTranslationTap 会识别这个前缀并导航到查词页面
    widget.onElementTap?.call('lookup:$plainText', plainText);
  }

  void _removeCurrentOverlay() {
    // 如果已经没有 overlay，直接返回，避免重复日志
    if (_currentOverlayEntry == null && _currentBarrierEntry == null) {
      return;
    }

    Logger.d(
      '_removeCurrentOverlay called, _currentOverlayEntry=$_currentOverlayEntry',
      tag: 'ContextMenu',
    );
    // 设置关闭标志，防止菜单重建
    _isClosingContextMenu = true;

    try {
      _currentOverlayEntry?.remove();
      _currentBarrierEntry?.remove();
      Logger.d(
        '_removeCurrentOverlay: overlay removed successfully',
        tag: 'ContextMenu',
      );
    } catch (e) {
      // 忽略已经移除的entry
      Logger.d(
        '_removeCurrentOverlay: error removing overlay: $e',
        tag: 'ContextMenu',
      );
    } finally {
      _currentOverlayEntry = null;
      _currentBarrierEntry = null;
      _isShowingContextMenu = false;
      // 注意：不清除 _currentSelectionPathData，保留路径数据供下次选择使用
      // 路径数据会在用户点击其他位置时更新
    }

    // 延迟重置关闭标志，给 SelectionArea 足够时间完成重建
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _isClosingContextMenu = false;
      }
    });
  }

  void _removePhraseOverlay() {
    try {
      _phraseOverlayEntry?.remove();
      _phraseBarrierEntry?.remove();
    } catch (e) {
      // 忽略已经移除的entry
    } finally {
      _phraseOverlayEntry = null;
      _phraseBarrierEntry = null;
    }
  }

  void _handlePhraseTap(String phrase, Offset position) async {
    _removePhraseOverlay();

    final plainPhrase = _removeFormatting(phrase);
    Logger.d('Phrase tapped: $plainPhrase', tag: 'PhraseTap');

    final dbService = DatabaseService();
    final currentDictId = _localEntry.dictId;
    final currentPage = _localEntry.page;

    // 只搜索当前词典
    final searchResult = await dbService.getAllEntries(
      plainPhrase,
      exactMatch: false,
      sourceLanguage: _sourceLanguage,
      dictId: currentDictId,
    );

    // 只保留与当前page相同的词条
    final filteredEntries = searchResult.entries
        .where((entry) => entry.page == currentPage)
        .toList();

    if (filteredEntries.isEmpty) {
      if (mounted) {
        showToast(context, context.t.entry.phraseNotFound(phrase: plainPhrase));
      }
      return;
    }

    if (mounted) {
      _showPhraseOverlay(filteredEntries, plainPhrase, position);
    }
  }

  void _showPhraseOverlay(
    List<DictionaryEntry> entries,
    String phrase,
    Offset position,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);

    final fontScale =
        (FontLoaderService().resolveFontScale(
          _sourceLanguage ?? 'en',
          isSerif: true,
        ) ??
        _fontScales[_sourceLanguage ?? 'en']?['serif'] ??
        1.0);
    final dictionaryContentScale = FontLoaderService()
        .getDictionaryContentScale();
    final iconSize = 18 * fontScale * dictionaryContentScale;

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;

    double overlayWidth;
    double dx;

    if (isMobile) {
      overlayWidth = screenSize.width - 32;
      dx = 16;
    } else {
      overlayWidth = 420.0 * dictionaryContentScale.clamp(0.8, 1.2);
      dx = position.dx;

      if (dx + overlayWidth > screenSize.width) {
        dx = screenSize.width - overlayWidth - 16;
      }
      if (dx < 16) {
        dx = 16;
      }
    }

    // maxHeight 预估，用于限制弹窗最大高度（在 builder 中会用到）
    final maxHeight = (screenSize.height * 0.55).clamp(150.0, 480.0);

    _phraseBarrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _removePhraseOverlay();
          },
          onSecondaryTapDown: (_) {
            _removePhraseOverlay();
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    _phraseOverlayEntry = OverlayEntry(
      builder: (ctx) {
        // 在 overlay 的 context 中获取状态栏高度（不受 SafeArea 影响的真实物理值）
        final statusBarHeight = MediaQuery.of(ctx).viewPadding.top;
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        final effectiveDy = (position.dy + 20).clamp(
          statusBarHeight + 8.0,
          screenSize.height - maxHeight - safeBottom - 8.0,
        );
        final effectiveDx = dx.clamp(
          8.0,
          screenSize.width - overlayWidth - 8.0,
        );
        return Positioned(
          left: effectiveDx,
          top: effectiveDy,
          width: overlayWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.75),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(
                              12 * fontScale * dictionaryContentScale,
                            ),
                            child: PageScaleWrapper(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: entries.asMap().entries.map((e) {
                                  final isLast = e.key == entries.length - 1;
                                  final phraseEntry = e.value;

                                  // 当短语弹窗中需要对 AI 翻译、编辑或询问AI时，导航到该短语词条的全屏详情页
                                  void navigateToPhraseDetail() async {
                                    _removePhraseOverlay();
                                    if (mounted) {
                                      final entryGroup =
                                          DictionaryEntryGroup.groupEntries(
                                            entries,
                                          );

                                      // 记录搜索历史
                                      final historyService =
                                          SearchHistoryService();
                                      await historyService.addSearchRecord(
                                        phrase,
                                      );

                                      // 获取历史记录构建浏览列表
                                      final records = await historyService
                                          .getSearchRecords();
                                      final historyWords = records
                                          .map((r) => r.word)
                                          .toList();
                                      final currentIndex = historyWords.indexOf(
                                        phrase,
                                      );

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EntryDetailPage(
                                            entryGroup: entryGroup,
                                            initialWord: phrase,
                                            browseList: historyWords.isNotEmpty
                                                ? BrowseList(
                                                    source: BrowseListSource
                                                        .searchHistory,
                                                    words: historyWords,
                                                    initialIndex:
                                                        currentIndex >= 0
                                                        ? currentIndex
                                                        : 0,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      );
                                    }
                                  }

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ComponentRenderer(
                                        entry: phraseEntry,
                                        topPadding: 8,
                                        bottomPadding: 8,
                                        enableElementActions: false,
                                        enableSelection: false,
                                        onElementTap: (path, label) {
                                          navigateToPhraseDetail();
                                        },
                                        onEditElement: (path, label) {
                                          navigateToPhraseDetail();
                                        },
                                        onAiAsk: (path, label) {
                                          navigateToPhraseDetail();
                                        },
                                        onGroupJump: (groupId, ctx) {
                                          navigateToPhraseDetail();
                                        },
                                      ),
                                      if (!isLast)
                                        Divider(
                                          height: 1,
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.4),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () async {
                            _removePhraseOverlay();
                            // 放大时搜索所有词典并跳转全屏查词
                            final dbService = DatabaseService();
                            final allResult = await dbService.getAllEntries(
                              phrase,
                              exactMatch: false,
                            );
                            if (!mounted) return;
                            final allEntryGroup = allResult.entries.isNotEmpty
                                ? DictionaryEntryGroup.groupEntries(
                                    allResult.entries,
                                  )
                                : DictionaryEntryGroup.groupEntries(entries);

                            // 记录搜索历史
                            final historyService = SearchHistoryService();
                            await historyService.addSearchRecord(phrase);

                            // 获取历史记录构建浏览列表
                            final records = await historyService
                                .getSearchRecords();
                            final historyWords = records
                                .map((r) => r.word)
                                .toList();
                            final currentIndex = historyWords.indexOf(phrase);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EntryDetailPage(
                                  entryGroup: allEntryGroup,
                                  initialWord: phrase,
                                  browseList: historyWords.isNotEmpty
                                      ? BrowseList(
                                          source:
                                              BrowseListSource.searchHistory,
                                          words: historyWords,
                                          initialIndex: currentIndex >= 0
                                              ? currentIndex
                                              : 0,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.all(
                              8 * fontScale * dictionaryContentScale,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(
                                alpha: 0.85,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.open_in_full,
                              size: iconSize,
                              color: colorScheme.primary,
                            ),
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
      },
    );

    overlay.insert(_phraseBarrierEntry!);
    overlay.insert(_phraseOverlayEntry!);
  }

  @override
  void dispose() {
    // _tempContentScale 是纯本地状态，无需还原全局缩放
    _scaleIndicatorTimer?.cancel();
    _scaleOverlayEntry?.remove();
    _scaleOverlayEntry = null;
    _longPressTimer?.cancel();
    _scrollSubscription?.cancel();
    _translationInsertSubscription?.cancel();
    _toggleHiddenSubscription?.cancel();
    _batchToggleHiddenSubscription?.cancel();
    // 只有在使用内部通知器时才销毁
    if (widget.hiddenLanguagesNotifier == null) {
      _hiddenLanguagesNotifier.dispose();
    }
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    for (final subscription in _streamSubscriptions) {
      subscription.cancel();
    }
    _streamSubscriptions.clear();
    _removeCurrentOverlay();
    _removePhraseOverlay();
    unawaited(_cleanupPlayer());
    // 清理闪烁动画控制器
    for (final controller in _highlightControllers.values) {
      controller.dispose();
    }
    _highlightControllers.clear();
    super.dispose();
  }

  /// 安全清理音频播放器
  Future<void> _cleanupPlayer() async {
    try {
      _playbackCompletionSub?.cancel();
      _playbackCompletionSub = null;

      final player = _currentPlayer;
      if (player != null) {
        _currentPlayer = null;
        // 从管理器注销
        MediaKitManager().unregisterPlayer(player);

        // 先停止再释放
        try {
          await player.stop().timeout(const Duration(milliseconds: 300));
        } catch (_) {}

        // 释放 native 资源
        try {
          await player.dispose().timeout(const Duration(milliseconds: 300));
        } catch (_) {}

        Logger.d('播放器已释放', tag: 'ComponentRenderer');
      }
    } catch (e) {
      Logger.d('清理播放器时出错: $e', tag: 'ComponentRenderer');
    }
  }

  String _getPage() {
    final entry = _localEntry;
    try {
      final jsonStr = entry.toString();
      if (jsonStr.contains('"page"')) {
        final RegExp pageRegExp = RegExp(r'"page"\s*:\s*"([^"]+)"');
        final match = pageRegExp.firstMatch(jsonStr);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    } catch (e) {
      return '';
    }
    return '';
  }

  List<String> _getSections() {
    final entry = _localEntry;
    final sections = entry.sense
        .map((sense) {
          final section = sense['section'] as String?;
          return section ?? '';
        })
        .where((s) => s.isNotEmpty)
        .toSet() // 去重
        .toList();

    // 如果只有一个section，则不显示
    if (sections.length <= 1) {
      return [];
    }

    return sections;
  }

  // ── 桌面端 Ctrl/Cmd + 滚轮 缩放 ──────────────────────────────────────────
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        (Platform.isMacOS && HardwareKeyboard.instance.isMetaPressed);
    if (!isCtrl) return;
    // 声明消费此事件，阻止 SingleChildScrollView 滚动
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent e,
    ) {
      if (e is PointerScrollEvent) _handleCtrlScroll(e.scrollDelta.dy);
    });
  }

  void _handleCtrlScroll(double deltaY) {
    const step = 0.05;
    final newScale = (_tempContentScale - deltaY.sign * step).clamp(0.5, 4.0);
    final rounded = (newScale * 20).round() / 20.0;
    if ((rounded - _tempContentScale).abs() < 0.001) return;
    _applyContentScale(rounded);
  }

  void _applyContentScale(double scale) {
    if (!mounted) return;
    setState(() {
      _tempContentScale = scale;
      _showScaleIndicator = true;
    });
    _updateScaleOverlay();
    _scaleIndicatorTimer?.cancel();
    _scaleIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showScaleIndicator = false);
        _scaleOverlayEntry?.markNeedsBuild();
      }
    });
  }

  void _updateScaleOverlay() {
    if (!mounted) return;
    if (_scaleOverlayEntry == null) {
      _scaleOverlayEntry = OverlayEntry(builder: _buildScaleOverlayContent);
      Overlay.of(context).insert(_scaleOverlayEntry!);
    } else {
      _scaleOverlayEntry!.markNeedsBuild();
    }
  }

  /// 缩放指示器固定显示在视口右上角（通过 Overlay 实现）
  Widget _buildScaleOverlayContent(BuildContext overlayCtx) {
    if (!_showScaleIndicator) return const SizedBox.shrink();
    final colorScheme = Theme.of(overlayCtx).colorScheme;
    final topPadding = MediaQuery.paddingOf(overlayCtx).top;
    final percent = (_tempContentScale * 100).round();
    final isDefault = (_tempContentScale - 1.0).abs() < 0.001;
    return Positioned(
      right: 16,
      top: topPadding + 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.zoom_in,
                size: 15,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (!isDefault) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _resetContentScale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.85,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '重置',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _resetContentScale() => _applyContentScale(1.0);

  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entry = _localEntry;
    final page = _getPage();
    final sections = _getSections();

    // 使用 VisibilityDetector 实现懒加载
    final visibilityWidget = VisibilityDetector(
      key: ValueKey('component_renderer_${entry.id}'),
      onVisibilityChanged: (visibilityInfo) {
        final visibleFraction = visibilityInfo.visibleFraction;
        final wasVisible = _isVisible;
        _isVisible = visibleFraction > 0;

        // 当组件首次可见时
        if (_isVisible && !wasVisible && !_hasBeenVisible) {
          Logger.d(
            'ComponentRenderer became visible for entry: ${entry.headword}',
            tag: 'ComponentRenderer',
          );
          // 设置标志并触发重建，确保 GlobalKey 被创建
          setState(() {
            _hasBeenVisible = true;
          });
          // 在下一帧处理待处理的滚动请求（等待 GlobalKey 创建完成）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _processPendingScrollRequests();
            }
          });
        }
      },
      child: HiddenLanguagesScope(
        notifier: _hiddenLanguagesNotifier,
        child: DictionaryInteractionScope(
          onElementTap: widget.onElementTap,
          onElementSecondaryTap: _handleElementSecondaryTap,
          child: PathScope(
            // 使用 dictId 和 entry_id 作为路径前缀，使各词典各条目的隐藏逻辑独立
            path: [widget.entry.dictId ?? '', widget.entry.entryIdAsInt.toString()],
            child: Builder(
              builder: (innerContext) {
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // 监听滚动结束事件
                    if (notification is ScrollEndNotification) {
                      _onScrollEnded();
                    }
                    return false; // 不阻止事件继续传递
                  },
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: widget.leftPadding >= 0 ? widget.leftPadding : 16,
                      right: widget.rightPadding >= 0 ? widget.rightPadding : 16,
                      top: widget.topPadding >= 0
                          ? widget.topPadding
                          : MediaQuery.of(context).padding.top + 16,
                      bottom: widget.bottomPadding >= 0 ? widget.bottomPadding : 16,
                    ),
                    child: widget.enableSelection
                        ? Listener(
                            // 捕获所有触摸事件，记录长按开始时的位置
                            onPointerDown: (event) {
                              _selectionStartPosition = event.position;
                            },
                            child: SelectionArea(
                              // 使用 key 强制在滚动结束后重建菜单
                              key: ValueKey('selection_area_$_menuRebuildCounter'),
                              // 自定义上下文菜单：上方显示系统文本选择菜单，下方显示软件右键菜单
                              contextMenuBuilder: (context, state) {
                                return _buildSelectionContextMenu(context, state);
                              },
                              onSelectionChanged: (selection) {
                                // 只记录选择状态，不触发任何操作
                                _currentSelection = selection;
                              },
                              child: _buildContentColumn(
                                innerContext,
                                page,
                                sections,
                                entry,
                              ),
                            ),
                          )
                        : _buildContentColumn(innerContext, page, sections, entry),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    // 桌面端：包裹 Listener 以支持 Ctrl/Cmd+滚轮缩放 + 叠加缩放指示器
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (!isDesktop) return visibilityWidget;
    return Shortcuts(
      shortcuts: {
        // Ctrl+C 或 Cmd+C 复制选中文本
        LogicalKeySet(
          Platform.isMacOS
              ? LogicalKeyboardKey.meta
              : LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyC,
        ): const _CopySelectionIntent(),
      },
      child: Actions(
        actions: {
          _CopySelectionIntent: _CopySelectionAction(onCopy: _copySelectedText),
        },
        child: Listener(
          onPointerSignal: _onPointerSignal,
          // 始终保持 ScaleLayoutWrapper 在树中，避免 scale 在 1.0/非1.0 间切换时
          // 因子节点类型变化导致子树（包括 _LazyImageLoader）被销毁重建
          child: ScaleLayoutWrapper(
            scale: _tempContentScale,
            child: visibilityWidget,
          ),
        ),
      ),
    );
  }

  /// 复制当前选中的文本
  void _copySelectedText() {
    final selectedText = _currentSelection?.plainText ?? '';
    if (selectedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selectedText));
      showToast(context, context.t.entry.copiedToClipboard);
    }
  }

  /// 构建内容列，提取为单独方法以便在 enableSelection 为 true/false 时复用
  Widget _buildContentColumn(
    BuildContext context,
    String page,
    List<String> sections,
    DictionaryEntry entry,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page.isNotEmpty) ...[
          _buildPageDisplay(context, page),
          const SizedBox(height: 16),
        ],
        if (sections.isNotEmpty) ...[
          _buildSectionNavigation(context, sections),
          const SizedBox(height: 12),
        ],
        _buildWord(context),
        if (entry.frequency.isNotEmpty ||
            entry.pronunciations.isNotEmpty ||
            entry.certifications.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (entry.frequency.isNotEmpty) _buildFrequencyStars(context),
              if (entry.pronunciations.isNotEmpty)
                _buildPronunciations(context),
              if (entry.certifications.isNotEmpty) ...[
                ..._buildCertificationsInline(context),
              ],
            ],
          ),
        ],
        // 渲染 data（在 sense 之前）
        _buildDataIfExist(context),
        if (entry.sense.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSenses(context),
        ],
        if (entry.senseGroup.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSenseGroups(context),
        ],
        // 渲染 phrase
        _buildPhrases(context),
        // 渲染 note（在普通 board 之前）
        _buildNoteIfExist(context),
        // 渲染所有未渲染的 key 为 board
        _buildRemainingBoards(context),
        // 渲染 clob 和 text（在最后）
        _buildClobIfExist(context),
        _buildTextIfExist(context),
      ],
    );
  }

  /// 构建词条标题（headline 或 headword）
  /// 优先显示 headline，如果没有则显示 headword
  /// 支持动态字体调整和右键菜单
  /// 支持点击切换音节形式（如果有 headword_syllable）
  Widget _buildWord(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    // 判断是否有音节形式可用
    final hasSyllable = entry.headwordSyllable != null &&
        entry.headwordSyllable!.isNotEmpty;

    // 决定当前显示的文本
    String displayText;
    bool isUsingHeadword;
    bool isShowingSyllable = false;

    if (entry.hasOriginalHeadword && entry.headword.isNotEmpty) {
      // 有 headword
      if (hasSyllable && _showHeadwordSyllable == true) {
        // 显示音节形式
        displayText = entry.headwordSyllable!;
        isUsingHeadword = true;
        isShowingSyllable = true;
      } else {
        // 显示原始 headword
        displayText = entry.headword;
        isUsingHeadword = true;
      }
    } else {
      // 没有 headword，使用 headline
      displayText = entry.headline ?? '';
      isUsingHeadword = false;
    }

    // 优先使用根节点 pos，如果没有则回退到 sense[0]['pos']
    final rootPosList = entry.posList;
    final sensePos = entry.sense.isNotEmpty
        ? (entry.sense[0]['pos'] as String? ?? '')
        : '';
    final isRootPos = rootPosList.isNotEmpty;
    final posList = isRootPos
        ? rootPosList
        : (sensePos.isNotEmpty ? [sensePos] : <String>[]);

    final isPhrase = entry.entryType == 'phrase';
    final headwordElementType = isPhrase
        ? DictElementType.headwordPhrase
        : DictElementType.headword;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: PathScope.append(
                context,
                key: isUsingHeadword ? 'headword' : 'headline',
                child: Builder(
                  builder: (context) {
                    return _buildHeadwordWithContextMenu(
                      context: context,
                      text: displayText,
                      elementType: headwordElementType,
                      colorScheme: colorScheme,
                      pathKey: isUsingHeadword ? 'headword' : 'headline',
                      label: isUsingHeadword ? 'Headword' : 'Headline',
                      canToggleSyllable: hasSyllable && isUsingHeadword,
                      isShowingSyllable: isShowingSyllable,
                    );
                  },
                ),
              ),
            ),
            if (posList.isNotEmpty) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _buildPosTags(context, posList, isRootPos: isRootPos),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 构建带有右键菜单和动态字体调整的标题widget
  Widget _buildHeadwordWithContextMenu({
    required BuildContext context,
    required String text,
    required DictElementType elementType,
    required ColorScheme colorScheme,
    required String pathKey,
    required String label,
    bool canToggleSyllable = false,
    bool isShowingSyllable = false,
  }) {
    final baseStyle = DictTypography.getBaseStyle(
      elementType,
      color: colorScheme.onSurface,
    );

    final path = PathScope.of(context);
    final pathData = _PathData(path, label);

    // 点击 headword 时的处理：如果有音节形式，则切换显示
    void onHeadwordTap() {
      if (canToggleSyllable) {
        // 切换音节显示状态
        setState(() {
          _showHeadwordSyllable = !isShowingSyllable;
        });
      } else {
        // 没有音节形式，执行默认点击动作
        _handleElementTap(_convertPathToString(path), label);
      }
    }

    // 创建手势识别器以支持点击事件
    final tapRecognizer = TapGestureRecognizer()
      ..onTapDown = (details) {
        _lastTapPosition = details.globalPosition;
        _currentSelectionPathData = pathData;
      }
      ..onTap = onHeadwordTap;

    // 解析格式化文本，传递 recognizer 以支持点击
    final formattedResult = _parseFormattedText(
      text,
      baseStyle,
      context: context,
      elementType: elementType,
      isBold: true,
      recognizer: tapRecognizer,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 GestureDetector 包装以支持点击和右键菜单
        return _buildTappableWidget(
          context: context,
          pathData: pathData,
          child: GestureDetector(
            onTap: onHeadwordTap,
            onSecondaryTapUp: (details) {
              _lastTapPosition = details.globalPosition;
              _handleElementSecondaryTap(
                _convertPathToString(path),
                label,
                context,
                details.globalPosition,
              );
            },
            child: _AutoScalingText(
              text: text,
              baseStyle: baseStyle,
              elementType: elementType,
              fontScales: _fontScales,
              sourceLanguage: _sourceLanguage,
              maxWidth: constraints.maxWidth,
              isBold: true,
              spans: formattedResult.spans,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrequencyStars(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;
    final frequency = entry.frequency;

    final starsValue = frequency['stars'] as String? ?? '';
    if (starsValue.isEmpty) return const SizedBox.shrink();

    final parts = starsValue.split('/');
    if (parts.length != 2) return const SizedBox.shrink();

    final filledCount = int.tryParse(parts[0]) ?? 0;
    final totalCount = int.tryParse(parts[1]) ?? 5;

    final level = frequency['level'] as String? ?? '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (level.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              level,
              style: DictTypography.getScaledStyle(
                DictElementType.frequencyLevel,
                language: _sourceLanguage,
                fontScales: _fontScales,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalCount, (index) {
            final isFilled = index < filledCount;
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: isFilled
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildExample(
    BuildContext context,
    dynamic value, {
    double leftMargin = 0,
    List<String>? path,
  }) {
    String usage = '';
    List<MapEntry<String, String>> texts = [];
    Map<String, dynamic>? source;
    List<Map<String, dynamic>> audios = [];
    dynamic comment;

    if (value is String) {
      texts.add(MapEntry('', value));
    } else if (value is Map<String, dynamic>) {
      usage = value['usage'] as String? ?? '';
      final sourceLang = _sourceLanguage ?? 'en';

      // 解析 source 字段
      final sourceValue = value['source'];
      if (sourceValue is Map<String, dynamic>) {
        source = sourceValue;
      }

      // 解析 audios 字段
      final audiosValue = value['audios'];
      if (audiosValue is List<dynamic>) {
        audios = audiosValue.whereType<Map<String, dynamic>>().toList();
      }

      // 解析 comment 字段
      comment = value['comment'];

      for (final entry in value.entries) {
        final key = entry.key;
        final val = entry.value;

        if (key == 'usage' ||
            key == 'source' ||
            key == 'audios' ||
            key == 'comment')
          continue;

        if (val is String && val.isNotEmpty) {
          texts.add(MapEntry(key, val));
        }
      }

      if (texts.isEmpty) {
        return const SizedBox.shrink();
      }

      texts.sort((a, b) {
        if (a.key == sourceLang) return -1;
        if (b.key == sourceLang) return 1;
        return 0;
      });
    }

    final examplePath = path ?? PathScope.of(context);
    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<String>(
      selector: (hiddenLanguages) {
        final relevantHidden = <String>[];
        for (final entry in texts) {
          final key = entry.key;
          final path = key.isEmpty ? examplePath : [...examplePath, key];
          final pathStr = path.join('.');
          if (hiddenLanguages.contains(pathStr)) {
            relevantHidden.add(pathStr);
          }
        }
        relevantHidden.sort();
        return relevantHidden.join(',');
      },
      builder: (context, hiddenPathsStr, child) {
        // Logger.d(
        //   '重建 Example: path=${examplePath.join('.')}, hiddenPaths=$hiddenPathsStr',
        //   tag: 'Rebuild',
        // );
        return _buildExampleItem(
          context: context,
          texts: texts,
          usage: usage,
          leftMargin: leftMargin,
          basePath: examplePath,
          onElementTap: _handleElementTap,
          onElementSecondaryTapWithPosition: (path, label, position) {
            _handleElementSecondaryTap(path, label, context, position);
          },
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
          audios: audios,
          source: source,
          dictId: _localEntry.dictId,
          comment: comment,
        );
      },
    );
  }

  /// 渲染带 [usage_group] 分组的例句块。
  /// [item] 须同时含有 "usage_group"（字符串）和 "example"（列表）字段。
  Widget _buildUsageGroupExample(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final usageGroup = item['usage_group'] as String? ?? '';
    final subExamples = (item['example'] as List<dynamic>?) ?? [];

    final usageGroupStyle = DictTypography.getScaledStyle(
      DictElementType.exampleUsage,
      language: _sourceLanguage,
      fontScales: _fontScales,
      color: colorScheme.primary,
      fontStyleOverride: FontStyle.italic,
    ).copyWith(fontSize: 14.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧浅色竖线
            Container(
              width: 2,
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 10),
            // 内容区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (usageGroup.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Builder(
                        builder: (context) {
                          final pathData = _PathData([
                            ...PathScope.of(context),
                            'usage_group',
                          ], 'Usage Group');
                          final textKey = GlobalKey();
                          final pathStr = _convertPathToString(pathData.path);

                          final result = _parseFormattedText(
                            usageGroup,
                            usageGroupStyle,
                            context: context,
                            elementType: DictElementType.exampleUsage,
                          );

                          return _buildTappableWidget(
                            context: context,
                            pathData: pathData,
                            text: usageGroup,
                            textStyle: usageGroupStyle,
                            customTextKey: textKey,
                            child: GestureDetector(
                              onSecondaryTapUp: (details) {
                                _handleElementSecondaryTap(
                                  pathStr,
                                  pathData.label,
                                  context,
                                  details.globalPosition,
                                );
                              },
                              onLongPress: () {
                                _handleElementSecondaryTap(
                                  pathStr,
                                  pathData.label,
                                  context,
                                  Offset.zero,
                                );
                              },
                              onTapDown: (details) {
                                _lastTapPosition = details.globalPosition;
                              },
                              onTap: () {
                                final now = DateTime.now();
                                final isDoubleTap = _lastTapTime != null &&
                                    now.difference(_lastTapTime!) <
                                        const Duration(milliseconds: 300);

                                if (isDoubleTap && _lastTapPosition != null) {
                                  _handleDoubleTapOnText(
                                    _lastTapPosition!,
                                    usageGroup,
                                    usageGroupStyle,
                                    textKey,
                                    context,
                                  );
                                  _lastTapTime = null;
                                  _lastTapPosition = null;
                                } else {
                                  _lastTapTime = now;
                                }
                              },
                              child: Builder(
                                key: textKey,
                                builder: (context) => Text.rich(
                                  TextSpan(children: result.spans),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ...subExamples.asMap().entries.map((entry) {
                    return PathScope.append(
                      context,
                      key: 'example.${entry.key}',
                      child: Builder(
                        builder: (context) =>
                            _buildExample(context, entry.value, leftMargin: 0),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildData(
    BuildContext context,
    Map<String, dynamic> value, {
    List<String>? path,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final keys = value.keys.toList();

    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DataTabWidget(
      keys: keys,
      value: value,
      path: path ?? PathScope.of(context),
      colorScheme: colorScheme,
      contentBuilder: (board, p) => _buildBoardContent(context, board, p),
      onElementTap: _handleElementTap,
      onElementSecondaryTap: _handleElementSecondaryTap,
      sourceLanguage: _sourceLanguage,
      fontScales: _fontScales,
    );
  }

  Widget _buildnote(
    BuildContext context,
    Map<String, String> noteMap, {
    List<String>? path,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final notePath = path ?? PathScope.of(context);

    List<MapEntry<String, String>> texts = [];
    for (final entry in noteMap.entries) {
      if (entry.value.isNotEmpty) {
        texts.add(MapEntry(entry.key, entry.value));
      }
    }

    if (texts.isEmpty) {
      return const SizedBox.shrink();
    }

    final sourceLang = _sourceLanguage ?? 'en';
    texts.sort((a, b) {
      if (a.key == sourceLang) return -1;
      if (b.key == sourceLang) return 1;
      return 0;
    });

    return HiddenLanguagesSelector<String>(
      selector: (hiddenLanguages) {
        final relevantHidden = <String>[];
        for (final entry in texts) {
          final textPath = [...notePath, entry.key];
          final pathStr = textPath.join('.');
          if (hiddenLanguages.contains(pathStr)) {
            relevantHidden.add(pathStr);
          }
        }
        relevantHidden.sort();
        return relevantHidden.join(',');
      },
      builder: (context, hiddenPathsStr, child) {
        return _buildNoteItem(
          context: context,
          texts: texts,
          basePath: notePath,
          sourceLanguage: _sourceLanguage,
        );
      },
    );
  }

  Widget _buildNoteItem({
    required BuildContext context,
    required List<MapEntry<String, String>> texts,
    required List<String> basePath,
    String? sourceLanguage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteBaseStyle = DictTypography.getBaseStyle(
      DictElementType.note,
      color: colorScheme.onSurfaceVariant,
    );
    final noteStyle = noteBaseStyle.copyWith(
      fontSize: (noteBaseStyle.fontSize ?? 14) + 1.0,
    );

    final spans = <InlineSpan>[];
    final noteTextKey = GlobalKey();
    final sourceLang = sourceLanguage ?? 'en';
    int currentTextOffset = 0;

    for (int i = 0; i < texts.length; i++) {
      final textEntry = texts[i];
      final text = textEntry.value;
      final langKey = textEntry.key;

      final textPath = [...basePath, langKey];
      final pathStr = textPath.join('.');
      final hidden = _hiddenLanguagesNotifier.value.contains(pathStr);

      if (hidden) continue;

      if (i > 0 && spans.isNotEmpty) {
        spans.add(WidgetSpan(child: SizedBox(width: 12)));
        currentTextOffset += 1;
      }

      final startOffset = currentTextOffset;
      currentTextOffset += text.length;

      final pathData = _PathData(textPath, 'Note');

      Logger.d(
        'Note: 创建 tapRecognizer, text=$text, langKey=$langKey',
        tag: 'NoteDebug',
      );

      final tapRecognizer = TapGestureRecognizer()
        ..onTapDown = (details) {
          Logger.d(
            'Note onTapDown: position=${details.globalPosition}',
            tag: 'NoteDebug',
          );
          _lastTapPosition = details.globalPosition;
          _currentSelectionPathData = pathData;
        }
        ..onTap = () {
          Logger.d('Note onTap 触发', tag: 'NoteDebug');
          _handleElementTap(_convertPathToString(textPath), pathData.label);

          final now = DateTime.now();
          final isDoubleTap =
              _lastTapTime != null &&
              now.difference(_lastTapTime!) <
                  const Duration(milliseconds: 300) &&
              _lastTapButton == 0;

          Logger.d(
            'Note onTap: isDoubleTap=$isDoubleTap, _lastTapTime=$_lastTapTime, _lastTapButton=$_lastTapButton',
            tag: 'NoteDebug',
          );

          if (isDoubleTap && _lastTapPosition != null) {
            Logger.d(
              'Note 双击触发, 准备调用 _handleDoubleTapOnText',
              tag: 'NoteDebug',
            );
            _handleDoubleTapOnText(
              _lastTapPosition!,
              text,
              noteStyle,
              noteTextKey,
              context,
              startOffset: startOffset,
            );
            _lastTapTime = null;
            _lastTapButton = null;
            _lastTapPosition = null;
          } else {
            _lastTapTime = now;
            _lastTapButton = 0;
          }
        };

      final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
        ..onSecondaryTapUp = (details) {
          Logger.d(
            'Note onSecondaryTapUp: position=${details.globalPosition}',
            tag: 'NoteDebug',
          );
          _lastTapPosition = details.globalPosition;
          _handleElementSecondaryTap(
            _convertPathToString(textPath),
            pathData.label,
            context,
            details.globalPosition,
          );
        };

      _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

      final recognizer = _MultiGestureRecognizer(
        tapRecognizer: tapRecognizer,
        secondaryTapRecognizer: secondaryTapRecognizer,
        longPressRecognizer: null,
        doubleTapRecognizer: null,
      );

      final result = _parseFormattedText(
        text,
        noteStyle,
        context: context,
        path: textPath,
        language: langKey,
        label: 'Note ($langKey)',
        recognizer: recognizer,
        elementType: DictElementType.note,
        mouseCursor: SystemMouseCursors.text,
        onShowMenu: (position, menuText) {
          Logger.d(
            'Note onShowMenu: position=$position, text=$menuText',
            tag: 'NoteDebug',
          );
          _handleElementSecondaryTap(
            _convertPathToString(textPath),
            pathData.label,
            context,
            position,
          );
        },
        onDoubleTapWord: (word, position) {
          Logger.d(
            'Note onDoubleTapWord: word=$word, position=$position',
            tag: 'NoteDebug',
          );
          _performDoubleTapSearch(word, context);
        },
      );

      spans.addAll(result.spans);
    }

    if (spans.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(basePath, 'Note'),
      customTextKey: noteTextKey,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(children: spans), key: noteTextKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageDisplay(BuildContext context, String page) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.rich(
        TextSpan(
          children: _parseFormattedText(
            page[0].toUpperCase() + page.substring(1),
            DictTypography.getBaseStyle(
              DictElementType.pageDisplay,
              color: colorScheme.onPrimaryContainer,
            ),
            context: context,
            elementType: DictElementType.pageDisplay,
          ).spans,
        ),
      ),
    );
  }

  Widget _buildSectionNavigation(BuildContext context, List<String> sections) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;

          return _buildTappableWidget(
            context: context,
            pathData: _PathData([
              'entry',
              'sense',
              '$index',
              'section',
            ], 'Section'),
            child: InkWell(
              onTap: () => _scrollToSection(index),
              borderRadius: BorderRadius.circular(8),
              mouseCursor: SystemMouseCursors.click,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text.rich(
                  TextSpan(
                    children: _parseFormattedText(
                      section,
                      DictTypography.getBaseStyle(
                        DictElementType.sectionNav,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      context: context,
                      elementType: DictElementType.sectionNav,
                    ).spans,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPronunciations(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    return PathScope.append(
      context,
      key: 'pronunciation',
      child: Builder(
        builder: (context) {
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            children: entry.pronunciations.asMap().entries.map((entryMap) {
              final index = entryMap.key;
              final pronunciation = entryMap.value;
              final region = pronunciation['region'] as String? ?? '';
              final notation = pronunciation['notation'] as String? ?? '';
              final audioFile = pronunciation['audio_file'] as String? ?? '';
              final note = pronunciation['note'] as String? ?? '';

              if (notation.isEmpty && audioFile.isEmpty) {
                return const SizedBox.shrink();
              }

              // 当原始 pronunciation 是单个对象（非列表）时，不添加索引路径段
              final isSingleObject = entry.pronunciationIsSingleObject;
              final indexKey = isSingleObject ? null : '$index';

              // 如果是单个对象，直接使用当前 context；否则添加索引路径段
              return indexKey == null
                  ? _buildPronunciationItem(
                      context,
                      region,
                      notation,
                      audioFile,
                      note,
                      entry.dictId,
                    )
                  : PathScope.append(
                      context,
                      key: indexKey,
                      child: Builder(
                        builder: (context) {
                          return _buildPronunciationItem(
                            context,
                            region,
                            notation,
                            audioFile,
                            note,
                            entry.dictId,
                          );
                        },
                      ),
                    );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildPronunciationItem(
    BuildContext context,
    String region,
    String notation,
    String audioFile,
    String note,
    String? dictId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = PathScope.of(context);
    final pathData = _PathData(path, 'Pronunciation');

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              _lastTapPosition = details.globalPosition;
              _handleElementSecondaryTap(
                _convertPathToString(path),
                pathData.label,
                context,
                details.globalPosition,
              );
            },
            child: InkWell(
              onTap: audioFile.isNotEmpty
                  ? () {
                      _playAudio(dictId ?? '', audioFile);
                    }
                  : null,
              onLongPress: () {
                _handleElementSecondaryTap(
                  _convertPathToString(path),
                  pathData.label,
                  context,
                  Offset.zero,
                );
              },
              borderRadius: BorderRadius.circular(12),
              splashColor: audioFile.isNotEmpty
                  ? colorScheme.primary.withValues(alpha: 0.1)
                  : null,
              mouseCursor: audioFile.isNotEmpty
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: audioFile.isNotEmpty
                      ? colorScheme.surfaceContainerHighest
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: audioFile.isNotEmpty
                      ? null
                      : Border.all(
                          color: colorScheme.outlineVariant,
                          width: 1,
                        ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (region.isNotEmpty)
                      PathScope.append(
                        context,
                        key: 'region',
                        child: Builder(
                          builder: (context) {
                            return _buildPronunciationRegionElement(
                              context,
                              region,
                              hasAudio: audioFile.isNotEmpty,
                            );
                          },
                        ),
                      ),
                    if (notation.isNotEmpty)
                      PathScope.append(
                        context,
                        key: 'notation',
                        child: Builder(
                          builder: (context) {
                            return _buildPronunciationPhoneticElement(
                              context,
                              notation,
                              hasAudio: audioFile.isNotEmpty,
                            );
                          },
                        ),
                      ),
                    if (audioFile.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Icon(
                        Icons.volume_up,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(width: 6),
          Builder(
            builder: (context) {
              // 使用已修正的 path 作为基础，添加 'note' 键
              final notePath = [...path, 'note'];
              final notePathData = _PathData(
                notePath,
                'Pronunciation Note',
              );

              // 创建手势识别器以支持双击查词和右键菜单
              final noteStyle = DictTypography.getBaseStyle(
                DictElementType.example,
                color: colorScheme.onSurfaceVariant,
              );

              final tapRecognizer = TapGestureRecognizer()
                ..onTapDown = (details) {
                  _lastTapPosition = details.globalPosition;
                  _currentSelectionPathData = notePathData;
                }
                ..onTap = () {
                  _handleElementTap(
                    _convertPathToString(notePath),
                    notePathData.label,
                  );
                  // 检测双击
                  final now = DateTime.now();
                  final isDoubleTap =
                      _lastTapTime != null &&
                      now.difference(_lastTapTime!) <
                          const Duration(milliseconds: 300) &&
                      _lastTapButton == 0;
                  if (isDoubleTap && _lastTapPosition != null) {
                    Logger.d('双击触发', tag: 'DoubleTapWord');
                    _handleDoubleTapOnText(
                      _lastTapPosition!,
                      note,
                      noteStyle,
                      GlobalKey(),
                      context,
                    );
                    _lastTapTime = null;
                    _lastTapButton = null;
                    _lastTapPosition = null;
                  } else {
                    _lastTapTime = now;
                    _lastTapButton = 0;
                  }
                };

              final secondaryTapRecognizer =
                  _SecondaryTapGestureRecognizer()
                    ..onSecondaryTapUp = (details) {
                      Logger.d(
                        'SecondaryTapRecognizer.onSecondaryTapUp called (note): position=${details.globalPosition}',
                        tag:
                            'ComponentRenderer._buildPronunciations',
                      );
                      _lastTapPosition = details.globalPosition;
                      _handleElementSecondaryTap(
                        _convertPathToString(notePath),
                        notePathData.label,
                        context,
                        details.globalPosition,
                      );
                    };

              _recognizers.addAll([
                tapRecognizer,
                secondaryTapRecognizer,
              ]);

              final recognizer = _MultiGestureRecognizer(
                tapRecognizer: tapRecognizer,
                secondaryTapRecognizer: secondaryTapRecognizer,
                longPressRecognizer: null,
                doubleTapRecognizer: null,
              );

              final result = _parseFormattedText(
                note,
                noteStyle,
                context: context,
                path: notePath,
                elementType: DictElementType.example,
                recognizer: recognizer,
                mouseCursor: SystemMouseCursors.text,
                onShowMenu: (position, text) {
                  _handleElementSecondaryTap(
                    _convertPathToString(notePath),
                    notePathData.label,
                    context,
                    position,
                  );
                },
                onDoubleTapWord: (word, position) {
                  _performDoubleTapSearch(word, context);
                },
              );

              return _HighlightWrapper(
                isHighlighting: _isHighlighting(
                  _convertPathToString(notePath),
                ),
                child: _TappableWrapper(
                  pathData: notePathData,
                  child: Text.rich(
                    TextSpan(children: result.spans),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _buildCertificationsInline(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    return entry.certifications.asMap().entries.map((entryMap) {
      final index = entryMap.key;
      final cert = entryMap.value;
      return _buildTappableWidget(
        context: context,
        pathData: _PathData([
          'entry',
          'certifications',
          '$index',
        ], 'Certification'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: colorScheme.tertiary.withValues(alpha: 0.3),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: _parseFormattedText(
                cert,
                DictTypography.getBaseStyle(
                  DictElementType.certification,
                  color: colorScheme.tertiary,
                ),
                context: context,
                elementType: DictElementType.certification,
              ).spans,
            ),
          ),
        ),
      );
    }).toList();
  }

  String _parseIndexValue(dynamic indexValue) {
    if (indexValue == null) return '';
    if (indexValue is int) return '$indexValue';
    if (indexValue is String && indexValue.isNotEmpty) return indexValue;
    return '';
  }

  Widget _renderIndex(
    BuildContext context,
    String indexStr, {
    double baseFontSize = 14,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // index 与 definition 的 baseline 对齐由父级
    // Row(crossAxisAlignment: CrossAxisAlignment.baseline) 保证，
    // 不再需要手动计算 topPadding。
    if (indexStr.isEmpty) {
      return _buildTappableWidget(
        context: context,
        pathData: _PathData(PathScope.of(context), 'Index'),
        child: Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text(
            '•',
            style: DictTypography.getBaseStyle(
              DictElementType.senseIndex,
              color: colorScheme.primary.withValues(alpha: 0.8),
            ).copyWith(fontSize: baseFontSize),
          ),
        ),
      );
    }
    return _buildTappableWidget(
      context: context,
      pathData: _PathData(PathScope.of(context), 'Index'),
      child: Transform.translate(
        offset: const Offset(0, -1.0),
        child: Text.rich(
          TextSpan(
            children: _parseFormattedText(
              indexStr,
              DictTypography.getBaseStyle(
                DictElementType.senseIndex,
                color: colorScheme.primary,
              ).copyWith(fontSize: baseFontSize),
              context: context,
              elementType: DictElementType.senseIndex,
            ).spans,
          ),
        ),
      ),
    );
  }

  Widget _renderPos(BuildContext context, String pos) {
    final colorScheme = Theme.of(context).colorScheme;

    if (pos.isEmpty) return const SizedBox.shrink();

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(PathScope.of(context), 'Part of Speech'),
      child: Text.rich(
        TextSpan(
          children: _parseFormattedText(
            pos,
            DictTypography.getBaseStyle(
              DictElementType.pos,
              color: colorScheme.primary,
            ),
            context: context,
            elementType: DictElementType.pos,
          ).spans,
        ),
      ),
    );
  }

  Widget _buildPosElement(
    BuildContext context,
    String pos, {
    bool isRootPos = false,
  }) {
    if (pos.isEmpty) return const SizedBox.shrink();

    // 根节点 pos 使用带圆角方框的样式
    if (isRootPos) {
      return _buildRootPosTag(context, pos, index: 0);
    }

    return PathScope.append(
      context,
      key: 'pos',
      child: Builder(builder: (context) => _renderPos(context, pos)),
    );
  }

  /// 构建多个 pos 标签（支持 List<string> 类型）
  Widget _buildPosTags(
    BuildContext context,
    List<String> posList, {
    required bool isRootPos,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: posList.asMap().entries.map((entry) {
        final index = entry.key;
        final pos = entry.value;
        return Padding(
          padding: EdgeInsets.only(left: index > 0 ? 6 : 0),
          child: _buildRootPosTag(
            context,
            pos,
            index: index,
            isRootPos: isRootPos,
          ),
        );
      }).toList(),
    );
  }

  /// 构建单个 pos 标签（带圆角方框样式）
  Widget _buildRootPosTag(
    BuildContext context,
    String pos, {
    required int index,
    bool isRootPos = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final textStyle = DictTypography.getBaseStyle(
      DictElementType.pos,
      color: colorScheme.primary,
    );

    final result = _parseFormattedText(
      pos,
      textStyle,
      context: context,
      elementType: DictElementType.pos,
    );

    // 根节点路径：pos（单个）或 pos.0, pos.1（多个）
    // sense 内路径：senses.0.pos（单个）或 senses.0.pos.0, senses.0.pos.1（多个）
    final String pathKey;
    if (isRootPos) {
      pathKey = index == 0 && _localEntry.posList.length == 1
          ? 'pos'
          : 'pos.$index';
    } else {
      pathKey = index == 0 ? 'pos' : 'pos.$index';
    }
    final pathData = _PathData([pathKey], 'Part of Speech');

    return PathScope.append(
      context,
      key: pathKey,
      child: Builder(
        builder: (context) {
          return GestureDetector(
            onLongPressStart: (details) {
              _showContextMenu(context, details.globalPosition, pathData);
            },
            onSecondaryTapDown: (details) {
              _showContextMenu(context, details.globalPosition, pathData);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.4),
                  width: 0.6,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text.rich(TextSpan(children: result.spans)),
            ),
          );
        },
      ),
    );
  }

  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// 检查键名是否为 child_xxxx 格式
  bool _isChildKey(String key) => key.startsWith('child_');

  /// 从 child_xxxx 键名提取显示标题
  String _getChildTitle(String key) {
    return key.length > 6 ? key.substring(6) : key;
  }

  Widget _buildPronunciationRegionElement(
    BuildContext context,
    String region, {
    bool hasAudio = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = PathScope.of(context);
    final pathData = _PathData(path, 'Region');

    final text = Text.rich(
      strutStyle: const StrutStyle(
        forceStrutHeight: true,
        height: 1.2,
        leading: 0,
      ),
      TextSpan(
        children: _parseFormattedText(
          '$region ',
          DictTypography.getBaseStyle(
            DictElementType.pronunciationRegion,
            color: colorScheme.outline,
          ),
          context: context,
          elementType: DictElementType.pronunciationRegion,
        ).spans,
      ),
    );

    return hasAudio
        ? text
        : _buildTappableWidget(
            context: context,
            pathData: pathData,
            child: GestureDetector(
              onSecondaryTapUp: (details) {
                _lastTapPosition = details.globalPosition;
                _handleElementSecondaryTap(
                  _convertPathToString(path),
                  pathData.label,
                  context,
                  details.globalPosition,
                );
              },
              child: text,
            ),
          );
  }

  Widget _buildPronunciationPhoneticElement(
    BuildContext context,
    String phonetic, {
    bool hasAudio = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = PathScope.of(context);
    final pathData = _PathData(path, 'Phonetic');

    final text = Text.rich(
      strutStyle: const StrutStyle(
        forceStrutHeight: true,
        height: 1.2,
        leading: 0,
      ),
      TextSpan(
        children: _parseFormattedText(
          phonetic,
          // 音标使用等宽字体；简单 copyWith 保留用户可修改的缩放比例
          DictTypography.getBaseStyle(
            DictElementType.phonetic,
            color: hasAudio
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ).copyWith(fontFamily: 'Monospace'),
          context: context,
          elementType: DictElementType.phonetic,
        ).spans,
      ),
    );

    return hasAudio
        ? text
        : _buildTappableWidget(
            context: context,
            pathData: pathData,
            child: GestureDetector(
              onSecondaryTapUp: (details) {
                _lastTapPosition = details.globalPosition;
                _handleElementSecondaryTap(
                  _convertPathToString(path),
                  pathData.label,
                  context,
                  details.globalPosition,
                );
              },
              child: text,
            ),
          );
  }

  Widget _buildSenseContent({
    required BuildContext context,
    String pos = '',
    required List<Map<String, dynamic>>? labels,
    bool labelsIsOriginalList = false,
    List<MapEntry<String, String>>? definitions,
    String? sourceLanguage,
    required List<String> targetLanguages,
    Map<String, Map<String, double>>? fontScales,
    dynamic synonym,
    dynamic antonym,
    dynamic related,
    Map<String, dynamic>? tail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    int currentTextOffset = 0;

    // 获取当前 sense 的路径作为 basePath
    final basePath = PathScope.of(context);

    final labelSpans = <InlineSpan>[];
    if (labels != null && labels.isNotEmpty) {
      for (int i = 0; i < labels.length; i++) {
        final labelPrefix = labelsIsOriginalList ? 'label.$i' : 'label';
        labelSpans.addAll(
          _buildLabelInlineSpans(context, labels[i], labelPrefix: labelPrefix),
        );
      }
    }
    for (final span in labelSpans) {
      spans.add(span);
      if (span is WidgetSpan) {
        currentTextOffset += 1; // WidgetSpan 占 1 个字符
      } else if (span is TextSpan) {
        currentTextOffset += span.toPlainText().length;
      }
    }

    final definitionTextKey = GlobalKey();

    if (definitions != null) {
      for (int i = 0; i < definitions.length; i++) {
        final definition = definitions[i];
        if (definition.value.isNotEmpty) {
          // 不同语言的 definition 之间添加间距
          if (i > 0) {
            spans.add(WidgetSpan(child: SizedBox(width: 12)));
            currentTextOffset += 1; // WidgetSpan 占 1 个字符
          } else if (spans.isNotEmpty) {
            spans.add(const TextSpan(text: ' '));
            currentTextOffset += 1; // 空格占 1 个字符
          }

          final startOffset = currentTextOffset;
          currentTextOffset += definition.value.length;

          final path = [...PathScope.of(context), definition.key];
          final pathData = _PathData(path, 'Definition');

          final hiddenPath = path.join('.');
          // 使用 notifier 的当前值，这样当状态变化时会重建
          final hidden = _hiddenLanguagesNotifier.value.contains(hiddenPath);

          // 使用 DictTypography 获取 definition 基础样式（字体族和缩放由 _parseFormattedText 处理）
          final definitionTextStyle = DictTypography.getBaseStyle(
            DictElementType.definition,
            color: colorScheme.onSurface,
          );

          // 创建手势识别器以支持点击和右键菜单
          final tapRecognizer = TapGestureRecognizer()
            ..onTapDown = (details) {
              _lastTapPosition = details.globalPosition;
              // 记录当前路径数据，用于手机端文本选择菜单
              _currentSelectionPathData = pathData;
            }
            ..onTap = () {
              // 单击立即生效
              _handleElementTap(_convertPathToString(path), pathData.label);

              // 检测双击
              final now = DateTime.now();
              final isDoubleTap =
                  _lastTapTime != null &&
                  now.difference(_lastTapTime!) <
                      const Duration(milliseconds: 300) &&
                  _lastTapButton == 0;

              if (isDoubleTap && _lastTapPosition != null) {
                Logger.d('双击触发', tag: 'DoubleTapWord');
                _handleDoubleTapOnText(
                  _lastTapPosition!,
                  definition.value,
                  definitionTextStyle,
                  definitionTextKey,
                  context,
                  startOffset: startOffset,
                );
                _lastTapTime = null;
                _lastTapButton = null;
                _lastTapPosition = null;
              } else {
                _lastTapTime = now;
                _lastTapButton = 0;
              }
            };

          // 恢复 SecondaryTapGestureRecognizer 用于电脑端右键菜单
          // 长按选择由 SelectionArea 处理
          final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
            ..onSecondaryTapUp = (details) {
              Logger.d(
                'SecondaryTapRecognizer.onSecondaryTapUp called (definition): position=${details.globalPosition}',
                tag: 'ComponentRenderer._buildSenseContent',
              );
              _lastTapPosition = details.globalPosition;
              _handleElementSecondaryTap(
                _convertPathToString(path),
                pathData.label,
                context,
                details.globalPosition,
              );
            };

          _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

          // 使用 MultiGestureRecognizer 支持点击和右键
          final recognizer = _MultiGestureRecognizer(
            tapRecognizer: tapRecognizer,
            secondaryTapRecognizer: secondaryTapRecognizer,
            longPressRecognizer: null,
            doubleTapRecognizer: null,
          );

          // definition.key 格式为 'definition.en'，需剥掉前缀取出真实语言代码
          final definitionLangKey = definition.key.contains('.')
              ? definition.key.split('.').last
              : definition.key;
          final result = _parseFormattedText(
            definition.value,
            definitionTextStyle,
            context: context,
            path: path,
            language: definitionLangKey.isEmpty ? null : definitionLangKey,
            label: 'Definition',
            recognizer: recognizer,
            hidden: hidden,
            elementType: DictElementType.definition,
            mouseCursor: SystemMouseCursors.text,
            onShowMenu: (position, text) {
              _handleElementSecondaryTap(
                _convertPathToString(path),
                pathData.label,
                context,
                position,
              );
            },
            onDoubleTapWord: (word, position) {
              _performDoubleTapSearch(word, context);
            },
          );
          // 直接使用 TextSpan 而不是 WidgetSpan，以实现文本接着换行的效果
          spans.addAll(result.spans);
        }
      }
    }

    // 渲染 synonym（同义词）
    if (synonym != null) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '  '));
      }
      spans.add(
        _buildInlineFieldSpan(
          context,
          'synonym',
          synonym,
          Theme.of(context).colorScheme.primary,
          basePath: basePath,
        ),
      );
    }

    // 渲染 antonym（反义词）
    if (antonym != null) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '  '));
      }
      spans.add(
        _buildInlineFieldSpan(
          context,
          'antonym',
          antonym,
          Theme.of(context).colorScheme.tertiary,
          basePath: basePath,
        ),
      );
    }

    // 渲染 related（相关词）
    if (related != null) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '  '));
      }
      spans.add(
        _buildInlineFieldSpan(
          context,
          'related',
          related,
          Theme.of(context).colorScheme.secondary,
          basePath: basePath,
        ),
      );
    }

    // 渲染 tail 字段
    if (tail != null && tail.isNotEmpty) {
      for (final entry in tail.entries) {
        if (entry.value != null) {
          if (spans.isNotEmpty) {
            spans.add(const TextSpan(text: '  '));
          }
          // tail 内的 synonym/antonym/related 使用对应颜色，其他字段使用 primary
          Color fieldColor;
          if (entry.key == 'synonym') {
            fieldColor = Theme.of(context).colorScheme.primary;
          } else if (entry.key == 'antonym') {
            fieldColor = Theme.of(context).colorScheme.tertiary;
          } else if (entry.key == 'related') {
            fieldColor = Theme.of(context).colorScheme.secondary;
          } else {
            fieldColor = Theme.of(context).colorScheme.primary;
          }
          spans.add(
            _buildInlineFieldSpan(
              context,
              entry.key,
              entry.value,
              fieldColor,
              labelPrefix: 'tail',
              basePath: basePath,
            ),
          );
        }
      }
    }

    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      strutStyle: const StrutStyle(
        forceStrutHeight: true,
        height: 1.8,
        leading: 0,
      ),
      TextSpan(children: spans),
      key: definitionTextKey,
    );
  }

  /// 渲染 sense 层级的内联字段（synonym/antonym/related/tail 内字段等）
  /// 前面带框的标签 + 后面带虚线下划线的文本，点击可直接查词
  InlineSpan _buildInlineFieldSpan(
    BuildContext context,
    String fieldName,
    dynamic value,
    Color color, {
    String? labelPrefix,
    required List<String> basePath,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // 字段名缩写映射
    final labelMap = {'synonym': 'SYN', 'antonym': 'OPP', 'related': 'RLT'};
    final displayLabel = labelMap[fieldName] ?? fieldName;

    final labelStyle = DictTypography.getBaseStyle(
      DictElementType.label,
      color: color,
    ).copyWith(fontSize: 12, fontWeight: FontWeight.w600);

    final textStyle = DictTypography.getBaseStyle(
      DictElementType.definition,
      color: colorScheme.onSurface,
    );

    final spans = <InlineSpan>[];

    // 标签部分
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
          ),
          child: Text(displayLabel, style: labelStyle),
        ),
      ),
    );

    // 构建值的路径前缀
    // 对于 sense 层级的 synonym/antonym/related，labelPrefix 为空
    // 对于 tail 内的字段，labelPrefix 为 'tail'
    final valuePathPrefix = (labelPrefix != null && labelPrefix.isNotEmpty)
        ? '$labelPrefix.$fieldName'
        : fieldName;

    // 构建字段路径（用于右键菜单）
    // 如果有 labelPrefix（如 'tail'），需要添加到路径中
    final fieldPath = (labelPrefix != null && labelPrefix.isNotEmpty)
        ? [...basePath, labelPrefix, fieldName]
        : [...basePath, fieldName];

    // 渲染值部分 - 使用原生下划线装饰
    if (value is List) {
      // 数组：逐个元素渲染，每个元素有独立的样式以支持点击查词
      for (int i = 0; i < value.length; i++) {
        if (i > 0) {
          spans.add(TextSpan(text: ', ', style: textStyle));
        }

        final itemText = value[i].toString();
        final itemPath = [...fieldPath, i.toString()];
        final itemPathData = _PathData(itemPath, itemText);

        final tapRecognizer = TapGestureRecognizer()
          ..onTapDown = (details) {
            _lastTapPosition = details.globalPosition;
            // 记录当前路径数据，用于手机端文本选择菜单
            _currentSelectionPathData = itemPathData;
          }
          ..onTap = () {
            widget.onElementTap?.call('lookup:$itemText', itemText);
          };

        final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
          ..onSecondaryTapUp = (details) {
            _lastTapPosition = details.globalPosition;
            _handleElementSecondaryTap(
              _convertPathToString(itemPath),
              itemText,
              context,
              details.globalPosition,
            );
          };

        _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

        final recognizer = _MultiGestureRecognizer(
          tapRecognizer: tapRecognizer,
          secondaryTapRecognizer: secondaryTapRecognizer,
          longPressRecognizer: null,
          doubleTapRecognizer: null,
        );

        // 使用原生下划线装饰
        spans.add(
          TextSpan(
            text: itemText,
            style: textStyle.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: color,
            ),
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
        );
      }
    } else {
      final itemText = value.toString();
      final itemPathData = _PathData(fieldPath, itemText);

      final tapRecognizer = TapGestureRecognizer()
        ..onTapDown = (details) {
          _lastTapPosition = details.globalPosition;
          // 记录当前路径数据，用于手机端文本选择菜单
          _currentSelectionPathData = itemPathData;
        }
        ..onTap = () {
          widget.onElementTap?.call('lookup:$itemText', itemText);
        };

      final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
        ..onSecondaryTapUp = (details) {
          _lastTapPosition = details.globalPosition;
          _handleElementSecondaryTap(
            _convertPathToString(fieldPath),
            itemText,
            context,
            details.globalPosition,
          );
        };

      _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

      final recognizer = _MultiGestureRecognizer(
        tapRecognizer: tapRecognizer,
        secondaryTapRecognizer: secondaryTapRecognizer,
        longPressRecognizer: null,
        doubleTapRecognizer: null,
      );

      // 使用原生下划线装饰
      spans.add(
        TextSpan(
          text: itemText,
          style: textStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  /// 创建统一的手势识别器，支持点击、右键和双击查词
  /// 长按由 SelectionArea 处理
  _MultiGestureRecognizer _createGestureRecognizer({
    required String pathKey,
    required String label,
    required List<String> path,
    required BuildContext context,
    String? text,
    TextStyle? textStyle,
    GlobalKey? textKey,
  }) {
    final tapRecognizer = TapGestureRecognizer()
      ..onTapDown = (details) {
        _lastTapPosition = details.globalPosition;
        // 记录当前路径数据，用于手机端文本选择菜单
        _currentSelectionPathData = _PathData(path, label);
      }
      ..onTap = () {
        // 单击立即生效
        _handleElementTap(pathKey, label);

        // 检测双击
        final now = DateTime.now();
        final isDoubleTap =
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
            _lastTapButton == 0;

        if (isDoubleTap &&
            _lastTapPosition != null &&
            text != null &&
            textStyle != null &&
            textKey != null) {
          Logger.d('$label 双击触发', tag: 'DoubleTapWord');
          _handleDoubleTapOnText(
            _lastTapPosition!,
            text,
            textStyle,
            textKey,
            context,
          );
          _lastTapTime = null;
          _lastTapButton = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapButton = 0;
        }
      };

    // 恢复 SecondaryTapGestureRecognizer 用于电脑端右键菜单
    final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
      ..onSecondaryTapUp = (details) {
        _lastTapPosition = details.globalPosition;
        _handleElementSecondaryTap(
          _convertPathToString(path),
          label,
          context,
          details.globalPosition,
        );
      };

    _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

    return _MultiGestureRecognizer(
      tapRecognizer: tapRecognizer,
      secondaryTapRecognizer: secondaryTapRecognizer,
      longPressRecognizer: null,
      doubleTapRecognizer: null,
    );
  }

  /// label 子元素的样式配置
  static const _labelStyleConfig = {
    'word': (
      isPlain: true,
      fontSize: 15.5,
      fontWeight: FontWeight.bold,
      isSerif: true,
      format: 'none',
    ),
    'pos': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w600,
      isSerif: false,
      format: 'none',
    ),
    'grammar': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w600,
      isSerif: false,
      format: 'bracket',
    ),
    'pronunciation': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w500,
      isSerif: false,
      format: 'none',
    ),
    'variant': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w600,
      isSerif: true,
      format: 'none',
    ),
    'region': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w500,
      isSerif: false,
      format: 'none',
    ),
    'pattern': (
      isPlain: true,
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      isSerif: false,
      format: 'bracket',
    ),
    'complex': (
      isPlain: true,
      fontSize: 15.0,
      fontWeight: FontWeight.w400,
      isSerif: false,
      format: 'corner',
    ),
  };

  /// 获取 label 子元素的样式
  TextStyle _getLabelElementStyle(
    BuildContext context,
    String key, {
    Color? overrideColor,
    double? fontSize,
    FontWeight? fontWeight,
    bool isSerif = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = overrideColor ?? colorScheme.primary;
    final baseStyle = DictTypography.getBaseStyle(
      DictElementType.labelPattern,
      color: key == 'word' ? colorScheme.onSurface : color,
    );

    TextStyle style = baseStyle;
    if (fontSize != null) {
      style = style.copyWith(fontSize: fontSize);
    }
    if (fontWeight != null) {
      style = style.copyWith(fontWeight: fontWeight);
    }
    if (isSerif) {
      final serifFont = FontLoaderService().getFontInfo(
        _sourceLanguage ?? '',
        isSerif: true,
      );
      if (serifFont != null) {
        style = style.copyWith(fontFamily: serifFont.fontFamily);
      }
    }

    return style;
  }

  /// 格式化 label 子元素的文本
  String _formatLabelText(String key, String value) {
    final format = _labelStyleConfig[key]?.format ?? 'none';
    switch (format) {
      case 'bracket':
        return '[$value]';
      case 'corner':
        return '「$value」';
      default:
        return value;
    }
  }

  /// 构建单个 label 子元素的 InlineSpan（统一处理所有子元素）
  InlineSpan _buildLabelElementSpan(
    BuildContext context,
    String key,
    String text, {
    int? index,
    String labelPrefix = 'label',
    Color? overrideColor,
    double? fontSize,
    FontWeight? fontWeight,
    bool isSerif = false,
    bool isPlain = true,
    bool hasBackground = false,
    bool isPattern = false,
  }) {
    final pathKey = index != null
        ? '$labelPrefix.$key.$index'
        : '$labelPrefix.$key';
    final path = [...PathScope.of(context), pathKey];
    final label = _capitalizeFirst(key);

    // 纯文本标签：获取样式并支持格式化文本
    if (isPlain) {
      final style = _getLabelElementStyle(
        context,
        key,
        overrideColor: overrideColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        isSerif: isSerif,
      );

      final textKey = GlobalKey();

      // 创建手势识别器以支持点击、右键和双击查词
      final recognizer = _createGestureRecognizer(
        pathKey: pathKey,
        label: label,
        path: path,
        context: context,
        text: text,
        textStyle: style,
        textKey: textKey,
      );

      final result = _parseFormattedText(
        text,
        style,
        context: context,
        elementType: DictElementType.labelPattern,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
      );

      // 使用 WidgetSpan 包裹独立的 Text.rich，以支持双击查词
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Text.rich(
          strutStyle: const StrutStyle(
            forceStrutHeight: true,
            height: 1.5,
            leading: 0,
          ),
          TextSpan(children: result.spans),
          key: textKey,
        ),
      );
    }

    // 带背景的标签使用 WidgetSpan（样式在 _buildLabelWidget 内部处理）
    final labelWidget = _buildLabelWidget(
      context,
      text,
      key,
      hasBackground,
      index: index,
      labelPrefix: labelPrefix,
      isPattern: isPattern,
      overrideColor: overrideColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );

    // 使用 baseline 对齐，确保跨平台一致性
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: labelWidget,
      ),
    );
  }

  List<InlineSpan> _buildLabelInlineSpans(
    BuildContext context,
    Map<String, dynamic>? label, {
    String labelPrefix = 'label',
  }) {
    if (label == null || label.isEmpty) return [];

    final spans = <InlineSpan>[];

    // 定义渲染顺序（signpost 最先，word 和 pos 其次，然后是其他）
    final renderOrder = [
      'signpost',
      'word',
      'pos',
      'grammar',
      'pronunciation',
      'variant',
      'region',
      'pattern',
      'register',
      'usage',
      'tone',
      'complex',
      'topic',
    ];

    // 已处理的 key
    final processedKeys = <String>{};

    // 辅助函数：添加 label 元素 spans
    void addLabelElementSpans(
      String key,
      dynamic value, {
      double? fontSize,
      FontWeight? fontWeight,
      bool isSerif = false,
      bool isPlain = false,
      bool hasBackground = false,
      bool isPattern = false,
      Color? overrideColor,
    }) {
      final values = value is List<dynamic> ? value : [value];
      for (int i = 0; i < values.length; i++) {
        final item = values[i];
        final itemValue = item is String ? item : '$item';
        final formattedValue = _formatLabelText(key, itemValue);
        final index = value is List<dynamic> ? i : null;

        spans.add(
          _buildLabelElementSpan(
            context,
            key,
            formattedValue,
            index: index,
            labelPrefix: labelPrefix,
            overrideColor: overrideColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
            isSerif: isSerif,
            isPlain: isPlain,
            hasBackground: hasBackground,
            isPattern: isPattern,
          ),
        );
        if (isPlain) {
          spans.add(const TextSpan(text: '  '));
        }
      }
    }

    for (final key in renderOrder) {
      final value = label[key];
      if (value == null) continue;
      processedKeys.add(key);

      // signpost 特殊处理（使用 Widget）
      if (key == 'signpost') {
        final signpostText = value is String ? value : '$value';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSignpostWidget(
                context,
                signpostText,
                labelPrefix: labelPrefix,
              ),
            ),
          ),
        );
        continue;
      }

      // 获取样式配置
      final config = _labelStyleConfig[key];
      final isPattern = key == 'pattern';
      final isPlain = isPattern ? false : (config?.isPlain ?? false);
      final hasBackground = isPattern ? false : !isPlain;

      // 获取颜色覆盖
      final colorScheme = Theme.of(context).colorScheme;
      final overrideColor = switch (key) {
        'pronunciation' ||
        'word' ||
        'variant' ||
        'pattern' => colorScheme.onSurface,
        _ => null,
      };

      addLabelElementSpans(
        key,
        value,
        fontSize: config?.fontSize,
        fontWeight: config?.fontWeight,
        isSerif: config?.isSerif ?? false,
        isPlain: isPlain,
        hasBackground: hasBackground,
        isPattern: isPattern,
        overrideColor: overrideColor,
      );
    }

    // 渲染未在 renderOrder 中定义的其他 label key
    // 这些没有特殊样式配置的label，字体小0.5号，垂直位置降低一点（在 _buildLabelWidget 和 _buildLabelElementSpan 中处理）
    for (final key in label.keys) {
      if (processedKeys.contains(key)) continue;
      final value = label[key];
      if (value == null) continue;

      addLabelElementSpans(key, value, isPlain: false, hasBackground: true);
    }

    return spans;
  }

  /// 渲染 signpost 标签：背景为主题色 primary，文字与页面背景色一致
  Widget _buildSignpostWidget(
    BuildContext context,
    String text, {
    String labelPrefix = 'label',
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = colorScheme.primary;
    final fgColor = colorScheme.surface;
    final textKey = GlobalKey();

    final textStyle = DictTypography.getBaseStyle(
      DictElementType.label,
      color: fgColor,
    ).copyWith(fontWeight: FontWeight.w600);

    final result = _parseFormattedText(
      text,
      textStyle,
      context: context,
      elementType: DictElementType.label,
    );

    final richText = Text.rich(
      strutStyle: const StrutStyle(
        forceStrutHeight: true,
        height: 1.3,
        leading: 0,
      ),
      TextSpan(children: result.spans),
    );

    final pathKey = '$labelPrefix.signpost';
    final path = [...PathScope.of(context), pathKey];
    final pathData = _PathData(path, 'Signpost');

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Builder(key: textKey, builder: (context) => richText),
    );

    return PathScope.append(
      context,
      key: pathKey,
      child: Builder(
        builder: (context) {
          return _buildTappableWidget(
            context: context,
            pathData: pathData,
            text: text,
            textStyle: textStyle,
            customTextKey: textKey,
            child: GestureDetector(
              onSecondaryTapUp: (details) {
                _handleElementSecondaryTap(
                  _convertPathToString(path),
                  'Signpost',
                  context,
                  details.globalPosition,
                );
              },
              onLongPress: () {
                _handleElementSecondaryTap(
                  _convertPathToString(path),
                  'Signpost',
                  context,
                  Offset.zero,
                );
              },
              onTapDown: (details) {
                _lastTapPosition = details.globalPosition;
              },
              onTap: () {
                final now = DateTime.now();
                final isDoubleTap = _lastTapTime != null &&
                    now.difference(_lastTapTime!) <
                        const Duration(milliseconds: 300);

                if (isDoubleTap && _lastTapPosition != null) {
                  _handleDoubleTapOnText(
                    _lastTapPosition!,
                    text,
                    textStyle,
                    textKey,
                    context,
                  );
                  _lastTapTime = null;
                  _lastTapPosition = null;
                } else {
                  _lastTapTime = now;
                }
              },
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabelWidget(
    BuildContext context,
    String text,
    String key,
    bool hasBackground, {
    int? index,
    Color? overrideColor,
    String labelPrefix = 'label',
    bool isPattern = false,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final pathKey = index != null
        ? '$labelPrefix.$key.$index'
        : '$labelPrefix.$key';
    final textKey = GlobalKey();

    TextStyle textStyle;
    if (!hasBackground) {
      // 无背景的语法模式标签（label.pattern）
      textStyle =
          DictTypography.getBaseStyle(
            DictElementType.labelPattern,
            color: overrideColor ?? colorScheme.primary,
          ).copyWith(
            fontWeight: fontWeight ?? FontWeight.normal,
            fontSize: fontSize,
          );
    } else {
      // 带背景的语法/地区/用法标签
      // 没有特殊指定样式的label，字体小0.5号，行高更紧凑
      final defaultFontSize = fontSize ?? 13.5; // 比基础13.5小约0.5号
      final defaultLineHeight = fontSize == null ? 1.5 : null; // 默认标签使用更紧凑的行高
      textStyle =
          DictTypography.getBaseStyle(
            DictElementType.label,
            color: overrideColor ?? colorScheme.onSurface,
          ).copyWith(
            fontWeight: FontWeight.w500,
            fontSize: defaultFontSize,
            height: defaultLineHeight,
          );
    }

    final elementType = hasBackground
        ? DictElementType.label
        : (isPattern ? DictElementType.label : DictElementType.labelPattern);

    // 使用PathScope包裹
    return PathScope.append(
      context,
      key: pathKey,
      child: Builder(
        builder: (context) {
          final path = PathScope.of(context);
          final labelName = _capitalizeFirst(key);

          // 创建手势识别器以支持点击、右键和双击查词
          final recognizer = _createGestureRecognizer(
            pathKey: _convertPathToString(path),
            label: labelName,
            path: path,
            context: context,
            text: text,
            textStyle: textStyle,
            textKey: textKey,
          );

          final result = _parseFormattedText(
            text,
            textStyle,
            context: context,
            elementType: elementType,
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          );
          final richText = Text.rich(
            strutStyle: const StrutStyle(
              forceStrutHeight: true,
              height: 1.5,
              leading: 0,
            ),
            TextSpan(children: result.spans),
          );

          Widget child;
          if (!hasBackground) {
            if (isPattern) {
              // pattern 标签：使用默认色纯文本，两边有 []，背景为主题色
              child = Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Builder(key: textKey, builder: (context) => richText),
              );
            } else {
              child = Builder(key: textKey, builder: (context) => richText);
            }
          } else {
            final onSurface = colorScheme.onSurface;

            child = Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.07),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.45),
                  width: 0.7,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(key: textKey, builder: (context) => richText),
            );
          }

          return _buildTappableWidget(
            context: context,
            pathData: _PathData(path, labelName),
            text: text,
            textStyle: textStyle,
            customTextKey: textKey,
            child: child,
          );
        },
      ),
    );
  }

  // 公共的 sense 渲染键列表
  static const List<String> _renderedSenseKeys = [
    'index',
    'pos',
    'definition',
    'label',
    'example',
    'subsense',
    'note',
    'image',
    'synonym',
    'antonym',
    'related',
    'tail',
  ];

  /// 渲染单个 sense 项
  Widget _buildSenseWidget(
    BuildContext context,
    Map<String, dynamic> sense,
    String indexStr, {
    bool isSubsense = false,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final senseLeftIndent = responsiveValue(
      screenWidth: screenWidth,
      minWidth: 400,
      maxWidth: 900,
      minValue: 20,
      maxValue: 40,
    );

    final labelRaw = sense['label'];
    // label 既可以是单个 map，也可以是 map list
    final labelList = <Map<String, dynamic>>[];
    if (labelRaw is Map<String, dynamic>) {
      labelList.add(labelRaw);
    } else if (labelRaw is List<dynamic>) {
      labelList.addAll(labelRaw.whereType<Map<String, dynamic>>());
    }
    final labelsIsOriginalList = labelRaw is List<dynamic>;
    final senselabel = labelList.isNotEmpty ? labelList : null;
    final pos = senselabel?.isNotEmpty == true
        ? (senselabel![0]['pos'] as String? ?? '')
        : '';
    final definitionObj = sense['definition'] as Map<String, dynamic>?;
    final exampleRaw = sense['example'];
    final List<dynamic>? example;
    final bool exampleIsOriginalList;
    if (exampleRaw is List<dynamic>) {
      example = exampleRaw;
      exampleIsOriginalList = true;
    } else if (exampleRaw is Map<String, dynamic>) {
      example = [exampleRaw];
      exampleIsOriginalList = false;
    } else {
      example = null;
      exampleIsOriginalList = false;
    }
    final subSenses = sense['subsense'] as List<dynamic>?;
    final noteRaw = sense['note'];
    Map<String, String>? noteMap;
    if (noteRaw is Map<String, dynamic>) {
      noteMap = {};
      for (final entry in noteRaw.entries) {
        if (entry.value is String && entry.value.isNotEmpty) {
          noteMap[entry.key] = entry.value as String;
        }
      }
      if (noteMap.isEmpty) noteMap = null;
    } else if (noteRaw is String && noteRaw.isNotEmpty) {
      final sourceLang = _sourceLanguage ?? 'en';
      noteMap = {sourceLang: noteRaw};
    }
    final image = sense['image'] as Map<String, dynamic>?;
    final synonym = sense['synonym'];
    final antonym = sense['antonym'];
    final related = sense['related'];
    final tail = sense['tail'] as Map<String, dynamic>?;

    List<MapEntry<String, String>> definitions = [];
    if (definitionObj != null) {
      for (final entry in definitionObj.entries) {
        if (entry.value is String && entry.value.isNotEmpty) {
          definitions.add(
            MapEntry('definition.${entry.key}', entry.value as String),
          );
        }
      }
    }

    final extraKeys = sense.keys
        .where((k) => !_renderedSenseKeys.contains(k))
        .toList();

    final extraWidgets = <Widget>[];
    for (final key in extraKeys) {
      final value = sense[key];
      if (value == null) continue;
      final widget = PathScope.append(
        context,
        key: key,
        child: Builder(
          builder: (context) {
            return renderJsonElement(
              context,
              key,
              value,
              PathScope.of(context),
            );
          },
        ),
      );
      extraWidgets.add(widget);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: senseLeftIndent,
          child: PathScope.append(
            context,
            key: 'index',
            child: Builder(
              builder: (context) => _renderIndex(
                context,
                indexStr,
                baseFontSize: isSubsense ? 13 : 14,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
                    child: HiddenLanguagesSelector<String>(
                      selector: (hiddenLanguages) {
                        final relevantHidden = <String>[];
                        for (final def in definitions) {
                          final path = [...PathScope.of(context), def.key];
                          final pathStr = path.join('.');
                          if (hiddenLanguages.contains(pathStr)) {
                            relevantHidden.add(pathStr);
                          }
                        }
                        relevantHidden.sort();
                        return relevantHidden.join(',');
                      },
                      builder: (context, hiddenPathsStr, child) {
                        // Logger.d(
                        //   '重建 SenseContent: pos=$pos, definitions=$definitions, hiddenPaths=$hiddenPathsStr',
                        //   tag: 'Rebuild',
                        // );
                        return _buildSenseContent(
                          context: context,
                          pos: pos,
                          labels: senselabel,
                          labelsIsOriginalList: labelsIsOriginalList,
                          definitions: definitions,
                          sourceLanguage: _sourceLanguage,
                          targetLanguages: _targetLanguages,
                          fontScales: _fontScales,
                          synonym: synonym,
                          antonym: antonym,
                          related: related,
                          tail: tail,
                        );
                      },
                    ),
                  ),
                  if (image != null && image.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final imageFile = image['image_file'] as String?;
                        if (imageFile == null || imageFile.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _buildImageElement(
                          context,
                          image,
                          _localEntry.dictId,
                          'image',
                          imageFile,
                        );
                      },
                    ),
                ],
              ),
              // end of definition Row
              if (example != null && example.isNotEmpty) ...[
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: example
                      .asMap()
                      .entries
                      .map(
                        (exampleEntry) => PathScope.append(
                          context,
                          key: exampleIsOriginalList
                              ? 'example.${exampleEntry.key}'
                              : 'example',
                          child: Builder(
                            builder: (context) {
                              final val = exampleEntry.value;
                              if (val is Map<String, dynamic> &&
                                  val.containsKey('usage_group') &&
                                  val.containsKey('example')) {
                                return _buildUsageGroupExample(context, val);
                              }
                              return _buildExample(context, val, leftMargin: 0);
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (noteMap != null && noteMap.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: PathScope.append(
                    context,
                    key: 'note',
                    child: Builder(
                      builder: (context) => _buildnote(context, noteMap!),
                    ),
                  ),
                ),
              if (extraWidgets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: extraWidgets,
                  ),
                ),
              if (subSenses != null && subSenses.isNotEmpty) ...[
                // 仅当 sense 中有其他内容时才添加上边距
                if (definitions.isNotEmpty ||
                    (example != null && example.isNotEmpty) ||
                    (noteMap != null && noteMap.isNotEmpty) ||
                    (image != null && image.isNotEmpty) ||
                    extraWidgets.isNotEmpty)
                  const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: subSenses.asMap().entries.expand((subEntry) {
                    final subIndexStr = _parseIndexValue(
                      subEntry.value['index'],
                    );
                    final widgets = <Widget>[
                      PathScope.append(
                        context,
                        key: 'subsense.${subEntry.key}',
                        child: Builder(
                          builder: (context) {
                            final subSensePath = PathScope.of(context);
                            final subSensePathStr = _convertPathToString(
                              subSensePath,
                            );
                            final isHighlighting = _isHighlighting(
                              subSensePathStr,
                            );
                            return _HighlightWrapper(
                              isHighlighting: isHighlighting,
                              child: Container(
                                key: _getElementKey(subSensePathStr),
                                child: _buildSenseWidget(
                                  context,
                                  subEntry.value as Map<String, dynamic>,
                                  subIndexStr,
                                  isSubsense: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ];
                    if (subEntry.key < subSenses.length - 1) {
                      widgets.add(const SizedBox(height: 12));
                    }
                    return widgets;
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSenses(BuildContext context, [DictionaryEntry? entry]) {
    final effectiveEntry = entry ?? _localEntry;

    return PathScope.append(
      context,
      key: 'sense',
      child: Builder(
        builder: (context) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: effectiveEntry.sense.asMap().entries.map((entryData) {
              final sense = entryData.value;
              final indexStr = _parseIndexValue(sense['index']);

              return PathScope.append(
                context,
                key: '${entryData.key}',
                child: Builder(
                  builder: (context) {
                    final sensePath = PathScope.of(context);
                    final sensePathStr = _convertPathToString(sensePath);
                    final isHighlighting = _isHighlighting(sensePathStr);
                    return _HighlightWrapper(
                      isHighlighting: isHighlighting,
                      child: Container(
                        key: _getElementKey(sensePathStr),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSenseWidget(context, sense, indexStr),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildTappableGroupName(
    String text,
    String path,
    String label,
    TextStyle textStyle,
  ) {
    // 创建路径数据用于菜单
    final pathData = _PathData(path.split('.'), text);

    // Logger.d(
    //   '_buildTappableGroupName: text=$text, path=$path, label=$label',
    //   tag: 'GroupName',
    // );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        // 长按触发菜单
        onLongPressStart: (details) {
          Logger.d(
            'onLongPressStart: position=${details.globalPosition}',
            tag: 'GroupName',
          );
          _showContextMenu(context, details.globalPosition, pathData);
        },
        // 右键触发菜单
        onSecondaryTapDown: (details) {
          Logger.d(
            'onSecondaryTapDown: position=${details.globalPosition}',
            tag: 'GroupName',
          );
          _showContextMenu(context, details.globalPosition, pathData);
        },
        child: Text.rich(
          TextSpan(
            children: _parseFormattedText(
              text,
              textStyle,
              context: context,
              onShowMenu: (position, selectedText) {
                Logger.d(
                  'onShowMenu called: position=$position, selectedText=$selectedText',
                  tag: 'GroupName',
                );
                _showContextMenu(context, position, pathData);
              },
            ).spans,
          ),
        ),
      ),
    );
  }

  Widget _buildSenseGroups(BuildContext context, [DictionaryEntry? entry]) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveEntry = entry ?? _localEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: effectiveEntry.senseGroup.asMap().entries.map((groupEntry) {
        final groupIndex = groupEntry.key;
        final group = groupEntry.value;
        final groupName = group['group_name'] as String? ?? '';
        final groupSubName = group['group_sub_name'] as String? ?? '';
        final senses = group['sense'] as List<dynamic>? ?? [];

        final groupPath = 'sense_group.$groupIndex';

        return Column(
          key: _sectionKeys.putIfAbsent(groupIndex, () => GlobalKey()),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groupName.isNotEmpty || groupSubName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (groupName.isNotEmpty)
                      _buildTappableGroupName(
                        groupName,
                        '${groupPath}.group_name',
                        'Group Name',
                        DictTypography.getBaseStyle(
                          DictElementType.groupName,
                          color: colorScheme.primary,
                        ),
                      ),
                    if (groupSubName.isNotEmpty)
                      _buildTappableGroupName(
                        groupSubName,
                        '${groupPath}.group_sub_name',
                        'Group Sub Name',
                        DictTypography.getBaseStyle(
                          DictElementType.groupSubName,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            if (senses.isNotEmpty)
              PathScope.append(
                context,
                key: 'sense_group.$groupIndex.sense',
                child: Builder(
                  builder: (context) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: senses.asMap().entries.map((senseEntry) {
                        final sense = senseEntry.value;
                        final indexStr = _parseIndexValue(sense['index']);

                        return PathScope.append(
                          context,
                          key: '${senseEntry.key}',
                          child: Builder(
                            builder: (context) {
                              final sensePath = PathScope.of(context);
                              final sensePathStr = _convertPathToString(
                                sensePath,
                              );
                              final isHighlighting = _isHighlighting(
                                sensePathStr,
                              );
                              return _HighlightWrapper(
                                isHighlighting: isHighlighting,
                                child: Container(
                                  key: _getElementKey(sensePathStr),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSenseWidget(
                                        context,
                                        sense as Map<String, dynamic>,
                                        indexStr,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  // 已单独渲染的 key 列表，这些 key 不会出现在 _buildRemainingBoards 中
  // 使用共享常量，确保与 dictionary_navigation_panel 保持一致
  static const List<String> _renderedKeys = kExcludedEntryKeys;

  /// 渲染 data（如果存在），在 sense 之前显示
  Widget _buildDataIfExist(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    if (!entryJson.containsKey('data')) return const SizedBox.shrink();

    final value = entryJson['data'];
    if (value is! Map<String, dynamic> || value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildData(context, value, path: ['data']),
      ],
    );
  }

  /// 渲染 note（如果存在），在普通 board 之前显示
  Widget _buildNoteIfExist(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    if (!entryJson.containsKey('note')) return const SizedBox.shrink();

    final value = entryJson['note'];
    if (value == null) return const SizedBox.shrink();

    Map<String, String>? noteMap;
    if (value is Map<String, dynamic>) {
      noteMap = {};
      for (final entry in value.entries) {
        if (entry.value is String && entry.value.isNotEmpty) {
          noteMap[entry.key] = entry.value as String;
        }
      }
      if (noteMap.isEmpty) noteMap = null;
    } else if (value is String && value.isNotEmpty) {
      final sourceLang = _sourceLanguage ?? 'en';
      noteMap = {sourceLang: value};
    }

    if (noteMap == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildnote(context, noteMap, path: ['note']),
      ],
    );
  }

  /// 渲染 clob（如果存在），在最后显示
  Widget _buildClobIfExist(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    if (!entryJson.containsKey('clob')) return const SizedBox.shrink();

    final value = entryJson['clob'];
    if (value == null) return const SizedBox.shrink();

    return _buildClobContent(context, value, ['clob']);
  }

  /// 渲染 text（如果存在），在最后显示
  Widget _buildTextIfExist(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    if (!entryJson.containsKey('text')) return const SizedBox.shrink();

    final value = entryJson['text'];
    if (value == null) return const SizedBox.shrink();

    return _buildTextContent(context, value, ['text']);
  }

  Widget _buildPhrases(BuildContext context, [DictionaryEntry? entry]) {
    final effectiveEntry = entry ?? _localEntry;
    final phrases = effectiveEntry.phrase;

    if (phrases.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final phraseTitleStyle = DictTypography.getScaledStyle(
      DictElementType.phraseTitle,
      language: _sourceLanguage,
      fontScales: _fontScales,
      color: colorScheme.primary,
    );
    final phraseIconScale = DictTypography.getScale(
      DictElementType.phraseTitle,
      language: _sourceLanguage,
      fontScales: _fontScales,
    );

    // 获取 phrases 的 GlobalKey 用于滚动定位
    final phrasesKey = _getElementKey('phrase');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        PathScope.append(
          context,
          key: 'phrases',
          child: Builder(
            builder: (context) {
              return Container(
                key: phrasesKey, // 绑定 GlobalKey 用于滚动定位
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote,
                          size: 16 * phraseIconScale,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text('Phrases', style: phraseTitleStyle),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        // 动态判断：用 TextPainter 测量最长短语宽度，
                        // 若两个最长的短语都能放进一行则用双列，否则单列。
                        final phraseBaseStyle = DictTypography.getBaseStyle(
                          DictElementType.phraseWord,
                          color: Colors.black,
                        );
                        double measurePhraseWidth(String text) {
                          final tp = TextPainter(
                            text: TextSpan(
                              text: _removeFormatting(text),
                              style: phraseBaseStyle,
                            ),
                            maxLines: 1,
                            textDirection: TextDirection.ltr,
                          );
                          tp.layout(maxWidth: double.infinity);
                          return tp.width;
                        }

                        const itemPaddingH =
                            12.0 * 2; // horizontal padding inside each chip
                        final maxPhraseWidth = phrases
                            .map((p) => measurePhraseWidth(p.toString()))
                            .fold<double>(0.0, (a, b) => a > b ? a : b);
                        final twoColItemWidth =
                            (constraints.maxWidth - spacing) / 2;
                        final useTwoColumns =
                            maxPhraseWidth + itemPaddingH <= twoColItemWidth;
                        final itemWidth = useTwoColumns
                            ? twoColItemWidth
                            : constraints.maxWidth;

                        return Wrap(
                          spacing: useTwoColumns ? spacing : 0,
                          runSpacing: 6,
                          children: phrases.asMap().entries.map((entry) {
                            final index = entry.key;
                            final phrase = entry.value;
                            return SizedBox(
                              width: itemWidth,
                              child: PathScope.append(
                                context,
                                key: '$index',
                                child: Builder(
                                  builder: (context) {
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (details) {
                                        _handlePhraseTap(
                                          phrase,
                                          details.globalPosition,
                                        );
                                      },
                                      onSecondaryTapUp: (details) {
                                        _handleElementSecondaryTap(
                                          _convertPathToString(
                                            PathScope.of(context),
                                          ),
                                          'Phrase',
                                          context,
                                          details.globalPosition,
                                        );
                                      },
                                      onLongPressStart: (details) {
                                        _handleElementSecondaryTap(
                                          _convertPathToString(
                                            PathScope.of(context),
                                          ),
                                          'Phrase',
                                          context,
                                          details.globalPosition,
                                        );
                                      },
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: colorScheme.outlineVariant
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text.rich(
                                            TextSpan(
                                              children: parseFormattedText(
                                                phrase,
                                                DictTypography.getBaseStyle(
                                                  DictElementType.phraseWord,
                                                  color: colorScheme.onSurface,
                                                ),
                                                sourceLanguage: _sourceLanguage,
                                                fontScales: _fontScales,
                                                elementType:
                                                    DictElementType.phraseWord,
                                                isBold: true,
                                              ).spans,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建子词条（child_xxxx 字段，单个 Map 格式）
  /// 子词条是一个可折叠的组件，包含 headword、pos、pronunciation（同行）、sense 等
  /// 默认展开，点击可折叠
  Widget _buildChildEntrySingle(
    BuildContext context,
    String key,
    Map<String, dynamic> childData,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _getChildTitle(key);
    final pathStr = key;
    // 默认展开：只有明确标记为折叠时才折叠
    final isExpanded = !_collapsedChildPaths.contains(pathStr);

    // 使用 key 作为 GlobalKey 路径
    final elementKey = _getElementKey(pathStr);

    return PathScope.append(
      context,
      key: key,
      child: Builder(
        builder: (context) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 可折叠的标题栏（紧凑布局）- GlobalKey 绑定在这里
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        // 当前展开，点击后折叠
                        _collapsedChildPaths.add(pathStr);
                      } else {
                        // 当前折叠，点击后展开
                        _collapsedChildPaths.remove(pathStr);
                      }
                    });
                  },
                  child: Padding(
                    key: elementKey, // GlobalKey 绑定在标题行
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: DictTypography.getScaledStyle(
                            DictElementType.childTitle,
                            language: _sourceLanguage,
                            fontScales: _fontScales,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0 : -0.25,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 展开的内容
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  firstCurve: Curves.easeInOut,
                  secondCurve: Curves.easeInOut,
                  sizeCurve: Curves.easeInOut,
                  crossFadeState: isExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: _buildChildEntryContent(context, childData, pathStr),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建多个子词条（child_xxxx 为 List 格式时）
  /// 一个标题 xxxx，下面包含多个子词条内容
  Widget _buildChildEntryList(
    BuildContext context,
    String key,
    List<dynamic> children,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _getChildTitle(key);
    final pathStr = key;
    // 默认展开：只有明确标记为折叠时才折叠
    final isExpanded = !_collapsedChildPaths.contains(pathStr);

    // 使用 key 作为 GlobalKey 路径
    final elementKey = _getElementKey(pathStr);

    return PathScope.append(
      context,
      key: key,
      child: Builder(
        builder: (context) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 可折叠的标题栏（紧凑布局）- GlobalKey 绑定在这里
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        // 当前展开，点击后折叠
                        _collapsedChildPaths.add(pathStr);
                      } else {
                        // 当前折叠，点击后展开
                        _collapsedChildPaths.remove(pathStr);
                      }
                    });
                  },
                  child: Padding(
                    key: elementKey, // GlobalKey 绑定在标题行
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: DictTypography.getScaledStyle(
                            DictElementType.childTitle,
                            language: _sourceLanguage,
                            fontScales: _fontScales,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0 : -0.25,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 展开的内容：多个子词条
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  firstCurve: Curves.easeInOut,
                  secondCurve: Curves.easeInOut,
                  sizeCurve: Curves.easeInOut,
                  crossFadeState: isExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: _buildChildEntryListContent(context, key, children),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建多个子词条的内容列表
  /// 每个子词条之间用分隔线隔开
  Widget _buildChildEntryListContent(
    BuildContext context,
    String key,
    List<dynamic> children,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];

    for (int i = 0; i < children.length; i++) {
      final childData = children[i];
      if (childData is! Map<String, dynamic>) continue;

      final pathStr = '$key.$i';
      final headword = childData['headword'] as String? ?? '';
      final headline = childData['headline'] as String?;
      final displayText = headword.isNotEmpty ? headword : (headline ?? '');
      final pos = childData['pos'];
      final posList = _parsePosToList(pos);
      final pronunciations = _parsePronunciationsFromData(childData['pronunciation']);

      // 从 childData 创建 DictionaryEntry 用于复用渲染方法
      final childEntry = DictionaryEntry.fromJson({
        ...childData,
        'id': '${_localEntry.id}_child_$i',
        'dict_id': _localEntry.dictId,
      });

      widgets.add(
        PathScope.append(
          context,
          key: '$i',
          child: Builder(
            builder: (context) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // headword + pos + pronunciation 同一行 - GlobalKey 绑定在 headword 行
                  if (displayText.isNotEmpty)
                    Padding(
                      key: _getElementKey(pathStr), // GlobalKey 绑定在 headword 行
                      padding: EdgeInsets.zero,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          PathScope.append(
                            context,
                            key: 'headword',
                            child: Builder(
                              builder: (context) {
                                return _buildHeadwordWithContextMenu(
                                  context: context,
                                  text: displayText,
                                  elementType: DictElementType.childHeadword,
                                  colorScheme: colorScheme,
                                  pathKey: 'headword',
                                  label: 'Headword',
                                );
                              },
                            ),
                          ),
                          if (posList.isNotEmpty) _buildChildPosPlainText(context, posList),
                          if (pronunciations.isNotEmpty)
                            _buildChildPronunciationsInline(context, pronunciations),
                        ],
                      ),
                    ),
                  // 复用现有渲染方法
                  if (childEntry.sense.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSenses(context, childEntry),
                  ],
                  if (childEntry.senseGroup.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSenseGroups(context, childEntry),
                  ],
                  if (childEntry.phrase.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildPhrases(context, childEntry),
                  ],
                  if (childData['data'] != null) ...[
                    const SizedBox(height: 12),
                    PathScope.append(
                      context,
                      key: 'data',
                      child: Builder(
                        builder: (context) {
                          return renderJsonElement(context, 'data', childData['data'], pathStr.split('.')..add('data'));
                        },
                      ),
                    ),
                  ],
                  if (childData['note'] != null) ...[
                    const SizedBox(height: 8),
                    PathScope.append(
                      context,
                      key: 'note',
                      child: Builder(
                        builder: (context) {
                          return renderJsonElement(context, 'note', childData['note'], pathStr.split('.')..add('note'));
                        },
                      ),
                    ),
                  ],
                  if (childData['clob'] != null) ...[
                    const SizedBox(height: 8),
                    PathScope.append(
                      context,
                      key: 'clob',
                      child: Builder(
                        builder: (context) {
                          return renderJsonElement(context, 'clob', childData['clob'], pathStr.split('.')..add('clob'));
                        },
                      ),
                    ),
                  ],
                  if (childData['text'] != null) ...[
                    const SizedBox(height: 8),
                    PathScope.append(
                      context,
                      key: 'text',
                      child: Builder(
                        builder: (context) {
                          return renderJsonElement(context, 'text', childData['text'], pathStr.split('.')..add('text'));
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );

    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// 构建子词条内容
  /// headword + pos + pronunciation 在同一行，然后是 sense 等其他内容
  /// 复用现有渲染方法，通过传递 DictionaryEntry 参数
  Widget _buildChildEntryContent(
    BuildContext context,
    Map<String, dynamic> childData,
    String pathStr,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final pathList = pathStr.split('.');

    // 提取字段用于 headword 行
    final headword = childData['headword'] as String? ?? '';
    final headline = childData['headline'] as String?;
    final displayText = headword.isNotEmpty ? headword : (headline ?? '');
    final pos = childData['pos'];
    final posList = _parsePosToList(pos);
    final pronunciations = _parsePronunciationsFromData(childData['pronunciation']);

    // 从 childData 创建 DictionaryEntry 用于复用渲染方法
    final childEntry = DictionaryEntry.fromJson({
      ...childData,
      'id': '${_localEntry.id}_child',
      'dict_id': _localEntry.dictId,
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // headword + pos + pronunciation 同一行（与根节点布局不同）
        if (displayText.isNotEmpty)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              // 子词条 headword（小字号衬线体）
              PathScope.append(
                context,
                key: 'headword',
                child: Builder(
                  builder: (context) {
                    return _buildHeadwordWithContextMenu(
                      context: context,
                      text: displayText,
                      elementType: DictElementType.childHeadword,
                      colorScheme: colorScheme,
                      pathKey: 'headword',
                      label: 'Headword',
                    );
                  },
                ),
              ),
              // pos 纯文本显示（无背景边框）
              if (posList.isNotEmpty) _buildChildPosPlainText(context, posList),
              if (pronunciations.isNotEmpty)
                _buildChildPronunciationsInline(context, pronunciations),
            ],
          ),
        // 复用现有渲染方法
        if (childEntry.sense.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSenses(context, childEntry),
        ],
        if (childEntry.senseGroup.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSenseGroups(context, childEntry),
        ],
        if (childEntry.phrase.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildPhrases(context, childEntry),
        ],
        if (childData['data'] != null) ...[
          const SizedBox(height: 12),
          PathScope.append(
            context,
            key: 'data',
            child: Builder(
              builder: (context) {
                return renderJsonElement(context, 'data', childData['data'], [...pathList, 'data']);
              },
            ),
          ),
        ],
        if (childData['note'] != null) ...[
          const SizedBox(height: 8),
          PathScope.append(
            context,
            key: 'note',
            child: Builder(
              builder: (context) {
                return renderJsonElement(context, 'note', childData['note'], [...pathList, 'note']);
              },
            ),
          ),
        ],
        if (childData['clob'] != null) ...[
          const SizedBox(height: 8),
          PathScope.append(
            context,
            key: 'clob',
            child: Builder(
              builder: (context) {
                return renderJsonElement(context, 'clob', childData['clob'], [...pathList, 'clob']);
              },
            ),
          ),
        ],
        if (childData['text'] != null) ...[
          const SizedBox(height: 8),
          PathScope.append(
            context,
            key: 'text',
            child: Builder(
              builder: (context) {
                return renderJsonElement(context, 'text', childData['text'], [...pathList, 'text']);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// 解析 pos 字段为 List<String>
  List<String> _parsePosToList(dynamic pos) {
    if (pos == null) return [];
    if (pos is String) return pos.isNotEmpty ? [pos] : [];
    if (pos is List) return pos.cast<String>();
    return [];
  }

  /// 从 pronunciation 数据解析发音列表
  List<Map<String, dynamic>> _parsePronunciationsFromData(dynamic pronunciation) {
    if (pronunciation == null) return [];
    if (pronunciation is Map<String, dynamic>) {
      return [pronunciation];
    }
    if (pronunciation is List) {
      return pronunciation.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// 构建子词条的 pos 纯文本显示（无背景边框）
  Widget _buildChildPosPlainText(BuildContext context, List<String> posList) {
    final colorScheme = Theme.of(context).colorScheme;
    final posText = posList.join(' ');

    return Text(
      posText,
      style: DictTypography.getScaledStyle(
        DictElementType.childPos,
        language: _sourceLanguage,
        fontScales: _fontScales,
        color: colorScheme.primary.withValues(alpha: 0.8),
      ),
    );
  }

  /// 构建子词条的内联发音显示（简化版，用于同行显示）
  Widget _buildChildPronunciationsInline(
    BuildContext context,
    List<Map<String, dynamic>> pronunciations,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: pronunciations.map((pron) {
        final region = pron['region'] as String? ?? '';
        final notation = pron['notation'] as String? ?? '';
        final audioFile = pron['audio_file'] as String? ?? '';

        if (notation.isEmpty && audioFile.isEmpty) {
          return const SizedBox.shrink();
        }

        return _buildPronunciationItem(
          context,
          region,
          notation,
          audioFile,
          '', // note 不在行内显示
          _localEntry.dictId,
        );
      }).toList(),
    );
  }

  /// 渲染所有未单独渲染的 key 为 board
  Widget _buildRemainingBoards(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    final widgets = <Widget>[];

    for (final entry in entryJson.entries) {
      final key = entry.key;
      final value = entry.value;

      // 跳过已单独渲染的 key
      if (_renderedKeys.contains(key)) continue;

      // 跳过 null 值
      if (value == null) continue;

      // 跳过空列表
      if (value is List && value.isEmpty) continue;

      final path = [key];

      Widget boardWidget;
      // 处理 child_xxxx 字段（支持 Map 和 List<Map> 两种格式）
      if (_isChildKey(key)) {
        if (value is Map<String, dynamic>) {
          // 单个子词条（Map 格式）
          boardWidget = _buildChildEntrySingle(context, key, value, path);
          widgets.add(boardWidget);
          continue;
        } else if (value is List<dynamic> && value.isNotEmpty) {
          // 多个子词条（List 格式）：一个标题，下面多个子词条
          boardWidget = _buildChildEntryList(context, key, value, path);
          widgets.add(boardWidget);
          continue;
        }
      }

      // 获取 board 的 GlobalKey 用于滚动定位
      final boardKey = _getElementKey(key);

      if (predefinedRenderers.containsKey(key)) {
        // 预定义渲染器优先
        boardWidget = renderJsonElement(context, key, value, path);
      } else if (value is Map<String, dynamic>) {
        final title = value['title'] as String? ?? key;
        final display = value['display'] as String? ?? '00';
        final boardData = {...value, 'title': title, 'display': display};

        boardWidget = BoardWidget(
          board: boardData,
          contentBuilder: (board, path) =>
              _buildBoardContent(context, board, path),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      } else if (value is List<dynamic>) {
        boardWidget = renderJsonElement(context, key, value, path);
      } else {
        // 其他类型（字符串、数字等）也包装为 board
        final boardData = {'title': key, 'text': value.toString()};
        boardWidget = BoardWidget(
          board: boardData,
          contentBuilder: (board, path) =>
              _buildBoardContent(context, board, path),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      }

      // 使用 Container 包装并绑定 GlobalKey 用于滚动定位
      widgets.add(Container(key: boardKey, child: boardWidget));
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SizedBox(height: 12), ...widgets],
    );
  }

  Widget _buildBoardContent(
    BuildContext context,
    Map<String, dynamic> board,
    List<String> path,
  ) {
    final keys = board.keys
        .where((k) => k != 'title' && k != 'display')
        .toList();

    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }

    // sense 最先渲染，data 最后渲染
    final hasData = keys.contains('data');
    final senseKeys = keys.where((k) => k == 'sense').toList();
    final normalKeys = keys.where((k) => k != 'data' && k != 'sense').toList();
    final dataValue = hasData ? board['data'] : null;

    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<String>(
      selector: (hiddenLanguages) {
        final relevantHidden = <String>[];
        for (final key in [...senseKeys, ...normalKeys]) {
          final isLanguageCode =
              LanguageUtils.getLanguageDisplayName(key) != key.toUpperCase();
          if (isLanguageCode) {
            final pathStr = [...path, key].join('.');
            if (hiddenLanguages.contains(pathStr)) {
              relevantHidden.add(pathStr);
            }
          }
        }
        relevantHidden.sort();
        return relevantHidden.join(',');
      },
      builder: (context, hiddenPathsStr, child) {
        // Logger.d(
        //   '重建 BoardContent: path=${path.join('.')}, keys=$keys, hiddenPaths=$hiddenPathsStr',
        //   tag: 'Rebuild',
        // );
        final widgets = <Widget>[];
        final hiddenLanguages = _hiddenLanguagesNotifier.value;

        void renderKey(String key) {
          final value = board[key];
          final keyPath = [...path, key];

          // 检查是否是语言代码且被隐藏
          final isLanguageCode =
              LanguageUtils.getLanguageDisplayName(key) != key.toUpperCase();
          if (isLanguageCode) {
            final hiddenPath = keyPath.join('.');
            if (hiddenLanguages.contains(hiddenPath)) {
              return;
            }
          }

          // 预定义渲染器优先（sense、example、note 等）
          if (predefinedRenderers.containsKey(key)) {
            widgets.add(renderJsonElement(context, key, value, keyPath));
          } else if (value is Map<String, dynamic>) {
            widgets.add(
              BoardWidget(
                board: {'title': key, ...value},
                contentBuilder: (board, path) =>
                    _buildBoardContent(context, board, path),
                path: keyPath,
                fontScales: _fontScales,
                sourceLanguage: _sourceLanguage,
                forceNested: true,
              ),
            );
          } else if (value is List<dynamic>) {
            widgets.add(
              renderJsonElement(
                context,
                key,
                value,
                keyPath,
                forceNested: true,
              ),
            );
          } else {
            final text = value is String ? value : (value?.toString() ?? '');
            if (isLanguageCode) {
              widgets.add(_buildPlainTextItem(context, text, keyPath));
            } else {
              widgets.add(_buildContentItem(context, text, keyPath));
            }
          }
        }

        // sense 最先渲染
        for (final key in senseKeys) {
          renderKey(key);
        }
        for (final key in normalKeys) {
          renderKey(key);
        }

        // 在最后渲染 data（如果存在）
        if (dataValue is Map<String, dynamic> && dataValue.isNotEmpty) {
          widgets.add(_buildData(context, dataValue, path: [...path, 'data']));
        }

        if (widgets.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }

  Widget _buildContentItem(
    BuildContext context,
    String text,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = DictTypography.getBaseStyle(
      DictElementType.boardContent,
      color: colorScheme.onSurfaceVariant,
    );

    final textKey = GlobalKey();

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(path, 'Content Item'),
      text: text,
      textStyle: textStyle,
      customTextKey: textKey,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.75),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDoubleTapText(
                context: context,
                text: text,
                style: textStyle,
                textKey: textKey,
                path: path,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlainTextItem(
    BuildContext context,
    String text,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    // plain text item 等价于 boardContent
    final textStyle = DictTypography.getBaseStyle(
      DictElementType.boardContent,
      color: colorScheme.onSurfaceVariant,
    );

    final textKey = GlobalKey();
    final hiddenPath = path.join('.');

    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<bool>(
      selector: (hiddenLanguages) => hiddenLanguages.contains(hiddenPath),
      builder: (context, hidden, child) {
        // Logger.d(
        //   '重建 PlainTextItem: path=${path.join('.')}, hidden=$hidden',
        //   tag: 'Rebuild',
        // );
        return _buildTappableWidget(
          context: context,
          pathData: _PathData(path, 'Plain Text Item'),
          text: text,
          textStyle: textStyle,
          customTextKey: textKey,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildDoubleTapText(
              context: context,
              text: text,
              style: textStyle,
              textKey: textKey,
              hidden: hidden,
              path: path,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoubleTapText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    GlobalKey? textKey,
    bool hidden = false,
    List<String>? path,
  }) {
    final result = _parseFormattedText(
      text,
      style,
      context: context,
      hidden: hidden,
    );

    // 如果没有 path，使用简单的 Text.rich
    if (path == null) {
      if (textKey != null) {
        return Text.rich(TextSpan(children: result.spans), key: textKey);
      }
      return Text.rich(TextSpan(children: result.spans));
    }

    final pathData = _PathData(path, 'Board Text');

    // 创建手势识别器以支持点击和右键菜单
    final tapRecognizer = TapGestureRecognizer()
      ..onTapDown = (details) {
        _lastTapPosition = details.globalPosition;
        _currentSelectionPathData = pathData;
      }
      ..onTap = () {
        // 单击立即生效
        _handleElementTap(_convertPathToString(path), pathData.label);

        // 检测双击
        final now = DateTime.now();
        final isDoubleTap =
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
            _lastTapButton == 0;

        if (isDoubleTap && _lastTapPosition != null && textKey != null) {
          _handleDoubleTapOnText(
            _lastTapPosition!,
            text,
            style,
            textKey,
            context,
          );
          _lastTapTime = null;
          _lastTapButton = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapButton = 0;
        }
      };

    // 恢复 SecondaryTapGestureRecognizer 用于电脑端右键菜单
    final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
      ..onSecondaryTapUp = (details) {
        Logger.d(
          'Board text secondary tap: path=${_convertPathToString(path)}',
          tag: 'DoubleTapWord',
        );
        _lastTapPosition = details.globalPosition;
        _handleElementSecondaryTap(
          _convertPathToString(path),
          pathData.label,
          context,
          details.globalPosition,
        );
      };

    _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

    // 使用 MultiGestureRecognizer 支持点击和右键
    final recognizer = _MultiGestureRecognizer(
      tapRecognizer: tapRecognizer,
      secondaryTapRecognizer: secondaryTapRecognizer,
      longPressRecognizer: null,
      doubleTapRecognizer: null,
    );

    // 重新解析文本，添加手势识别器
    final resultWithRecognizer = _parseFormattedText(
      text,
      style,
      context: context,
      hidden: hidden,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.text,
    );

    if (textKey != null) {
      return Text.rich(
        TextSpan(children: resultWithRecognizer.spans),
        key: textKey,
      );
    }
    return Text.rich(TextSpan(children: resultWithRecognizer.spans));
  }

  Player? _currentPlayer;
  StreamSubscription<bool>? _playbackCompletionSub;

  /// 检查是否为 opus 格式音频
  bool _isOpusFormat(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ext == 'opus' || ext == 'ogg';
  }

  /// 检查当前平台是否为 Apple 平台（iOS/macOS）
  bool get _isApplePlatform {
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (e) {
      // 如果在不支持的平台（如 Web）上，返回 false
      return false;
    }
  }

  void _playAudio(String dictionaryId, String audioFileName) async {
    if (dictionaryId.isEmpty || audioFileName.isEmpty) return;

    unawaited(_playAudioInternal(dictionaryId, audioFileName));
  }

  Future<void> _playAudioInternal(
    String dictionaryId,
    String audioFileName,
  ) async {
    if (dictionaryId.isEmpty || audioFileName.isEmpty) return;

    Player? player;

    try {
      final dictManager = DictionaryManager();

      String? audioSource;
      bool isLocal = false;

      // 优先从 media.db 读取音频
      final audioBytes = await dictManager.getAudioBytes(
        dictionaryId,
        audioFileName,
      );

      if (audioBytes != null && audioBytes.isNotEmpty) {
        final tempDir = await dictManager.getTempDirectory();
        final tempFile = File(path.join(tempDir, audioFileName));
        await tempFile.writeAsBytes(audioBytes);
        audioSource = tempFile.path;
        isLocal = true;
        Logger.d('从media.db读取本地音频成功: $audioSource', tag: '_playAudio');
      } else {
        // 没有本地音频，使用在线音频
        final domain = await dictManager.onlineSubscriptionUrl;
        if (domain.isEmpty) {
          Logger.e('无法获取订阅网站地址', tag: '_playAudio');
          return;
        }

        final cleanDomain = domain.trim().replaceAll(RegExp(r'/$'), '');
        audioSource =
            '$cleanDomain/audio/$dictionaryId/${Uri.encodeComponent(audioFileName)}';
        isLocal = false;
        Logger.d('使用在线音频: $audioSource', tag: '_playAudio');
      }

      // 取消之前的完成监听，但不停止播放
      // 让 open() 自动处理切换，避免 stop() 导致的音频管道重置
      _playbackCompletionSub?.cancel();
      _playbackCompletionSub = null;

      // 复用现有 player 或创建新实例
      if (_currentPlayer != null) {
        player = _currentPlayer!;
        Logger.d('复用现有播放器', tag: '_playAudio');
      } else {
        player = Player();
        _currentPlayer = player;
        // 注册到管理器以便热重启时清理
        MediaKitManager().registerPlayer(player);
        Logger.d('创建新播放器', tag: '_playAudio');
      }

      Logger.d('播放音频: ${isLocal ? "本地" : "在线"}', tag: '_playAudio');
      // 直接打开并播放，避免 open 和 play 之间的间隙导致 Android 抖动
      // 使用 play: true 让播放器内部处理缓冲和播放的衔接
      await player.open(Media(audioSource), play: true);

      // 保存临时文件路径用于播放完成后清理
      final localAudioPath = isLocal ? audioSource : null;

      // 监听播放完成，等待尾帧稳定后再清理，避免尾部被截断
      _playbackCompletionSub?.cancel();
      _playbackCompletionSub = player.stream.completed.listen((
        completed,
      ) async {
        if (!completed) return;

        await Future.delayed(const Duration(milliseconds: 500));

        if (_currentPlayer == player) {
          await _cleanupPlayer();
        }

        // 播放完成1秒后清理临时音频文件
        if (localAudioPath != null) {
          unawaited(
            Future.delayed(const Duration(seconds: 1), () async {
              try {
                final tempFile = File(localAudioPath);
                if (await tempFile.exists()) {
                  await tempFile.delete();
                  Logger.d('已删除临时音频文件: $localAudioPath', tag: '_playAudio');
                }
              } catch (_) {}
            }),
          );
        }
      });

      Logger.d('音频播放已启动: $audioFileName', tag: '_playAudio');
    } catch (e, stackTrace) {
      Logger.e('播放音频失败: $e', tag: '_playAudio', error: e);
      Logger.e('堆栈跟踪: $stackTrace', tag: '_playAudio');

      await _cleanupPlayer();

      if (_isOpusFormat(audioFileName) && _isApplePlatform) {
        Logger.w('opus 格式在 iOS/macOS 上可能需要额外的配置支持', tag: '_playAudio');
      }
    }
  }

  static const Map<String, String> predefinedRenderers = {
    'headword': 'word',
    'headline': 'word', // headline 使用与 headword 相同的渲染方法
    'frequency': 'frequency',
    'pronunciation': 'pronunciation',
    'certifications': 'certification',
    'sense': 'sense',
    'example': 'example',
    'data': 'data',
    'note': 'note',
    'image': 'image',
    'clob': 'clob',
    'text': 'text',
    'table': 'table',
  };

  Widget _buildStringListAsRow(
    BuildContext context,
    List<String> strings,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 13,
      color: colorScheme.onSurface,
      letterSpacing: 0.15,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.75),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: strings.asMap().entries.map((entry) {
                final itemPath = [...path, '${entry.key}'];
                final textKey = GlobalKey();
                return _buildTappableWidget(
                  context: context,
                  pathData: _PathData(itemPath, 'Inline Item'),
                  text: entry.value,
                  textStyle: textStyle,
                  customTextKey: textKey,
                  child: _buildInlineItemText(
                    context: context,
                    text: entry.value,
                    style: textStyle,
                    path: itemPath,
                    textKey: textKey,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 渲染内联项目文本，支持右键菜单和双击查词
  Widget _buildInlineItemText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required List<String> path,
    GlobalKey? textKey,
  }) {
    final pathData = _PathData(path, 'Inline Item');
    final effectiveTextKey = textKey ?? GlobalKey();

    // 创建手势识别器以支持点击和右键菜单
    final tapRecognizer = TapGestureRecognizer()
      ..onTapDown = (details) {
        _lastTapPosition = details.globalPosition;
        _currentSelectionPathData = pathData;
      }
      ..onTap = () {
        // 单击立即生效
        _handleElementTap(_convertPathToString(path), pathData.label);

        // 检测双击
        final now = DateTime.now();
        final isDoubleTap =
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
            _lastTapButton == 0;

        if (isDoubleTap && _lastTapPosition != null) {
          Logger.d('Inline item 双击触发', tag: 'DoubleTapWord');
          _handleDoubleTapOnText(
            _lastTapPosition!,
            text,
            style,
            effectiveTextKey,
            context,
          );
          _lastTapTime = null;
          _lastTapButton = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapButton = 0;
        }
      };

    // 添加右键菜单支持
    final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
      ..onSecondaryTapUp = (details) {
        _lastTapPosition = details.globalPosition;
        _handleElementSecondaryTap(
          _convertPathToString(path),
          pathData.label,
          context,
          details.globalPosition,
        );
      };

    _recognizers.addAll([tapRecognizer, secondaryTapRecognizer]);

    // 使用 MultiGestureRecognizer 支持点击和右键
    final recognizer = _MultiGestureRecognizer(
      tapRecognizer: tapRecognizer,
      secondaryTapRecognizer: secondaryTapRecognizer,
      longPressRecognizer: null,
      doubleTapRecognizer: null,
    );

    // 解析文本，添加手势识别器
    final result = _parseFormattedText(
      text,
      style,
      context: context,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.text,
    );

    return Text.rich(TextSpan(children: result.spans), key: effectiveTextKey);
  }

  Widget renderJsonElement(
    BuildContext context,
    String key,
    dynamic value,
    List<String> path, {
    bool forceNested = false,
  }) {
    final isNumericKey = RegExp(r'^\d+$').hasMatch(key);

    // 1. 如果key不是数字，表明是一个键值对
    if (!isNumericKey) {
      // 1.1 如果key在预定义列表中
      if (predefinedRenderers.containsKey(key)) {
        // 1.1.1 如果value不是list，使用预定义方法渲染
        if (value is! List) {
          return _renderWithPredefinedMethod(context, key, value, path);
        }
        // 1.1.2 如果value是list，渲染一个widget容器，对于list的每个元素，都使用key所定义的渲染函数渲染
        if (value.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: value.asMap().entries.map((entry) {
              final itemPath = [...path, '${entry.key}'];
              return _renderWithPredefinedMethod(
                context,
                key,
                entry.value,
                itemPath,
              );
            }).toList(),
          );
        }
        return const SizedBox.shrink();
      }

      // 1.2 如果key不在预定义列表中，则渲染为一个board，标题为key
      // 1.2.1 如果value是map，则按照board里的排序，调用renderJsonElement自身渲染各个map里的key1:value1
      if (value is Map<String, dynamic>) {
        return BoardWidget(
          board: {'title': key, ...value},
          contentBuilder: (board, p) => _buildBoardContent(context, board, p),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
          forceNested: forceNested,
        );
      }

      // 1.2.2 如果value是一个list
      if (value is List) {
        if (value.isEmpty) return const SizedBox.shrink();
        // 渲染为 BoardWidget（标题为 key）
        return BoardWidget(
          board: {'title': key, 'content': value},
          contentBuilder: (board, p) {
            final content = board['content'] as List;
            // 1.2.2.1 如果value是一个list<string>，则使用_buildStringListAsRow渲染value
            if (content.every((e) => e is String)) {
              return _buildStringListAsRow(
                context,
                content.cast<String>(),
                path,
              );
            }
            // 1.2.2.2 其它情况，则迭代调用renderJsonElement自身渲染value中的每一个元素
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.asMap().entries.map((entry) {
                final itemPath = [...path, '${entry.key}'];
                return renderJsonElement(
                  context,
                  '${entry.key}',
                  entry.value,
                  itemPath,
                  forceNested: forceNested,
                );
              }).toList(),
            );
          },
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
          forceNested: forceNested,
        );
      }
    }

    // 2. 如果key是数字，表明value是list中的一个元素
    if (isNumericKey) {
      // 2.1 如果value是一个Map，迭代渲染其中的每个键值对
      if (value is Map<String, dynamic>) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.entries.map((entry) {
            final itemPath = [...path, entry.key];
            return renderJsonElement(
              context,
              entry.key,
              entry.value,
              itemPath,
              forceNested: forceNested,
            );
          }).toList(),
        );
      }
      // 2.2 如果value是一个list<string>，则使用_buildStringListAsRow渲染value
      if (value is List &&
          value.isNotEmpty &&
          value.every((e) => e is String)) {
        return _buildStringListAsRow(context, value.cast<String>(), path);
      }
      // 2.3 如果value是一个list<list>，则迭代调用renderJsonElement自身渲染value中的每一个子list
      if (value is List && value.isNotEmpty && value.every((e) => e is List)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.asMap().entries.map((entry) {
            final itemPath = [...path, '${entry.key}'];
            return renderJsonElement(
              context,
              '${entry.key}',
              entry.value,
              itemPath,
            );
          }).toList(),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _renderWithPredefinedMethod(
    BuildContext context,
    String key,
    dynamic value,
    List<String> path,
  ) {
    final renderer = predefinedRenderers[key] ?? '';

    if (value is Map<String, dynamic>) {
      return _renderMapWithPredefinedMethod(context, renderer, value, path);
    }

    if (value is List<dynamic>) {
      return renderJsonElement(context, key, value, path);
    }

    // 处理字符串类型的值（如 headline、headword）
    if (value is String) {
      return _renderStringWithPredefinedMethod(context, renderer, value, path);
    }

    return const SizedBox.shrink();
  }

  /// 渲染字符串类型的预定义元素
  Widget _renderStringWithPredefinedMethod(
    BuildContext context,
    String renderer,
    String value,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (renderer) {
      case 'word':
        // 对于字符串类型的 headline/headword，直接渲染为标题文本
        final isPhrase = _localEntry.entryType == 'phrase';
        final headwordElementType = isPhrase
            ? DictElementType.headwordPhrase
            : DictElementType.headword;

        return PathScope(
          path: path,
          child: Builder(
            builder: (context) {
              return _buildHeadwordWithContextMenu(
                context: context,
                text: value,
                elementType: headwordElementType,
                colorScheme: colorScheme,
                pathKey: path.last,
                label: path.last == 'headline' ? 'Headline' : 'Headword',
              );
            },
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _renderMapWithPredefinedMethod(
    BuildContext context,
    String renderer,
    Map<String, dynamic> value,
    List<String> path,
  ) {
    switch (renderer) {
      case 'word':
        return _buildWord(context);
      case 'frequency':
        return _buildFrequencyStars(context);
      case 'example':
        return _buildExample(context, value, path: path);
      case 'data':
        return _buildData(context, value, path: path);
      case 'sense':
        final indexValue = value['index'];
        final indexStr = indexValue is int
            ? '$indexValue'
            : (indexValue as String? ?? '');
        return PathScope(
          path: path,
          child: Builder(
            builder: (ctx) => _buildSenseWidget(ctx, value, indexStr),
          ),
        );
      case 'note':
        final noteMap = <String, String>{};
        for (final entry in value.entries) {
          if (entry.value is String && (entry.value as String).isNotEmpty) {
            noteMap[entry.key] = entry.value as String;
          }
        }
        if (noteMap.isEmpty) return const SizedBox.shrink();
        return _buildnote(context, noteMap, path: path);
      case 'image':
        final imageFile = value['image_file'] as String?;
        if (imageFile == null || imageFile.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildImageElement(
          context,
          value,
          _localEntry.dictId,
          path.join('.'),
          imageFile,
        );
      case 'clob':
        return _buildClobContent(context, value, path);
      case 'text':
        return _buildTextContent(context, value, path);
      case 'table':
        return _buildTable(context, value, path);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildImageElement(
    BuildContext context,
    Map<String, dynamic> imageData,
    String? dictId,
    String path,
    String imageFile,
  ) {
    if (imageFile.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSvg = imageFile.toLowerCase().endsWith('.svg');

    final cacheKey = '${dictId}_$imageFile';

    return _LazyImageLoader(
      key: ValueKey(cacheKey),
      dictId: dictId,
      imageFile: imageFile,
      isSvg: isSvg,
      onImageLoaded: (bytes) =>
          _buildImageWidget(context, bytes, isSvg, imageFile),
    );
  }

  // 缩略图尺寸常量
  // 图片尺寸缓存
  static final Map<String, Size> _dimensionCache = {};

  // 获取图片真实尺寸
  static Future<Size?> _getImageDimensions(
    Uint8List bytes,
    String cacheKey,
  ) async {
    if (_dimensionCache.containsKey(cacheKey)) {
      return _dimensionCache[cacheKey];
    }
    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      _dimensionCache[cacheKey] = size;
      return size;
    } catch (e) {
      return null;
    }
  }

  String _cleanSvgString(String svgString) {
    return svgString;
  }

  Uint8List? _extractBase64Image(String svgString) {
    try {
      final base64Pattern = RegExp(
        r'data:image/([a-zA-Z]+);base64,([A-Za-z0-9+/=\s]+)',
        dotAll: true,
      );
      final match = base64Pattern.firstMatch(svgString);

      if (match != null && match.groupCount >= 2) {
        final base64Data = match.group(2)!.replaceAll(RegExp(r'\s'), '');
        final imageBytes = base64Decode(base64Data);
        return imageBytes;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Widget _buildImageWidget(
    BuildContext context,
    Uint8List imageBytes,
    bool isSvg,
    String imageFile,
  ) {
    // 使用 MediaQuery 获取窗口宽度，确保响应式调整
    final windowWidth = MediaQuery.of(context).size.width;
    final thumbnailHeight = responsiveValue(
      screenWidth: windowWidth,
      minWidth: 400,
      maxWidth: 900,
      minValue: 100,
      maxValue: 175,
    );

    if (isSvg) {
      final svgString = String.fromCharCodes(imageBytes);
      final cleanedSvg = _cleanSvgString(svgString);
      final cleanedBytes = Uint8List.fromList(cleanedSvg.codeUnits);

      final base64Image = _extractBase64Image(cleanedSvg);
      if (base64Image != null) {
        // SVG 内嵌 base64 图片，获取真实尺寸按比例显示
        return _buildResponsiveImageThumbnail(
          context: context,
          imageBytes: base64Image,
          thumbnailHeight: thumbnailHeight,
          onTap: () =>
              _showImageDialog(context, imageFile, cleanedBytes, isSvg),
        );
      }

      // 纯 SVG，保持正方形
      return GestureDetector(
        onTap: () => _showImageDialog(context, imageFile, cleanedBytes, isSvg),
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SizedBox(
            width: thumbnailHeight,
            height: thumbnailHeight,
            child: SvgPicture.string(
              cleanedSvg,
              fit: BoxFit.contain,
              allowDrawingOutsideViewBox: true,
              clipBehavior: Clip.none,
              placeholderBuilder: (context) {
                return Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // 普通图片，按真实比例显示
    return _buildResponsiveImageThumbnail(
      context: context,
      imageBytes: imageBytes,
      thumbnailHeight: thumbnailHeight,
      onTap: () => _showImageDialog(context, imageFile, imageBytes, isSvg),
    );
  }

  // 构建响应式图片缩略图，根据真实比例显示
  Widget _buildResponsiveImageThumbnail({
    required BuildContext context,
    required Uint8List imageBytes,
    required double thumbnailHeight,
    required VoidCallback onTap,
  }) {
    final cacheKey = imageBytes.hashCode.toString();

    return FutureBuilder<Size?>(
      future: _getImageDimensions(imageBytes, cacheKey),
      builder: (context, snapshot) {
        double displayWidth = thumbnailHeight;
        double displayHeight = thumbnailHeight;

        if (snapshot.hasData && snapshot.data != null) {
          final imageSize = snapshot.data!;
          final aspectRatio = imageSize.width / imageSize.height;
          // 以高度为基准，根据宽高比计算宽度
          displayWidth = thumbnailHeight * aspectRatio;
          displayHeight = thumbnailHeight;
        }

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                imageBytes,
                width: displayWidth,
                height: displayHeight,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.broken_image,
                    color: Theme.of(context).colorScheme.outline,
                    size: 24,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _showImageDialog(
    BuildContext context,
    String fileName,
    Uint8List? imageBytes,
    bool isSvg,
  ) {
    if (imageBytes == null) {
      showToast(context, context.t.entry.imageLoadFailed);
      return;
    }

    String? displaySvg;
    Uint8List? displayImageBytes;
    if (isSvg) {
      final svgString = String.fromCharCodes(imageBytes);
      displaySvg = _cleanSvgString(svgString);
      displayImageBytes = _extractBase64Image(displaySvg);
    }

    showDialog(
      context: context,
      builder: (context) {
        return _ImageViewerDialog(
          imageBytes: displayImageBytes ?? imageBytes,
          svgString: displayImageBytes != null ? null : displaySvg,
        );
      },
    );
  }
}

/// 图片查看器对话框
class _ImageViewerDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String? svgString;

  const _ImageViewerDialog({
    required this.imageBytes,
    this.svgString,
  });

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  final TransformationController _transformController =
      TransformationController();
  Size? _imageSize;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImageDimensions();
  }

  Future<void> _loadImageDimensions() async {
    try {
      final codec = await instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        _isLoading = false;
      });
      image.dispose();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = 32.0;
    final availableSize = Size(
      screenSize.width - padding * 2,
      screenSize.height - padding * 2,
    );

    // 计算图片初始显示尺寸：保持比例，尽可能占满宽度或高度
    double? displayWidth;
    double? displayHeight;
    if (_imageSize != null) {
      final aspectRatio = _imageSize!.width / _imageSize!.height;
      final screenAspectRatio = availableSize.width / availableSize.height;

      if (aspectRatio > screenAspectRatio) {
        // 图片更宽，以宽度为准
        displayWidth = availableSize.width;
        displayHeight = displayWidth / aspectRatio;
      } else {
        // 图片更高，以高度为准
        displayHeight = availableSize.height;
        displayWidth = displayHeight * aspectRatio;
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: _isLoading
              ? CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                )
              : InteractiveViewer(
                  transformationController: _transformController,
                  maxScale: 5.0,
                  minScale: 0.5,
                  constrained: true,
                  clipBehavior: Clip.none,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: widget.svgString != null
                      ? SvgPicture.string(
                          widget.svgString!,
                          width: displayWidth,
                          height: displayHeight,
                          fit: BoxFit.contain,
                          allowDrawingOutsideViewBox: true,
                          clipBehavior: Clip.none,
                        )
                      : Image.memory(
                          widget.imageBytes,
                          width: displayWidth,
                          height: displayHeight,
                          fit: BoxFit.contain,
                        ),
                ),
        ),
      ),
    );
  }
}

// 懒加载图片组件，等其他元素渲染完后再加载图片
class _LazyImageLoader extends StatefulWidget {
  final String? dictId;
  final String imageFile;
  final bool isSvg;
  final Widget Function(Uint8List bytes) onImageLoaded;

  const _LazyImageLoader({
    super.key,
    required this.dictId,
    required this.imageFile,
    required this.isSvg,
    required this.onImageLoaded,
  });

  @override
  State<_LazyImageLoader> createState() => _LazyImageLoaderState();
}

class _LazyImageLoaderState extends State<_LazyImageLoader>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, Uint8List> _imageCache = {};
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasTriedLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  void _loadImageIfNeeded() {
    final cacheKey = '${widget.dictId}_${widget.imageFile}';
    if (_imageCache.containsKey(cacheKey)) {
      // 缓存命中：同步赋值，不触发 setState（initState 阶段直接赋值即可）
      _imageBytes = _imageCache[cacheKey];
      _hasTriedLoading = true;
    } else if (!_hasTriedLoading && !_isLoading) {
      _hasTriedLoading = true;
      // 直接发起异步加载，不推迟到下一帧，避免先渲染无图占位符再重绘
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(_LazyImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageFile != oldWidget.imageFile ||
        widget.dictId != oldWidget.dictId) {
      _hasTriedLoading = false;
      _loadImageIfNeeded();
    }
  }

  Future<void> _loadImage() async {
    if (_isLoading || _imageBytes != null) return;

    final cacheKey = '${widget.dictId}_${widget.imageFile}';
    _isLoading = true;

    try {
      Uint8List? bytes;

      if (_imageCache.containsKey(cacheKey)) {
        bytes = _imageCache[cacheKey];
      } else {
        if (widget.dictId != null && widget.dictId!.isNotEmpty) {
          // 优先从本地 media.db 读取图片
          bytes = await DictionaryManager().getImageBytes(
            widget.dictId!,
            widget.imageFile,
          );

          // 如果本地没有，尝试从在线服务器获取
          if (bytes == null || bytes.isEmpty) {
            final domain = await DictionaryManager().onlineSubscriptionUrl;
            if (domain.isNotEmpty) {
              final cleanDomain = domain.trim().replaceAll(RegExp(r'/$'), '');
              final imageUrl =
                  '$cleanDomain/image/${widget.dictId}/${Uri.encodeComponent(widget.imageFile)}';
              try {
                final response = await http.get(Uri.parse(imageUrl));
                if (response.statusCode == 200 &&
                    response.bodyBytes.isNotEmpty) {
                  bytes = response.bodyBytes;
                }
              } catch (e) {
                // 在线获取失败，忽略
              }
            }
          }

          if (bytes != null && bytes.isNotEmpty) {
            _imageCache[cacheKey] = bytes;
          }
        }
      }

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_imageBytes != null) {
      return widget.onImageLoaded(_imageBytes!);
    }

    // 加载中或等待加载，返回透明占位符
    return const SizedBox(width: 48, height: 48);
  }
}

class _DataTabWidget extends StatefulWidget {
  final List<String> keys;
  final Map<String, dynamic> value;
  final List<String> path;
  final ColorScheme colorScheme;
  final Widget Function(Map<String, dynamic> board, List<String> path)
  contentBuilder;
  final void Function(String path, String label)? onElementTap;
  final void Function(
    String path,
    String label,
    BuildContext context,
    Offset position,
  )?
  onElementSecondaryTap;
  final String? sourceLanguage;
  final Map<String, Map<String, double>> fontScales;

  const _DataTabWidget({
    required this.keys,
    required this.value,
    required this.path,
    required this.colorScheme,
    required this.contentBuilder,
    this.onElementTap,
    this.onElementSecondaryTap,
    this.sourceLanguage,
    required this.fontScales,
  });

  @override
  State<_DataTabWidget> createState() => _DataTabWidgetState();
}

/// 右上角切角裁剪器
class _ChamferCornerClipper extends CustomClipper<Path> {
  final double cutWidth; // 上面切的宽度
  final double cutHeight; // 右边切的高度

  _ChamferCornerClipper({required this.cutWidth, required this.cutHeight});

  @override
  Path getClip(Size size) {
    final path = Path();
    // 从左上角开始
    path.moveTo(0, 0);
    // 左边
    path.lineTo(0, size.height);
    // 底边
    path.lineTo(size.width, size.height);
    // 右边（到底部）
    path.lineTo(size.width, cutHeight);
    // 右上角切角
    path.lineTo(size.width - cutWidth, 0);
    // 顶部
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_ChamferCornerClipper oldClipper) {
    return cutWidth != oldClipper.cutWidth || cutHeight != oldClipper.cutHeight;
  }
}

class _DataTabWidgetState extends State<_DataTabWidget> {
  int? _selectedIndex;

  void _selectTab(int? index, String key) {
    setState(() {
      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else {
        _selectedIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.keys.asMap().entries.map((entry) {
            final index = entry.key;
            final key = entry.value;
            final isSelected = _selectedIndex == index;

            // 展开状态：圆角矩形，内边框较窄
            // 未展开状态：右上角切角效果 + 外边框
            final borderRadius = isSelected
                ? BorderRadius.circular(4)
                : const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                    topRight: Radius.circular(0),
                  );

            // 统一使用前景装饰绘制边框，确保展开/折叠状态容器尺寸一致
            // 两种状态都使用 foregroundDecoration 绘制边框，避免边框宽度影响容器尺寸
            Widget tabContent = Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? widget.colorScheme.primaryContainer
                    : widget.colorScheme.surfaceContainerHighest,
                borderRadius: borderRadius,
              ),
              // 统一使用前景装饰绘制边框，不改变容器尺寸
              foregroundDecoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: isSelected
                      ? widget.colorScheme.primary.withValues(alpha: 0.6)
                      : widget.colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                  width: isSelected ? 0.7 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: parseFormattedText(
                        key,
                        DictTypography.getBaseStyle(
                          DictElementType.dataTabLabel,
                          color: isSelected
                              ? widget.colorScheme.onPrimaryContainer
                              : widget.colorScheme.onSurface,
                          // 统一字体粗细，确保展开/折叠状态容器宽度一致
                          fontWeightOverride: FontWeight.w600,
                        ),
                        context: context,
                        sourceLanguage: widget.sourceLanguage,
                        fontScales: widget.fontScales,
                        elementType: DictElementType.dataTabLabel,
                      ).spans,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_up,
                      size: 14,
                      color: widget.colorScheme.onPrimaryContainer,
                    ),
                  ] else ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: widget.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            );

            // 未展开状态使用 ClipPath 实现右上角切角效果
            Widget finalTabContent = isSelected
                ? tabContent
                : ClipPath(
                    clipper: _ChamferCornerClipper(cutWidth: 11, cutHeight: 8),
                    child: tabContent,
                  );

            return GestureDetector(
              onSecondaryTapUp: (details) {
                final tabPath = [...widget.path, key];
                if (widget.onElementSecondaryTap != null) {
                  widget.onElementSecondaryTap!(
                    tabPath.join('.'),
                    'Data Tab',
                    context,
                    details.globalPosition,
                  );
                }
              },
              child: InkWell(
                onTap: () => _selectTab(index, key),
                borderRadius: borderRadius,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: finalTabContent,
              ),
            );
          }).toList(),
        ),
        // 使用 AnimatedSize 实现展开/收起动画
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _selectedIndex != null
              ? Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Builder(
                    key: ValueKey(_selectedIndex),
                    builder: (context) {
                      final selectedKey = widget.keys[_selectedIndex!];
                      final selectedValue = widget.value[selectedKey];

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        child: selectedValue is Map<String, dynamic>
                            ? widget.contentBuilder(selectedValue, [
                                ...widget.path,
                                selectedKey,
                              ])
                            : selectedValue is List<dynamic>
                            ? widget.contentBuilder(
                                {selectedKey: selectedValue},
                                [...widget.path, selectedKey],
                              )
                            : Text(
                                selectedValue?.toString() ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: widget.colorScheme.onSurfaceVariant,
                                ),
                              ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 用于定位选择上下文菜单的布局委托
class _SelectionContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final double dx;
  final double dy;

  _SelectionContextMenuLayoutDelegate({required this.dx, required this.dy});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // 菜单宽度固定为 200
    return BoxConstraints.tightFor(width: 200.0);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 返回计算好的位置
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_SelectionContextMenuLayoutDelegate oldDelegate) {
    return dx != oldDelegate.dx || dy != oldDelegate.dy;
  }
}

/// 选择菜单关闭遮罩层组件
/// 使用全局事件监听，不干扰任何 widget 的事件处理
/// 这样滚动和光标拖动可以正常工作
class _SelectionDismissOverlay extends StatefulWidget {
  final Rect menuRect;
  final VoidCallback onDismiss;

  const _SelectionDismissOverlay({
    required this.menuRect,
    required this.onDismiss,
  });

  @override
  State<_SelectionDismissOverlay> createState() =>
      _SelectionDismissOverlayState();
}

class _SelectionDismissOverlayState extends State<_SelectionDismissOverlay> {
  Offset? _tapDownPosition;
  bool _isDragging = false;
  static const double _dragThreshold = 20.0;
  int? _trackedPointer;
  PointerRoute? _globalRoute;

  @override
  void initState() {
    super.initState();
    _registerGlobalRoute();
  }

  @override
  void dispose() {
    _unregisterGlobalRoute();
    super.dispose();
  }

  void _registerGlobalRoute() {
    _globalRoute = (PointerEvent event) {
      if (!mounted) return;

      if (event is PointerDownEvent) {
        _tapDownPosition = event.position;
        _isDragging = false;
        _trackedPointer = event.pointer;
      } else if (event is PointerMoveEvent) {
        if (_trackedPointer == event.pointer && _tapDownPosition != null) {
          final distance = (event.position - _tapDownPosition!).distance;
          if (distance > _dragThreshold) {
            _isDragging = true;
          }
        }
      } else if (event is PointerUpEvent) {
        if (_trackedPointer == event.pointer) {
          // 只有在不是拖动且点击在菜单外时才关闭
          if (!_isDragging && _tapDownPosition != null) {
            if (!widget.menuRect.contains(event.position)) {
              // 使用 microtask 来避免在事件处理中调用回调
              scheduleMicrotask(() {
                if (mounted) {
                  widget.onDismiss();
                }
              });
            }
          }
          _tapDownPosition = null;
          _isDragging = false;
          _trackedPointer = null;
        }
      } else if (event is PointerCancelEvent) {
        if (_trackedPointer == event.pointer) {
          _tapDownPosition = null;
          _isDragging = false;
          _trackedPointer = null;
        }
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(_globalRoute!);
  }

  void _unregisterGlobalRoute() {
    if (_globalRoute != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalRoute!);
      _globalRoute = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不返回任何 widget，使用全局事件监听
    // 这样不会干扰任何 widget 的事件处理
    return const SizedBox.shrink();
  }
}
