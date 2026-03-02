import 'package:flutter/material.dart';
import '../../services/font_loader_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 词典内容元素类型枚举
// 「元素类型」决定使用衬线(serif)或非衬线(sans)字体，以及基础字号等排版属性。
// ─────────────────────────────────────────────────────────────────────────────

enum DictElementType {
  /// 词条大标题（入口词/headword）
  headword,

  /// 短语词条标题（比标准 headword 稍小）
  headwordPhrase,

  /// 释义正文（definition 字段中的翻译/解释内容）
  definition,

  /// 例句文本（example 字段中各语言的句子）
  example,

  /// 例句的用法标签（example.usage 小标签）
  exampleUsage,

  /// 词性标注（pos 字段，如 n. / vt. / adj.）
  pos,

  /// 音标/注音（phonetic notation，特殊字体：使用等宽/IPA字体）
  phonetic,

  /// 发音地区标注（RP / GA 等）
  pronunciationRegion,

  /// 带背景色的语法/地区/用法标签（label 字段中非 pattern 类型）
  label,

  /// 无背景的语法模式标签（label.pattern）
  labelPattern,

  /// 释义备注（note 字段）
  note,

  /// 释义序号（sense.index 字段）
  senseIndex,

  /// 证书/等级标注（certifications 字段）
  certification,

  /// 词频等级标注（frequency.level 字段）
  frequencyLevel,

  /// Phrase 章节标题（"Phrase" 大标题）
  phraseTitle,

  /// 短语词目文本（phrase 列表中每个短语）
  phraseWord,

  /// Board 嵌套标题（isNested=true 时的小标题）
  boardTitle,

  /// Board 普通内容项（带子弹点的文本）
  boardContent,

  /// Board 内联内容项（带边框的内联文本块）
  inlineContent,

  /// 页面/章节显示标题（page 字段）
  pageDisplay,

  /// 章节导航标签（section 字段，横向滚动）
  sectionNav,

  /// Datas 标签页标签文字
  datasTabLabel,

  /// sense 分组标题（group_name 字段）
  groupName,

  /// sense 分组副标题（group_sub_name 字段）
  groupSubName,
}

// ─────────────────────────────────────────────────────────────────────────────
// 元素排版元数据（私有）
// ─────────────────────────────────────────────────────────────────────────────

class _ElementMeta {
  final double baseFontSize;

  /// true = 衬线字体(serif)；false = 非衬线(sans)；
  /// null = 特殊字体（等宽，phonetic 专用）
  final bool? isSerifOrMonospace;

  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? lineHeight;
  final double? letterSpacing;

  const _ElementMeta({
    required this.baseFontSize,
    this.isSerifOrMonospace,
    this.fontWeight,
    this.fontStyle,
    this.lineHeight,
    this.letterSpacing,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DictTypography：词典排版系统
//
// 职责：
//   1. 集中维护"元素类型 → 排版属性"的映射表（基础字号、衬线/非衬线等）
//   2. 提供两个核心方法：
//      • getBaseStyle()   ─ 返回含基础字号、字重、行高等属性的 TextStyle，
//                           字体族中不包含字体族（供走 parseFormattedText 路径的代码使用）
//      • getScaledStyle() ─ 返回已正确注入字体族 & 乘以用户字体缩放比例的 TextStyle，
//                           供直接用在 Text() / RichText() 的代码使用
//
// 字体选取链：
//   用户自定义字体 → 同语言同类别回退 → SourceSerif4 / SourceSans3 → 系统默认
//   （具体查找由 FontLoaderService.getFontInfo() 完成）
// ─────────────────────────────────────────────────────────────────────────────

class DictTypography {
  DictTypography._();

  // ── 排版元数据注册表 ──────────────────────────────────────────────────────

  static const Map<DictElementType, _ElementMeta> _meta = {
    // ── 词条标题 ──
    DictElementType.headword: _ElementMeta(
      baseFontSize: 28.0,
      isSerifOrMonospace: true, // serif
      fontWeight: FontWeight.bold,
      lineHeight: 1.0,
    ),
    DictElementType.headwordPhrase: _ElementMeta(
      baseFontSize: 20.0,
      isSerifOrMonospace: true, // serif
      fontWeight: FontWeight.bold,
      lineHeight: 1.0,
    ),

    // ── 释义 ──
    DictElementType.definition: _ElementMeta(
      baseFontSize: 15.5,
      isSerifOrMonospace: false, 
      lineHeight: 1.6,
    ),

    // ── 例句 ──
    DictElementType.example: _ElementMeta(
      baseFontSize: 14.0,
      isSerifOrMonospace: false, // sans
      lineHeight: 1.5,
    ),
    DictElementType.exampleUsage: _ElementMeta(
      baseFontSize: 12.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w500,
    ),

    // ── 词性/标签 ──
    DictElementType.pos: _ElementMeta(
      baseFontSize: 14.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
    DictElementType.label: _ElementMeta(
      baseFontSize: 12.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w500,
    ),
    DictElementType.labelPattern: _ElementMeta(
      baseFontSize: 11.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w700,
    ),

    // ── 发音 ──
    DictElementType.phonetic: _ElementMeta(
      baseFontSize: 13.0,
      isSerifOrMonospace: null, // 特殊：等宽字体
    ),
    DictElementType.pronunciationRegion: _ElementMeta(
      baseFontSize: 11.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w500,
    ),

    // ── 备注/序号 ──
    DictElementType.note: _ElementMeta(
      baseFontSize: 13.0,
      isSerifOrMonospace: false,
      lineHeight: 1.5,
    ),
    DictElementType.senseIndex: _ElementMeta(
      baseFontSize: 14.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w500,
    ),

    // ── 标注芯片 ──
    DictElementType.certification: _ElementMeta(
      baseFontSize: 10.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
    DictElementType.frequencyLevel: _ElementMeta(
      baseFontSize: 11.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),

    // ── 短语 ──
    DictElementType.phraseTitle: _ElementMeta(
      baseFontSize: 15.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
    DictElementType.phraseWord: _ElementMeta(
      baseFontSize: 15,
      isSerifOrMonospace: true, // serif（短语词目保持衬线风格）
      fontWeight: FontWeight.w600,
    ),

    // ── Board ──
    DictElementType.boardTitle: _ElementMeta(
      baseFontSize: 14.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
    ),
    DictElementType.boardContent: _ElementMeta(
      baseFontSize: 14.0,
      isSerifOrMonospace: false,
      lineHeight: 1.6,
      letterSpacing: 0.2,
    ),
    DictElementType.inlineContent: _ElementMeta(
      baseFontSize: 13.0,
      isSerifOrMonospace: false,
      letterSpacing: 0.15,
    ),

    // ── 页面 / 导航 ──
    DictElementType.pageDisplay: _ElementMeta(
      baseFontSize: 13.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
    ),
    DictElementType.sectionNav: _ElementMeta(
      baseFontSize: 12.0,
      isSerifOrMonospace: false,
    ),

    // ── Datas ──
    DictElementType.datasTabLabel: _ElementMeta(
      baseFontSize: 12.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w500,
    ),

    // ── sense 分组 ──
    DictElementType.groupName: _ElementMeta(
      baseFontSize: 16.0,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w600,
    ),
    DictElementType.groupSubName: _ElementMeta(
      baseFontSize: 13.5,
      isSerifOrMonospace: false,
      fontWeight: FontWeight.w400,
    ),
  };

  // ── 快捷访问器 ──────────────────────────────────────────────────────────────

  /// 返回该元素类型是否使用衬线字体（serif）。
  /// 音标等宽字体返回 false（作为 sans 处理，但字体族为 Monospace）。
  static bool isSerif(DictElementType type) {
    return _meta[type]?.isSerifOrMonospace == true;
  }

  /// 该元素类型是否使用音标等宽字体（phonetic）。
  static bool isMonospace(DictElementType type) {
    return _meta[type]?.isSerifOrMonospace == null;
  }

  /// 返回该元素类型的基础字号（不含用户缩放）。
  static double baseFontSize(DictElementType type) {
    return _meta[type]?.baseFontSize ?? 14.0;
  }

  // ── 核心方法 ────────────────────────────────────────────────────────────────

  /// 返回基础 TextStyle（含字号、字重、行高等），但**不含字体族**。
  ///
  /// 适用于随后会经过 [parseFormattedText] 的文本——该函数会负责注入字体族和缩放比例。
  /// [color] 由调用方根据当前主题色传入，不在排版层管理。
  /// [fontWeightOverride] / [fontStyleOverride] 用于覆盖默认值（例如 CJK 例句不使用斜体）。
  static TextStyle getBaseStyle(
    DictElementType type, {
    Color? color,
    FontWeight? fontWeightOverride,
    FontStyle? fontStyleOverride,
  }) {
    final m = _meta[type];
    return TextStyle(
      fontSize: m?.baseFontSize ?? 14.0,
      fontWeight: fontWeightOverride ?? m?.fontWeight,
      fontStyle: fontStyleOverride ?? m?.fontStyle,
      color: color,
      height: m?.lineHeight,
      letterSpacing: m?.letterSpacing,
    );
  }

  /// 返回完整 TextStyle（含字体族 + 用户缩放后的字号）。
  ///
  /// 适用于**直接**在 [Text] / [RichText] 中使用的场景（不经过 parseFormattedText）。
  ///
  /// 字体查找链：用户自定义字体 → 同语言同类别回退 → SourceSerif4/SourceSans3 → 系统默认。
  ///
  /// [language]    该文本所属的语言代码（如 'en'、'zh'、'ja'）。
  /// [fontScales]  用户在字体配置页面设置的每语言缩放比例
  ///               格式：{ language: { 'serif'|'sans': scale } }
  /// [isBold]      是否需要粗体变体（影响字体族选取）。
  /// [isItalic]    是否需要斜体变体（影响字体族选取）。
  static TextStyle getScaledStyle(
    DictElementType type, {
    required String? language,
    required Map<String, Map<String, double>> fontScales,
    Color? color,
    FontWeight? fontWeightOverride,
    FontStyle? fontStyleOverride,
    bool isBold = false,
    bool isItalic = false,
  }) {
    final m = _meta[type];
    final serif = isSerif(type);
    final mono = isMonospace(type);
    final effectiveLang = language ?? 'en';

    // ── 1. 字体族 ─────────────────────────────────────────────────────────
    String? fontFamily;
    if (mono) {
      // 音标等宽字体：优先取用户 sans 字体，回退到等宽系统字体
      final fontService = FontLoaderService();
      final fontInfo = fontService.getFontInfo(
        effectiveLang,
        isSerif: false,
        isBold: false,
        isItalic: false,
      );
      // 如果用户配置了 sans 字体就用，否则保留 null（系统会选择 Monospace）
      fontFamily = fontInfo?.fontFamily ?? 'Monospace';
    } else {
      final effectiveBold =
          isBold ||
          (fontWeightOverride ?? m?.fontWeight) == FontWeight.bold ||
          (fontWeightOverride ?? m?.fontWeight) == FontWeight.w700 ||
          (fontWeightOverride ?? m?.fontWeight) == FontWeight.w800 ||
          (fontWeightOverride ?? m?.fontWeight) == FontWeight.w900;
      final effectiveItalic =
          isItalic || (fontStyleOverride ?? m?.fontStyle) == FontStyle.italic;

      final fontService = FontLoaderService();
      final fontInfo = fontService.getFontInfo(
        effectiveLang,
        isSerif: serif,
        isBold: effectiveBold,
        isItalic: effectiveItalic,
      );
      fontFamily = fontInfo?.fontFamily;
    }

    // ── 2. 字体缩放 ───────────────────────────────────────────────────────
    // 缩放键：衬线用 'serif'，非衬线（含等宽）用 'sans'
    final scaleKey = serif ? 'serif' : 'sans';
    final scale = fontScales[effectiveLang]?[scaleKey] ?? 1.0;
    final scaledSize = (m?.baseFontSize ?? 14.0) * scale;

    return TextStyle(
      fontFamily: fontFamily,
      fontSize: scaledSize,
      fontWeight: fontWeightOverride ?? m?.fontWeight,
      fontStyle: fontStyleOverride ?? m?.fontStyle,
      color: color,
      height: m?.lineHeight,
      letterSpacing: m?.letterSpacing,
    );
  }

  /// 仅返回用户缩放比例（不含字体信息），供需要手动缩放图标/间距的场景使用。
  static double getScale(
    DictElementType type, {
    required String? language,
    required Map<String, Map<String, double>> fontScales,
  }) {
    final serif = isSerif(type);
    final effectiveLang = language ?? 'en';
    final scaleKey = serif ? 'serif' : 'sans';
    return fontScales[effectiveLang]?[scaleKey] ?? 1.0;
  }
}
