import 'package:shared_preferences/shared_preferences.dart';
import '../pages/llm_config_page.dart';

class LLMConfig {
  final LLMProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  LLMConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
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
      default:
        return action;
    }
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
    final prefix = isFast ? 'fast_llm' : 'standard_llm';

    final providerIndex = p.getInt('${prefix}_provider');
    if (providerIndex == null) return null;

    final apiKey = p.getString('${prefix}_api_key') ?? '';
    final baseUrl = p.getString('${prefix}_base_url') ?? '';
    final model = p.getString('${prefix}_model') ?? '';

    return LLMConfig(
      provider: LLMProvider.values[providerIndex],
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );
  }

  Future<void> setLLMConfig({
    required bool isFast,
    required LLMProvider provider,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final p = await prefs;
    final prefix = isFast ? 'fast_llm' : 'standard_llm';

    await p.setInt('${prefix}_provider', provider.index);
    await p.setString('${prefix}_api_key', apiKey);
    await p.setString('${prefix}_base_url', baseUrl);
    await p.setString('${prefix}_model', model);
  }

  Future<Map<String, dynamic>?> getTTSConfig() async {
    final p = await prefs;

    final providerIndex = p.getInt('tts_provider');
    if (providerIndex == null) return null;

    final providers = [
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

    return {
      'provider': provider,
      'baseUrl':
          p.getString('tts_base_url') ?? providers[providerIndex]['baseUrl'],
      'apiKey': p.getString('tts_api_key') ?? '',
      'model': p.getString('tts_model') ?? '',
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
    await p.setInt('tts_provider', providerIndex);
    await p.setString('tts_api_key', apiKey);
    await p.setString('tts_base_url', baseUrl);
    await p.setString('tts_model', model);
    await p.setString('tts_voice', voice);
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

  Future<Map<String, Map<String, String>>> getFontConfigs() async {
    final p = await prefs;
    final fontConfigs = <String, Map<String, String>>{};
    final languages = ['en', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'ru', 'pt', 'ar'];
    final fontTypes = ['serif_regular', 'serif_bold', 'serif_italic', 'serif_bold_italic',
                        'sans_regular', 'sans_bold', 'sans_italic', 'sans_bold_italic'];

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
    print('[PreferencesService] clearFontConfig: key=$key, existed=$existed, removed=$removed');
  }

  Future<void> clearAllFontConfigs() async {
    final p = await prefs;
    final languages = ['en', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'ru', 'pt', 'ar'];
    final fontTypes = ['serif_regular', 'serif_bold', 'serif_italic', 'serif_bold_italic',
                        'sans_regular', 'sans_bold', 'sans_italic', 'sans_bold_italic'];
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
    return p.getDouble(key) ?? 1.0;
  }

  Future<void> setFontScale(String language, bool isSerif, double scale) async {
    final p = await prefs;
    final key = '$_kFontScalePrefix${language}_${isSerif ? 'serif' : 'sans'}';
    await p.setDouble(key, scale);
  }

  Future<Map<String, Map<String, double>>> getAllFontScales() async {
    final p = await prefs;
    final fontScales = <String, Map<String, double>>{};
    final languages = ['en', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'ru', 'pt', 'ar'];

    for (final lang in languages) {
      final langScales = <String, double>{};
      final serifKey = '$_kFontScalePrefix${lang}_serif';
      final sansKey = '$_kFontScalePrefix${lang}_sans';
      final serifScale = p.getDouble(serifKey);
      final sansScale = p.getDouble(sansKey);
      if (serifScale != null) {
        langScales['serif'] = serifScale;
      }
      if (sansScale != null) {
        langScales['sans'] = sansScale;
      }
      if (langScales.isNotEmpty) {
        fontScales[lang] = langScales;
      }
    }
    return fontScales;
  }
}
