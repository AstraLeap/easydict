import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeModeOption { light, dark, system }

class ThemeProvider with ChangeNotifier {
  final SharedPreferences _prefs;
  ThemeModeOption _themeMode = ThemeModeOption.system;
  bool _notificationsEnabled = true;
  Color _seedColor = Colors.blue;

  ThemeModeOption get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;
  Color get seedColor => _seedColor;

  static const String _prefKeyThemeMode = 'theme_mode';
  static const String _prefKeyNotifications = 'notifications_enabled';
  static const String _prefKeySeedColor = 'seed_color';

  static const List<Color> predefinedColors = [
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.deepPurple,
    Colors.pink,
    Colors.red,
    Colors.deepOrange,
    Colors.orange,
    Colors.amber,
    Colors.yellow,
    Colors.lime,
    Colors.lightGreen,
    Colors.green,
    Colors.teal,
    Colors.cyan,
  ];

  // 系统主题色（动态颜色）
  static const Color systemAccentColor = Color(0xFF000001);

  ThemeProvider(this._prefs) {
    _loadPreferences();
  }

  void _loadPreferences() {
    final themeModeIndex = _prefs.getInt(_prefKeyThemeMode);
    if (themeModeIndex != null &&
        themeModeIndex >= 0 &&
        themeModeIndex < ThemeModeOption.values.length) {
      _themeMode = ThemeModeOption.values[themeModeIndex];
    }
    _notificationsEnabled = _prefs.getBool(_prefKeyNotifications) ?? true;

    final seedColorValue = _prefs.getInt(_prefKeySeedColor);
    if (seedColorValue != null) {
      _seedColor = Color(seedColorValue);
    }
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    await _prefs.setInt(_prefKeyThemeMode, mode.index);
  }

  Future<void> setSeedColor(Color color) async {
    if (_seedColor == color) return;
    _seedColor = color;
    notifyListeners();

    await _prefs.setInt(_prefKeySeedColor, color.toARGB32());
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled == enabled) return;
    _notificationsEnabled = enabled;
    notifyListeners();

    await _prefs.setBool(_prefKeyNotifications, enabled);
  }

  ThemeMode getThemeMode() {
    switch (_themeMode) {
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
      case ThemeModeOption.system:
        return ThemeMode.system;
    }
  }

  String getThemeModeDisplayName() {
    switch (_themeMode) {
      case ThemeModeOption.light:
        return '浅色';
      case ThemeModeOption.dark:
        return '深色';
      case ThemeModeOption.system:
        return '跟随系统';
    }
  }
}
