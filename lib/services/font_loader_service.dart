import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preferences_service.dart';
import '../core/logger.dart';

class FontInfo {
  final String fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String fontPath;

  FontInfo({
    required this.fontFamily,
    required this.fontWeight,
    required this.fontStyle,
    required this.fontPath,
  });
}

class FontLoaderService {
  static final FontLoaderService _instance = FontLoaderService._internal();
  factory FontLoaderService() => _instance;
  FontLoaderService._internal();

  final Map<String, bool> _loadedFonts = {};
  final Map<String, String> _fontPaths = {};
  bool _isInitialized = false;

  // 缓存字体缩放配置，避免重复异步读取
  Map<String, Map<String, double>> _cachedFontScales = {};
  // 缓存软件布局缩放，避免重复异步读取
  double _cachedDictionaryContentScale = 1.0;

  /// 全局软件布局缩放通知器，用于通知所有监听者缩放值的变化
  final ValueNotifier<double> dictionaryContentScaleNotifier = ValueNotifier(
    1.0,
  );

  static const List<String> _serifTypes = [
    'serif_regular',
    'serif_bold',
    'serif_italic',
    'serif_bold_italic',
  ];

  static const List<String> _sansTypes = [
    'sans_regular',
    'sans_bold',
    'sans_italic',
    'sans_bold_italic',
  ];

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await loadAllCustomFonts();
    await _loadFontScales();
    await _loadDictionaryContentScale();
  }

  /// 加载字体缩放配置到缓存
  Future<void> _loadFontScales() async {
    final prefs = PreferencesService();
    _cachedFontScales = await prefs.getAllFontScales();
    Logger.i('字体缩放配置已加载: $_cachedFontScales', tag: 'FontLoader');
  }

  /// 同步获取字体缩放配置，避免异步加载导致的闪烁问题
  Map<String, Map<String, double>> getFontScales() {
    return _cachedFontScales;
  }

  /// 解析指定语言的字体缩放值。
  ///
  /// 对 "zh" 等存在子分组的语言，按候选顺序（zh-hans → zh-hant → zh）查找；
  /// 找不到时返回 null。
  double? resolveFontScale(String language, {required bool isSerif}) {
    final candidates = _getLanguageCandidates(language);
    final key = isSerif ? 'serif' : 'sans';
    for (final lang in candidates) {
      final scale = _cachedFontScales[lang]?[key];
      if (scale != null) return scale;
    }
    return null;
  }

  /// 刷新字体缩放配置缓存
  Future<void> reloadFontScales() async {
    await _loadFontScales();
  }

  /// 加载软件布局缩放到缓存
  Future<void> _loadDictionaryContentScale() async {
    final prefs = PreferencesService();
    _cachedDictionaryContentScale = await prefs.getDictionaryContentScale();
    dictionaryContentScaleNotifier.value = _cachedDictionaryContentScale;
    Logger.i('软件布局缩放已加载: $_cachedDictionaryContentScale', tag: 'FontLoader');
  }

  /// 同步获取软件布局缩放，避免异步加载导致的闪烁问题
  double getDictionaryContentScale() {
    return _cachedDictionaryContentScale;
  }

  /// 立即同步更新缩放缓存并广播（用于快捷键即时调整，调用方负责持久化）
  void setContentScaleImmediate(double scale) {
    _cachedDictionaryContentScale = scale;
    dictionaryContentScaleNotifier.value = scale;
  }

  /// 刷新软件布局缩放缓存
  Future<void> reloadDictionaryContentScale() async {
    await _loadDictionaryContentScale();
  }

  Future<void> loadAllCustomFonts() async {
    try {
      final prefs = PreferencesService();
      final fontConfigs = await prefs.getFontConfigs();

      Logger.i('开始加载自定义字体, 语言数量: ${fontConfigs.length}', tag: 'FontLoader');

      if (fontConfigs.isEmpty) {
        Logger.w('没有找到任何字体配置', tag: 'FontLoader');
      }

      for (final langEntry in fontConfigs.entries) {
        final language = langEntry.key;
        final configs = langEntry.value;
        Logger.i('语言: $language, 配置: $configs', tag: 'FontLoader');

        for (final fontTypeEntry in configs.entries) {
          final fontType = fontTypeEntry.key;
          final fontPath = fontTypeEntry.value;

          if (fontPath.isNotEmpty) {
            await _loadFont(language, fontType, fontPath);
          }
        }
      }

      final loadedFonts = getAllAvailableFonts();
      Logger.i('自定义字体加载完成, 已加载: $loadedFonts', tag: 'FontLoader');
    } catch (e, stack) {
      Logger.e('加载自定义字体失败: $e, stack: $stack', tag: 'FontLoader');
    }
  }

  Future<void> _loadFont(
    String language,
    String fontType,
    String fontPath,
  ) async {
    final fontKey = '${language}_$fontType';
    if (_loadedFonts[fontKey] == true) return;

    try {
      final file = File(fontPath);
      if (!await file.exists()) {
        Logger.w('字体文件不存在: $fontPath', tag: 'FontLoader');
        return;
      }

      final bytes = await file.readAsBytes();
      final fontLoader = FontLoader(_getFontFamilyName(language, fontType));
      fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await fontLoader.load();

      _loadedFonts[fontKey] = true;
      _fontPaths[fontKey] = fontPath;
    } catch (e) {
      Logger.e('加载字体失败 $fontPath: $e', tag: 'FontLoader');
    }
  }

  String _getFontFamilyName(String language, String fontType) {
    return 'Custom_${language}_$fontType';
  }

  FontWeight _getFontWeight(String fontType) {
    if (fontType.contains('bold')) {
      return FontWeight.bold;
    }
    return FontWeight.normal;
  }

  FontStyle _getFontStyle(String fontType) {
    if (fontType.contains('italic')) {
      return FontStyle.italic;
    }
    return FontStyle.normal;
  }

  String? getCustomFontFamily(String language, String fontType) {
    final fontKey = '${language}_$fontType';
    if (_loadedFonts[fontKey] == true) {
      return _getFontFamilyName(language, fontType);
    }
    return null;
  }

  FontInfo? getFontInfo(
    String language, {
    bool isSerif = true,
    bool isBold = false,
    bool isItalic = false,
  }) {
    String fontType;
    if (isSerif) {
      fontType = isBold
          ? (isItalic ? 'serif_bold_italic' : 'serif_bold')
          : (isItalic ? 'serif_italic' : 'serif_regular');
    } else {
      fontType = isBold
          ? (isItalic ? 'sans_bold_italic' : 'sans_bold')
          : (isItalic ? 'sans_italic' : 'sans_regular');
    }

    // 查找顺序：原始 language key → 语言扩展候选 key（如 zh → zh-hans → zh-hant）
    final candidates = _getLanguageCandidates(language);
    for (final lang in candidates) {
      final fontKey = '${lang}_$fontType';
      if (_loadedFonts[fontKey] == true) {
        return FontInfo(
          fontFamily: _getFontFamilyName(lang, fontType),
          fontWeight: _getFontWeight(fontType),
          fontStyle: _getFontStyle(fontType),
          fontPath: _fontPaths[fontKey] ?? '',
        );
      }
    }

    // 回退逻辑：尝试找到同类型的其他可用字体（对每个候选语言）
    for (final lang in candidates) {
      final fallbackFontType = _findFallbackFontType(lang, isSerif: isSerif);
      if (fallbackFontType != null) {
        final fallbackKey = '${lang}_$fallbackFontType';
        return FontInfo(
          fontFamily: _getFontFamilyName(lang, fallbackFontType),
          fontWeight: _getFontWeight(fallbackFontType),
          fontStyle: _getFontStyle(fallbackFontType),
          fontPath: _fontPaths[fallbackKey] ?? '',
        );
      }
    }

    // 最终回退：使用内置 bundled 字体（SourceSerif4 / SourceSans3）
    return _getBundledFontInfo(isSerif: isSerif, isItalic: isItalic);
  }

  /// 返回查找字体时的候选语言代码列表（按优先级从高到低）。
  ///
  /// 对于 "zh"：先尝试 zh-hans（简体），再尝试 zh-hant（繁体），最后 zh 本身。
  /// 其他语言：仅自身。
  /// 将语言代码映射为字体查找候选列表（按优先级排列）。
  ///
  /// 规则：
  ///   zh / zh-hans          → ['zh-hans']      简体中文字体
  ///   zh-hant / zh-hk 等繁体 → ['zh-hant']      繁体中文字体
  ///   其他语言               → [小写基础代码]
  ///
  /// 当最优候选无字体时，调用方的循环会依次尝试后续候选。
  static List<String> _getLanguageCandidates(String language) {
    final lower = language.toLowerCase();
    // 处理所有中文变体
    if (lower == 'zh' || lower == 'zh-hans') return ['zh-hans'];
    if (lower == 'zh-hant' ||
        lower == 'zh-hk' ||
        lower == 'zh-tw' ||
        lower == 'zh-mo') {
      return ['zh-hant'];
    }
    // 带子标签的中文（如 zh-sg 等未明确分类的）默认简体
    if (lower.startsWith('zh-')) return ['zh-hans', 'zh-hant'];
    // 其他语言：取基础语言代码（去除地区子标签）
    final base = lower.contains('-')
        ? lower.substring(0, lower.indexOf('-'))
        : lower;
    return [base];
  }

  /// 返回内置 bundled 字体信息（SourceSerif4 衬线 / SourceSans3 非衬线）
  FontInfo _getBundledFontInfo({
    required bool isSerif,
    required bool isItalic,
  }) {
    return FontInfo(
      fontFamily: isSerif ? 'SourceSerif4' : 'SourceSans3',
      fontWeight: FontWeight.normal,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      fontPath: '',
    );
  }

  /// 获取统一的字体回退链，用于 AI 聊天等需要统一字体排序的场景。
  ///
  /// 排序规则：
  /// 1. 大框架：英文字体 → 中文字体 → 日文字体 → 韩文字体 → 其他语言字体
  /// 2. 每个语言内部：用户自定义字体 → 系统默认字体（SourceSans3/SourceSerif4）
  ///
  /// [isSerif] 是否使用衬线字体
  /// [isItalic] 是否使用斜体
  List<String> getUnifiedFontFallbackChain({
    bool isSerif = false,
    bool isItalic = false,
  }) {
    final chain = <String>[];
    final addedFonts = <String>{};

    String fontType;
    if (isSerif) {
      fontType = isItalic ? 'serif_italic' : 'serif_regular';
    } else {
      fontType = isItalic ? 'sans_italic' : 'sans_regular';
    }

    final bundledFont = isSerif ? 'SourceSerif4' : 'SourceSans3';

    void addFontIfExists(String language) {
      final fontKey = '${language}_$fontType';
      if (_loadedFonts[fontKey] == true) {
        final fontFamily = _getFontFamilyName(language, fontType);
        if (!addedFonts.contains(fontFamily)) {
          chain.add(fontFamily);
          addedFonts.add(fontFamily);
        }
      }
    }

    final languageOrder = [
      'en',
      'zh-hans',
      'zh-hant',
      'jp',
      'ko',
      'fr',
      'de',
      'es',
      'it',
      'ru',
      'pt',
      'ar',
    ];

    for (final lang in languageOrder) {
      addFontIfExists(lang);
    }

    final allFonts = getAllAvailableFonts();
    for (final lang in allFonts.keys) {
      if (!languageOrder.contains(lang)) {
        addFontIfExists(lang);
      }
    }

    if (!addedFonts.contains(bundledFont)) {
      chain.add(bundledFont);
    }

    return chain;
  }

  String? _findFallbackFontType(String language, {required bool isSerif}) {
    final types = isSerif ? _serifTypes : _sansTypes;
    for (final type in types) {
      final fontKey = '${language}_$type';
      if (_loadedFonts[fontKey] == true) {
        return type;
      }
    }
    return null;
  }

  List<String> getAvailableFontTypes(String language, {bool isSerif = true}) {
    final types = isSerif ? _serifTypes : _sansTypes;
    final available = <String>[];
    for (final type in types) {
      final fontKey = '${language}_$type';
      if (_loadedFonts[fontKey] == true) {
        available.add(type);
      }
    }
    return available;
  }

  Map<String, List<String>> getAllAvailableFonts() {
    final result = <String, List<String>>{};
    for (final entry in _loadedFonts.entries) {
      if (entry.value) {
        final parts = entry.key.split('_');
        if (parts.length >= 2) {
          final language = parts[0];
          result[language] ??= [];
          result[language]!.add(entry.key);
        }
      }
    }
    return result;
  }

  Future<void> reloadFonts() async {
    _loadedFonts.clear();
    _isInitialized = false;
    await initialize();
  }
}
