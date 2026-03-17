import 'package:shared_preferences/shared_preferences.dart';

/// 语言默认搜索选项配置
class LanguageDefaultSearchOptions {
  final bool exactMatch;

  const LanguageDefaultSearchOptions({
    this.exactMatch = false,
  });

  Map<String, dynamic> toJson() => {
    'exactMatch': exactMatch,
  };

  factory LanguageDefaultSearchOptions.fromJson(Map<String, dynamic> json) {
    return LanguageDefaultSearchOptions(
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

  static const String _exactMatchKey = 'advanced_search_exact_match';
  static const String _biaoyiExactMatchKey =
      'advanced_search_biaoyi_exact_match';
  static const String _lastSelectedGroupKey = 'last_selected_group';
  static const String _languageDefaultOptionsKey = 'language_default_options';
  static const String _languageOrderKey = 'language_display_order';

  /// 语言顺序缓存
  static List<String> _languageOrderCache = [];
  static bool _languageOrderCacheLoaded = false;

  /// 各语言默认搜索选项
  /// 英语: 关闭通配符搜索, 关闭区分大小写 (exactMatch = false)
  /// 其他语言可以根据需要配置
  static const Map<String, LanguageDefaultSearchOptions>
  _defaultOptionsByLanguage = {
    'en': LanguageDefaultSearchOptions(exactMatch: false),
    'zh': LanguageDefaultSearchOptions(exactMatch: false),
    'ja': LanguageDefaultSearchOptions(exactMatch: false),
    'ko': LanguageDefaultSearchOptions(exactMatch: false),
    'fr': LanguageDefaultSearchOptions(exactMatch: false),
    'de': LanguageDefaultSearchOptions(exactMatch: false),
    'es': LanguageDefaultSearchOptions(exactMatch: false),
    'it': LanguageDefaultSearchOptions(exactMatch: false),
    'ru': LanguageDefaultSearchOptions(exactMatch: false),
    'pt': LanguageDefaultSearchOptions(exactMatch: false),
    'ar': LanguageDefaultSearchOptions(exactMatch: false),
  };

  /// 加载所有高级搜索设置
  Future<Map<String, bool>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'exactMatch': prefs.getBool(_exactMatchKey) ?? false,
      'biaoyiExactMatch': prefs.getBool(_biaoyiExactMatchKey) ?? false,
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

  /// 获取保存的语言显示顺序
  Future<List<String>?> getLanguageOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_languageOrderKey);
  }

  /// 保存语言显示顺序
  Future<void> setLanguageOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_languageOrderKey, order);
    // 更新缓存
    _languageOrderCache = order;
    _languageOrderCacheLoaded = true;
  }

  /// 同步获取语言显示顺序（从缓存获取）
  /// 如果缓存未加载，返回空列表
  List<String> getLanguageOrderSync() {
    if (_languageOrderCacheLoaded) {
      return _languageOrderCache;
    }
    return [];
  }

  /// 加载语言顺序到缓存
  Future<void> loadLanguageOrderToCache() async {
    final order = await getLanguageOrder();
    _languageOrderCache = order ?? [];
    _languageOrderCacheLoaded = true;
  }

  /// 按照已保存的语言顺序对语言列表进行排序。
  ///
  /// 已保存顺序中的语言按顺序排列，未在保存顺序中的语言排在后面（保持字母排序）。
  static List<String> sortLanguagesByOrder(
    List<String> languages,
    List<String>? savedOrder,
  ) {
    if (savedOrder == null || savedOrder.isEmpty) return languages;
    return [...languages]..sort((a, b) {
      final ia = savedOrder.indexOf(a);
      final ib = savedOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });
  }

  /// 保存精确搜索设置（已废弃，请使用 setExactMatchForLanguage）
  @deprecated
  Future<void> setExactMatch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exactMatchKey, value);
  }

  /// 保存简繁区分设置（已废弃，请使用 setExactMatchForLanguage）
  @deprecated
  Future<void> setBiaoyiExactMatch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biaoyiExactMatchKey, value);
  }

  /// 获取指定语言的精确搜索设置
  /// [language] 语言代码，如 'en', 'zh', 'ja' 等
  Future<bool> getExactMatchForLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = language.toLowerCase();
    final key = 'exact_match_$langCode';
    return prefs.getBool(key) ?? false;
  }

  /// 保存指定语言的精确搜索设置
  Future<void> setExactMatchForLanguage(String language, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = language.toLowerCase();
    final key = 'exact_match_$langCode';
    await prefs.setBool(key, value);
  }

  /// 批量获取所有语言的精确搜索设置
  /// 返回 Map<语言代码, 精确搜索设置>
  Future<Map<String, bool>> getAllExactMatchSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, bool>{};
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('exact_match_')) {
        final langCode = key.substring('exact_match_'.length);
        final value = prefs.getBool(key);
        if (value != null) {
          result[langCode] = value;
        }
      }
    }
    return result;
  }

  /// 获取指定语言的默认搜索选项
  /// [language] 语言代码，如 'en', 'zh', 'ja' 等
  /// 如果没有自定义配置，返回内置的默认配置
  LanguageDefaultSearchOptions getDefaultOptionsForLanguage(String? language) {
    if (language == null || language.isEmpty || language == 'auto') {
      return const LanguageDefaultSearchOptions();
    }

    final langCode = language.toLowerCase();
    return _defaultOptionsByLanguage[langCode] ??
        const LanguageDefaultSearchOptions();
  }

  /// 获取指定语言的默认搜索选项（异步版本，支持从存储加载自定义配置）
  Future<LanguageDefaultSearchOptions> getDefaultOptionsForLanguageAsync(
    String? language,
  ) async {
    if (language == null || language.isEmpty || language == 'auto') {
      return const LanguageDefaultSearchOptions();
    }

    final langCode = language.toLowerCase();

    // 首先检查是否有用户自定义配置
    final prefs = await SharedPreferences.getInstance();
    final customOptionsJson = prefs.getString(
      '${_languageDefaultOptionsKey}_$langCode',
    );

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
    return _defaultOptionsByLanguage[langCode] ??
        const LanguageDefaultSearchOptions();
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
    if (jsonStr.endsWith('}'))
      jsonStr = jsonStr.substring(0, jsonStr.length - 1);

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
