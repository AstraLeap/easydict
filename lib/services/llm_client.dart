import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../pages/llm_config_page.dart';

/// 流式输出的一个数据块
class LLMChunk {
  /// 正文增量（可为 null）
  final String? text;

  /// 思考过程增量（可为 null，仅支持深度思考的模型会有）
  final String? thinking;

  const LLMChunk({this.text, this.thinking});
}

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

  // ─────────────────────────────────────────────
  // 流式输出接口
  // ─────────────────────────────────────────────

  /// 单轮对话流式版本
  Stream<LLMChunk> callApiStream({
    required LLMProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
    bool enableThinking = false,
  }) {
    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return _callOpenAICompatibleStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
          temperature: temperature,
          provider: provider,
          enableThinking: enableThinking,
        );
      case LLMProvider.anthropic:
        return _callAnthropicStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          enableThinking: enableThinking,
        );
      case LLMProvider.gemini:
        return _callGeminiStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          systemPrompt: systemPrompt,
          enableThinking: enableThinking,
        );
    }
  }

  /// 多轮对话流式版本
  Stream<LLMChunk> callApiWithHistoryStream({
    required LLMProvider provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
    bool enableThinking = false,
  }) {
    switch (provider) {
      case LLMProvider.openAI:
      case LLMProvider.deepseek:
      case LLMProvider.moonshot:
      case LLMProvider.zhipu:
      case LLMProvider.ali:
      case LLMProvider.custom:
        return _callOpenAICompatibleWithHistoryStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
          temperature: temperature,
          provider: provider,
          enableThinking: enableThinking,
        );
      case LLMProvider.anthropic:
        return _callAnthropicWithHistoryStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          enableThinking: enableThinking,
        );
      case LLMProvider.gemini:
        return _callGeminiWithHistoryStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          question: question,
          history: history,
          systemPrompt: systemPrompt,
          enableThinking: enableThinking,
        );
    }
  }

  // ─────────────────────────────────────────────
  // OpenAI-compatible 流式实现（含 DeepSeek / Moonshot / 智谱 / 通义 / 自定义）
  // ─────────────────────────────────────────────

  Stream<LLMChunk> _callOpenAICompatibleStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    double temperature = 0.7,
    LLMProvider provider = LLMProvider.custom,
    bool enableThinking = false,
  }) async* {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});
    yield* _openAICompatibleSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
      provider: provider,
      enableThinking: enableThinking,
    );
  }

  Stream<LLMChunk> _callOpenAICompatibleWithHistoryStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    double temperature = 0.7,
    LLMProvider provider = LLMProvider.custom,
    bool enableThinking = false,
  }) async* {
    final messages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.addAll(history);
    messages.add({'role': 'user', 'content': question});
    yield* _openAICompatibleSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
      provider: provider,
      enableThinking: enableThinking,
    );
  }

  /// 核心 SSE 解析逻辑（OpenAI-compatible）
  Stream<LLMChunk> _openAICompatibleSseStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    LLMProvider provider = LLMProvider.custom,
    bool enableThinking = false,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Accept'] = 'text/event-stream';

      final body = <String, dynamic>{
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      };

      // 各厂商深度思考参数
      if (enableThinking) {
        switch (provider) {
          case LLMProvider.openAI:
            // o1/o3/o4 系列用 reasoning_effort
            body['reasoning_effort'] = 'high';
            break;
          case LLMProvider.ali:
            // 通义千问3 / Qwen3 系列
            body['enable_thinking'] = true;
            break;
          case LLMProvider.zhipu:
            // GLM-Z1 系列
            body['extra'] = {'thinking_mode': 'auto'};
            break;
          case LLMProvider.deepseek:
          case LLMProvider.moonshot:
          case LLMProvider.custom:
            // DeepSeek-R1 会自动在 delta 中返回 reasoning_content，无需额外参数
            // Moonshot / 自定义：不添加
            break;
          default:
            break;
        }
      }

      request.body = jsonEncode(body);

      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('API调用失败: ${streamedResponse.statusCode} - $errorBody');
      }

      String buffer = '';
      await for (final bytes in streamedResponse.stream) {
        buffer += utf8.decode(bytes);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final text = delta['content'] as String?;
            // DeepSeek-R1 / OpenAI 深度思考 reasoning_content
            final thinking = delta['reasoning_content'] as String?;

            if (text != null && text.isNotEmpty) yield LLMChunk(text: text);
            if (thinking != null && thinking.isNotEmpty) {
              yield LLMChunk(thinking: thinking);
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────
  // Anthropic 流式实现（含 Extended Thinking）
  // ─────────────────────────────────────────────

  Stream<LLMChunk> _callAnthropicStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 4096,
    bool enableThinking = false,
  }) async* {
    yield* _anthropicSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      enableThinking: enableThinking,
    );
  }

  Stream<LLMChunk> _callAnthropicWithHistoryStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    int maxTokens = 4096,
    bool enableThinking = false,
  }) async* {
    final messages = <Map<String, String>>[...history];
    messages.add({'role': 'user', 'content': question});
    yield* _anthropicSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      enableThinking: enableThinking,
    );
  }

  Stream<LLMChunk> _anthropicSseStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    int maxTokens = 4096,
    bool enableThinking = false,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/messages'));
      request.headers['Content-Type'] = 'application/json';
      request.headers['x-api-key'] = apiKey;
      request.headers['anthropic-version'] = '2023-06-01';
      request.headers['Accept'] = 'text/event-stream';

      final int effectiveMaxTokens = enableThinking
          ? (maxTokens < 16384 ? 16384 : maxTokens)
          : maxTokens;
      final int thinkingBudget = enableThinking
          ? (effectiveMaxTokens - 4096)
          : 0;

      final body = <String, dynamic>{
        'model': model,
        'messages': messages,
        'max_tokens': effectiveMaxTokens,
        'stream': true,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'system': systemPrompt,
        if (enableThinking)
          'thinking': {'type': 'enabled', 'budget_tokens': thinkingBudget},
      };

      request.body = jsonEncode(body);

      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('API调用失败: ${streamedResponse.statusCode} - $errorBody');
      }

      // 记录每个 content block 的类型（thinking/text）
      final blockTypes = <int, String>{};

      String buffer = '';
      await for (final bytes in streamedResponse.stream) {
        buffer += utf8.decode(bytes);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'content_block_start') {
              final index = json['index'] as int? ?? 0;
              final blockType =
                  (json['content_block'] as Map<String, dynamic>?)?['type']
                      as String?;
              if (blockType != null) blockTypes[index] = blockType;
            } else if (type == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              final deltaType = delta?['type'] as String?;

              if (deltaType == 'text_delta') {
                final text = delta?['text'] as String?;
                if (text != null && text.isNotEmpty) yield LLMChunk(text: text);
              } else if (deltaType == 'thinking_delta') {
                final thinking = delta?['thinking'] as String?;
                if (thinking != null && thinking.isNotEmpty) {
                  yield LLMChunk(thinking: thinking);
                }
              }
            } else if (type == 'message_stop') {
              return;
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────
  // Gemini 流式实现
  // ─────────────────────────────────────────────

  Stream<LLMChunk> _callGeminiStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    bool enableThinking = false,
  }) async* {
    yield* _geminiSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      systemPrompt: systemPrompt,
      enableThinking: enableThinking,
    );
  }

  Stream<LLMChunk> _callGeminiWithHistoryStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String question,
    required List<Map<String, String>> history,
    String? systemPrompt,
    bool enableThinking = false,
  }) async* {
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
    yield* _geminiSseStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      contents: contents,
      systemPrompt: systemPrompt,
      enableThinking: enableThinking,
    );
  }

  Stream<LLMChunk> _geminiSseStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> contents,
    String? systemPrompt,
    bool enableThinking = false,
  }) async* {
    final url = '$baseUrl/models/$model:streamGenerateContent?alt=sse&key=$apiKey';
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';

      final requestBody = <String, dynamic>{'contents': contents};

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        requestBody['systemInstruction'] = {
          'parts': [
            {'text': systemPrompt},
          ],
        };
      }

      // Gemini 2.5 系列支持 thinkingConfig
      if (enableThinking) {
        requestBody['generationConfig'] = {
          'thinkingConfig': {'thinkingBudget': 8192},
        };
      }

      request.body = jsonEncode(requestBody);

      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception('API调用失败: ${streamedResponse.statusCode} - $errorBody');
      }

      String buffer = '';
      await for (final bytes in streamedResponse.stream) {
        buffer += utf8.decode(bytes);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final parts = (json['candidates'] as List?)
                ?.firstOrNull?['content']?['parts'] as List?;
            for (final part in parts ?? []) {
              final p = part as Map<String, dynamic>;
              final isThought = p['thought'] as bool? ?? false;
              final text = p['text'] as String?;
              if (text != null && text.isNotEmpty) {
                if (isThought) {
                  yield LLMChunk(thinking: text);
                } else {
                  yield LLMChunk(text: text);
                }
              }
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────
  // 非流式实现（保留原有）
  // ─────────────────────────────────────────────

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
        // Anthropic 要求 system 字段必须是字符串，传 null 会导致 400 错误
        if (systemPrompt != null && systemPrompt.isNotEmpty)
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
        if (systemPrompt != null && systemPrompt.isNotEmpty)
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

    final requestBody = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    };

    // 使用正确的 systemInstruction 字段，而不是将其拼接到用户消息中
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
