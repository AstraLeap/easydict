// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/logger.dart';
import '../../core/utils/dict_typography.dart';
import '../../services/font_loader_service.dart';

/// Result of parsing formatted text containing spans and plain text.
class FormattedTextResult {
  final List<InlineSpan> spans;
  final List<String> plainTexts;
  final bool hidden;

  const FormattedTextResult(this.spans, this.plainTexts, {this.hidden = false});

  /// Creates an empty hidden result.
  static const FormattedTextResult hiddenResult = FormattedTextResult(
    [],
    [],
    hidden: true,
  );

  /// Creates an empty result.
  static const FormattedTextResult empty = FormattedTextResult([], []);

  /// Returns true if this result has no content.
  bool get isEmpty => spans.isEmpty && plainTexts.isEmpty;

  /// Returns the combined plain text.
  String get combinedText => plainTexts.join();
}

// ============================================================================
// Constants
// ============================================================================

/// Color mapping for text formatting.
const Map<String, Color> kColorMap = {
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

/// Maximum nesting depth for formatted text parsing.
const int kMaxNestingDepth = 10;

/// Default font size used when base style has no font size.
const double kDefaultFontSize = 12.0;

/// Font size scale factor for superscript and subscript text.
const double kScriptFontScale = 0.7;

/// Vertical offset factor for superscript text (negative = upward).
const double kSuperscriptOffsetFactor = -0.1;

/// Vertical offset factor for subscript text (positive = downward).
const double kSubscriptOffsetFactor = 0.3;

/// Font size scale factor for label text.
const double kLabelFontScale = 0.85;

/// Label container border radius.
const double kLabelBorderRadius = 4.0;

/// Label container border width.
const double kLabelBorderWidth = 0.7;

/// Label container horizontal padding.
const double kLabelHorizontalPadding = 5.0;

/// Label container vertical padding.
const double kLabelVerticalPadding = 1.0;

/// Label container horizontal margin.
const double kLabelHorizontalMargin = 1.0;

/// Alpha value for label border color.
const int kLabelBorderAlpha = 140;

/// Alpha value for label background color.
const int kLabelBackgroundAlpha = 13;

/// Alpha value for AI text mark background.
const int kAiTextMarkBackgroundAlpha = 115;

/// Font size scale factor for ruby text (furigana).
const double kRubyFontScale = 0.5;

/// Spacing between ruby text and base text.
const double kRubySpacing = 0.0;

/// Known language codes for validation.
const Set<String> kKnownLanguageCodes = {
  'en',
  'zh',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
  'it',
  'ru',
  'pt',
  'ar',
};

/// Language code prefixes that indicate valid language codes.
const Set<String> kLanguagePrefixes = {'zh_', 'ja_', 'ko_'};

/// Pre-compiled regex pattern for removing formatting.
final RegExp _removeFormattingPattern = RegExp(r'\[([^\]]*?)\]\([^\)]*?\)');

// ============================================================================
// Parsing Context
// ============================================================================

/// Context for parsing formatted text.
class _ParseContext {
  final String text;
  int pos = 0;
  final int maxDepth;
  int currentDepth = 0;

  _ParseContext(this.text, {this.maxDepth = kMaxNestingDepth});

  bool get isAtEnd => pos >= text.length;
  String get currentChar => isAtEnd ? '' : text[pos];
  String get peekNext => pos + 1 >= text.length ? '' : text[pos + 1];

  /// Creates a copy of this context for nested parsing.
  _ParseContext nestedCopy(String nestedText) {
    return _ParseContext(nestedText, maxDepth: maxDepth)
      ..currentDepth = currentDepth + 1;
  }
}

// ============================================================================
// Parsed Segments (Sealed Class Pattern)
// ============================================================================

/// Base class for parsed segments.
abstract class _ParsedSegment {
  const _ParsedSegment();

  /// Returns the text content of this segment.
  String get textContent;

  /// Accepts a visitor for processing.
  R accept<R>(_SegmentVisitor<R> visitor);
}

/// A plain text segment without formatting.
class _PlainTextSegment extends _ParsedSegment {
  final String text;

  const _PlainTextSegment(this.text);

  @override
  String get textContent => text;

  @override
  R accept<R>(_SegmentVisitor<R> visitor) => visitor.visitPlain(this);
}

/// A formatted text segment with style annotations.
class _FormattedSegment extends _ParsedSegment {
  final String content;
  final String typesStr;
  final List<_ParsedSegment>? children;

  const _FormattedSegment(this.content, this.typesStr, this.children);

  @override
  String get textContent => content;

  /// Returns true if this segment has nested children.
  bool get hasChildren => children != null && children!.isNotEmpty;

  /// Returns true if the content contains nested formatting.
  bool get hasNestedFormatting =>
      content.contains('[') && content.contains('](');

  @override
  R accept<R>(_SegmentVisitor<R> visitor) => visitor.visitFormatted(this);
}

/// A ruby text segment for Japanese furigana.
/// Syntax: [漢](:かん) where 漢 is the base text and かん is the ruby text.
class _RubySegment extends _ParsedSegment {
  final String baseText;
  final String rubyText;

  const _RubySegment(this.baseText, this.rubyText);

  @override
  String get textContent => baseText;

  @override
  R accept<R>(_SegmentVisitor<R> visitor) => visitor.visitRuby(this);
}

/// Visitor pattern for processing parsed segments.
abstract class _SegmentVisitor<R> {
  R visitPlain(_PlainTextSegment segment);
  R visitFormatted(_FormattedSegment segment);
  R visitRuby(_RubySegment segment);
}

// ============================================================================
// Style Information
// ============================================================================

/// Style information extracted from type annotations.
class StyleInfo {
  final TextStyle style;
  final List<TextDecoration> decorations;
  final bool isSup;
  final bool isSub;
  final bool aiTextMark;
  final bool isWordLabel;
  final bool isLabelType;
  final Color? customColor;
  final String? linkTarget;
  final String? exactJumpTarget;

  const StyleInfo({
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
  });

  /// Returns true if this style has a link target.
  bool get hasLink => linkTarget != null;

  /// Returns true if this style has an exact jump target.
  bool get hasExactJump => exactJumpTarget != null;

  /// Returns true if this style requires special rendering (sup/sub/label).
  bool get requiresSpecialRendering => isSup || isSub || isLabelType;
}

// ============================================================================
// Type Parser
// ============================================================================

/// Parses type annotation strings into style information.
class TypeParser {
  const TypeParser._();

  /// Parses type annotations and returns style information.
  static StyleInfo parse(
    String typesStr,
    TextStyle baseStyle,
    BuildContext? context,
  ) {
    final types = _parseTypeList(typesStr);

    TextStyle style = baseStyle;
    final decorations = <TextDecoration>[];
    bool isSup = false;
    bool isSub = false;
    bool aiTextMark = false;
    bool isWordLabel = false;
    bool isLabelType = false;
    Color? customColor;
    String? linkTarget;
    String? exactJumpTarget;

    for (final type in types) {
      if (type.isEmpty) continue;

      // Check for color
      final color = _tryParseColor(type);
      if (color != null) {
        customColor = color;
        continue;
      }

      // Check for link target
      final link = _tryParseLink(type);
      if (link != null) {
        linkTarget = link;
        continue;
      }

      // Check for exact jump target
      final jump = _tryParseExactJump(type);
      if (jump != null) {
        exactJumpTarget = jump;
        continue;
      }

      // Parse style modifiers
      final result = _parseStyleModifier(
        type: type,
        style: style,
        baseStyle: baseStyle,
        context: context,
        types: types,
        decorations: decorations,
      );
      style = result.style;

      // Track boolean flags
      if (result.isSup) isSup = true;
      if (result.isSub) isSub = true;
      if (result.aiTextMark) aiTextMark = true;
      if (result.isWordLabel) isWordLabel = true;
      if (result.isLabelType) isLabelType = true;
    }

    // Apply decorations
    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: baseStyle.color,
      );
    }

    // Apply custom color
    if (customColor != null) {
      style = style.copyWith(color: customColor);
    }

    return StyleInfo(
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
    );
  }

  static List<String> _parseTypeList(String typesStr) {
    return typesStr.split(',').map((t) => t.trim()).toList();
  }

  static Color? _tryParseColor(String type) {
    return kColorMap[type.toLowerCase()];
  }

  static String? _tryParseLink(String type) {
    if (type.startsWith('->')) {
      return type.substring(2).trim();
    }
    return null;
  }

  static String? _tryParseExactJump(String type) {
    if (type.startsWith('==')) {
      return type.substring(2).trim();
    }
    return null;
  }

  static _StyleParseResult _parseStyleModifier({
    required String type,
    required TextStyle style,
    required TextStyle baseStyle,
    required BuildContext? context,
    required List<String> types,
    required List<TextDecoration> decorations,
  }) {
    TextStyle newStyle = style;
    bool isSup = false;
    bool isSub = false;
    bool aiTextMark = false;
    bool isWordLabel = false;
    bool isLabelType = false;

    switch (type) {
      case 'strike':
        decorations.add(TextDecoration.lineThrough);
        break;
      case 'underline':
        decorations.add(TextDecoration.underline);
        break;
      case 'double_underline':
        newStyle = style.copyWith(
          decoration: TextDecoration.combine([
            TextDecoration.underline,
            TextDecoration.underline,
          ]),
          decorationColor: baseStyle.color,
        );
        break;
      case 'wavy':
        newStyle = style.copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: baseStyle.color,
        );
        break;
      case 'bold':
        newStyle = style.copyWith(
          fontWeight: types.contains('label')
              ? FontWeight.w600
              : FontWeight.bold,
        );
        break;
      case 'italic':
        newStyle = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'sup':
        isSup = true;
        break;
      case 'sub':
        isSub = true;
        break;
      case 'special':
        newStyle = style.copyWith(
          fontStyle: FontStyle.italic,
          color: context != null ? Theme.of(context).colorScheme.primary : null,
        );
        break;
      case 'ai':
        aiTextMark = true;
        break;
      case 'label':
      case 'pattern':
        isLabelType = true;
        newStyle = style.copyWith(fontWeight: FontWeight.w500);
        break;
      case 'word':
        isWordLabel = true;
        newStyle = style.copyWith(fontWeight: FontWeight.w700);
        break;
    }

    return _StyleParseResult(
      style: newStyle,
      isSup: isSup,
      isSub: isSub,
      aiTextMark: aiTextMark,
      isWordLabel: isWordLabel,
      isLabelType: isLabelType,
    );
  }
}

/// Result of parsing a single style modifier.
class _StyleParseResult {
  final TextStyle style;
  final bool isSup;
  final bool isSub;
  final bool aiTextMark;
  final bool isWordLabel;
  final bool isLabelType;

  const _StyleParseResult({
    required this.style,
    this.isSup = false,
    this.isSub = false,
    this.aiTextMark = false,
    this.isWordLabel = false,
    this.isLabelType = false,
  });
}

// ============================================================================
// Segment Parser
// ============================================================================

/// Parses formatted text into segments.
class SegmentParser {
  const SegmentParser._();

  /// Parses the given text into a list of segments.
  // ignore: library_private_types_in_public_api
  static List<_ParsedSegment> parse(_ParseContext ctx) {
    final segments = <_ParsedSegment>[];
    final buffer = StringBuffer();

    while (!ctx.isAtEnd) {
      if (ctx.currentChar == '[') {
        _flushBuffer(buffer, segments);
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

    _flushBuffer(buffer, segments);
    return segments;
  }

  static void _flushBuffer(StringBuffer buffer, List<_ParsedSegment> segments) {
    if (buffer.isNotEmpty) {
      segments.add(_PlainTextSegment(buffer.toString()));
      buffer.clear();
    }
  }

  static _ParsedSegment? _tryParseFormattedSegment(_ParseContext ctx) {
    if (ctx.currentChar != '[') return null;

    final startPos = ctx.pos;
    ctx.pos++;

    // Parse content within brackets
    final contentResult = _parseBracketContent(ctx);
    if (contentResult == null) {
      ctx.pos = startPos;
      return null;
    }

    // Parse types within parentheses
    final typesResult = _parseParenthesesContent(ctx);
    if (typesResult == null) {
      ctx.pos = startPos;
      return null;
    }

    final content = contentResult;
    final typesStr = typesResult;

    // 调试信息
    Logger.d('=== Formatted Segment Debug ===', tag: 'RubyParser');
    Logger.d('content: $content', tag: 'RubyParser');
    Logger.d('typesStr: $typesStr', tag: 'RubyParser');

    // Check for Ruby syntax: [text](:ruby)
    if (typesStr.startsWith(':')) {
      final rubyText = typesStr.substring(1);
      Logger.d(
        '>>> Ruby detected! baseText: $content, rubyText: $rubyText',
        tag: 'RubyParser',
      );
      return _RubySegment(content, rubyText);
    }

    // Handle nested formatting
    if (content.contains('[') && content.contains('](')) {
      if (ctx.currentDepth >= ctx.maxDepth) {
        return _FormattedSegment(content, typesStr, null);
      }

      final nestedCtx = ctx.nestedCopy(content);
      final children = parse(nestedCtx);
      return _FormattedSegment(content, typesStr, children);
    }

    return _FormattedSegment(content, typesStr, null);
  }

  static String? _parseBracketContent(_ParseContext ctx) {
    final buffer = StringBuffer();
    int depth = 1;

    while (!ctx.isAtEnd && depth > 0) {
      final ch = ctx.currentChar;

      if (ch == '[') {
        depth++;
        buffer.write(ch);
      } else if (ch == ']') {
        depth--;
        if (depth > 0) {
          buffer.write(ch);
        }
      } else {
        buffer.write(ch);
      }
      ctx.pos++;
    }

    if (ctx.isAtEnd || ctx.currentChar != '(') {
      return null;
    }

    return buffer.toString();
  }

  static String? _parseParenthesesContent(_ParseContext ctx) {
    if (ctx.currentChar != '(') return null;
    ctx.pos++;

    final buffer = StringBuffer();
    int depth = 1;

    while (!ctx.isAtEnd && depth > 0) {
      final ch = ctx.currentChar;

      if (ch == '(') {
        depth++;
        buffer.write(ch);
      } else if (ch == ')') {
        depth--;
        if (depth > 0) {
          buffer.write(ch);
        }
      } else {
        buffer.write(ch);
      }
      ctx.pos++;
    }

    return depth == 0 ? buffer.toString() : null;
  }
}

// ============================================================================
// Public Utility Functions
// ============================================================================

/// Pre-compiled regex pattern for removing ruby formatting.
final RegExp _removeRubyPattern = RegExp(r'\[([^\]]*?)\]\(:[^\)]*?\)');

/// Removes formatting markers from text.
String removeFormatting(String text) {
  // First handle Ruby syntax: [漢](:かん) -> 漢
  String result = text.replaceAllMapped(
    _removeRubyPattern,
    (match) => match.group(1) ?? '',
  );

  // Then handle regular formatting syntax
  result = result.replaceAllMapped(
    _removeFormattingPattern,
    (match) => match.group(1) ?? '',
  );

  return result;
}

/// Extracts text to copy from a dynamic value.
String? extractTextToCopy(dynamic value) {
  if (value == null) return null;

  final String rawText;
  if (value is String) {
    rawText = value;
  } else if (value is Map) {
    rawText = value['text'] ?? value['word'] ?? value['content'] ?? '';
  } else {
    rawText = value.toString();
  }

  final textToCopy = removeFormatting(rawText);
  return textToCopy.isNotEmpty ? textToCopy : null;
}

/// Checks if a string is a known language code.
bool isKnownLanguageCode(String key) {
  if (kKnownLanguageCodes.contains(key)) return true;
  return kLanguagePrefixes.any((prefix) => key.startsWith(prefix));
}

/// Determines the effective language from various sources.
String? determineEffectiveLanguage({
  String? language,
  List<String>? path,
  String? sourceLanguage,
}) {
  if (language != null && language.isNotEmpty) {
    return language;
  }

  if (path != null && path.isNotEmpty) {
    final firstKey = path.first;
    if (isKnownLanguageCode(firstKey)) {
      return firstKey;
    }
  }

  return sourceLanguage;
}

// ============================================================================
// Formatted Text Parser
// ============================================================================

/// Configuration for formatted text parsing.
class FormattedTextConfig {
  final BuildContext? context;
  final List<String>? path;
  final String? label;
  final void Function(String path, String label)? onElementTap;
  final void Function(String path, String label)? onElementSecondaryTap;
  final GestureRecognizer? recognizer;
  final MouseCursor? mouseCursor;
  final String? language;
  final String? sourceLanguage;
  final Map<String, Map<String, double>>? fontScales;
  final bool isSerif;
  final bool isBold;
  final DictElementType? elementType;
  final bool useCustomFont;
  final void Function(String word, BuildContext context)? onLinkTap;
  final void Function(String target, BuildContext context)? onExactJump;

  const FormattedTextConfig({
    this.context,
    this.path,
    this.label,
    this.onElementTap,
    this.onElementSecondaryTap,
    this.recognizer,
    this.mouseCursor,
    this.language,
    this.sourceLanguage,
    this.fontScales,
    this.isSerif = false,
    this.isBold = false,
    this.elementType,
    this.useCustomFont = true,
    this.onLinkTap,
    this.onExactJump,
  });

  /// Returns effective isSerif value based on element type.
  bool get effectiveIsSerif =>
      elementType != null ? DictTypography.isSerif(elementType!) : isSerif;
}

/// Parses formatted text and returns the result.
FormattedTextResult parseFormattedText(
  String text,
  TextStyle baseStyle, {
  BuildContext? context,
  List<String>? path,
  String? label,
  void Function(String path, String label)? onElementTap,
  void Function(String path, String label)? onElementSecondaryTap,
  GestureRecognizer? recognizer,
  bool hidden = false,
  String? language,
  String? sourceLanguage,
  Map<String, Map<String, double>>? fontScales,
  bool isSerif = false,
  bool isBold = false,
  DictElementType? elementType,
  MouseCursor? mouseCursor,
  bool useCustomFont = true,
  void Function(String word, BuildContext context)? onLinkTap,
  void Function(String target, BuildContext context)? onExactJump,
}) {
  final config = FormattedTextConfig(
    context: context,
    path: path,
    label: label,
    onElementTap: onElementTap,
    onElementSecondaryTap: onElementSecondaryTap,
    recognizer: recognizer,
    mouseCursor: mouseCursor,
    language: language,
    sourceLanguage: sourceLanguage,
    fontScales: fontScales,
    isSerif: isSerif,
    isBold: isBold,
    elementType: elementType,
    useCustomFont: useCustomFont,
    onLinkTap: onLinkTap,
    onExactJump: onExactJump,
  );

  return _FormattedTextParser.parse(text, baseStyle, config, hidden);
}

/// Internal parser implementation.
class _FormattedTextParser {
  const _FormattedTextParser._();

  static FormattedTextResult parse(
    String text,
    TextStyle baseStyle,
    FormattedTextConfig config,
    bool hidden,
  ) {
    // 调试：打印输入文本
    Logger.d('=== parseFormattedText called ===', tag: 'RubyParser');
    Logger.d('text: $text', tag: 'RubyParser');
    Logger.d('hidden: $hidden', tag: 'RubyParser');

    if (hidden) {
      return FormattedTextResult.hiddenResult;
    }

    final effectiveBaseStyle = _resolveEffectiveStyle(baseStyle, config);
    final ctx = _ParseContext(text);
    final segments = SegmentParser.parse(ctx);

    Logger.d('segments count: ${segments.length}', tag: 'RubyParser');
    for (int i = 0; i < segments.length; i++) {
      Logger.d(
        '  segment[$i]: ${segments[i].runtimeType} - ${segments[i].textContent}',
        tag: 'RubyParser',
      );
    }

    final processor = _SegmentProcessor(
      baseStyle: effectiveBaseStyle,
      config: config,
    );

    for (final segment in segments) {
      segment.accept(processor);
    }

    return FormattedTextResult(
      processor.spans,
      processor.plainTexts,
      hidden: hidden,
    );
  }

  static TextStyle _resolveEffectiveStyle(
    TextStyle baseStyle,
    FormattedTextConfig config,
  ) {
    TextStyle style = baseStyle;

    final effectiveLanguage = determineEffectiveLanguage(
      language: config.language,
      path: config.path,
      sourceLanguage: config.sourceLanguage,
    );

    if (config.useCustomFont && effectiveLanguage != null) {
      style = _applyFontSettings(style, effectiveLanguage, config);
    }

    return style.copyWith(locale: const Locale('zh', 'CN'));
  }

  static TextStyle _applyFontSettings(
    TextStyle style,
    String language,
    FormattedTextConfig config,
  ) {
    final fontService = FontLoaderService();
    final fontInfo = fontService.getFontInfo(
      language,
      isSerif: config.effectiveIsSerif,
      isBold: config.isBold,
    );

    final fontScale = _resolveFontScale(fontService, language, config);

    if (fontInfo != null && style.fontFamily == null) {
      style = style.copyWith(fontFamily: fontInfo.fontFamily);
    }

    if (fontScale != 1.0 && style.fontSize != null) {
      style = style.copyWith(fontSize: style.fontSize! * fontScale);
    }

    return style;
  }

  static double _resolveFontScale(
    FontLoaderService fontService,
    String language,
    FormattedTextConfig config,
  ) {
    if (config.fontScales == null) return 1.0;

    final resolvedScale = fontService.resolveFontScale(
      language,
      isSerif: config.effectiveIsSerif,
    );

    if (resolvedScale != null) {
      return resolvedScale;
    }

    final scaleKey = config.effectiveIsSerif ? 'serif' : 'sans';
    return config.fontScales![language]?[scaleKey] ?? 1.0;
  }
}

// ============================================================================
// Segment Processor
// ============================================================================

/// Processes parsed segments into InlineSpans.
class _SegmentProcessor extends _SegmentVisitor<void> {
  final List<InlineSpan> spans = [];
  final List<String> plainTexts = [];
  final TextStyle baseStyle;
  final FormattedTextConfig config;

  _SegmentProcessor({required this.baseStyle, required this.config});

  @override
  void visitPlain(_PlainTextSegment segment) {
    spans.add(
      TextSpan(
        text: segment.text,
        style: baseStyle,
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
    plainTexts.add(segment.text);
  }

  @override
  void visitFormatted(_FormattedSegment segment) {
    final typesStr = segment.typesStr;
    final styleInfo = TypeParser.parse(typesStr, baseStyle, config.context);

    if (segment.hasChildren) {
      _processNestedSegment(segment, styleInfo);
    } else {
      _processFlatSegment(segment, styleInfo);
    }
  }

  @override
  void visitRuby(_RubySegment segment) {
    final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
    final rubyFontSize = fontSize * kRubyFontScale;

    // 振假名特殊样式：使用淡灰色
    final rubyColor = Colors.grey.shade600;

    // 使用 Stack 实现 Ruby 文本，确保振假名显示在汉字上方
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 基础文本（汉字）
            Text(segment.baseText, style: baseStyle),
            // 振假名，定位在汉字上方
            Positioned(
              top: -fontSize * kRubyFontScale - kRubySpacing,
              left: 0,
              right: 0,
              child: Text(
                segment.rubyText,
                textAlign: TextAlign.center,
                style: baseStyle.copyWith(
                  fontSize: rubyFontSize,
                  height: 1.0,
                  color: rubyColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    plainTexts.add(segment.baseText);
  }

  void _processNestedSegment(_FormattedSegment segment, StyleInfo styleInfo) {
    final childProcessor = _SegmentProcessor(
      baseStyle: styleInfo.style,
      config: config,
    );

    for (final child in segment.children!) {
      child.accept(childProcessor);
    }

    spans.add(
      TextSpan(
        children: childProcessor.spans,
        style: styleInfo.style,
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
    plainTexts.addAll(childProcessor.plainTexts);
  }

  void _processFlatSegment(_FormattedSegment segment, StyleInfo styleInfo) {
    final text = segment.content;

    // Priority order for special rendering
    if (styleInfo.hasLink &&
        config.context != null &&
        config.onLinkTap != null) {
      _addLinkSpan(text, styleInfo);
    } else if (styleInfo.hasExactJump &&
        config.context != null &&
        config.onExactJump != null) {
      _addExactJumpSpan(text, styleInfo);
    } else if (styleInfo.isLabelType && config.context != null) {
      _addLabelSpan(text, styleInfo);
    } else if (styleInfo.isSup) {
      _addSuperscriptSpan(text, styleInfo);
    } else if (styleInfo.isSub) {
      _addSubscriptSpan(text, styleInfo);
    } else {
      _addDefaultSpan(text, styleInfo);
    }

    plainTexts.add(text);
  }

  void _addLinkSpan(String text, StyleInfo styleInfo) {
    final style = styleInfo.style.copyWith(
      color: Theme.of(config.context!).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    spans.add(
      TextSpan(
        text: text,
        style: style,
        recognizer: TapGestureRecognizer()
          ..onTap = () =>
              config.onLinkTap!(styleInfo.linkTarget!, config.context!),
      ),
    );
  }

  void _addExactJumpSpan(String text, StyleInfo styleInfo) {
    final style = styleInfo.style.copyWith(
      color: Theme.of(config.context!).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );
    spans.add(
      TextSpan(
        text: text,
        style: style,
        recognizer: TapGestureRecognizer()
          ..onTap = () =>
              config.onExactJump!(styleInfo.exactJumpTarget!, config.context!),
      ),
    );
  }

  void _addLabelSpan(String text, StyleInfo styleInfo) {
    final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
    var labelStyle = styleInfo.style.copyWith(
      fontSize: fontSize * kLabelFontScale,
    );

    if (styleInfo.isWordLabel) {
      final serifFontInfo = FontLoaderService().getFontInfo(
        config.language ?? '',
        isSerif: true,
      );
      if (serifFontInfo != null) {
        labelStyle = labelStyle.copyWith(fontFamily: serifFontInfo.fontFamily);
      }
    }

    final theme = Theme.of(config.context!);
    final bgColor = theme.colorScheme.onSurface.withAlpha(
      kLabelBackgroundAlpha,
    );

    // 使用纯 TextSpan 实现标签效果，保持选择连续性
    // 通过 backgroundColor 模拟背景，使用特殊字符模拟边框
    spans.add(
      TextSpan(
        text: text,
        style: labelStyle.copyWith(
          backgroundColor: bgColor,
          letterSpacing: 1.5, // 增加字距模拟 padding 效果
        ),
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
  }

  void _addSuperscriptSpan(String text, StyleInfo styleInfo) {
    final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
    // 使用纯 TextSpan 实现上标效果，保持选择连续性
    // 通过 fontFeatures 启用上标特性（如果字体支持）
    // 同时缩小字号实现视觉效果
    spans.add(
      TextSpan(
        text: text,
        style: styleInfo.style.copyWith(
          fontSize: fontSize * kScriptFontScale,
          fontFeatures: const [FontFeature.superscripts()],
          height: 1.0, // 紧凑行高
        ),
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
  }

  void _addSubscriptSpan(String text, StyleInfo styleInfo) {
    final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
    // 使用纯 TextSpan 实现下标效果，保持选择连续性
    // 通过 fontFeatures 启用下标特性（如果字体支持）
    // 同时缩小字号实现视觉效果
    spans.add(
      TextSpan(
        text: text,
        style: styleInfo.style.copyWith(
          fontSize: fontSize * kScriptFontScale,
          fontFeatures: const [FontFeature.subscripts()],
          height: 1.0, // 紧凑行高
        ),
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
  }

  void _addDefaultSpan(String text, StyleInfo styleInfo) {
    var style = styleInfo.style;
    if (styleInfo.aiTextMark && config.context != null) {
      final bgColor = Theme.of(config.context!).colorScheme.primaryContainer;
      style = style.copyWith(
        backgroundColor: bgColor.withAlpha(kAiTextMarkBackgroundAlpha),
      );
    }
    spans.add(
      TextSpan(
        text: text,
        style: style,
        recognizer: config.recognizer,
        mouseCursor: config.mouseCursor,
      ),
    );
  }
}
