import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  static const String _kNavPanelPosition = 'nav_panel_position';
  static const String _kClickActionOrder = 'click_action_order';

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
}
