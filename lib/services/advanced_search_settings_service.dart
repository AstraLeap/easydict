import 'package:shared_preferences/shared_preferences.dart';

/// 高级搜索设置服务
class AdvancedSearchSettingsService {
  static final AdvancedSearchSettingsService _instance =
      AdvancedSearchSettingsService._internal();
  factory AdvancedSearchSettingsService() => _instance;
  AdvancedSearchSettingsService._internal();

  static const String _useFuzzySearchKey = 'advanced_search_use_fuzzy';
  static const String _exactMatchKey = 'advanced_search_exact_match';
  static const String _lastSelectedGroupKey = 'last_selected_group';

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
}
