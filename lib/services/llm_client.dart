import 'dart:convert';
import 'package:http/http.dart' as http;
import '../pages/llm_config_page.dart';

class LLMClient {
  static final LLMClient _instance = LLMClient._internal();
  factory LLMClient() => _instance;
  LLMClient._internal();

  Future<String> callApi({
    required LLMProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return await _callOpenAICompatible(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
          temperature: temperature,
        );
      case LLMProvider.anthropic:
        return await _callAnthropic(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
        );
      case LLMProvider.gemini:
        return await _callGemini(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
        );
    }
  }

  Future<String> callApiWithHistory({
    required LLMProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return await _callOpenAICompatibleWithHistory(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
          temperature: temperature,
        );
      case LLMProvider.anthropic:
        return await _callAnthropicWithHistory(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
        );
      case LLMProvider.gemini:
        return await _callGeminiWithHistory(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
        );
    }
  }

  Future<String> _callOpenAICompatible({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    double temperature = 0.7,
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
        'temperature': temperature,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> _callOpenAICompatibleWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    double temperature = 0.7,
  }) async {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.addAll(history);
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
        'temperature': temperature,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> _callAnthropic({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 4096,
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
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> _callAnthropicWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    int maxTokens = 4096,
  }) async {
    final messages = <Map<String, String>>[];
    messages.addAll(history);
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
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'] as String;
    } else {
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> _callGemini({
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

  Future<String> _callGeminiWithHistory({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) async {
    final url = '$baseUrl/models/$model:generateContent?key=$apiKey';

    final contents = <Map<String, dynamic>>[];

    for (final msg in history) {
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      contents.add({
        'role': role,
        'parts': [
          {'text': msg['content']},
        ],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': question},
      ],
    });

    final requestBody = <String, dynamic>{'contents': contents};

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      requestBody['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt},
        ],
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
}
