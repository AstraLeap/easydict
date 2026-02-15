import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preferences_service.dart';
import '../logger.dart';

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
  // 缓存词典内容缩放，避免重复异步读取
  double _cachedDictionaryContentScale = 1.0;

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

  /// 刷新字体缩放配置缓存
  Future<void> reloadFontScales() async {
    await _loadFontScales();
  }

  /// 加载词典内容缩放到缓存
  Future<void> _loadDictionaryContentScale() async {
    final prefs = PreferencesService();
    _cachedDictionaryContentScale = await prefs.getDictionaryContentScale();
    Logger.i('词典内容缩放已加载: $_cachedDictionaryContentScale', tag: 'FontLoader');
  }

  /// 同步获取词典内容缩放，避免异步加载导致的闪烁问题
  double getDictionaryContentScale() {
    return _cachedDictionaryContentScale;
  }

  /// 刷新词典内容缩放缓存
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
            Logger.i('准备加载字体: language=$language, fontType=$fontType, path=$fontPath', tag: 'FontLoader');
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
      Logger.i('字体加载成功: $fontKey -> $fontPath', tag: 'FontLoader');
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

    final fontKey = '${language}_$fontType';
    if (_loadedFonts[fontKey] == true) {
      return FontInfo(
        fontFamily: _getFontFamilyName(language, fontType),
        fontWeight: _getFontWeight(fontType),
        fontStyle: _getFontStyle(fontType),
        fontPath: _fontPaths[fontKey] ?? '',
      );
    }

    // 回退逻辑：尝试找到同类型的其他可用字体
    final fallbackFontType = _findFallbackFontType(language, isSerif: isSerif);
    if (fallbackFontType != null) {
      final fallbackKey = '${language}_$fallbackFontType';
      Logger.d(
        '字体回退: 请求 $fontKey -> 使用 $fallbackKey',
        tag: 'FontLoader',
      );
      return FontInfo(
        fontFamily: _getFontFamilyName(language, fallbackFontType),
        fontWeight: _getFontWeight(fallbackFontType),
        fontStyle: _getFontStyle(fallbackFontType),
        fontPath: _fontPaths[fallbackKey] ?? '',
      );
    }

    return null;
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
