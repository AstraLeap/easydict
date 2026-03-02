class LanguageUtils {
  /// 使用字母文字（拉丁、西里尔、阿拉伯等拼音字母书写系统）的语言代码集合。
  ///
  /// 这些语言使用字母（每个字母代表一个音素），在小字号时视觉上偏小，
  /// 建议默认放大 1.15 倍以改善可读性。
  ///
  /// 注意：日语（ja）和韩语（ko）虽属表音系统，但使用非字母文字
  /// （假名/谚文），与CJK汉字在视觉尺寸上接近，不在此列。
  static const Set<String> phoneticScriptLanguages = {
    'en',
    'fr',
    'de',
    'es',
    'it',
    'ru',
    'pt',
    'ar',
  };

  /// 未设置字体缩放倍率时的默认值。
  ///
  /// 字母文字语言（拉丁/西里尔/阿拉伯）返回 1.15；
  static double getDefaultFontScale(String? langCode) {
    if (langCode == null) return 1.0;
    return phoneticScriptLanguages.contains(langCode.toLowerCase()) ? 1.1 : 1.0;
  }

  static String getLanguageDisplayName(String langCode) {
    if (langCode == 'auto') return '自动';

    final languageNames = {
      'en': '英语',
      'zh': '中文',
      'ja': '日语',
      'ko': '韩语',
      'fr': '法语',
      'de': '德语',
      'es': '西班牙语',
      'it': '意大利语',
      'ru': '俄语',
      'pt': '葡萄牙语',
      'ar': '阿拉伯语',
      'text': '文本',
    };
    return languageNames[langCode.toLowerCase()] ?? langCode.toUpperCase();
  }
}
