import 'package:shared_preferences/shared_preferences.dart';

/// 语言默认搜索选项配置
class LanguageDefaultSearchOptions {
  final bool useFuzzySearch;
  final bool exactMatch;

  const LanguageDefaultSearchOptions({
    this.useFuzzySearch = false,
    this.exactMatch = false,
  });

  Map<String, dynamic> toJson() => {
    'useFuzzySearch': useFuzzySearch,
    'exactMatch': exactMatch,
  };

  factory LanguageDefaultSearchOptions.fromJson(Map<String, dynamic> json) {
    return LanguageDefaultSearchOptions(
      useFuzzySearch: json['useFuzzySearch'] ?? false,
      exactMatch: json['exactMatch'] ?? false,
    );
  }
}

/// 高级搜索设置服务
class AdvancedSearchSettingsService {
  static final AdvancedSearchSettingsService _instance =
      AdvancedSearchSettingsService._internal();
  factory AdvancedSearchSettingsService() => _instance;
  AdvancedSearchSettingsService._internal();

  static const String _useFuzzySearchKey = 'advanced_search_use_fuzzy';
  static const String _exactMatchKey = 'advanced_search_exact_match';
  static const String _lastSelectedGroupKey = 'last_selected_group';
  static const String _languageDefaultOptionsKey = 'language_default_options';

  /// 各语言默认搜索选项
  /// 英语: 关闭通配符搜索, 关闭区分大小写 (exactMatch = false)
  /// 其他语言可以根据需要配置
  static const Map<String, LanguageDefaultSearchOptions> _defaultOptionsByLanguage = {
    'en': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'zh': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'ja': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'ko': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'fr': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'de': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'es': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'it': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'ru': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'pt': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
    'ar': LanguageDefaultSearchOptions(useFuzzySearch: false, exactMatch: false),
  };

  /// 加载所有高级搜索设置
  Future<Map<String, bool>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'useFuzzySearch': prefs.getBool(_useFuzzySearchKey) ?? false,
      'exactMatch': prefs.getBool(_exactMatchKey) ?? false,
    };
  }

  /// 获取上次选择的语言分组
  Future<String?> getLastSelectedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSelectedGroupKey);
  }

  /// 保存选择的语言分组
  Future<void> setLastSelectedGroup(String group) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSelectedGroupKey, group);
  }

  /// 保存模糊搜索设置
  Future<void> setUseFuzzySearch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFuzzySearchKey, value);
  }

  /// 保存精确搜索设置
  Future<void> setExactMatch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exactMatchKey, value);
  }

  /// 获取指定语言的默认搜索选项
  /// [language] 语言代码，如 'en', 'zh', 'ja' 等
  /// 如果没有自定义配置，返回内置的默认配置
  LanguageDefaultSearchOptions getDefaultOptionsForLanguage(String? language) {
    if (language == null || language.isEmpty || language == 'auto') {
      return const LanguageDefaultSearchOptions();
    }
    
    final langCode = language.toLowerCase();
    return _defaultOptionsByLanguage[langCode] ?? const LanguageDefaultSearchOptions();
  }

  /// 获取指定语言的默认搜索选项（异步版本，支持从存储加载自定义配置）
  Future<LanguageDefaultSearchOptions> getDefaultOptionsForLanguageAsync(String? language) async {
    if (language == null || language.isEmpty || language == 'auto') {
      return const LanguageDefaultSearchOptions();
    }

    final langCode = language.toLowerCase();
    
    // 首先检查是否有用户自定义配置
    final prefs = await SharedPreferences.getInstance();
    final customOptionsJson = prefs.getString('${_languageDefaultOptionsKey}_$langCode');
    
    if (customOptionsJson != null) {
      try {
        // 解析自定义配置
        final Map<String, dynamic> json = _parseJson(customOptionsJson);
        return LanguageDefaultSearchOptions.fromJson(json);
      } catch (e) {
        // 解析失败，使用默认配置
      }
    }
    
    // 使用内置默认配置
    return _defaultOptionsByLanguage[langCode] ?? const LanguageDefaultSearchOptions();
  }

  /// 保存指定语言的默认搜索选项
  Future<void> setDefaultOptionsForLanguage(
    String language,
    LanguageDefaultSearchOptions options,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = language.toLowerCase();
    await prefs.setString(
      '${_languageDefaultOptionsKey}_$langCode',
      _encodeJson(options.toJson()),
    );
  }

  /// 简单的 JSON 解析
  Map<String, dynamic> _parseJson(String jsonStr) {
    // 移除花括号
    jsonStr = jsonStr.trim();
    if (jsonStr.startsWith('{')) jsonStr = jsonStr.substring(1);
    if (jsonStr.endsWith('}')) jsonStr = jsonStr.substring(0, jsonStr.length - 1);
    
    final result = <String, dynamic>{};
    if (jsonStr.isEmpty) return result;
    
    // 简单解析 key: value 对
    final pairs = jsonStr.split(',');
    for (final pair in pairs) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim().replaceAll('"', '').replaceAll("'", '');
        final value = parts[1].trim();
        if (value == 'true') {
          result[key] = true;
        } else if (value == 'false') {
          result[key] = false;
        } else {
          result[key] = value;
        }
      }
    }
    return result;
  }

  /// 简单的 JSON 编码
  String _encodeJson(Map<String, dynamic> json) {
    final pairs = json.entries.map((e) => '"${e.key}": ${e.value}').join(', ');
    return '{$pairs}';
  }
}
