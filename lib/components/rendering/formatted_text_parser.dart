// ignore_for_file: library_private_types_in_public_api

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/logger.dart';
import '../../core/utils/dict_typography.dart';
import '../../services/font_loader_service.dart';
import 'ruby_layout.dart';

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

/// Spacing ratio between ruby text and base text (as fraction of base font size).
/// This ensures the visual spacing scales proportionally with font size.
const double kRubySpacingRatio = 0.25;

/// Known language codes for validation.
const Set<String> kKnownLanguageCodes = {
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

/// Language code prefixes that indicate valid language codes.
const Set<String> kLanguagePrefixes = {'zh_', 'jp_', 'ko_'};

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

/// An inline image segment.
/// Syntax: [](~font.png) where font.png is the image file name from media.db.
/// The image height matches the text line height.
class _ImageSegment extends _ParsedSegment {
  final String content;
  final String imageFile;

  const _ImageSegment(this.content, this.imageFile);

  @override
  String get textContent => content;

  @override
  R accept<R>(_SegmentVisitor<R> visitor) => visitor.visitImage(this);
}

/// Visitor pattern for processing parsed segments.
abstract class _SegmentVisitor<R> {
  R visitPlain(_PlainTextSegment segment);
  R visitFormatted(_FormattedSegment segment);
  R visitRuby(_RubySegment segment);
  R visitImage(_ImageSegment segment);
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
  final String? pathJumpTarget;
  final String? groupJumpTarget;

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
    this.pathJumpTarget,
    this.groupJumpTarget,
  });

  /// Returns true if this style has a link target.
  bool get hasLink => linkTarget != null;

  /// Returns true if this style has an exact jump target.
  bool get hasExactJump => exactJumpTarget != null;

  /// Returns true if this style has a path jump target.
  bool get hasPathJump => pathJumpTarget != null;

  /// Returns true if this style has a group jump target.
  bool get hasGroupJump => groupJumpTarget != null;

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
    String? pathJumpTarget;
    String? groupJumpTarget;

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

      // Check for path jump target (::path)
      final pathJump = _tryParsePathJump(type);
      if (pathJump != null) {
        pathJumpTarget = pathJump;
        continue;
      }

      // Check for exact jump target
      final jump = _tryParseExactJump(type);
      if (jump != null) {
        exactJumpTarget = jump;
        continue;
      }

      // Check for group jump target
      final groupJump = _tryParseGroupJump(type);
      if (groupJump != null) {
        groupJumpTarget = groupJump;
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
      pathJumpTarget: pathJumpTarget,
      groupJumpTarget: groupJumpTarget,
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

  static String? _tryParseGroupJump(String type) {
    if (type.startsWith('=>')) {
      return type.substring(2).trim();
    }
    return null;
  }

  static String? _tryParsePathJump(String type) {
    if (type.startsWith('::')) {
      return type.substring(2).trim();
    }
    return null;
  }

  /// 解析 exactJumpTarget 为 entryId 和 path
  /// 新格式: entryid::path (如 25153::sense.0)
  /// 兼容旧格式: entryid.path (如 25153.sense.0)
  static ({String entryId, String? path}) parseExactJumpTarget(String target) {
    // 使用 :: 分隔 entryId 和 path
    final doubleColonIndex = target.indexOf('::');
    if (doubleColonIndex != -1) {
      final entryId = target.substring(0, doubleColonIndex);
      final path = target.substring(doubleColonIndex + 2);
      return (entryId: entryId, path: path.isEmpty ? null : path);
    }

    // 兼容旧格式：用 . 分隔，但注意 path 本身可能包含 .
    final dotIndex = target.indexOf('.');
    if (dotIndex != -1) {
      final entryId = target.substring(0, dotIndex);
      final path = target.substring(dotIndex + 1);
      return (entryId: entryId, path: path.isEmpty ? null : path);
    }

    // 只有 entryId，无 path
    return (entryId: target, path: null);
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

    // Check for Ruby syntax: [text](:ruby)
    // 注意：只匹配单冒号开头，排除双冒号 (::path) 的 path jump 格式
    if (typesStr.startsWith(':') && !typesStr.startsWith('::')) {
      final rubyText = typesStr.substring(1);
      return _RubySegment(content, rubyText);
    }

    // Check for image syntax: [](~image.png)
    if (typesStr.startsWith('~')) {
      final imageFile = typesStr.substring(1);
      Logger.d(
        'SegmentParser: found image segment, content=$content, imageFile=$imageFile',
        tag: 'InlineImage',
      );
      return _ImageSegment(content, imageFile);
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

/// Pre-compiled regex pattern for removing inline image formatting.
final RegExp _removeImagePattern = RegExp(r'\[([^\]]*?)\]\(~[^\)]*?\)');

/// Removes formatting markers from text.
String removeFormatting(String text) {
  // First handle image syntax: [](~image.png) -> content inside brackets
  String result = text.replaceAllMapped(
    _removeImagePattern,
    (match) => match.group(1) ?? '',
  );

  // Then handle Ruby syntax: [漢](:かん) -> 漢
  result = result.replaceAllMapped(
    _removeRubyPattern,
    (match) => match.group(1) ?? '',
  );

  // Finally handle regular formatting syntax
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
  final void Function(Offset position, String text)? onShowMenu;
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
  final void Function(String path, BuildContext context)? onPathJump;
  final void Function(int groupId, BuildContext context)? onGroupJump;
  final String? dictId;
  final Future<Uint8List?> Function(String dictId, String imageFile)?
  onLoadImage;

  const FormattedTextConfig({
    this.context,
    this.path,
    this.label,
    this.onElementTap,
    this.onElementSecondaryTap,
    this.onShowMenu,
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
    this.onPathJump,
    this.onGroupJump,
    this.dictId,
    this.onLoadImage,
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
  void Function(Offset position, String text)? onShowMenu,
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
  void Function(String path, BuildContext context)? onPathJump,
  void Function(int groupId, BuildContext context)? onGroupJump,
  String? dictId,
  Future<Uint8List?> Function(String dictId, String imageFile)? onLoadImage,
}) {
  final config = FormattedTextConfig(
    context: context,
    path: path,
    label: label,
    onElementTap: onElementTap,
    onElementSecondaryTap: onElementSecondaryTap,
    onShowMenu: onShowMenu,
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
    onPathJump: onPathJump,
    onGroupJump: onGroupJump,
    dictId: dictId,
    onLoadImage: onLoadImage,
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
    if (hidden) {
      return FormattedTextResult.hiddenResult;
    }

    final effectiveBaseStyle = _resolveEffectiveStyle(baseStyle, config);
    final ctx = _ParseContext(text);
    final segments = SegmentParser.parse(ctx);

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
    final baseFontSize = baseStyle.fontSize ?? kDefaultFontSize;
    final rubyFontSize = baseFontSize * kRubyFontScale;
    final rubySpacing = baseFontSize * kRubySpacingRatio;

    // 获取主题色用于振假名
    final rubyColor = config.context != null
        ? Theme.of(config.context!).colorScheme.primary
        : null;

    // 创建振假名widget
    Widget rubyWidget = RubyLayout(
      rubyFontSize: rubyFontSize,
      rubySpacing: rubySpacing,
      baseText: segment.baseText,
      baseStyle: baseStyle,
      rubyText: segment.rubyText,
      rubyColor: rubyColor,
    );

    // 如果有 onShowMenu 回调，添加右键事件处理
    if (config.onShowMenu != null) {
      rubyWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            config.onShowMenu!(event.position, segment.baseText);
          }
        },
        onPointerUp: (event) {
          // 移动端长按由 SelectionArea 处理，这里不处理
        },
        child: rubyWidget,
      );
    } else {
      // 如果没有回调，使用 IgnorePointer 让事件穿透
      rubyWidget = IgnorePointer(ignoring: true, child: rubyWidget);
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: rubyWidget,
      ),
    );
    plainTexts.add(segment.baseText);
  }

  @override
  void visitImage(_ImageSegment segment) {
    final imageHeight = baseStyle.fontSize ?? kDefaultFontSize;
    final fallbackText = segment.content.isNotEmpty
        ? segment.content
        : segment.imageFile;

    Logger.d(
      'visitImage: imageFile=${segment.imageFile}, content=${segment.content}, '
      'dictId=${config.dictId}, onLoadImage=${config.onLoadImage != null}',
      tag: 'InlineImage',
    );

    if (config.dictId != null &&
        config.dictId!.isNotEmpty &&
        config.onLoadImage != null) {
      final imageWidget = _InlineImageLoader(
        dictId: config.dictId!,
        imageFile: segment.imageFile,
        imageHeight: imageHeight,
        fallbackText: fallbackText,
        onLoadImage: config.onLoadImage!,
      );

      spans.add(
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: imageWidget),
      );
    } else {
      Logger.d(
        'visitImage: fallback to text (dictId=${config.dictId}, onLoadImage=${config.onLoadImage != null})',
        tag: 'InlineImage',
      );
      spans.add(TextSpan(text: fallbackText, style: baseStyle));
    }
    plainTexts.add(fallbackText);
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
    } else if (styleInfo.hasPathJump &&
        config.context != null &&
        config.onPathJump != null) {
      _addPathJumpSpan(text, styleInfo);
    } else if (styleInfo.hasGroupJump &&
        config.context != null &&
        config.onGroupJump != null) {
      _addGroupJumpSpan(text, styleInfo);
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

    Widget linkWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => config.onLinkTap!(styleInfo.linkTarget!, config.context!),
        child: Text(text, style: style),
      ),
    );

    if (config.onShowMenu != null) {
      linkWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            config.onShowMenu!(event.position, text);
          }
        },
        child: linkWidget,
      );
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: linkWidget,
      ),
    );
    plainTexts.add(text);
  }

  void _addExactJumpSpan(String text, StyleInfo styleInfo) {
    final style = styleInfo.style.copyWith(
      color: Theme.of(config.context!).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );

    Widget linkWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            config.onExactJump!(styleInfo.exactJumpTarget!, config.context!),
        child: Text(text, style: style),
      ),
    );

    if (config.onShowMenu != null) {
      linkWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            config.onShowMenu!(event.position, text);
          }
        },
        child: linkWidget,
      );
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: linkWidget,
      ),
    );
    plainTexts.add(text);
  }

  void _addPathJumpSpan(String text, StyleInfo styleInfo) {
    final style = styleInfo.style.copyWith(
      color: Theme.of(config.context!).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );

    Widget linkWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            config.onPathJump!(styleInfo.pathJumpTarget!, config.context!),
        child: Text(text, style: style),
      ),
    );

    if (config.onShowMenu != null) {
      linkWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            config.onShowMenu!(event.position, text);
          }
        },
        child: linkWidget,
      );
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: linkWidget,
      ),
    );
    plainTexts.add(text);
  }

  void _addGroupJumpSpan(String text, StyleInfo styleInfo) {
    final groupId = int.tryParse(styleInfo.groupJumpTarget!);
    if (groupId == null) return;

    final style = styleInfo.style.copyWith(
      color: Theme.of(config.context!).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );

    Widget linkWidget = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => config.onGroupJump!(groupId, config.context!),
        child: Text(text, style: style),
      ),
    );

    if (config.onShowMenu != null) {
      linkWidget = Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            config.onShowMenu!(event.position, text);
          }
        },
        child: linkWidget,
      );
    }

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: linkWidget,
      ),
    );
    plainTexts.add(text);
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

class _InlineImageLoader extends StatefulWidget {
  final String dictId;
  final String imageFile;
  final double imageHeight;
  final String fallbackText;
  final Future<Uint8List?> Function(String dictId, String imageFile)
  onLoadImage;

  const _InlineImageLoader({
    required this.dictId,
    required this.imageFile,
    required this.imageHeight,
    required this.fallbackText,
    required this.onLoadImage,
  });

  @override
  State<_InlineImageLoader> createState() => _InlineImageLoaderState();
}

class _InlineImageLoaderState extends State<_InlineImageLoader> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    Logger.d(
      'InlineImageLoader.initState: dictId=${widget.dictId}, imageFile=${widget.imageFile}, height=${widget.imageHeight}',
      tag: 'InlineImage',
    );
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      Logger.d(
        'InlineImageLoader._loadImage: loading image ${widget.imageFile} from dict ${widget.dictId}',
        tag: 'InlineImage',
      );
      final bytes = await widget.onLoadImage(widget.dictId, widget.imageFile);
      Logger.d(
        'InlineImageLoader._loadImage: loaded ${bytes?.length ?? 0} bytes for ${widget.imageFile}',
        tag: 'InlineImage',
      );
      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      Logger.e(
        'InlineImageLoader._loadImage error: $e',
        tag: 'InlineImage',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: widget.imageHeight,
        width: widget.imageHeight * 0.6,
        child: const SizedBox.shrink(),
      );
    }

    if (_imageBytes != null && _imageBytes!.isNotEmpty) {
      final isSvg = widget.imageFile.toLowerCase().endsWith('.svg');

      if (isSvg) {
        try {
          final svgString = String.fromCharCodes(_imageBytes!);
          return SvgPicture.string(
            svgString,
            height: widget.imageHeight,
            fit: BoxFit.fitHeight,
          );
        } catch (e) {
          Logger.e(
            'InlineImageLoader SvgPicture error: $e',
            tag: 'InlineImage',
          );
          return Text(
            widget.fallbackText,
            style: TextStyle(fontSize: widget.imageHeight),
          );
        }
      }

      return Image.memory(
        _imageBytes!,
        height: widget.imageHeight,
        fit: BoxFit.fitHeight,
        errorBuilder: (context, error, stackTrace) {
          Logger.e(
            'InlineImageLoader Image.memory error: $error',
            tag: 'InlineImage',
          );
          return Text(
            widget.fallbackText,
            style: TextStyle(fontSize: widget.imageHeight),
          );
        },
      );
    }

    Logger.d(
      'InlineImageLoader.build: no image bytes, showing fallback text "${widget.fallbackText}", error=$_errorMessage',
      tag: 'InlineImage',
    );
    return Text(
      widget.fallbackText,
      style: TextStyle(fontSize: widget.imageHeight),
    );
  }
}
