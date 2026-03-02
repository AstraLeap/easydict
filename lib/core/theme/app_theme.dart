import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  /// 主字体族：Windows 下以 Microsoft YaHei UI 为主（含中文+拉丁），
  /// 避免 DWrite 自行中文替换绕过 fontFamilyFallback 列表。
  /// macOS/iOS 以 SF Pro Text 为主；其他平台不设置，交由系统默认处理。
  static String get fontFamily {
    if (Platform.isWindows) return 'Microsoft YaHei UI';
    if (Platform.isMacOS || Platform.isIOS) return 'SF Pro Text';
    return 'Roboto';
  }

  static List<String> get fontFamilyFallback {
    if (Platform.isWindows) {
      return [
        'Segoe UI',           // Windows 拉丁优选
        'Microsoft YaHei',    // 备用 CJK
        'Arial',
        'SimHei',
        'SimSun',
      ];
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return [
        'Helvetica Neue',
        'PingFang SC',
        'Arial',
      ];
    }
    // Android / Linux
    return [
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'Ubuntu',
      'Arial',
    ];
  }

  static SystemUiOverlayStyle lightSystemUiOverlayStyle() {
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static SystemUiOverlayStyle darkSystemUiOverlayStyle() {
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// 为 TextTheme 每个样式附加 zh-CN locale，确保 CJK 统一汉字在所有
  /// 平台（尤其 Windows DWrite）上统一使用简体中文字形，而非日文字形。
  static TextTheme _withChineseLocale(TextTheme theme) {
    const loc = Locale('zh', 'CN');
    return theme.copyWith(
      displayLarge:   theme.displayLarge?.copyWith(locale: loc),
      displayMedium:  theme.displayMedium?.copyWith(locale: loc),
      displaySmall:   theme.displaySmall?.copyWith(locale: loc),
      headlineLarge:  theme.headlineLarge?.copyWith(locale: loc),
      headlineMedium: theme.headlineMedium?.copyWith(locale: loc),
      headlineSmall:  theme.headlineSmall?.copyWith(locale: loc),
      titleLarge:     theme.titleLarge?.copyWith(locale: loc),
      titleMedium:    theme.titleMedium?.copyWith(locale: loc),
      titleSmall:     theme.titleSmall?.copyWith(locale: loc),
      bodyLarge:      theme.bodyLarge?.copyWith(locale: loc),
      bodyMedium:     theme.bodyMedium?.copyWith(locale: loc),
      bodySmall:      theme.bodySmall?.copyWith(locale: loc),
      labelLarge:     theme.labelLarge?.copyWith(locale: loc),
      labelMedium:    theme.labelMedium?.copyWith(locale: loc),
      labelSmall:     theme.labelSmall?.copyWith(locale: loc),
    );
  }

  /// 构建一个显式指定 textTheme 字体族的主题，确保在 Windows 等平台上
  /// fontFamily 能够可靠生效，而不仅依赖 ThemeData.fontFamily 参数。
  static ThemeData _build({required ColorScheme colorScheme}) {
    final family = fontFamily;
    final fallback = fontFamilyFallback;
    final typo = Typography.material2021(platform: defaultTargetPlatform);
    final isDark = colorScheme.brightness == Brightness.dark;
    final textTheme = _withChineseLocale(
      (isDark ? typo.white : typo.black).apply(
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: family,
      fontFamilyFallback: fallback,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
    );
  }

  static ThemeData lightTheme({Color? seedColor}) {
    return _build(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor ?? Colors.blue,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData darkTheme({Color? seedColor}) {
    return _build(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor ?? Colors.blue,
        brightness: Brightness.dark,
      ),
    );
  }
}
