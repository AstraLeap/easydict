import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import '../logger.dart';
import 'llm_client.dart';
import 'preferences_service.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final _llmClient = LLMClient();
  final _prefsService = PreferencesService();

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

    return await _llmClient.callApi(
      provider: config.provider,
      baseUrl: config.effectiveBaseUrl,
      apiKey: config.apiKey,
      model: config.model,
      prompt: prompt,
      systemPrompt: systemPrompt,
    );
  }

  Future<String> translate(String text, String targetLang) async {
    const systemPrompt =
        "You are a professional translator. Translate the following text into the target language. Only provide the translation result, no explanations or other text.";
    final prompt = "Target Language: $targetLang\nText: $text";

    return await chat(prompt, systemPrompt: systemPrompt, useFastModel: true);
  }

  Future<String> summarizeDictionary(String jsonContent) async {
    const systemPrompt =
        "你是一个专业的词典内容分析师。你的任务是分析词典JSON数据并提供简洁、有用的总结。"
        "请从以下几个方面进行分析："
        "1. 单词的主要含义和用法"
        "2. 词源信息（如果有）"
        "3. 重要的搭配和例句"
        "4. 任何特别的语言点或注意事项"
        "请以清晰、易读的格式输出，使用Markdown格式。";

    final prompt =
        "请分析以下词典JSON数据并提供总结：\n\n"
        "```json\n"
        "$jsonContent\n"
        "```\n\n"
        "请提供详细的分析和总结。";

    return await chat(prompt, systemPrompt: systemPrompt);
  }

  Future<String> askAboutElement(
    String elementJson,
    String path,
    String question,
  ) async {
    const systemPrompt =
        "你是一个专业的语言学习助手。用户会提供词典中的特定内容，请你根据这些内容回答用户的问题。"
        "请提供准确、有帮助的回答，并尽可能结合上下文给出解释。";

    final prompt =
        "JSON路径: $path\n\n"
        "内容:\n"
        "```json\n"
        "$elementJson\n"
        "```\n\n"
        "用户问题: $question\n\n"
        "请根据以上内容回答问题。";

    return await chat(prompt, systemPrompt: systemPrompt);
  }

  Future<String> chatWithHistory(
    String question, {
    required List<Map<String, String>> history,
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

    return await _llmClient.callApiWithHistory(
      provider: config.provider,
      baseUrl: config.effectiveBaseUrl,
      apiKey: config.apiKey,
      model: config.model,
      question: question,
      history: history,
      systemPrompt: systemPrompt,
    );
  }

  Future<String> freeChat(
    String question, {
    required List<Map<String, String>> history,
    String? context,
  }) async {
    const systemPrompt =
        "你是一个专业的语言学习助手。用户可能正在学习词汇或语言相关内容。"
        "请提供准确、有帮助的回答，如果用户提供了上下文信息，请结合上下文回答。";

    String fullQuestion = question;
    if (context != null && context.isNotEmpty) {
      fullQuestion = "当前学习上下文:\n$context\n\n用户问题: $question";
    }

    return await chatWithHistory(
      fullQuestion,
      history: history,
      systemPrompt: systemPrompt,
    );
  }

  Future<List<int>> textToSpeech(String text) async {
    final config = await _prefsService.getTTSConfig();
    if (config == null) {
      throw Exception('未配置TTS服务，请先在设置中配置API');
    }

    final provider = config['provider'] as String;
    final apiKey = config['apiKey'] as String;
    final baseUrl = config['baseUrl'] as String;
    final model = config['model'] as String;
    final voice = config['voice'] as String;

    if (apiKey.isEmpty) {
      if (provider == 'google') {
        throw Exception(
          'Google TTS 需要配置 API Key。请访问 https://console.cloud.google.com 创建项目并启用 Cloud Text-to-Speech API',
        );
      } else {
        throw Exception('未配置API Key');
      }
    }

    switch (provider) {
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
