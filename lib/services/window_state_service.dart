import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';

class WindowStateService {
  static final WindowStateService _instance = WindowStateService._internal();
  factory WindowStateService() => _instance;
  WindowStateService._internal();

  static const String _kWindowWidth = 'window_width';
  static const String _kWindowHeight = 'window_height';
  static const String _kWindowPosX = 'window_pos_x';
  static const String _kWindowPosY = 'window_pos_y';
  static const String _kWindowMaximized = 'window_maximized';

  static const double defaultWidth = 1200;
  static const double defaultHeight = 800;

  Future<Map<String, dynamic>> getWindowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'width': prefs.getDouble(_kWindowWidth) ?? defaultWidth,
        'height': prefs.getDouble(_kWindowHeight) ?? defaultHeight,
        'posX': prefs.getDouble(_kWindowPosX),
        'posY': prefs.getDouble(_kWindowPosY),
        'maximized': prefs.getBool(_kWindowMaximized) ?? false,
      };
    } catch (e) {
      Logger.e('获取窗口状态失败: $e', tag: 'WindowStateService');
      return {
        'width': defaultWidth,
        'height': defaultHeight,
        'posX': null,
        'posY': null,
        'maximized': false,
      };
    }
  }

  Future<void> saveWindowState({
    required double width,
    required double height,
    double? posX,
    double? posY,
    required bool maximized,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kWindowWidth, width);
      await prefs.setDouble(_kWindowHeight, height);
      if (posX != null) await prefs.setDouble(_kWindowPosX, posX);
      if (posY != null) await prefs.setDouble(_kWindowPosY, posY);
      await prefs.setBool(_kWindowMaximized, maximized);
      Logger.d(
        '窗口状态已保存: ${width.toInt()}x${height.toInt()}',
        tag: 'WindowStateService',
      );
    } catch (e) {
      Logger.e('保存窗口状态失败: $e', tag: 'WindowStateService');
    }
  }

  Future<void> clearWindowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kWindowWidth);
      await prefs.remove(_kWindowHeight);
      await prefs.remove(_kWindowPosX);
      await prefs.remove(_kWindowPosY);
      await prefs.remove(_kWindowMaximized);
    } catch (e) {
      Logger.e('清除窗口状态失败: $e', tag: 'WindowStateService');
    }
  }
}
