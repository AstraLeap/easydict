import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';
import 'llm_client.dart';
import 'preferences_service.dart';

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
          delay = Duration(
            milliseconds: (delay.inMilliseconds * 2).round(),
          );
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
  Stream<LLMChunk> summarizeDictionaryStream(String jsonContent) {
    const systemPrompt =
        '你是一位专业的词典内容解析师，擅长从词典数据中提炼关键语言信息。'
        '请对提供的词典 JSON 数据进行分析，输出结构清晰的 Markdown 总结，内容包括：\n'
        '1. **核心含义**：列出主要词义及词性，表述简洁\n'
        '2. **词源 / 构词**（如有）：简述词根、词缀或来源\n'
        '3. **重要搭配与例句**：优先列出高频、实用的搭配和典型例句\n'
        '4. **语言要点**：发音、用法区分、常见错误或文体色彩等值得注意之处\n'
        '输出要条理分明，篇幅适中，以学习者视角呈现最有价值的信息。';

    final prompt =
        '请分析以下词典 JSON 数据：\n\n'
        '```json\n'
        '$jsonContent\n'
        '```\n\n'
        '按照要求输出结构化总结。';

    return chatStream(prompt, systemPrompt: systemPrompt);
  }

  /// 询问AI关于词典元素的流式版本
  Stream<LLMChunk> askAboutElementStream(
    String elementJson,
    String path,
    String question,
  ) {
    const systemPrompt =
        '你是一位专业的语言学老师，擅长词汇、语法、翻译和语言文化解析。'
        '用户会向你展示词典中的某段具体内容（如例句、释义、搭配、词源等），并提出问题。'
        '请结合语言学知识和实际用法，给出准确、有深度的解答。'
        '回答要简洁清晰、重点突出，语言风格贴近语言学习者的需求。';

    final prompt =
        '词典路径：$path\n\n'
        '内容：\n'
        '```json\n'
        '$elementJson\n'
        '```\n\n'
        '问题：$question\n\n'
        '请针对上述内容和问题，给出专业、实用的解答。';

    return chatStream(prompt, systemPrompt: systemPrompt);
  }

  /// 自由聊天流式版本
  Stream<LLMChunk> freeChatStream(
    String question, {
    required List<Map<String, String>> history,
    String? context,
  }) {
    const systemPrompt =
        '你是一位专业的语言学习助手，擅长词汇解析、语法说明、翻译辨析和语言文化知识。'
        '请提供准确、有帮助的回答，语言简洁明了。'
        '若用户提供了学习上下文（如词典条目、例句等），请充分结合上下文作答，避免孤立回答。'
        '对于语言相关问题，适当举例说明，帮助用户加深理解。';

    String fullQuestion = question;
    if (context != null && context.isNotEmpty) {
      fullQuestion = '当前学习上下文：\n$context\n\n用户问题：$question';
    }

    return chatWithHistoryStream(
      fullQuestion,
      history: history,
      systemPrompt: systemPrompt,
    );
  }

  Future<List<int>> textToSpeech(String text, {String? languageCode}) async {
    final config = await _prefsService.getTTSConfig();
    if (config == null) {
      throw Exception('未配置TTS服务，请先在设置中配置API');
    }

    final provider = config['provider'] as String;
    var apiKey = config['apiKey'] as String;
    final baseUrl = config['baseUrl'] as String;
    final model = config['model'] as String;
    var voice = config['voice'] as String;

    Logger.d(
      'textToSpeech: provider=$provider, languageCode=$languageCode, defaultVoice=$voice',
      tag: 'textToSpeech',
    );

    // 如果提供了语言代码，尝试获取该语言对应的音色
    if (languageCode != null &&
        languageCode.isNotEmpty &&
        languageCode != 'text') {
      final prefs = await SharedPreferences.getInstance();
      final langVoiceKey = 'voice_$languageCode';
      final langVoice = prefs.getString(langVoiceKey);
      Logger.d(
        '查找音色: key=$langVoiceKey, value=$langVoice',
        tag: 'textToSpeech',
      );
      if (langVoice != null && langVoice.isNotEmpty) {
        voice = langVoice;
        Logger.d('使用语言音色: $languageCode -> $voice', tag: 'textToSpeech');
      }
    }

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
        return await _callEdgeTTS(voice: voice, text: text);
      case 'google':
        return await _callGoogleTTS(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          voice: voice,
          text: text,
        );
      case 'azure':
        return await _callAzureTTS(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          voice: voice,
          text: text,
        );
      default:
        throw Exception('不支持的TTS服务商: $provider');
    }
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
