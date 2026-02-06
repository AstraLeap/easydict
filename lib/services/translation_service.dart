import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database_service.dart';
import '../pages/llm_config_page.dart';
import 'dictionary_manager.dart';
import '../models/dictionary_metadata.dart';
import '../logger.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  Future<String?> _getFastLLMConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final providerIndex = prefs.getInt('fast_llm_provider');
    if (providerIndex == null) return null;

    final apiKey = prefs.getString('fast_llm_api_key') ?? '';
    final baseUrl = prefs.getString('fast_llm_base_url') ?? '';
    final model = prefs.getString('fast_llm_model') ?? '';

    if (apiKey.isEmpty) return null;

    final provider = LLMProvider.values[providerIndex];
    final effectiveBaseUrl = baseUrl.isEmpty
        ? provider.defaultBaseUrl
        : baseUrl;

    return jsonEncode({
      'provider': provider.index,
      'apiKey': apiKey,
      'baseUrl': effectiveBaseUrl,
      'model': model,
    });
  }

  String _getTargetLanguage(DictionaryMetadata metadata) {
    final sourceLang = metadata.sourceLanguage;
    for (final target in metadata.targetLanguages) {
      if (target != sourceLang) {
        return target;
      }
    }
    return 'zh';
  }

  Future<bool> translateAndInsert({
    required String dictionaryId,
    required String entryId,
    required Map<String, dynamic> entryJson,
    required List<String> sourcePath,
    required String sourceLanguage,
    required String sourceText,
  }) async {
    try {
      final configStr = await _getFastLLMConfig();
      if (configStr == null) {
        Logger.e('快速模型未配置', tag: 'TranslationService');
        return false;
      }

      final config = jsonDecode(configStr) as Map<String, dynamic>;
      final apiKey = config['apiKey'] as String;
      final baseUrl = config['baseUrl'] as String;
      final model = config['model'] as String;
      final providerIndex = config['provider'] as int;
      final provider = LLMProvider.values[providerIndex];

      final dictManager = DictionaryManager();
      final metadata = await dictManager.getDictionaryMetadata(dictionaryId);
      if (metadata == null) {
        Logger.e('无法获取词典元数据', tag: 'TranslationService');
        return false;
      }

      final targetLanguage = _getTargetLanguage(metadata);

      dynamic current = entryJson;
      final pathParts = List<String>.from(sourcePath);

      for (int i = 0; i < pathParts.length - 1; i++) {
        final part = pathParts[i];
        if (current is! Map<String, dynamic>) {
          break;
        }

        if (part.startsWith('[') && part.endsWith(']')) {
          final index = int.parse(part.substring(1, part.length - 1));
          current = current.values.elementAt(index);
        } else {
          current = current[part];
        }
      }

      if (current is! Map<String, dynamic>) {
        Logger.e('无法访问释义路径', tag: 'TranslationService');
        return false;
      }

      final lastPart = pathParts.last;
      dynamic existingValue;

      if (lastPart.startsWith('[') && lastPart.endsWith(']')) {
        final index = int.parse(lastPart.substring(1, lastPart.length - 1));
        final keys = current.keys.toList();
        if (index < keys.length) {
          final key = keys[index];
          existingValue = current[key];
        }
      } else {
        existingValue = current[lastPart];
      }

      if (existingValue is Map<String, dynamic> &&
          existingValue.containsKey(targetLanguage)) {
        Logger.d('释义已存在目标语言翻译，跳过翻译', tag: 'TranslationService');
        return false;
      }

      final prompt = _buildTranslationPrompt(
        sourceText,
        sourceLanguage,
        targetLanguage,
      );

      String translatedText = '';
      switch (provider) {
        case LLMProvider.openAI:
        case LLMProvider.deepseek:
        case LLMProvider.moonshot:
        case LLMProvider.zhipu:
        case LLMProvider.ali:
        case LLMProvider.custom:
          translatedText = await _callOpenAICompatibleApi(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
          );
        case LLMProvider.anthropic:
          translatedText = await _callAnthropicApi(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
          );
        case LLMProvider.gemini:
          translatedText = await _callGeminiApi(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
          );
      }

      final translatedTextClean = translatedText.trim();

      final updatedJson = _insertTranslation(
        entryJson,
        sourcePath,
        targetLanguage,
        translatedTextClean,
      );

      final newEntry = DictionaryEntry.fromJson(updatedJson);

      final success = await DatabaseService().updateEntry(newEntry);
      if (success) {
        Logger.d('翻译已保存: $dictionaryId/$entryId', tag: 'TranslationService');
      }

      return success;
    } catch (e) {
      Logger.e('翻译失败: $e', tag: 'TranslationService', error: e);
      return false;
    }
  }

  String _buildTranslationPrompt(
    String text,
    String sourceLang,
    String targetLang,
  ) {
    final langName = _getLangName(targetLang);
    return '请将以下文本翻译成$langName，只输出翻译结果，不要任何解释或格式：\n\n$text';
  }

  String _getLangName(String code) {
    final names = {
      'zh': '中文',
      'en': '英语',
      'ja': '日语',
      'ko': '韩语',
      'fr': '法语',
      'de': '德语',
      'es': '西班牙语',
      'it': '意大利语',
      'pt': '葡萄牙语',
      'ru': '俄语',
    };
    return names[code] ?? code;
  }

  Map<String, dynamic> _insertTranslation(
    Map<String, dynamic> entryJson,
    List<String> sourcePath,
    String targetLanguage,
    String translatedText,
  ) {
    final updatedJson = Map<String, dynamic>.from(entryJson);

    dynamic current = updatedJson;
    final pathParts = List<String>.from(sourcePath);

    for (int i = 0; i < pathParts.length - 1; i++) {
      final part = pathParts[i];
      if (current is! Map<String, dynamic>) {
        return updatedJson;
      }

      if (part.startsWith('[') && part.endsWith(']')) {
        final index = int.parse(part.substring(1, part.length - 1));
        current = current.values.elementAt(index);
      } else {
        current = current[part];
      }
    }

    if (current is! Map<String, dynamic>) {
      return updatedJson;
    }

    final lastPart = pathParts.last;
    if (lastPart.startsWith('[') && lastPart.endsWith(']')) {
      final index = int.parse(lastPart.substring(1, lastPart.length - 1));
      final keys = current.keys.toList();
      if (index < keys.length) {
        final key = keys[index];
        final existingValue = current[key];
        if (existingValue is Map<String, dynamic>) {
          final newValue = Map<String, dynamic>.from(existingValue);
          newValue[targetLanguage] = translatedText;
          current[key] = newValue;
        }
      }
    } else {
      final existingValue = current[lastPart];
      if (existingValue is Map<String, dynamic>) {
        final newValue = Map<String, dynamic>.from(existingValue);
        newValue[targetLanguage] = translatedText;
        current[lastPart] = newValue;
      } else if (existingValue is String) {
        current[lastPart] = {
          'er': existingValue,
          targetLanguage: translatedText,
        };
      }
    }

    return updatedJson;
  }

  Future<String> _callOpenAICompatibleApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.3,
        'max_tokens': 1000,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    } else {
      throw Exception('翻译API调用失败: ${response.statusCode}');
    }
  }

  Future<String> _callAnthropicApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
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
        'max_tokens': 1000,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'] as String;
    } else {
      throw Exception('翻译API调用失败: ${response.statusCode}');
    }
  }

  Future<String> _callGeminiApi({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final url = '$baseUrl/models/$model:generateContent?key=$apiKey';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] as String;
    } else {
      throw Exception('翻译API调用失败: ${response.statusCode}');
    }
  }
}
