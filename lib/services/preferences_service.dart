import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';
import '../core/utils/language_utils.dart';
import '../pages/llm_config_page.dart';

class LLMConfig {
  final LLMProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  /// 是否启用深度思考（仅标准模型有效）
  final bool enableThinking;

  LLMConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.enableThinking = false,
  });

  String get effectiveBaseUrl =>
      baseUrl.isEmpty ? provider.defaultBaseUrl : baseUrl;

  bool get isValid => apiKey.isNotEmpty;
}

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const String _kNavPanelPosition = 'nav_panel_position';
  static const String _kClickActionOrder = 'click_action_order';
  static const String _kGlobalTranslationVisibility =
      'global_translation_visibility';
  static const String _kDictionaryContentScale = 'dictionary_content_scale';

  // 剪切板监听和托盘设置键名
  static const String _kClipboardWatchEnabled = 'clipboard_watch_enabled';
  static const String _kMinimizeToTray = 'minimize_to_tray';

  // LLM 模型键名
  static const String _kLlmFastPrefix = 'fast_llm';
  static const String _kLlmStandardPrefix = 'standard_llm';
  static const String _kLlmSuffixProvider = '_provider';
  static const String _kLlmSuffixApiKey = '_api_key';
  static const String _kLlmSuffixBaseUrl = '_base_url';
  static const String _kLlmSuffixModel = '_model';
  static const String _kLlmStandardEnableThinking =
      'standard_llm_enable_thinking';

  // TTS 键名
  static const String _kTtsProvider = 'tts_provider';
  static const String _kTtsApiKey = 'tts_api_key';
  static const String _kTtsBaseUrl = 'tts_base_url';
  static const String _kTtsModel = 'tts_model';
  static const String _kTtsVoice = 'tts_voice';
  static const String _kGoogleTtsVoice = 'google_tts_voice';

  static const String navPositionLeft = 'left';
  static const String navPositionRight = 'right';

  Future<Map<String, double>> getNavPanelPosition() async {
    final p = await prefs;
    final position = p.getString(_kNavPanelPosition);
    final dy = p.getDouble('${_kNavPanelPosition}_dy') ?? 0.7;

    return {'isRight': (position != navPositionLeft) ? 1.0 : 0.0, 'dy': dy};
  }

  Future<void> setNavPanelPosition(bool isRight, double dy) async {
    final p = await prefs;
    await p.setString(
      _kNavPanelPosition,
      isRight ? navPositionRight : navPositionLeft,
    );
    await p.setDouble('${_kNavPanelPosition}_dy', dy);
  }

  static const String actionAiTranslate = 'ai_translate';
  static const String actionCopy = 'copy';
  static const String actionAskAi = 'ask_ai';
  static const String actionEdit = 'edit';
  static const String actionSpeak = 'speak';

  static const String actionBack = 'back';
  static const String actionSearch = 'search';
  static const String actionFavorite = 'favorite';
  static const String actionToggleTranslate = 'toggle_translate';
  static const String actionAiHistory = 'ai_history';
  static const String actionResetEntry = 'reset_entry';

  static const List<String> defaultActionOrder = [
    actionAiTranslate,
    actionCopy,
    actionAskAi,
    actionEdit,
    actionSpeak,
  ];

  Future<List<String>> getClickActionOrder() async {
    final p = await prefs;
    final order = p.getStringList(_kClickActionOrder);
    if (order == null || order.isEmpty) {
      return List.from(defaultActionOrder);
    }
    for (final action in defaultActionOrder) {
      if (!order.contains(action)) {
        order.add(action);
      }
    }
    return order;
  }

  Future<void> setClickActionOrder(List<String> order) async {
    final p = await prefs;
    await p.setStringList(_kClickActionOrder, order);
  }

  Future<String> getClickAction() async {
    final order = await getClickActionOrder();
    return order.isNotEmpty ? order.first : actionAiTranslate;
  }

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
      case actionBack:
        return '返回';
      case actionSearch:
        return '搜索';
      case actionFavorite:
        return '收藏';
      case actionToggleTranslate:
        return '显示/隐藏翻译';
      case actionAiHistory:
        return 'AI 历史记录';
      case actionResetEntry:
        return '重置词条';
      default:
        return action;
    }
  }

  static IconData getActionIcon(String action) {
    switch (action) {
      case actionAiTranslate:
        return Icons.translate;
      case actionCopy:
        return Icons.copy;
      case actionAskAi:
        return Icons.auto_awesome;
      case actionEdit:
        return Icons.edit;
      case actionSpeak:
        return Icons.volume_up;
      case actionBack:
        return Icons.arrow_back;
      case actionSearch:
        return Icons.search;
      case actionFavorite:
        return Icons.bookmark_outline;
      case actionToggleTranslate:
        return Icons.translate_outlined;
      case actionAiHistory:
        return Icons.auto_awesome;
      case actionResetEntry:
        return Icons.refresh;
      default:
        return Icons.more_horiz;
    }
  }

  static const String _kToolbarActions = 'toolbar_actions';
  static const String _kOverflowActions = 'overflow_actions';
  static const int maxToolbarItems = 5;

  static const List<String> defaultToolbarActions = [
    actionSearch,
    actionFavorite,
    actionToggleTranslate,
    actionAiHistory,
    actionResetEntry,
  ];

  static const List<String> defaultOverflowActions = [];

  static const List<String> validToolbarActions = [
    actionSearch,
    actionFavorite,
    actionToggleTranslate,
    actionAiHistory,
    actionResetEntry,
  ];

  Future<void> setToolbarAndOverflowActions(
    List<String> toolbarActions,
    List<String> overflowActions,
  ) async {
    final p = await prefs;
    await p.setStringList(_kToolbarActions, toolbarActions);
    await p.setStringList(_kOverflowActions, overflowActions);
  }

  Future<(List<String>, List<String>)> getToolbarAndOverflowActions() async {
    final p = await prefs;
    final toolbarActions = p.getStringList(_kToolbarActions);
    final overflowActions = p.getStringList(_kOverflowActions);

    if ((toolbarActions == null || toolbarActions.isEmpty) &&
        (overflowActions == null || overflowActions.isEmpty)) {
      return (
        List<String>.from(defaultToolbarActions),
        List<String>.from(defaultOverflowActions),
      );
    }

    final validToolbar = <String>[];
    final validOverflow = <String>[];

    if (toolbarActions != null) {
      for (final action in toolbarActions) {
        if (validToolbarActions.contains(action) &&
            !validToolbar.contains(action)) {
          validToolbar.add(action);
        }
      }
    }
    if (overflowActions != null) {
      for (final action in overflowActions) {
        if (validToolbarActions.contains(action) &&
            !validOverflow.contains(action)) {
          validOverflow.add(action);
        }
      }
    }

    for (final action in validToolbarActions) {
      if (!validToolbar.contains(action) && !validOverflow.contains(action)) {
        if (validToolbar.length < maxToolbarItems) {
          validToolbar.add(action);
        } else {
          validOverflow.add(action);
        }
      }
    }

    return (validToolbar, validOverflow);
  }

  Future<bool> getGlobalTranslationVisibility() async {
    final p = await prefs;
    return p.getBool(_kGlobalTranslationVisibility) ?? true;
  }

  Future<void> setGlobalTranslationVisibility(bool visible) async {
    final p = await prefs;
    await p.setBool(_kGlobalTranslationVisibility, visible);
  }

  Future<double> getDictionaryContentScale() async {
    final p = await prefs;
    return p.getDouble(_kDictionaryContentScale) ?? 1.0;
  }

  Future<void> setDictionaryContentScale(double scale) async {
    final p = await prefs;
    await p.setDouble(_kDictionaryContentScale, scale);
  }

  Future<LLMConfig?> getLLMConfig({bool isFast = false}) async {
    final p = await prefs;
    final prefix = isFast ? _kLlmFastPrefix : _kLlmStandardPrefix;

    final providerIndex = p.getInt('$prefix${_kLlmSuffixProvider}');
    if (providerIndex == null) return null;

    final apiKey = p.getString('$prefix${_kLlmSuffixApiKey}') ?? '';
    final baseUrl = p.getString('$prefix${_kLlmSuffixBaseUrl}') ?? '';
    final model = p.getString('$prefix${_kLlmSuffixModel}') ?? '';

    final enableThinking =
        !isFast && (p.getBool(_kLlmStandardEnableThinking) ?? false);

    return LLMConfig(
      provider: LLMProvider.values[providerIndex],
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      enableThinking: enableThinking,
    );
  }

  Future<void> setLLMConfig({
    required bool isFast,
    required LLMProvider provider,
    required String apiKey,
    required String baseUrl,
    required String model,
    bool enableThinking = false,
  }) async {
    final p = await prefs;
    final prefix = isFast ? _kLlmFastPrefix : _kLlmStandardPrefix;

    await p.setInt('$prefix${_kLlmSuffixProvider}', provider.index);
    await p.setString('$prefix${_kLlmSuffixApiKey}', apiKey);
    await p.setString('$prefix${_kLlmSuffixBaseUrl}', baseUrl);
    await p.setString('$prefix${_kLlmSuffixModel}', model);
    if (!isFast) {
      await p.setBool(_kLlmStandardEnableThinking, enableThinking);
    }
  }

  Future<Map<String, dynamic>?> getTTSConfig() async {
    final p = await prefs;

    final providerIndex = p.getInt(_kTtsProvider);
    if (providerIndex == null) return null;

    final providers = [
      {'name': 'edge', 'baseUrl': ''},
      {'name': 'azure', 'baseUrl': ''},
      {'name': 'google', 'baseUrl': 'https://texttospeech.googleapis.com/v1'},
    ];

    if (providerIndex >= providers.length) return null;

    final provider = providers[providerIndex]['name'];
    String voice = p.getString('tts_voice') ?? '';

    if (provider == 'google') {
      final googleVoice = p.getString('google_tts_voice');
      if (googleVoice != null && googleVoice.isNotEmpty) {
        voice = googleVoice;
      } else if (voice.isEmpty) {
        voice = 'en-US-Chirp3-HD-Puck';
      }
    }

    if (provider == 'edge' && voice.isEmpty) {
      voice = 'zh-CN-XiaoxiaoNeural';
    }

    return {
      'provider': provider,
      'baseUrl':
          p.getString(_kTtsBaseUrl) ?? providers[providerIndex]['baseUrl'],
      'apiKey': p.getString(_kTtsApiKey) ?? '',
      'model': p.getString(_kTtsModel) ?? '',
      'voice': voice,
    };
  }

  Future<void> setTTSConfig({
    required int providerIndex,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String voice,
  }) async {
    final p = await prefs;
    await p.setInt(_kTtsProvider, providerIndex);
    await p.setString(_kTtsApiKey, apiKey);
    await p.setString(_kTtsBaseUrl, baseUrl);
    await p.setString(_kTtsModel, model);
    await p.setString(_kTtsVoice, voice);
  }

  static const String _kFontFolderPath = 'font_folder_path';

  Future<String?> getFontFolderPath() async {
    final p = await prefs;
    return p.getString(_kFontFolderPath);
  }

  Future<void> setFontFolderPath(String path) async {
    final p = await prefs;
    await p.setString(_kFontFolderPath, path);
  }

  static const String _kFontConfigPrefix = 'font_config_';
  static const String _kFontInitializedPrefix = 'font_initialized_';

  /// Returns true if font configuration has been saved or manually touched
  /// for [language] at least once — used to prevent the auto-scan from
  /// overwriting settings the user has deliberately configured (or cleared).
  Future<bool> isFontLanguageInitialized(String language) async {
    final p = await prefs;
    return p.getBool('$_kFontInitializedPrefix$language') ?? false;
  }

  /// Marks [language] as having been initialised. Called both after the first
  /// auto-scan save and whenever the user manually picks or clears a font.
  Future<void> markFontLanguageInitialized(String language) async {
    final p = await prefs;
    await p.setBool('$_kFontInitializedPrefix$language', true);
  }

  /// 字体配置支持的所有语言分组键，需与 font_config_page.dart 的 _mapToFontGroupKey 保持一致。
  static const List<String> kFontLanguages = [
    'en',
    'zh-hans',
    'zh-hant',
    'jp',
    'ko',
    'fr',
    'de',
    'es',
    'it',
    'ru',
    'pt',
    'ar',
  ];

  Future<Map<String, Map<String, String>>> getFontConfigs() async {
    final p = await prefs;
    final fontConfigs = <String, Map<String, String>>{};
    final languages = kFontLanguages;
    final fontTypes = [
      'serif_regular',
      'serif_bold',
      'serif_italic',
      'serif_bold_italic',
      'sans_regular',
      'sans_bold',
      'sans_italic',
      'sans_bold_italic',
    ];

    for (final lang in languages) {
      final langConfig = <String, String>{};
      for (final fontType in fontTypes) {
        final key = '$_kFontConfigPrefix${lang}_$fontType';
        final value = p.getString(key);
        if (value != null && value.isNotEmpty) {
          langConfig[fontType] = value;
        }
      }
      if (langConfig.isNotEmpty) {
        fontConfigs[lang] = langConfig;
      }
    }
    return fontConfigs;
  }

  Future<void> setFontConfig({
    required String language,
    required String fontType,
    required String fontPath,
  }) async {
    final p = await prefs;
    final key = '$_kFontConfigPrefix${language}_$fontType';
    await p.setString(key, fontPath);
  }

  Future<void> clearFontConfig({
    required String language,
    required String fontType,
  }) async {
    final p = await prefs;
    final key = '$_kFontConfigPrefix${language}_$fontType';
    final existed = p.containsKey(key);
    await p.remove(key);
    final removed = !p.containsKey(key);
    Logger.d(
      'clearFontConfig: key=$key, existed=$existed, removed=$removed',
      tag: 'PreferencesService',
    );
  }

  Future<void> clearAllFontConfigs() async {
    final p = await prefs;
    final languages = kFontLanguages;
    final fontTypes = [
      'serif_regular',
      'serif_bold',
      'serif_italic',
      'serif_bold_italic',
      'sans_regular',
      'sans_bold',
      'sans_italic',
      'sans_bold_italic',
    ];
    for (final lang in languages) {
      for (final fontType in fontTypes) {
        final key = '$_kFontConfigPrefix${lang}_$fontType';
        await p.remove(key);
      }
    }
  }

  static const String _kFontScalePrefix = 'font_scale_';

  Future<double> getFontScale(String language, bool isSerif) async {
    final p = await prefs;
    final key = '$_kFontScalePrefix${language}_${isSerif ? 'serif' : 'sans'}';
    return p.getDouble(key) ?? LanguageUtils.getDefaultFontScale(language);
  }

  Future<void> setFontScale(String language, bool isSerif, double scale) async {
    final p = await prefs;
    final key = '$_kFontScalePrefix${language}_${isSerif ? 'serif' : 'sans'}';
    await p.setDouble(key, scale);
  }

  Future<Map<String, Map<String, double>>> getAllFontScales() async {
    final p = await prefs;
    final fontScales = <String, Map<String, double>>{};
    final languages = kFontLanguages;

    for (final lang in languages) {
      final langScales = <String, double>{};
      final serifKey = '$_kFontScalePrefix${lang}_serif';
      final sansKey = '$_kFontScalePrefix${lang}_sans';
      final defaultScale = LanguageUtils.getDefaultFontScale(lang);
      final serifScale = p.getDouble(serifKey) ?? defaultScale;
      final sansScale = p.getDouble(sansKey) ?? defaultScale;
      // 始终将所有语言的缩放比例填入 map：未用户设置时使用语言的默认值
      langScales['serif'] = serifScale;
      langScales['sans'] = sansScale;
      fontScales[lang] = langScales;
    }
    return fontScales;
  }

  static const String _kAuthToken = 'auth_token';
  static const String _kAuthUserData = 'auth_user_data';

  Future<String?> getAuthToken() async {
    final p = await prefs;
    return p.getString(_kAuthToken);
  }

  Future<void> setAuthToken(String? token) async {
    final p = await prefs;
    if (token != null && token.isNotEmpty) {
      await p.setString(_kAuthToken, token);
    } else {
      await p.remove(_kAuthToken);
    }
  }

  Future<Map<String, dynamic>?> getAuthUserData() async {
    final p = await prefs;
    final userData = p.getString(_kAuthUserData);
    if (userData != null && userData.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(
          const JsonDecoder().convert(userData) as Map<dynamic, dynamic>,
        );
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> setAuthUserData(Map<String, dynamic>? userData) async {
    final p = await prefs;
    if (userData != null) {
      await p.setString(_kAuthUserData, const JsonEncoder().convert(userData));
    } else {
      await p.remove(_kAuthUserData);
    }
  }

  Future<void> clearAuthData() async {
    final p = await prefs;
    await p.remove(_kAuthToken);
    await p.remove(_kAuthUserData);
  }

  static const String _kAutoCheckDictUpdate = 'auto_check_dict_update';
  static const String _kLastDictUpdateCheckTime = 'last_dict_update_check_time';
  static const String _kSkipUserSettings = 'skip_user_settings';

  Future<bool> getSkipUserSettings() async {
    final p = await prefs;
    return p.getBool(_kSkipUserSettings) ?? false;
  }

  Future<void> setSkipUserSettings(bool skip) async {
    final p = await prefs;
    await p.setBool(_kSkipUserSettings, skip);
  }

  Future<bool> getAutoCheckDictUpdate() async {
    final p = await prefs;
    return p.getBool(_kAutoCheckDictUpdate) ?? true;
  }

  Future<void> setAutoCheckDictUpdate(bool enabled) async {
    final p = await prefs;
    await p.setBool(_kAutoCheckDictUpdate, enabled);
  }

  Future<DateTime?> getLastDictUpdateCheckTime() async {
    final p = await prefs;
    final timeStr = p.getString(_kLastDictUpdateCheckTime);
    if (timeStr != null) {
      try {
        return DateTime.parse(timeStr);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> setLastDictUpdateCheckTime(DateTime time) async {
    final p = await prefs;
    await p.setString(_kLastDictUpdateCheckTime, time.toIso8601String());
  }

  static const String _kLastAppUpdateCheckTime = 'last_app_update_check_time';

  Future<DateTime?> getLastAppUpdateCheckTime() async {
    final p = await prefs;
    final timeStr = p.getString(_kLastAppUpdateCheckTime);
    if (timeStr != null) {
      try {
        return DateTime.parse(timeStr);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> setLastAppUpdateCheckTime(DateTime time) async {
    final p = await prefs;
    await p.setString(_kLastAppUpdateCheckTime, time.toIso8601String());
  }

  // ── 应用语言 ──────────────────────────────────────────────────────────────
  // 存储值: null / "auto" = 跟随系统；"zh" / "en" = 用户手动选择的语言代码
  static const String _kAppLocale = 'app_locale';

  /// 读取已存储的语言设置。返回 null 表示"跟随系统"（未配置或已设为 auto）。
  Future<String?> getAppLocale() async {
    final p = await prefs;
    final value = p.getString(_kAppLocale);
    if (value == null || value == 'auto') return null;
    return value;
  }

  /// 保存语言设置。传入 null 表示"跟随系统"。
  Future<void> setAppLocale(String? localeCode) async {
    final p = await prefs;
    if (localeCode == null || localeCode == 'auto') {
      await p.remove(_kAppLocale);
    } else {
      await p.setString(_kAppLocale, localeCode);
    }
  }

  // ── 剪切板监听和托盘设置 ──────────────────────────────────────────────────────

  /// 获取剪切板监听是否启用
  Future<bool> isClipboardWatchEnabled() async {
    final p = await prefs;
    return p.getBool(_kClipboardWatchEnabled) ?? false;
  }

  /// 设置剪切板监听启用状态
  Future<void> setClipboardWatchEnabled(bool enabled) async {
    final p = await prefs;
    await p.setBool(_kClipboardWatchEnabled, enabled);
  }

  /// 获取是否最小化到托盘
  Future<bool> shouldMinimizeToTray() async {
    final p = await prefs;
    return p.getBool(_kMinimizeToTray) ?? false;
  }

  /// 设置是否最小化到托盘
  Future<void> setMinimizeToTray(bool value) async {
    final p = await prefs;
    await p.setBool(_kMinimizeToTray, value);
  }

  static const String _kGroupDetailSubGroupsExpanded =
      'group_detail_subgroups_expanded';
  static const String _kGroupDetailEntriesExpanded =
      'group_detail_entries_expanded';

  Future<bool> getGroupDetailSubGroupsExpanded() async {
    final p = await prefs;
    return p.getBool(_kGroupDetailSubGroupsExpanded) ?? false;
  }

  Future<void> setGroupDetailSubGroupsExpanded(bool expanded) async {
    final p = await prefs;
    await p.setBool(_kGroupDetailSubGroupsExpanded, expanded);
  }

  Future<bool> getGroupDetailEntriesExpanded() async {
    final p = await prefs;
    return p.getBool(_kGroupDetailEntriesExpanded) ?? false;
  }

  Future<void> setGroupDetailEntriesExpanded(bool expanded) async {
    final p = await prefs;
    await p.setBool(_kGroupDetailEntriesExpanded, expanded);
  }
}
