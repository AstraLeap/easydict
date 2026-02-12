import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  static const String _kNavPanelPosition = 'nav_panel_position';
  static const String _kClickActionOrder = 'click_action_order';

  // 全局翻译显示/隐藏状态
  static const String _kGlobalTranslationVisibility =
      'global_translation_visibility';

  // 导航栏位置模型
  static const String navPositionLeft = 'left';
  static const String navPositionRight = 'right';

  Future<Map<String, double>> getNavPanelPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final position = prefs.getString(_kNavPanelPosition);
    final dy =
        prefs.getDouble('${_kNavPanelPosition}_dy') ?? 0.7; // 默认在屏幕高度 70% 处

    return {
      'isRight': (position != navPositionLeft) ? 1.0 : 0.0, // 默认右边
      'dy': dy,
    };
  }

  Future<void> setNavPanelPosition(bool isRight, double dy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kNavPanelPosition,
      isRight ? navPositionRight : navPositionLeft,
    );
    await prefs.setDouble('${_kNavPanelPosition}_dy', dy);
  }

  // 点击动作枚举值
  static const String actionAiTranslate = 'ai_translate';
  static const String actionCopy = 'copy';
  static const String actionAskAi = 'ask_ai';
  static const String actionEdit = 'edit';
  static const String actionSpeak = 'speak';

  static const List<String> defaultActionOrder = [
    actionAiTranslate,
    actionCopy,
    actionAskAi,
    actionEdit,
    actionSpeak,
  ];

  Future<List<String>> getClickActionOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getStringList(_kClickActionOrder);
    if (order == null || order.isEmpty) {
      return List.from(defaultActionOrder);
    }
    // 确保包含所有默认动作
    for (final action in defaultActionOrder) {
      if (!order.contains(action)) {
        order.add(action);
      }
    }
    return order;
  }

  Future<void> setClickActionOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kClickActionOrder, order);
  }

  Future<String> getClickAction() async {
    final order = await getClickActionOrder();
    return order.isNotEmpty ? order.first : actionAiTranslate;
  }

  /// 获取动作的中文标签
  static String getActionLabel(String action) {
    switch (action) {
      case actionAiTranslate:
        return '切换翻译';
      case actionCopy:
        return '复制文本';
      case actionAskAi:
        return '询问 AI';
      case actionEdit:
        return '编辑';
      case actionSpeak:
        return '朗读';
      default:
        return action;
    }
  }

  // ==================== 全局翻译显示/隐藏状态 ====================

  /// 获取全局翻译显示状态
  /// 返回 true 表示显示所有目标语言，false 表示隐藏所有目标语言
  /// 默认为 true（显示所有语言）
  Future<bool> getGlobalTranslationVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGlobalTranslationVisibility) ?? true;
  }

  /// 设置全局翻译显示状态
  /// [visible] true 表示显示所有目标语言，false 表示隐藏所有目标语言
  Future<void> setGlobalTranslationVisibility(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGlobalTranslationVisibility, visible);
  }
}
