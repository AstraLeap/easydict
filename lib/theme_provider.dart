import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeModeOption {
  light,
  dark,
  system,
}

class ThemeProvider with ChangeNotifier {
  ThemeModeOption _themeMode = ThemeModeOption.system;
  bool _notificationsEnabled = true;

  ThemeModeOption get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;

  static const String _prefKeyThemeMode = 'theme_mode';
  static const String _prefKeyNotifications = 'notifications_enabled';

  ThemeProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_prefKeyThemeMode);
    if (themeModeIndex != null && themeModeIndex >= 0 && themeModeIndex < ThemeModeOption.values.length) {
      _themeMode = ThemeModeOption.values[themeModeIndex];
    }
    _notificationsEnabled = prefs.getBool(_prefKeyNotifications) ?? true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyThemeMode, mode.index);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled == enabled) return;
    _notificationsEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyNotifications, enabled);
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
