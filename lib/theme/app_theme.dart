import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'Segoe UI';

  static const List<String> fontFamilyFallback = [
    'SF Pro Text',
    'Helvetica Neue',
    'Roboto',
    'Ubuntu',
    'Arial',
    'Microsoft YaHei',
    'SimHei',
    'SimSun',
    'KaiTi',
    'FangSong',
    'Microsoft YaHei UI',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
  ];

  static ThemeData lightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      splashFactory: NoSplash.splashFactory,
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      splashFactory: NoSplash.splashFactory,
    );
  }
}
