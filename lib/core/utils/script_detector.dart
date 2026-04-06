/// Unicode 字符范围检测和语言检测工具类。
///
/// 根据字符的 Unicode 代码点判断其所属的语言/文字系统，
/// 用于渲染时自动选择合适的字体。
library;

/// 各语言文字的 Unicode 范围定义。
class ScriptRanges {
  /// 中文 CJK 字符（基本区、扩展A、兼容区、部首、标点）。
  static bool isCJK(int cu) =>
      (cu >= 0x4E00 && cu <= 0x9FFF) || // CJK 基本区
      (cu >= 0x3400 && cu <= 0x4DBF) || // CJK 扩展A
      (cu >= 0xF900 && cu <= 0xFAFF) || // CJK 兼容区
      (cu >= 0x2E80 && cu <= 0x2EFF) || // CJK 部首拓展
      (cu >= 0x3000 && cu <= 0x303F); // CJK 标点符号

  /// 日文平假名。
  static bool isHiragana(int cu) => cu >= 0x3040 && cu <= 0x309F;

  /// 日文片假名。
  static bool isKatakana(int cu) => cu >= 0x30A0 && cu <= 0x30FF;

  /// 日文（平假名或片假名）。
  static bool isJapanese(int cu) => isHiragana(cu) || isKatakana(cu);

  /// 韩文谚文。
  static bool isHangul(int cu) =>
      (cu >= 0xAC00 && cu <= 0xD7AF) || // 谚文音节
      (cu >= 0x1100 && cu <= 0x11FF); // 谚文兼容字母

  /// 阿拉伯文。
  static bool isArabic(int cu) =>
      (cu >= 0x0600 && cu <= 0x06FF) || // 阿拉伯文基本区
      (cu >= 0x0750 && cu <= 0x077F); // 阿拉伯文补充

  /// 西里尔文（俄语等）。
  static bool isCyrillic(int cu) =>
      (cu >= 0x0400 && cu <= 0x04FF) || // 西里尔文基本区
      (cu >= 0x0500 && cu <= 0x052F); // 西里尔文补充

  /// 拉丁字母（含扩展拉丁）。
  static bool isLatin(int cu) =>
      (cu >= 0x0041 && cu <= 0x005A) || // A-Z
      (cu >= 0x0061 && cu <= 0x007A) || // a-z
      (cu >= 0x00C0 && cu <= 0x00FF) || // 拉丁扩展A（部分）
      (cu >= 0x0100 && cu <= 0x017F) || // 拉丁扩展A
      (cu >= 0x0180 && cu <= 0x024F); // 拉丁扩展B

  /// ASCII 标点符号。
  static bool isASCIIPunctuation(int cu) =>
      (cu >= 0x0021 && cu <= 0x002F) || // !"#$%&'()*+,-./
      (cu >= 0x003A && cu <= 0x0040) || // :;<=>?@
      (cu >= 0x005B && cu <= 0x0060) || // [\]^_`
      (cu >= 0x007B && cu <= 0x007E); // {|}~

  /// CJK 标点符号和全角字符。
  static bool isCJKPunctuation(int cu) =>
      (cu >= 0x3000 && cu <= 0x303F) || // CJK 标点符号
      (cu >= 0xFF00 && cu <= 0xFFEF); // 全角字符

  /// 通用标点符号。
  static bool isGeneralPunctuation(int cu) =>
      (cu >= 0x2000 && cu <= 0x206F); // 通用标点（含空格、破折号等）

  /// 判断字符是否为标点符号。
  ///
  /// 包括 ASCII 标点、CJK 标点、全角字符、通用标点。
  static bool isPunctuation(int cu) =>
      isASCIIPunctuation(cu) ||
      isCJKPunctuation(cu) ||
      isGeneralPunctuation(cu) ||
      cu == 0x0020 || // 空格
      cu == 0x00A0; // 不换行空格

  /// 数字字符。
  static bool isDigit(int cu) => cu >= 0x0030 && cu <= 0x0039;

  /// 空白字符。
  static bool isWhitespace(int cu) =>
      cu == 0x0020 || // 空格
      cu == 0x0009 || // 制表符
      cu == 0x000A || // 换行符
      cu == 0x000D || // 回车符
      cu == 0x00A0 || // 不换行空格
      cu == 0x3000; // 全角空格

  // 私有构造函数，防止实例化
  ScriptRanges._();
}

/// 语言检测器。
///
/// 根据字符串中的字符 Unicode 范围检测其主要使用的语言。
class ScriptDetector {
  /// 检测字符串中主要使用的语言代码。
  ///
  /// 返回出现次数最多的非 [sourceLanguage] 语言，
  /// 如果只有 sourceLanguage 的字符或没有可识别字符，则返回 [sourceLanguage]。
  ///
  /// 例如：
  /// - sourceLanguage='en'，text="这是中文" → 'zh'
  /// - sourceLanguage='zh'，text="English text" → 'en'
  /// - sourceLanguage='en'，text="这是中文 and English" → 'zh'（中文占比最高）
  static String detectLanguage(String text, String sourceLanguage) {
    if (text.isEmpty) return sourceLanguage;

    final counts = <String, int>{};
    final sourceLang = _normalizeLanguage(sourceLanguage);

    for (final cu in text.codeUnits) {
      // 跳过标点、空白和数字
      if (ScriptRanges.isPunctuation(cu) ||
          ScriptRanges.isWhitespace(cu) ||
          ScriptRanges.isDigit(cu)) {
        continue;
      }

      final lang = _detectCharLanguage(cu);
      if (lang != null) {
        counts[lang] = (counts[lang] ?? 0) + 1;
      }
    }

    // 如果没有检测到任何语言字符，返回 sourceLanguage
    if (counts.isEmpty) return sourceLanguage;

    // 找出非 sourceLanguage 的语言中计数最高的
    String? detectedLang;
    int maxCount = 0;
    for (final entry in counts.entries) {
      if (entry.key != sourceLang && entry.value > maxCount) {
        maxCount = entry.value;
        detectedLang = entry.key;
      }
    }

    // 如果没有非 sourceLanguage 的语言，检查是否主要是 sourceLanguage
    if (detectedLang == null) {
      final sourceCount = counts[sourceLang] ?? 0;
      if (sourceCount > 0) {
        return sourceLanguage;
      }
      // 如果连 sourceLanguage 的字符都没有，返回计数最高的语言
      for (final entry in counts.entries) {
        if (entry.value > maxCount) {
          maxCount = entry.value;
          detectedLang = entry.key;
        }
      }
    }

    return detectedLang ?? sourceLanguage;
  }

  /// 检测字符串中包含的所有语言。
  static Set<String> detectLanguages(String text) {
    final languages = <String>{};

    for (final cu in text.codeUnits) {
      if (ScriptRanges.isPunctuation(cu) ||
          ScriptRanges.isWhitespace(cu) ||
          ScriptRanges.isDigit(cu)) {
        continue;
      }

      final lang = _detectCharLanguage(cu);
      if (lang != null) {
        languages.add(lang);
      }
    }

    return languages;
  }

  /// 检测单个字符所属的语言代码。
  ///
  /// 返回语言代码（'zh', 'jp', 'ko', 'ar', 'ru', 'en'）或 null（无法识别）。
  ///
  /// 注意：
  /// - 中文字符返回 'zh'
  /// - 日文假名返回 'jp'
  /// - CJK 汉字也被识别为中文，但日文词典中也会包含汉字
  /// - 拉丁字母返回 'en'（适用于英语和其他使用拉丁字母的语言）
  static String? detectCharLanguage(int codeUnit) {
    return _detectCharLanguage(codeUnit);
  }

  static String? _detectCharLanguage(int cu) {
    // 注意：日文假名必须在 CJK 之前检查，因为假名不属于 CJK 范围
    if (ScriptRanges.isJapanese(cu)) return 'jp';
    // CJK 汉字（包括中日韩统一表意文字）
    if (ScriptRanges.isCJK(cu)) return 'zh';
    if (ScriptRanges.isHangul(cu)) return 'ko';
    if (ScriptRanges.isArabic(cu)) return 'ar';
    if (ScriptRanges.isCyrillic(cu)) return 'ru';
    if (ScriptRanges.isLatin(cu)) return 'en';
    return null;
  }

  /// 标准化语言代码（小写，去除地区子标签）。
  static String _normalizeLanguage(String lang) {
    return lang.toLowerCase().split('-').first;
  }

  // 私有构造函数，防止实例化
  ScriptDetector._();
}
