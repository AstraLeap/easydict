import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/llm_config_page.dart';

/// AI服务类，用于调用大模型API
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  /// 获取LLM配置
  Future<Map<String, dynamic>?> _getLLMConfig({bool isFast = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = isFast ? 'fast_llm' : 'standard_llm';

    final providerIndex = prefs.getInt('${prefix}_provider');
    if (providerIndex == null) return null;

    return {
      'provider': LLMProvider.values[providerIndex],
      'apiKey': prefs.getString('${prefix}_api_key') ?? '',
      'baseUrl': prefs.getString('${prefix}_base_url') ?? '',
      'model': prefs.getString('${prefix}_model') ?? '',
    };
  }

  /// 调用AI进行对话
  Future<String> chat(
    String prompt, {
    String? systemPrompt,
    bool useFastModel = false,
  }) async {
    final config = await _getLLMConfig(isFast: useFastModel);
    if (config == null) {
      throw Exception('未配置${useFastModel ? "快速" : "标准"}AI模型，请先在设置中配置API');
    }

    final apiKey = config['apiKey'] as String;
    final baseUrl = config['baseUrl'] as String;
    final model = config['model'] as String;
    final provider = config['provider'] as LLMProvider;

    if (apiKey.isEmpty) {
      throw Exception('未配置API Key');
    }

    final effectiveBaseUrl = baseUrl.isEmpty
        ? provider.defaultBaseUrl
        : baseUrl;

    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return await _callOpenAICompatibleApi(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case LLMProvider.anthropic:
        return await _callAnthropicApi(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
      case LLMProvider.gemini:
        return await _callGeminiApi(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
    }
  }

  /// 翻译文本
  Future<String> translate(String text, String targetLang) async {
    const systemPrompt =
        "You are a professional translator. Translate the following text into the target language. Only provide the translation result, no explanations or other text.";
    final prompt = "Target Language: $targetLang\nText: $text";

    return await chat(prompt, systemPrompt: systemPrompt, useFastModel: true);
  }

  /// 调用OpenAI兼容API
  Future<String> _callOpenAICompatibleApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
  }) async {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 调用Anthropic API
  Future<String> _callAnthropicApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'system': systemPrompt,
        'max_tokens': 4096,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 调用Google Gemini API
  Future<String> _callGeminiApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
  }) async {
    final url = '$baseUrl/models/$model:generateContent?key=$apiKey';

    final parts = <Map<String, String>>[
      {'text': prompt},
    ];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      parts.insert(0, {'text': 'System: $systemPrompt\n\n'});
    }

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {'parts': parts},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 总结词典JSON内容
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

  /// 询问特定JSON元素
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

  /// 连续对话 - 支持多轮对话上下文
  Future<String> chatWithHistory(
    String question, {
    required List<Map<String, String>> history,
    String? systemPrompt,
    bool useFastModel = false,
  }) async {
    final config = await _getLLMConfig(isFast: useFastModel);
    if (config == null) {
      throw Exception('未配置${useFastModel ? "快速" : "标准"}AI模型，请先在设置中配置API');
    }

    final apiKey = config['apiKey'] as String;
    final baseUrl = config['baseUrl'] as String;
    final model = config['model'] as String;
    final provider = config['provider'] as LLMProvider;

    if (apiKey.isEmpty) {
      throw Exception('未配置API Key');
    }

    final effectiveBaseUrl = baseUrl.isEmpty
        ? provider.defaultBaseUrl
        : baseUrl;

    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return await _callOpenAICompatibleApiWithHistory(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
        );
      case LLMProvider.anthropic:
        return await _callAnthropicApiWithHistory(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
        );
      case LLMProvider.gemini:
        return await _callGeminiApiWithHistory(
          baseUrl: effectiveBaseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
        );
    }
  }

  /// 调用OpenAI兼容API（支持历史对话）
  Future<String> _callOpenAICompatibleApiWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) async {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    // 添加历史对话
    messages.addAll(history);
    // 添加当前问题
    messages.add({'role': 'user', 'content': question});

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 调用Anthropic API（支持历史对话）
  Future<String> _callAnthropicApiWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) async {
    final messages = <Map<String, String>>[];
    // 添加历史对话
    messages.addAll(history);
    // 添加当前问题
    messages.add({'role': 'user', 'content': question});

    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'system': systemPrompt,
        'max_tokens': 4096,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 调用Google Gemini API（支持历史对话）
  Future<String> _callGeminiApiWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) async {
    final url = '$baseUrl/models/$model:generateContent?key=$apiKey';

    final contents = <Map<String, dynamic>>[];
    
    // 添加历史对话
    for (final msg in history) {
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      contents.add({
        'role': role,
        'parts': [{'text': msg['content']}],
      });
    }
    
    // 添加当前问题
    contents.add({
      'role': 'user',
      'parts': [{'text': question}],
    });

    final requestBody = <String, dynamic>{
      'contents': contents,
    };
    
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      requestBody['systemInstruction'] = {
        'parts': [{'text': systemPrompt}],
      };
    }

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  /// 自由对话（支持连续对话）
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
}
