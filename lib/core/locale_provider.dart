import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import '../i18n/strings.g.dart';
import '../services/preferences_service.dart';
import '../core/logger.dart';

/// 枚举：应用语言选项
enum AppLocaleOption {
  /// 跟随系统，自动检测设备语言
  auto,
  /// 中文
  zh,
  /// 英文
  en;

  /// 转换为 slang AppLocale（auto 时返回 null）
  AppLocale? toAppLocale() {
    switch (this) {
      case AppLocaleOption.zh:
        return AppLocale.zh;
      case AppLocaleOption.en:
        return AppLocale.en;
      case AppLocaleOption.auto:
        return null;
    }
  }

  /// 对应的持久化存储字符串（auto 存 null）
  String? toStorageValue() {
    if (this == AppLocaleOption.auto) return null;
    return name; // 'zh' or 'en'
  }

  /// 从存储字符串解析
  static AppLocaleOption fromStorageValue(String? value) {
    switch (value) {
      case 'zh':
        return AppLocaleOption.zh;
      case 'en':
        return AppLocaleOption.en;
      default:
        return AppLocaleOption.auto;
    }
  }
}

/// 应用语言管理 Provider
///
/// 职责：
/// 1. 持久化读写用户的语言选项（通过 PreferencesService）
/// 2. 在启动时初始化 slang 的 LocaleSettings
/// 3. 当用户切换语言时通知 Flutter 重建依赖树
class LocaleProvider extends ChangeNotifier {
  LocaleProvider._();

  static final LocaleProvider _instance = LocaleProvider._();
  factory LocaleProvider() => _instance;

  AppLocaleOption _currentOption = AppLocaleOption.auto;

  /// 当前选择的语言选项（auto / zh / en）
  AppLocaleOption get currentOption => _currentOption;

  /// 当前 slang 正在使用的语言区域
  Locale get flutterLocale => LocaleSettings.currentLocale.flutterLocale;

  StreamSubscription<AppLocale>? _localeStreamSub;

  /// 在 main() 中 await 此方法完成初始化
  Future<void> initialize() async {
    try {
      final storedValue = await PreferencesService().getAppLocale();
      _currentOption = AppLocaleOption.fromStorageValue(storedValue);

      if (_currentOption == AppLocaleOption.auto) {
        // Follow device locale; if slang falls back to zh (base_locale) but
        // the device language isn't Chinese, prefer English instead.
        await LocaleSettings.useDeviceLocale();
        final deviceIsZh = PlatformDispatcher.instance.locales
            .any((l) => l.languageCode.toLowerCase() == 'zh');
        if (!deviceIsZh && LocaleSettings.currentLocale == AppLocale.zh) {
          await LocaleSettings.setLocale(AppLocale.en);
        }
        Logger.i(
          '语言初始化：跟随系统 → ${LocaleSettings.currentLocale}',
          tag: 'LocaleProvider',
        );
      } else {
        await LocaleSettings.setLocale(_currentOption.toAppLocale()!);
        Logger.i(
          '语言初始化：用户设定 → ${_currentOption.name}',
          tag: 'LocaleProvider',
        );
      }
    } catch (e) {
      Logger.w('语言初始化失败，使用默认语言: $e', tag: 'LocaleProvider');
      // 失败时不阻塞启动，使用 slang 默认（base_locale = zh）
    }

    // 监听 slang locale stream 触发重建
    _localeStreamSub = LocaleSettings.getLocaleStream().listen((_) {
      notifyListeners();
    });
  }

  /// 切换语言并持久化。传入 [AppLocaleOption.auto] 表示跟随系统。
  Future<void> setLocaleOption(AppLocaleOption option) async {
    if (_currentOption == option) return;

    _currentOption = option;

    try {
      // 持久化
      await PreferencesService().setAppLocale(option.toStorageValue());

      // 应用到 slang
      if (option == AppLocaleOption.auto) {
        await LocaleSettings.useDeviceLocale();
        final deviceIsZh = PlatformDispatcher.instance.locales
            .any((l) => l.languageCode.toLowerCase() == 'zh');
        if (!deviceIsZh && LocaleSettings.currentLocale == AppLocale.zh) {
          await LocaleSettings.setLocale(AppLocale.en);
        }
        Logger.i(
          '语言切换：→ 跟随系统（${LocaleSettings.currentLocale}）',
          tag: 'LocaleProvider',
        );
      } else {
        await LocaleSettings.setLocale(option.toAppLocale()!);
        Logger.i(
          '语言切换：→ ${option.name}',
          tag: 'LocaleProvider',
        );
      }
    } catch (e) {
      Logger.e('语言切换失败: $e', tag: 'LocaleProvider');
    }

    // slang stream 会触发 notifyListeners，但保险起见再调用一次
    notifyListeners();
  }

  @override
  void dispose() {
    _localeStreamSub?.cancel();
    super.dispose();
  }
}
