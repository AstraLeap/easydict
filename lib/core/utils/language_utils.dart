import 'dart:ui';
import '../../i18n/strings.g.dart';

Locale? getFontLocale() {
  final currentLocale = LocaleSettings.currentLocale;
  if (currentLocale == AppLocale.zh) {
    return const Locale('zh', 'CN');
  }
  return null;
}

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

  /// 将语言代码规范化用于词典分组（前四处分组场合）：
  /// 先小写化，再去除地区子标签（横杠及其后面部分），
  /// 例如 "zh-Hans" → "zh"，"Zh-HK" → "zh"，"EN" → "en"。
  static String normalizeSourceLanguage(String langCode) {
    final lower = langCode.toLowerCase();
    final hyphenIdx = lower.indexOf('-');
    return hyphenIdx == -1 ? lower : lower.substring(0, hyphenIdx);
  }

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

  /// 获取语言代码的显示名称，支持带地区子标签的完整代码。
  /// 用于字体配置界面，可区分简繁中文及其他地区变体。
  ///
  /// 对中文的处理：
  ///   zh-hans → 中文（简体）
  ///   zh-hant / zh-hk / zh-tw / zh-mo → 中文（繁体）
  ///
  /// 其他语言：先在扩展表中查找，找不到则回退到 [getLanguageDisplayName]
  /// 以基础语言代码（去掉地区子标签后）查找。
  static String getLanguageDisplayNameExtended(String langCode) {
    const extendedNames = <String, String>{
      // 中文地区变体
      'zh-hans': '中文（简体）',
      'zh-hant': '中文（繁体）',
      'zh-hk': '中文（繁体）',
      'zh-tw': '中文（繁体）',
      'zh-mo': '中文（繁体）',
      // 其他常见地区变体——沿用基础语言名
      'en-us': '英语',
      'en-gb': '英语',
      'pt-br': '葡萄牙语',
      'pt-pt': '葡萄牙语',
      'es-419': '西班牙语',
    };

    final lower = langCode.toLowerCase();
    if (lower == 'auto') return '自动';
    final extended = extendedNames[lower];
    if (extended != null) return extended;
    // 回退：使用基础语言代码
    return getLanguageDisplayName(normalizeSourceLanguage(lower));
  }

  /// I18n-aware display name for a basic language code.
  /// Falls back to [getLanguageDisplayName] for unknown codes.
  static String getDisplayName(String langCode, Translations t) {
    final lc = langCode.toLowerCase();
    final ln = t.langNames;
    switch (lc) {
      case 'auto': return ln.auto;
      case 'en':   return ln.en;
      case 'zh':   return ln.zh;
      case 'ja':   return ln.ja;
      case 'ko':   return ln.ko;
      case 'fr':   return ln.fr;
      case 'de':   return ln.de;
      case 'es':   return ln.es;
      case 'it':   return ln.it;
      case 'ru':   return ln.ru;
      case 'pt':   return ln.pt;
      case 'ar':   return ln.ar;
      case 'text': return ln.text;
      default:     return langCode.toUpperCase();
    }
  }

  /// I18n-aware display name supporting extended codes (zh-hans, zh-hant …).
  static String getDisplayNameExtended(String langCode, Translations t) {
    final lower = langCode.toLowerCase();
    switch (lower) {
      case 'zh-hans': return t.langNames.zhHans;
      case 'zh-hant':
      case 'zh-hk':
      case 'zh-tw':
      case 'zh-mo': return t.langNames.zhHant;
      default: return getDisplayName(normalizeSourceLanguage(lower), t);
    }
  }
}
