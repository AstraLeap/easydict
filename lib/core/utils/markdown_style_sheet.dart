import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../theme/app_theme.dart';

/// 缓存的 MarkdownStyleSheet 对象，避免每次调用都创建新对象
MarkdownStyleSheet? _cachedMarkdownStyleSheet;
ThemeData? _cachedTheme;
double? _cachedFontSize;

/// 构建统一风格的 MarkdownStyleSheet。
///
/// 用户笔记和AI聊天内容使用相同的样式策略：
/// - 使用默认字体 SourceSans3，不使用用户自定义字体
/// - 但保留正确的中文字体回退，避免显示日文字形
/// - 自定义 blockquote、code、表格的装饰样式
///
/// [fontSize] 可选参数：当与编辑器共用时应传入编辑器实际使用的字号，
/// 确保预览与编辑界面字号完全一致。
MarkdownStyleSheet buildMarkdownStyleSheet(
  BuildContext context, {
  double? fontSize,
}) {
  final theme = Theme.of(context);

  // 检查缓存：如果主题和字号都相同，直接返回缓存的样式表
  if (_cachedMarkdownStyleSheet != null &&
      identical(_cachedTheme, theme) &&
      _cachedFontSize == fontSize) {
    return _cachedMarkdownStyleSheet!;
  }

  final cs = theme.colorScheme;

  // 使用默认字体 SourceSans3，不使用用户自定义字体
  // 但保留 AppTheme 提供的中文字体回退，确保 CJK 使用中国大陆字形
  const defaultFont = 'SourceSans3';
  final fallback = AppTheme.fontFamilyFallback;
  // 笔记/AI 聊天内容字号比默认 bodyMedium 大 1.5pt
  // 如果外部传入了 fontSize（如编辑器实际字号），直接使用，保证编辑与预览完全一致
  final effectiveFontSize =
      fontSize ?? ((theme.textTheme.bodyMedium?.fontSize ?? 15) + 1.5);

  final baseBody = TextStyle(
    fontSize: effectiveFontSize,
    fontFamily: defaultFont,
    fontFamilyFallback: fallback,
    color: theme.textTheme.bodyMedium?.color,
  );

  final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: baseBody,
    a: TextStyle(
      color: cs.primary,
      fontSize: effectiveFontSize,
      fontFamily: defaultFont,
      fontFamilyFallback: fallback,
    ),
    h1: TextStyle(
      fontSize: (theme.textTheme.titleLarge?.fontSize ?? 22) + 1.5,
      fontWeight: FontWeight.w700,
      fontFamily: defaultFont,
      fontFamilyFallback: fallback,
    ),
    h2: TextStyle(
      fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) + 1.5,
      fontWeight: FontWeight.w700,
      fontFamily: defaultFont,
      fontFamilyFallback: fallback,
    ),
    h3: TextStyle(
      fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) + 1.5,
      fontWeight: FontWeight.w600,
      fontFamily: defaultFont,
      fontFamilyFallback: fallback,
    ),
    code: TextStyle(
      fontFamily: 'Consolas',
      fontSize: effectiveFontSize * 0.9,
      color: cs.onSurfaceVariant,
      backgroundColor: cs.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: baseBody.copyWith(
      color: cs.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: cs.primary.withOpacity(0.5), width: 4),
      ),
      color: cs.primaryContainer.withOpacity(0.15),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    listBullet: baseBody,
    strong: baseBody.copyWith(fontWeight: FontWeight.w700),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
    ),
    tableHead: baseBody.copyWith(fontWeight: FontWeight.w700),
    tableBody: baseBody,
    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
    tableColumnWidth: const FlexColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tableHeadAlign: TextAlign.left,
  );

  // 更新缓存
  _cachedMarkdownStyleSheet = styleSheet;
  _cachedTheme = theme;
  _cachedFontSize = fontSize;

  return styleSheet;
}