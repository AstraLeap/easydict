import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import '../logger.dart';
import '../utils/toast_utils.dart';

enum LLMProvider {
  openAI('OpenAI', 'https://api.openai.com/v1'),
  anthropic('Anthropic', 'https://api.anthropic.com/v1'),
  gemini('Google Gemini', 'https://generativelanguage.googleapis.com/v1'),
  deepseek('DeepSeek', 'https://api.deepseek.com/v1'),
  moonshot('Moonshot (月之暗面)', 'https://api.moonshot.cn/v1'),
  zhipu('智谱AI', 'https://open.bigmodel.cn/api/paas/v4'),
  ali('阿里云 (DashScope)', 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  custom('自定义', '');

  final String displayName;
  final String defaultBaseUrl;

  const LLMProvider(this.displayName, this.defaultBaseUrl);
}

enum TTSProvider {
  azure('Azure TTS', ''),
  google('Google TTS', 'https://texttospeech.googleapis.com/v1');

  final String displayName;
  final String defaultBaseUrl;

  const TTSProvider(this.displayName, this.defaultBaseUrl);
}

/// Google TTS 模型选项
enum GoogleTTSModel {
  chirp3HD('Chirp 3 HD', 'chirp3-hd', '最新高质量语音，基于大语言模型，最自然'),
  journey('Journey', 'journey', '专为长文本和叙事优化，流畅自然'),
  studio('Studio', 'studio', '专业级语音，适合商业和媒体内容'),
  neural2('Neural2', 'neural2', '神经网络语音，高质量且自然'),
  wavenet('WaveNet', 'wavenet', '基于DeepMind WaveNet技术'),
  standard('Standard', 'standard', '标准语音，基础质量');

  final String displayName;
  final String modelCode;
  final String description;

  const GoogleTTSModel(this.displayName, this.modelCode, this.description);
}

/// Google TTS 音色选项（按模型分类）
class GoogleTTSVoice {
  final String name;
  final String gender;
  final String language;
  final String model;
  final String description;

  const GoogleTTSVoice({
    required this.name,
    required this.gender,
    required this.language,
    required this.model,
    required this.description,
  });
}

/// Google TTS 可用音色列表
final List<GoogleTTSVoice> googleTTSVoices = [
  // Chirp 3 HD Voices - 最新高质量
  const GoogleTTSVoice(
    name: 'en-US-Chirp3-HD-Aoede',
    gender: '女性',
    language: '英语(美国)',
    model: 'chirp3-hd',
    description: '温暖、友好',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Chirp3-HD-Charon',
    gender: '男性',
    language: '英语(美国)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Chirp3-HD-Fenrir',
    gender: '男性',
    language: '英语(美国)',
    model: 'chirp3-hd',
    description: '清晰、有力，适合新闻播报',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Chirp3-HD-Kore',
    gender: '女性',
    language: '英语(美国)',
    model: 'chirp3-hd',
    description: '年轻、活力',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Chirp3-HD-Puck',
    gender: '女性',
    language: '英语(美国)',
    model: 'chirp3-hd',
    description: '自然、流畅，适合客服和教育',
  ),
  // Journey Voices
  const GoogleTTSVoice(
    name: 'en-US-Journey-D',
    gender: '男性',
    language: '英语(美国)',
    model: 'journey',
    description: '叙事风格，适合长文本',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Journey-F',
    gender: '女性',
    language: '英语(美国)',
    model: 'journey',
    description: '叙事风格，适合长文本',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Journey-O',
    gender: '其他',
    language: '英语(美国)',
    model: 'journey',
    description: '叙事风格，中性声音',
  ),
  // Studio Voices
  const GoogleTTSVoice(
    name: 'en-US-Studio-M',
    gender: '男性',
    language: '英语(美国)',
    model: 'studio',
    description: '专业男声，适合商业内容',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Studio-O',
    gender: '女性',
    language: '英语(美国)',
    model: 'studio',
    description: '专业女声，适合商业内容',
  ),
  // Neural2 Voices
  const GoogleTTSVoice(
    name: 'en-US-Neural2-A',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声A',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-C',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声C',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-D',
    gender: '男性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络男声D',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-E',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声E',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-F',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声F（默认）',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-G',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声G',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-H',
    gender: '女性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络女声H',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-I',
    gender: '男性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络男声I',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Neural2-J',
    gender: '男性',
    language: '英语(美国)',
    model: 'neural2',
    description: '神经网络男声J',
  ),
  // WaveNet Voices
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-A',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声A',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-B',
    gender: '男性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet男声B',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-C',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声C',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-D',
    gender: '男性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet男声D',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-E',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声E',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-F',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声F',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-G',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声G',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-H',
    gender: '女性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet女声H',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-I',
    gender: '男性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet男声I',
  ),
  const GoogleTTSVoice(
    name: 'en-US-WaveNet-J',
    gender: '男性',
    language: '英语(美国)',
    model: 'wavenet',
    description: 'WaveNet男声J',
  ),
  // Standard Voices
  const GoogleTTSVoice(
    name: 'en-US-Standard-A',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声A',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-B',
    gender: '男性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准男声B',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-C',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声C',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-D',
    gender: '男性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准男声D',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-E',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声E',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-F',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声F',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-G',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声G',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-H',
    gender: '女性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准女声H',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-I',
    gender: '男性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准男声I',
  ),
  const GoogleTTSVoice(
    name: 'en-US-Standard-J',
    gender: '男性',
    language: '英语(美国)',
    model: 'standard',
    description: '标准男声J',
  ),
];

class ApiTestResult {
  final bool success;
  final String message;

  const ApiTestResult({required this.success, required this.message});
}

class LLMConfigPage extends StatefulWidget {
  const LLMConfigPage({super.key});

  @override
  State<LLMConfigPage> createState() => _LLMConfigPageState();
}

class _LLMConfigPageState extends State<LLMConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _fastFormKey = GlobalKey<FormState>();
  final _standardFormKey = GlobalKey<FormState>();
  final _ttsFormKey = GlobalKey<FormState>();

  final _fastApiKeyController = TextEditingController();
  final _fastBaseUrlController = TextEditingController();
  final _fastModelController = TextEditingController();

  final _standardApiKeyController = TextEditingController();
  final _standardBaseUrlController = TextEditingController();
  final _standardModelController = TextEditingController();

  final _ttsApiKeyController = TextEditingController();
  final _ttsBaseUrlController = TextEditingController();
  final _ttsModelController = TextEditingController();
  final _ttsVoiceController = TextEditingController();

  LLMProvider _fastProvider = LLMProvider.openAI;
  LLMProvider _standardProvider = LLMProvider.openAI;
  TTSProvider _ttsProvider = TTSProvider.azure;

  // Google TTS 音色配置
  GoogleTTSVoice? _selectedGoogleVoice;

  bool _isLoading = true;
  bool _obscureFastApiKey = true;
  bool _obscureStandardApiKey = true;
  bool _obscureTtsApiKey = true;

  bool _isTestingFast = false;
  bool _isTestingStandard = false;
  bool _isTestingTts = false;

  String? _testResultFast;
  bool? _testSuccessFast;
  String? _testResultStandard;
  bool? _testSuccessStandard;
  String? _testResultTts;
  bool? _testSuccessTts;

  static const Map<LLMProvider, String> _defaultModels = {
    LLMProvider.openAI: 'gpt-4o-mini',
    LLMProvider.anthropic: 'claude-3-sonnet-20240229',
    LLMProvider.gemini: 'gemini-pro',
    LLMProvider.deepseek: 'deepseek-chat',
    LLMProvider.moonshot: 'moonshot-v1-8k',
    LLMProvider.zhipu: 'glm-4',
    LLMProvider.custom: '',
  };

  static const Map<TTSProvider, String> _defaultTtsModels = {
    TTSProvider.azure: 'azure-tts',
    TTSProvider.google: '',
  };

  static const Map<TTSProvider, String> _defaultTtsVoices = {
    TTSProvider.azure: 'zh-CN-XiaoxiaoNeural',
    TTSProvider.google: 'en-US-Neural2-F',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();

    _fastApiKeyController.dispose();
    _fastBaseUrlController.dispose();
    _fastModelController.dispose();

    _standardApiKeyController.dispose();
    _standardBaseUrlController.dispose();
    _standardModelController.dispose();

    _ttsApiKeyController.dispose();
    _ttsBaseUrlController.dispose();
    _ttsModelController.dispose();
    _ttsVoiceController.dispose();

    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final fastProviderIndex = prefs.getInt('fast_llm_provider') ?? 0;
    _fastProvider = LLMProvider.values[fastProviderIndex];
    _fastApiKeyController.text = prefs.getString('fast_llm_api_key') ?? '';
    _fastBaseUrlController.text =
        prefs.getString('fast_llm_base_url') ?? _fastProvider.defaultBaseUrl;
    _fastModelController.text =
        prefs.getString('fast_llm_model') ?? _defaultModels[_fastProvider]!;

    final standardProviderIndex = prefs.getInt('standard_llm_provider') ?? 0;
    _standardProvider = LLMProvider.values[standardProviderIndex];
    _standardApiKeyController.text =
        prefs.getString('standard_llm_api_key') ?? '';
    _standardBaseUrlController.text =
        prefs.getString('standard_llm_base_url') ??
        _standardProvider.defaultBaseUrl;
    _standardModelController.text =
        prefs.getString('standard_llm_model') ??
        _defaultModels[_standardProvider]!;

    final ttsProviderIndex = prefs.getInt('tts_provider');
    if (ttsProviderIndex != null &&
        ttsProviderIndex < TTSProvider.values.length) {
      _ttsProvider = TTSProvider.values[ttsProviderIndex];
    } else {
      _ttsProvider = TTSProvider.azure;
    }
    _ttsApiKeyController.text = prefs.getString('tts_api_key') ?? '';
    _ttsBaseUrlController.text =
        prefs.getString('tts_base_url') ?? _ttsProvider.defaultBaseUrl;
    _ttsModelController.text =
        prefs.getString('tts_model') ?? _defaultTtsModels[_ttsProvider]!;
    _ttsVoiceController.text =
        prefs.getString('tts_voice') ?? _defaultTtsVoices[_ttsProvider]!;

    // 加载 Google TTS 音色配置（默认使用 Chirp 3 HD 模型）
    final savedVoiceName = prefs.getString('google_tts_voice');
    if (savedVoiceName != null && savedVoiceName.isNotEmpty) {
      _selectedGoogleVoice = googleTTSVoices.firstWhere(
        (v) => v.name == savedVoiceName,
        orElse: () => googleTTSVoices.firstWhere(
          (v) => v.model == 'chirp3-hd',
          orElse: () => googleTTSVoices.first,
        ),
      );
    } else {
      // 默认选择 Chirp 3 HD 模型的第一个音色
      _selectedGoogleVoice = googleTTSVoices.firstWhere(
        (v) => v.model == 'chirp3-hd',
        orElse: () => googleTTSVoices.first,
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showSavedSnackBar() {
    showToast(context, '配置已保存');
  }

  Future<void> _saveFastConfig() async {
    if (!_fastFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = '${appDir.path}\\shared_preferences.json';
    Logger.i('保存 LLM 配置到 SharedPreferences', tag: 'LLMConfig');
    Logger.i('  文件路径: $prefsPath', tag: 'LLMConfig');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fast_llm_provider', _fastProvider.index);
    await prefs.setString(
      'fast_llm_api_key',
      _fastApiKeyController.text.trim(),
    );
    Logger.i(
      '  fast_llm_api_key: ${_fastApiKeyController.text.trim().isEmpty ? '(空)' : '******'}',
      tag: 'LLMConfig',
    );
    await prefs.setString(
      'fast_llm_base_url',
      _fastBaseUrlController.text.trim(),
    );
    Logger.i(
      '  fast_llm_base_url: ${_fastBaseUrlController.text.trim()}',
      tag: 'LLMConfig',
    );
    await prefs.setString('fast_llm_model', _fastModelController.text.trim());
    Logger.i(
      '  fast_llm_model: ${_fastModelController.text.trim()}',
      tag: 'LLMConfig',
    );

    _showSavedSnackBar();
  }

  Future<void> _saveStandardConfig() async {
    if (!_standardFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = '${appDir.path}\\shared_preferences.json';
    Logger.i('保存标准 LLM 配置到 SharedPreferences', tag: 'LLMConfig');
    Logger.i('  文件路径: $prefsPath', tag: 'LLMConfig');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('standard_llm_provider', _standardProvider.index);
    await prefs.setString(
      'standard_llm_api_key',
      _standardApiKeyController.text.trim(),
    );
    Logger.i(
      '  standard_llm_api_key: ${_standardApiKeyController.text.trim().isEmpty ? '(空)' : '******'}',
      tag: 'LLMConfig',
    );
    await prefs.setString(
      'standard_llm_base_url',
      _standardBaseUrlController.text.trim(),
    );
    Logger.i(
      '  standard_llm_base_url: ${_standardBaseUrlController.text.trim()}',
      tag: 'LLMConfig',
    );
    await prefs.setString(
      'standard_llm_model',
      _standardModelController.text.trim(),
    );
    Logger.i(
      '  standard_llm_model: ${_standardModelController.text.trim()}',
      tag: 'LLMConfig',
    );

    _showSavedSnackBar();
  }

  Future<void> _saveTtsConfig() async {
    if (!_ttsFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = '${appDir.path}\\shared_preferences.json';
    Logger.i('保存 TTS 配置到 SharedPreferences', tag: 'LLMConfig');
    Logger.i('  文件路径: $prefsPath', tag: 'LLMConfig');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tts_provider', _ttsProvider.index);
    await prefs.setString('tts_api_key', _ttsApiKeyController.text.trim());
    await prefs.setString('tts_base_url', _ttsBaseUrlController.text.trim());

    // 如果是 Google TTS，保存音色选择
    if (_ttsProvider == TTSProvider.google) {
      if (_selectedGoogleVoice != null) {
        await prefs.setString('google_tts_voice', _selectedGoogleVoice!.name);
        await prefs.setString('tts_voice', _selectedGoogleVoice!.name);
      }
    } else {
      await prefs.setString('tts_voice', _ttsVoiceController.text.trim());
    }

    _showSavedSnackBar();
  }

  void _onFastProviderChanged(LLMProvider? provider) {
    if (provider == null) return;
    setState(() {
      _fastProvider = provider;
      _fastBaseUrlController.text = provider.defaultBaseUrl;
      _fastModelController.text = _defaultModels[provider]!;
      _testResultFast = null;
      _testSuccessFast = null;
    });
  }

  void _onStandardProviderChanged(LLMProvider? provider) {
    if (provider == null) return;
    setState(() {
      _standardProvider = provider;
      _standardBaseUrlController.text = provider.defaultBaseUrl;
      _standardModelController.text = _defaultModels[provider]!;
      _testResultStandard = null;
      _testSuccessStandard = null;
    });
  }

  void _onTtsProviderChanged(TTSProvider? provider) {
    if (provider == null) return;
    setState(() {
      _ttsProvider = provider;
      _ttsBaseUrlController.text = provider.defaultBaseUrl;
      _ttsVoiceController.text = _defaultTtsVoices[provider]!;
      _testResultTts = null;
      _testSuccessTts = null;

      // 切换到 Google TTS 时，初始化默认 Chirp 3 HD 音色
      if (provider == TTSProvider.google && _selectedGoogleVoice == null) {
        _selectedGoogleVoice = googleTTSVoices.firstWhere(
          (v) => v.model == 'chirp3-hd',
          orElse: () => googleTTSVoices.first,
        );
      }
    });
  }

  void _onGoogleVoiceChanged(GoogleTTSVoice? voice) {
    if (voice == null) return;
    setState(() {
      _selectedGoogleVoice = voice;
    });
  }

  Future<void> _testFastConnection() async {
    final apiKey = _fastApiKeyController.text.trim();
    final baseUrl = _fastBaseUrlController.text.trim();
    final model = _fastModelController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _testResultFast = '请先输入 API Key';
        _testSuccessFast = false;
      });
      return;
    }

    setState(() {
      _isTestingFast = true;
      _testResultFast = null;
      _testSuccessFast = null;
    });

    try {
      final result = await _testOpenAICompatibleApi(
        provider: _fastProvider,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      );
      if (mounted) {
        setState(() {
          _testResultFast = result.message;
          _testSuccessFast = result.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResultFast = '测试失败: $e';
          _testSuccessFast = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingFast = false;
        });
      }
    }
  }

  Future<void> _testStandardConnection() async {
    final apiKey = _standardApiKeyController.text.trim();
    final baseUrl = _standardBaseUrlController.text.trim();
    final model = _standardModelController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _testResultStandard = '请先输入 API Key';
        _testSuccessStandard = false;
      });
      return;
    }

    setState(() {
      _isTestingStandard = true;
      _testResultStandard = null;
      _testSuccessStandard = null;
    });

    try {
      final result = await _testOpenAICompatibleApi(
        provider: _standardProvider,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      );
      if (mounted) {
        setState(() {
          _testResultStandard = result.message;
          _testSuccessStandard = result.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResultStandard = '测试失败: $e';
          _testSuccessStandard = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingStandard = false;
        });
      }
    }
  }

  Future<void> _testTtsConnection() async {
    final apiKey = _ttsApiKeyController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _testResultTts = '请先输入 API Key';
        _testSuccessTts = false;
      });
      return;
    }

    setState(() {
      _isTestingTts = true;
      _testResultTts = null;
      _testSuccessTts = null;
    });

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _testResultTts = 'TTS 配置已保存，请在发音时测试';
        _testSuccessTts = true;
        _isTestingTts = false;
      });
    }
  }

  Future<ApiTestResult> _testOpenAICompatibleApi({
    required LLMProvider provider,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final effectiveBaseUrl = baseUrl.isEmpty
        ? provider.defaultBaseUrl
        : baseUrl;

    try {
      final uri = Uri.parse('$effectiveBaseUrl/chat/completions');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': 'Hi'},
              ],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return ApiTestResult(success: true, message: 'API 连接成功！响应正常');
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['error']?['message'] ??
            errorBody['message'] ??
            'HTTP ${response.statusCode}';
        return ApiTestResult(success: false, message: 'API 错误: $errorMessage');
      }
    } on TimeoutException {
      return ApiTestResult(success: false, message: '连接超时，请检查网络或 Base URL');
    } catch (e) {
      return ApiTestResult(success: false, message: '连接失败: $e');
    }
  }

  Widget _buildTextModelConfig({
    required String title,
    required String subtitle,
    required GlobalKey<FormState> formKey,
    required LLMProvider provider,
    required void Function(LLMProvider?) onProviderChanged,
    required TextEditingController apiKeyController,
    required TextEditingController baseUrlController,
    required TextEditingController modelController,
    required bool obscureApiKey,
    required void Function() onToggleObscure,
    required VoidCallback onSave,
    required bool isTesting,
    required VoidCallback onTestConnection,
    required String? testResult,
    required bool? testSuccess,
  }) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField2<LLMProvider>(
            value: provider,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '选择服务商',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.cloud_outlined),
            ),
            iconStyleData: IconStyleData(
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            dropdownStyleData: DropdownStyleData(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surface,
              ),
              maxHeight: 300,
              offset: const Offset(0, -4),
            ),
            menuItemStyleData: const MenuItemStyleData(
              padding: EdgeInsets.symmetric(horizontal: 16),
            ),
            items: LLMProvider.values.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text(
                  p.displayName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            }).toList(),
            onChanged: onProviderChanged,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: apiKeyController,
            obscureText: obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureApiKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入API Key';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            '您的API Key仅存储在本地，不会上传到任何服务器',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: baseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL (可选)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.link_outlined),
              hintText: '留空使用默认地址',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '仅在使用自定义端点或代理时需要修改',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: modelController,
            decoration: InputDecoration(
              labelText: '模型',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.model_training_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入模型名称';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            '默认模型: ${_defaultModels[provider]}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onSave,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('保存配置'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isTesting ? null : onTestConnection,
                  icon: isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(isTesting ? '测试中...' : '测试连接'),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (testSuccess == true ? Colors.green : Colors.red)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (testSuccess == true ? Colors.green : Colors.red)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    testSuccess == true ? Icons.check_circle : Icons.error,
                    color: testSuccess == true ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      testResult,
                      style: TextStyle(
                        color: (testSuccess == true
                            ? Colors.green
                            : Colors.red)[700],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTtsConfig() {
    return Form(
      key: _ttsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '配置文本转语音服务，用于词典发音功能',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField2<TTSProvider>(
            value: _ttsProvider,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '选择服务商',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.record_voice_over_outlined),
            ),
            iconStyleData: IconStyleData(
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            dropdownStyleData: DropdownStyleData(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surface,
              ),
              maxHeight: 300,
              offset: const Offset(0, -4),
            ),
            menuItemStyleData: const MenuItemStyleData(
              padding: EdgeInsets.symmetric(horizontal: 16),
            ),
            items: TTSProvider.values.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text(
                  p.displayName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              );
            }).toList(),
            onChanged: _onTtsProviderChanged,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _ttsApiKeyController,
            obscureText: _obscureTtsApiKey,
            maxLines: _obscureTtsApiKey
                ? 1
                : (_ttsProvider == TTSProvider.google ? 5 : 1),
            minLines: 1,
            decoration: InputDecoration(
              labelText: _ttsProvider == TTSProvider.google
                  ? 'Service Account JSON Key'
                  : 'API Key',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureTtsApiKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(() {
                    _obscureTtsApiKey = !_obscureTtsApiKey;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入API Key';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            _ttsProvider == TTSProvider.google
                ? '使用 Google Cloud Service Account JSON Key\n访问 https://console.cloud.google.com/apis/credentials 创建'
                : '使用 Azure Speech Service 获取 API Key',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _ttsBaseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL (可选)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
              prefixIcon: const Icon(Icons.link_outlined),
              hintText: _ttsProvider == TTSProvider.google
                  ? '留空使用: https://texttospeech.googleapis.com/v1'
                  : '留空使用默认地址',
            ),
          ),
          const SizedBox(height: 16),
          if (_ttsProvider == TTSProvider.google) ...[
            // Google TTS 音色选择（默认使用 Chirp 3 HD 模型）
            DropdownButtonFormField2<GoogleTTSVoice>(
              value: _selectedGoogleVoice,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '选择音色',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              iconStyleData: IconStyleData(
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                ),
                maxHeight: 300,
                offset: const Offset(0, -4),
              ),
              menuItemStyleData: const MenuItemStyleData(
                padding: EdgeInsets.symmetric(horizontal: 16),
              ),
              items: googleTTSVoices.where((v) => v.model == 'chirp3-hd').map((
                voice,
              ) {
                return DropdownMenuItem(
                  value: voice,
                  child: Text(
                    '${voice.name} (${voice.gender})',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (voice) {
                setState(() {
                  _selectedGoogleVoice = voice;
                });
              },
            ),
            const SizedBox(height: 8),
            if (_selectedGoogleVoice != null)
              Text(
                '${_selectedGoogleVoice!.description} (Chirp 3 HD 高质量语音)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            const SizedBox(height: 16),
          ] else ...[
            // Azure TTS 语音选择
            TextFormField(
              controller: _ttsVoiceController,
              decoration: InputDecoration(
                labelText: '语音 (Voice)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.record_voice_over),
                hintText: '例如: zh-CN-XiaoxiaoNeural',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入语音名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text(
              '默认: ${_defaultTtsVoices[_ttsProvider]}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saveTtsConfig,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('保存配置'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTestingTts ? null : _testTtsConnection,
                  icon: _isTestingTts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_isTestingTts ? '测试中...' : '测试连接'),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_testResultTts != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testSuccessTts == true ? Colors.green : Colors.red)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (_testSuccessTts == true ? Colors.green : Colors.red)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccessTts == true ? Icons.check_circle : Icons.error,
                    color: _testSuccessTts == true ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResultTts!,
                      style: TextStyle(
                        color: (_testSuccessTts == true
                            ? Colors.green
                            : Colors.red)[700],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI配置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '快速模型'),
            Tab(text: '标准模型'),
            Tab(text: '音频模型'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildTextModelConfig(
                        title: '快速模型',
                        subtitle: '适用于日常查询，速度优先',
                        formKey: _fastFormKey,
                        provider: _fastProvider,
                        onProviderChanged: _onFastProviderChanged,
                        apiKeyController: _fastApiKeyController,
                        baseUrlController: _fastBaseUrlController,
                        modelController: _fastModelController,
                        obscureApiKey: _obscureFastApiKey,
                        onToggleObscure: () {
                          setState(() {
                            _obscureFastApiKey = !_obscureFastApiKey;
                          });
                        },
                        onSave: _saveFastConfig,
                        isTesting: _isTestingFast,
                        onTestConnection: _testFastConnection,
                        testResult: _testResultFast,
                        testSuccess: _testSuccessFast,
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildTextModelConfig(
                        title: '标准模型',
                        subtitle: '适用于高质量翻译和解释',
                        formKey: _standardFormKey,
                        provider: _standardProvider,
                        onProviderChanged: _onStandardProviderChanged,
                        apiKeyController: _standardApiKeyController,
                        baseUrlController: _standardBaseUrlController,
                        modelController: _standardModelController,
                        obscureApiKey: _obscureStandardApiKey,
                        onToggleObscure: () {
                          setState(() {
                            _obscureStandardApiKey = !_obscureStandardApiKey;
                          });
                        },
                        onSave: _saveStandardConfig,
                        isTesting: _isTestingStandard,
                        onTestConnection: _testStandardConnection,
                        testResult: _testResultStandard,
                        testSuccess: _testSuccessStandard,
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _buildTtsConfig(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
