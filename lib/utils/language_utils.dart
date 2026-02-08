class LanguageUtils {
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
    };
    return languageNames[langCode.toLowerCase()] ?? langCode.toUpperCase();
  }
}
