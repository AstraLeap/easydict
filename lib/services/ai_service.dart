import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';
import 'llm_client.dart';
import 'preferences_service.dart';

/// 语言默认音色映射（Edge TTS）
const Map<String, String> _edgeDefaultVoicesByLanguage = {
  'en': 'en-US-AriaNeural',
  'zh': 'zh-CN-XiaoxiaoNeural',
  'jp': 'ja-JP-NanamiNeural',
  'ko': 'ko-KR-SunHiNeural',
  'fr': 'fr-FR-DeniseNeural',
  'de': 'de-DE-KatjaNeural',
  'es': 'es-ES-ElviraNeural',
  'it': 'it-IT-ElsaNeural',
  'ru': 'ru-RU-SvetlanaNeural',
  'pt': 'pt-BR-FranciscaNeural',
  'ar': 'ar-EG-SalmaNeural',
};

/// 语言默认音色映射（Google TTS）
const Map<String, String> _googleDefaultVoicesByLanguage = {
  'en': 'en-US-Chirp3-HD-Aoede',
  'zh': 'cmn-CN-Chirp3-HD-A',
  'jp': 'ja-JP-Chirp3-HD-A',
  'ko': 'ko-KR-Chirp3-HD-A',
  'fr': 'fr-FR-Chirp3-HD-A',
  'de': 'de-DE-Chirp3-HD-A',
  'es': 'es-ES-Chirp3-HD-A',
  'it': 'it-IT-Chirp3-HD-A',
  'ru': 'ru-RU-Chirp3-HD-A',
  'pt': 'pt-BR-Chirp3-HD-A',
  'ar': 'ar-XA-Chirp3-HD-A',
};

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final _llmClient = LLMClient();
  final _prefsService = PreferencesService();

  /// 带指数退避的自动重试
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() fn, {
    int maxRetries = 2,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    Duration delay = initialDelay;
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          Logger.w(
            'AI 请求失败 (第 ${attempt + 1} 次)，${delay.inSeconds}s 后重试: $e',
            tag: 'AIService',
          );
          await Future.delayed(delay);
          delay = Duration(milliseconds: (delay.inMilliseconds * 2).round());
        }
      }
    }
    throw lastError!;
  }

  Future<String> chat(
    String prompt, {
    String? systemPrompt,
    bool useFastModel = false,
  }) async {
    final config = await _prefsService.getLLMConfig(isFast: useFastModel);
    if (config == null) {
      throw Exception('未配置${useFastModel ? "快速" : "标准"}AI模型，请先在设置中配置API');
    }

    if (!config.isValid) {
      throw Exception('未配置API Key');
    }

    return await _retryWithBackoff(
      () => _llmClient.callApi(
        provider: config.provider,
        baseUrl: config.effectiveBaseUrl,
        apiKey: config.apiKey,
        model: config.model,
        prompt: prompt,
        systemPrompt: systemPrompt,
      ),
    );
  }

  Future<String> translate(
    String text,
    String targetLang, {
    String? systemPrompt,
  }) async {
    final effectiveSystemPrompt =
        systemPrompt ??
        'You are a professional translator. '
            'Translate the given text into the specified target language naturally and accurately. '
            'Preserve the original meaning, tone, and any technical or domain-specific terminology. '
            'Output only the translated text — no explanations, no commentary, no extra formatting.';
    final prompt = 'Target Language: $targetLang\n\n$text';

    return await chat(
      prompt,
      systemPrompt: effectiveSystemPrompt,
      useFastModel: true,
    );
  }

  // ─────────────────────────────────────────────
  // 流式接口
  // ─────────────────────────────────────────────

  /// 单轮对话流式版本
  Stream<LLMChunk> chatStream(
    String prompt, {
    String? systemPrompt,
    bool useFastModel = false,
  }) async* {
    final config = await _prefsService.getLLMConfig(isFast: useFastModel);
    if (config == null) {
      throw Exception('未配置${useFastModel ? "快速" : "标准"}AI模型，请先在设置中配置API');
    }
    if (!config.isValid) {
      throw Exception('未配置API Key');
    }
    yield* _llmClient.callApiStream(
      provider: config.provider,
      baseUrl: config.effectiveBaseUrl,
      apiKey: config.apiKey,
      model: config.model,
      prompt: prompt,
      systemPrompt: systemPrompt,
      enableThinking: config.enableThinking,
    );
  }

  /// 多轮对话流式版本
  Stream<LLMChunk> chatWithHistoryStream(
    String question, {
    required List<Map<String, String>> history,
    String? systemPrompt,
    bool useFastModel = false,
  }) async* {
    final config = await _prefsService.getLLMConfig(isFast: useFastModel);
    if (config == null) {
      throw Exception('未配置${useFastModel ? "快速" : "标准"}AI模型，请先在设置中配置API');
    }
    if (!config.isValid) {
      throw Exception('未配置API Key');
    }
    yield* _llmClient.callApiWithHistoryStream(
      provider: config.provider,
      baseUrl: config.effectiveBaseUrl,
      apiKey: config.apiKey,
      model: config.model,
      question: question,
      history: history,
      systemPrompt: systemPrompt,
      enableThinking: config.enableThinking,
    );
  }

  /// 词典内容总结流式版本
  Stream<LLMChunk> summarizeDictionaryStream(
    String jsonContent, {
    String appLanguage = 'English',
    String?
    instruction, // e.g. 'Be more concise.' or 'Be more detailed and comprehensive.'
  }) {
    final systemPrompt =
        'You are a professional dictionary content analyst, skilled at distilling key linguistic information from dictionary data. '
        'Analyze the provided dictionary JSON data and output a well-structured Markdown summary covering:\n'
        '1. **Core Meanings**: List the main senses and parts of speech concisely\n'
        '2. **Etymology / Word Formation** (if available): Briefly describe roots, affixes, or origins\n'
        '3. **Key Collocations & Examples**: Prioritize high-frequency, practical collocations and typical example sentences\n'
        '4. **Language Notes**: Pronunciation, usage distinctions, common errors, or register worth noting\n'
        'Keep the output well-organized and appropriately concise, presenting the most valuable information from a learner\'s perspective.\n'
        'Respond in $appLanguage.';

    String prompt =
        'Analyze the following dictionary JSON data and output a structured summary as instructed.';
    if (instruction != null && instruction.isNotEmpty) {
      prompt += ' $instruction';
    }

    final fullPrompt = '$prompt\n\n```json\n$jsonContent\n```';

    return chatStream(fullPrompt, systemPrompt: systemPrompt);
  }

  /// 询问AI关于词典元素的流式版本
  Stream<LLMChunk> askAboutElementStream(
    String elementJson,
    String question, {
    String appLanguage = 'English',
  }) {
    final systemPrompt =
        'You are a professional language teacher with expertise in vocabulary, grammar, translation, and linguistic culture. '
        'The user will show you a specific piece of content from a dictionary (such as an example sentence, definition, collocation, or etymology) and ask a question. '
        'Provide accurate, in-depth answers drawing on linguistic knowledge and real-world usage. '
        'Keep your response concise and focused.\n'
        'Respond in $appLanguage.';

    final prompt =
        'Dictionary content:\n'
        '```json\n'
        '$elementJson\n'
        '```\n\n'
        'Question: $question';

    return chatStream(prompt, systemPrompt: systemPrompt);
  }

  /// 自由聊天流式版本
  Stream<LLMChunk> freeChatStream(
    String question, {
    required List<Map<String, String>> history,
    String? context,
    String appLanguage = 'English',
  }) {
    final systemPrompt =
        'You are a professional language learning assistant with expertise in vocabulary analysis, grammar, translation, and linguistic culture. '
        'Provide accurate and helpful answers in a clear, concise style. '
        'If the user provides a learning context (such as a dictionary entry or example sentence), incorporate it into your response.\n'
        'Respond in $appLanguage.';

    String fullQuestion = question;
    if (context != null && context.isNotEmpty) {
      fullQuestion = 'Context:\n$context\n\nQuestion: $question';
    }

    return chatWithHistoryStream(
      fullQuestion,
      history: history,
      systemPrompt: systemPrompt,
    );
  }

  Future<({List<int> audio, String voice})> textToSpeech(
    String text, {
    String? languageCode,
    String? languageSource,
  }) async {
    final config = await _prefsService.getTTSConfig();
    if (config == null) {
      throw Exception('未配置TTS服务，请先在设置中配置API');
    }

    final provider = config['provider'] as String;
    var apiKey = config['apiKey'] as String;
    final baseUrl = config['baseUrl'] as String;
    final model = config['model'] as String;
    final voice = await getVoiceForLanguage(
      languageCode,
      languageSource,
      config,
    );

    // Edge TTS 不需要 API Key
    if (apiKey.isEmpty) {
      if (provider == 'google') {
        throw Exception(
          'Google TTS 需要配置 API Key。请访问 https://console.cloud.google.com 创建项目并启用 Cloud Text-to-Speech API',
        );
      } else if (provider == 'azure') {
        throw Exception('未配置API Key');
      }
    }

    switch (provider) {
      case 'edge':
        final audio = await _callEdgeTTS(voice: voice, text: text);
        return (audio: audio, voice: voice);
      case 'google':
        final audio = await _callGoogleTTS(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          voice: voice,
          text: text,
        );
        return (audio: audio, voice: voice);
      case 'azure':
        final audio = await _callAzureTTS(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          voice: voice,
          text: text,
        );
        return (audio: audio, voice: voice);
      default:
        throw Exception('不支持的TTS服务商: $provider');
    }
  }

  Future<String> getVoiceForLanguage(
    String? languageCode,
    String? languageSource,
    Map<String, dynamic>? config,
  ) async {
    config ??= await _prefsService.getTTSConfig();
    if (config == null) {
      throw Exception('未配置TTS服务');
    }

    final provider = config['provider'] as String;
    var voice = config['voice'] as String;

    Logger.d(
      'getVoiceForLanguage: languageCode=$languageCode, defaultVoice=$voice',
      tag: 'getVoiceForLanguage',
    );

    if (languageCode != null &&
        languageCode.isNotEmpty &&
        languageCode != 'text') {
      final prefs = await SharedPreferences.getInstance();
      final langVoiceKey = 'voice_$languageCode';
      final langVoice = prefs.getString(langVoiceKey);
      if (langVoice != null && langVoice.isNotEmpty) {
        voice = langVoice;
        Logger.d(
          '根据 $languageSource 选择音色: $languageCode -> $voice',
          tag: 'getVoiceForLanguage',
        );
      } else {
        final defaultLangVoice = provider == 'google'
            ? _googleDefaultVoicesByLanguage[languageCode]
            : _edgeDefaultVoicesByLanguage[languageCode];
        if (defaultLangVoice != null && defaultLangVoice.isNotEmpty) {
          voice = defaultLangVoice;
          Logger.d(
            '未找到语言 $languageCode 的音色配置，回退到该语言默认音色: $voice',
            tag: 'getVoiceForLanguage',
          );
        }
      }
    }
    return voice;
  }

  Future<List<int>> _callEdgeTTS({
    required String voice,
    required String text,
  }) async {
    // 尝试使用用户选择的音色，如果失败则使用默认音色
    final fallbackVoices = [
      voice,
      'en-US-AriaNeural',
      'en-US-JennyNeural',
      'zh-CN-XiaoxiaoNeural',
    ];

    for (final currentVoice in fallbackVoices) {
      if (currentVoice.isEmpty) continue;

      try {
        Logger.d('Edge TTS 尝试音色: $currentVoice', tag: '_callEdgeTTS');

        final communicate = Communicate(text: text, voice: currentVoice);

        final List<int> audioData = [];

        await for (final chunk in communicate.stream()) {
          if (chunk.type == "audio" && chunk.audioData != null) {
            audioData.addAll(chunk.audioData!);
          }
        }

        if (audioData.isNotEmpty) {
          Logger.d('Edge TTS 成功使用音色: $currentVoice', tag: '_callEdgeTTS');
          return audioData;
        }
      } catch (e) {
        Logger.w('Edge TTS 音色 $currentVoice 失败: $e', tag: '_callEdgeTTS');
        continue;
      }
    }

    Logger.e('Edge TTS 所有音色都失败', tag: '_callEdgeTTS');
    throw Exception('Edge TTS 返回的音频数据为空');
  }

  Future<List<int>> _callGoogleTTS({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String voice,
    required String text,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception(
        'Google TTS 需要配置 Service Account JSON Key。请访问 https://console.cloud.google.com/apis/credentials 创建',
      );
    }

    try {
      final serviceAccountCredentials = ServiceAccountCredentials.fromJson(
        apiKey,
      );
      final scopes = [tts.TexttospeechApi.cloudPlatformScope];
      final client = await clientViaServiceAccount(
        serviceAccountCredentials,
        scopes,
      );

      try {
        final ttsApi = tts.TexttospeechApi(client);

        String languageCode = 'en-US';
        String voiceName = voice;

        if (['Zeus', 'Charon', 'Eros', 'Hera'].contains(voice)) {
          voiceName = 'en-US-Neural2-F';
        }

        final parts = voiceName.split('-');
        if (parts.length >= 2) {
          languageCode = '${parts[0]}-${parts[1]}';
        }

        final input = tts.SynthesisInput(text: text);
        final voiceSelection = tts.VoiceSelectionParams(
          languageCode: languageCode,
          name: voiceName.isNotEmpty ? voiceName : 'en-US-Neural2-F',
        );
        final audioConfig = tts.AudioConfig(audioEncoding: 'MP3');

        final request = tts.SynthesizeSpeechRequest(
          input: input,
          voice: voiceSelection,
          audioConfig: audioConfig,
        );

        final response = await ttsApi.text.synthesize(request);

        if (response.audioContent != null) {
          return base64Decode(response.audioContent!);
        } else {
          throw Exception('Google TTS API返回的音频内容为空');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      Logger.e('Google TTS API调用失败: $e', tag: '_callGoogleTTS', error: e);
      throw Exception('Google TTS API调用失败: $e');
    }
  }

  Future<List<int>> _callAzureTTS({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String voice,
    required String text,
  }) async {
    final effectiveBaseUrl = baseUrl.isEmpty
        ? 'https://eastus.tts.speech.microsoft.com/cognitiveservices/v1'
        : baseUrl;

    final response = await http.post(
      Uri.parse(effectiveBaseUrl),
      headers: {
        'Ocp-Apim-Subscription-Key': apiKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
      },
      body:
          '''<speak version='1.0' xml:lang='zh-CN'>
    <voice xml:lang='$voice' name='$voice'>
      <s>$text</s>
    </voice>
  </speak>''',
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception(
        'Azure TTS API调用失败: ${response.statusCode} - ${response.body}',
      );
    }
  }
}
