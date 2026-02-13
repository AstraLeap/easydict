import '../database_service.dart';
import 'dictionary_manager.dart';
import '../models/dictionary_metadata.dart';
import '../logger.dart';
import '../utils/language_utils.dart';
import 'llm_client.dart';
import 'preferences_service.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  final _llmClient = LLMClient();
  final _prefsService = PreferencesService();

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
      final config = await _prefsService.getLLMConfig(isFast: true);
      if (config == null || !config.isValid) {
        Logger.e('快速模型未配置', tag: 'TranslationService');
        return false;
      }

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
        return false;
      }

      final prompt = _buildTranslationPrompt(
        sourceText,
        sourceLanguage,
        targetLanguage,
      );

      final translatedText = await _llmClient.callApi(
        provider: config.provider,
        baseUrl: config.effectiveBaseUrl,
        apiKey: config.apiKey,
        model: config.model,
        prompt: prompt,
        temperature: 0.3,
      );

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
    final langName = LanguageUtils.getLanguageDisplayName(targetLang);
    return '请将以下文本翻译成$langName，只输出翻译结果，不要任何解释或格式：\n\n$text';
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
}
