import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import '../core/logger.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/toast_utils.dart';
import '../services/font_loader_service.dart';
import '../services/dictionary_manager.dart';
import '../services/entry_event_bus.dart';
import '../services/advanced_search_settings_service.dart';
import '../components/scale_layout_wrapper.dart';
import '../components/global_scale_wrapper.dart';
import '../i18n/strings.g.dart';

enum LLMProvider {
  openAI('OpenAI', 'https://api.openai.com/v1'),
  anthropic('Anthropic', 'https://api.anthropic.com/v1'),
  gemini('Google Gemini', 'https://generativelanguage.googleapis.com/v1beta'),
  deepseek('DeepSeek', 'https://api.deepseek.com/v1'),
  moonshot('Moonshot (月之暗面)', 'https://api.moonshot.cn/v1'),
  zhipu('智谱AI', 'https://open.bigmodel.cn/api/paas/v4'),
  ali('阿里云 (DashScope)', 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  custom('自定义', '');

  final String displayName;
  final String defaultBaseUrl;

  const LLMProvider(this.displayName, this.defaultBaseUrl);

  /// Returns a localized provider name using the current app locale.
  String localizedName(Translations t) {
    switch (this) {
      case LLMProvider.moonshot:
        return t.ai.providerMoonshot;
      case LLMProvider.zhipu:
        return t.ai.providerZhipu;
      case LLMProvider.ali:
        return t.ai.providerAli;
      case LLMProvider.custom:
        return t.ai.providerCustom;
      default:
        return displayName; // OpenAI/Anthropic/Gemini/DeepSeek are language-neutral
    }
  }
}

enum TTSProvider {
  edge('Edge TTS', ''),
  azure('Azure TTS', ''),
  google('Google TTS', 'https://texttospeech.googleapis.com/v1');

  final String displayName;
  final String defaultBaseUrl;

  const TTSProvider(this.displayName, this.defaultBaseUrl);
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
  // 英语(美国)
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
    description: '清晰、有力',
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
    description: '自然、流畅',
  ),
  // 英语(英国)
  const GoogleTTSVoice(
    name: 'en-GB-Chirp3-HD-A',
    gender: '女性',
    language: '英语(英国)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'en-GB-Chirp3-HD-B',
    gender: '男性',
    language: '英语(英国)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 英语(澳大利亚)
  const GoogleTTSVoice(
    name: 'en-AU-Chirp3-HD-A',
    gender: '女性',
    language: '英语(澳大利亚)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'en-AU-Chirp3-HD-B',
    gender: '男性',
    language: '英语(澳大利亚)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 英语(印度)
  const GoogleTTSVoice(
    name: 'en-IN-Chirp3-HD-A',
    gender: '女性',
    language: '英语(印度)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'en-IN-Chirp3-HD-B',
    gender: '男性',
    language: '英语(印度)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 中文(简体)
  const GoogleTTSVoice(
    name: 'cmn-CN-Chirp3-HD-A',
    gender: '女性',
    language: '中文(简体)',
    model: 'chirp3-hd',
    description: '清晰、自然',
  ),
  const GoogleTTSVoice(
    name: 'cmn-CN-Chirp3-HD-B',
    gender: '男性',
    language: '中文(简体)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 日语
  const GoogleTTSVoice(
    name: 'ja-JP-Chirp3-HD-A',
    gender: '女性',
    language: '日语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'ja-JP-Chirp3-HD-B',
    gender: '男性',
    language: '日语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 韩语
  const GoogleTTSVoice(
    name: 'ko-KR-Chirp3-HD-A',
    gender: '女性',
    language: '韩语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'ko-KR-Chirp3-HD-B',
    gender: '男性',
    language: '韩语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 德语
  const GoogleTTSVoice(
    name: 'de-DE-Chirp3-HD-A',
    gender: '女性',
    language: '德语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'de-DE-Chirp3-HD-B',
    gender: '男性',
    language: '德语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 法语(法国)
  const GoogleTTSVoice(
    name: 'fr-FR-Chirp3-HD-A',
    gender: '女性',
    language: '法语(法国)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'fr-FR-Chirp3-HD-B',
    gender: '男性',
    language: '法语(法国)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 法语(加拿大)
  const GoogleTTSVoice(
    name: 'fr-CA-Chirp3-HD-A',
    gender: '女性',
    language: '法语(加拿大)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'fr-CA-Chirp3-HD-B',
    gender: '男性',
    language: '法语(加拿大)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 西班牙语(西班牙)
  const GoogleTTSVoice(
    name: 'es-ES-Chirp3-HD-A',
    gender: '女性',
    language: '西班牙语(西班牙)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'es-ES-Chirp3-HD-B',
    gender: '男性',
    language: '西班牙语(西班牙)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 西班牙语(美国)
  const GoogleTTSVoice(
    name: 'es-US-Chirp3-HD-A',
    gender: '女性',
    language: '西班牙语(美国)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'es-US-Chirp3-HD-B',
    gender: '男性',
    language: '西班牙语(美国)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 意大利语
  const GoogleTTSVoice(
    name: 'it-IT-Chirp3-HD-A',
    gender: '女性',
    language: '意大利语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'it-IT-Chirp3-HD-B',
    gender: '男性',
    language: '意大利语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 葡萄牙语(巴西)
  const GoogleTTSVoice(
    name: 'pt-BR-Chirp3-HD-A',
    gender: '女性',
    language: '葡萄牙语(巴西)',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'pt-BR-Chirp3-HD-B',
    gender: '男性',
    language: '葡萄牙语(巴西)',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 俄语
  const GoogleTTSVoice(
    name: 'ru-RU-Chirp3-HD-A',
    gender: '女性',
    language: '俄语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'ru-RU-Chirp3-HD-B',
    gender: '男性',
    language: '俄语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 阿拉伯语
  const GoogleTTSVoice(
    name: 'ar-XA-Chirp3-HD-A',
    gender: '女性',
    language: '阿拉伯语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'ar-XA-Chirp3-HD-B',
    gender: '男性',
    language: '阿拉伯语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 印地语
  const GoogleTTSVoice(
    name: 'hi-IN-Chirp3-HD-A',
    gender: '女性',
    language: '印地语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'hi-IN-Chirp3-HD-B',
    gender: '男性',
    language: '印地语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 荷兰语
  const GoogleTTSVoice(
    name: 'nl-NL-Chirp3-HD-A',
    gender: '女性',
    language: '荷兰语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'nl-NL-Chirp3-HD-B',
    gender: '男性',
    language: '荷兰语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 波兰语
  const GoogleTTSVoice(
    name: 'pl-PL-Chirp3-HD-A',
    gender: '女性',
    language: '波兰语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'pl-PL-Chirp3-HD-B',
    gender: '男性',
    language: '波兰语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 土耳其语
  const GoogleTTSVoice(
    name: 'tr-TR-Chirp3-HD-A',
    gender: '女性',
    language: '土耳其语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'tr-TR-Chirp3-HD-B',
    gender: '男性',
    language: '土耳其语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 越南语
  const GoogleTTSVoice(
    name: 'vi-VN-Chirp3-HD-A',
    gender: '女性',
    language: '越南语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'vi-VN-Chirp3-HD-B',
    gender: '男性',
    language: '越南语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 泰语
  const GoogleTTSVoice(
    name: 'th-TH-Chirp3-HD-A',
    gender: '女性',
    language: '泰语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'th-TH-Chirp3-HD-B',
    gender: '男性',
    language: '泰语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 瑞典语
  const GoogleTTSVoice(
    name: 'sv-SE-Chirp3-HD-A',
    gender: '女性',
    language: '瑞典语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'sv-SE-Chirp3-HD-B',
    gender: '男性',
    language: '瑞典语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 丹麦语
  const GoogleTTSVoice(
    name: 'da-DK-Chirp3-HD-A',
    gender: '女性',
    language: '丹麦语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'da-DK-Chirp3-HD-B',
    gender: '男性',
    language: '丹麦语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 芬兰语
  const GoogleTTSVoice(
    name: 'fi-FI-Chirp3-HD-A',
    gender: '女性',
    language: '芬兰语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'fi-FI-Chirp3-HD-B',
    gender: '男性',
    language: '芬兰语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 希腊语
  const GoogleTTSVoice(
    name: 'el-GR-Chirp3-HD-A',
    gender: '女性',
    language: '希腊语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'el-GR-Chirp3-HD-B',
    gender: '男性',
    language: '希腊语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 捷克语
  const GoogleTTSVoice(
    name: 'cs-CZ-Chirp3-HD-A',
    gender: '女性',
    language: '捷克语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'cs-CZ-Chirp3-HD-B',
    gender: '男性',
    language: '捷克语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 罗马尼亚语
  const GoogleTTSVoice(
    name: 'ro-RO-Chirp3-HD-A',
    gender: '女性',
    language: '罗马尼亚语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'ro-RO-Chirp3-HD-B',
    gender: '男性',
    language: '罗马尼亚语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 乌克兰语
  const GoogleTTSVoice(
    name: 'uk-UA-Chirp3-HD-A',
    gender: '女性',
    language: '乌克兰语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'uk-UA-Chirp3-HD-B',
    gender: '男性',
    language: '乌克兰语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 匈牙利语
  const GoogleTTSVoice(
    name: 'hu-HU-Chirp3-HD-A',
    gender: '女性',
    language: '匈牙利语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'hu-HU-Chirp3-HD-B',
    gender: '男性',
    language: '匈牙利语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 希伯来语
  const GoogleTTSVoice(
    name: 'he-IL-Chirp3-HD-A',
    gender: '女性',
    language: '希伯来语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'he-IL-Chirp3-HD-B',
    gender: '男性',
    language: '希伯来语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
  // 印度尼西亚语
  const GoogleTTSVoice(
    name: 'id-ID-Chirp3-HD-A',
    gender: '女性',
    language: '印度尼西亚语',
    model: 'chirp3-hd',
    description: '自然、流畅',
  ),
  const GoogleTTSVoice(
    name: 'id-ID-Chirp3-HD-B',
    gender: '男性',
    language: '印度尼西亚语',
    model: 'chirp3-hd',
    description: '专业、沉稳',
  ),
];

class EdgeTTSVoice {
  final String name;
  final String gender;
  final String language;
  final String description;

  const EdgeTTSVoice({
    required this.name,
    required this.gender,
    required this.language,
    required this.description,
  });
}

final List<EdgeTTSVoice> edgeTTSVoices = [
  // ==========================================
  // 1. 英语 - 美国 (en-US) - 8个音色 (100% 免费)
  // ==========================================
  const EdgeTTSVoice(
    name: 'en-US-AriaNeural',
    gender: '女性',
    language: '英语(美国)',
    description: '成熟女声，语气多变，适合新闻与故事',
  ),
  const EdgeTTSVoice(
    name: 'en-US-JennyNeural',
    gender: '女性',
    language: '英语(美国)',
    description: '通用女声，语气亲切，适合各类应用',
  ),
  const EdgeTTSVoice(
    name: 'en-US-EmmaNeural',
    gender: '女性',
    language: '英语(美国)',
    description: '明快女声，适合交互式教育',
  ),
  const EdgeTTSVoice(
    name: 'en-US-AvaNeural',
    gender: '女性',
    language: '英语(美国)',
    description: '自然女声，语调现代且专业',
  ),
  const EdgeTTSVoice(
    name: 'en-US-GuyNeural',
    gender: '男性',
    language: '英语(美国)',
    description: '沉稳男声，非常有力量感，适合旁白',
  ),
  const EdgeTTSVoice(
    name: 'en-US-ChristopherNeural',
    gender: '男性',
    language: '英语(美国)',
    description: '职场男声，发音清晰，适合演示稿',
  ),
  const EdgeTTSVoice(
    name: 'en-US-AndrewNeural',
    gender: '男性',
    language: '英语(美国)',
    description: '亲切男声，语气平缓，适合长文本',
  ),
  const EdgeTTSVoice(
    name: 'en-US-BrianNeural',
    gender: '男性',
    language: '英语(美国)',
    description: '自信男声，节奏感强，适合广告语',
  ),

  // ==========================================
  // 2. 英语 - 英国 (en-GB) - 6个音色 (免费可用)
  // ==========================================
  const EdgeTTSVoice(
    name: 'en-GB-SoniaNeural',
    gender: '女性',
    language: '英语(英国)',
    description: '优雅英音女声，语调考究',
  ),
  const EdgeTTSVoice(
    name: 'en-GB-LibbyNeural',
    gender: '女性',
    language: '英语(英国)',
    description: '自然英音女声，适合有声读物',
  ),
  const EdgeTTSVoice(
    name: 'en-GB-MaisieNeural',
    gender: '女性',
    language: '英语(英国)',
    description: '活泼英国少女声',
  ),
  const EdgeTTSVoice(
    name: 'en-GB-RyanNeural',
    gender: '男性',
    language: '英语(英国)',
    description: '睿智英音男声，充满绅士感',
  ),
  const EdgeTTSVoice(
    name: 'en-GB-ThomasNeural',
    gender: '男性',
    language: '英语(英国)',
    description: '稳重英音男声，适合播音',
  ),
  const EdgeTTSVoice(
    name: 'en-GB-AlfieNeural',
    gender: '男性',
    language: '英语(英国)',
    description: '年轻英音男声，语气随性',
  ),

  // ==========================================
  // 3. 中文 - 大陆 (zh-CN) - 7个音色 (免费全集)
  // ==========================================
  const EdgeTTSVoice(
    name: 'zh-CN-XiaoxiaoNeural',
    gender: '女性',
    language: '中文(普通话)',
    description: '温柔女声，情感丰富',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-XiaoyiNeural',
    gender: '女性',
    language: '中文(普通话)',
    description: '活泼少女声，适合短视频解说',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-XiaoxuanNeural',
    gender: '女性',
    language: '中文(普通话)',
    description: '成熟女声，语气坚定，适合纪录片',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-YunxiNeural',
    gender: '男性',
    language: '中文(普通话)',
    description: '阳光男声，多才多艺，适合动漫和旁白',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-YunjianNeural',
    gender: '男性',
    language: '中文(普通话)',
    description: '专业男声，语调客观，适合新闻播报',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-YunyangNeural',
    gender: '男性',
    language: '中文(普通话)',
    description: '磁性男声，适合解说和商业广告',
  ),
  const EdgeTTSVoice(
    name: 'zh-CN-YunzeNeural',
    gender: '男性',
    language: '中文(普通话)',
    description: '稳重男声，语速适中，适合教育培训',
  ),

  // ==========================================
  // 4. 中文 - 地区 (HK/TW) - 全集
  // ==========================================
  const EdgeTTSVoice(
    name: 'zh-HK-HiuMaanNeural',
    gender: '女性',
    language: '中文(粤语)',
    description: '标准粤语女声',
  ),
  const EdgeTTSVoice(
    name: 'zh-HK-WanLungNeural',
    gender: '男性',
    language: '中文(粤语)',
    description: '磁性粤语男声',
  ),
  const EdgeTTSVoice(
    name: 'zh-TW-HsiaoChenNeural',
    gender: '女性',
    language: '中文(台湾)',
    description: '甜美台普女声',
  ),
  const EdgeTTSVoice(
    name: 'zh-TW-YunJheNeural',
    gender: '男性',
    language: '中文(台湾)',
    description: '自然台普男声',
  ),

  // ==========================================
  // 5. 其他核心语言 (法语、德语、西语等) - 仅保留免费可用音色
  // ==========================================
  const EdgeTTSVoice(
    name: 'fr-FR-DeniseNeural',
    gender: '女性',
    language: '法语',
    description: '优雅女声，发音优美',
  ),
  const EdgeTTSVoice(
    name: 'fr-FR-EloiseNeural',
    gender: '女性',
    language: '法语',
    description: '知性女声',
  ),
  const EdgeTTSVoice(
    name: 'fr-FR-HenriNeural',
    gender: '男性',
    language: '法语',
    description: '稳重男声，韵律自然',
  ),

  const EdgeTTSVoice(
    name: 'de-DE-KatjaNeural',
    gender: '女性',
    language: '德语',
    description: '标准德语女声，严谨专业',
  ),
  const EdgeTTSVoice(
    name: 'de-DE-KillianNeural',
    gender: '男性',
    language: '德语',
    description: '磁性男声',
  ),
  const EdgeTTSVoice(
    name: 'de-DE-ConradNeural',
    gender: '男性',
    language: '德语',
    description: '男声代表，语气有力',
  ),

  const EdgeTTSVoice(
    name: 'es-ES-ElviraNeural',
    gender: '女性',
    language: '西班牙语(西班牙)',
    description: '明亮女声，叙事性强',
  ),
  const EdgeTTSVoice(
    name: 'es-ES-AlvaroNeural',
    gender: '男性',
    language: '西班牙语(西班牙)',
    description: '稳重男声，充满张力',
  ),

  const EdgeTTSVoice(
    name: 'it-IT-ElsaNeural',
    gender: '女性',
    language: '意大利语',
    description: '优雅女声，韵律优美',
  ),
  const EdgeTTSVoice(
    name: 'it-IT-IsabellaNeural',
    gender: '女性',
    language: '意大利语',
    description: '自信女声',
  ),
  const EdgeTTSVoice(
    name: 'it-IT-DiegoNeural',
    gender: '男性',
    language: '意大利语',
    description: '清爽男声，适合播客',
  ),

  const EdgeTTSVoice(
    name: 'ru-RU-SvetlanaNeural',
    gender: '女性',
    language: '俄语',
    description: '标准女声，极具穿透力',
  ),
  const EdgeTTSVoice(
    name: 'ru-RU-DmitryNeural',
    gender: '男性',
    language: '俄语',
    description: '男声代表，播音范十足',
  ),

  const EdgeTTSVoice(
    name: 'pt-BR-FranciscaNeural',
    gender: '女性',
    language: '葡萄牙语(巴西)',
    description: '热情女声，典型的南美风格',
  ),
  const EdgeTTSVoice(
    name: 'pt-BR-AntonioNeural',
    gender: '男性',
    language: '葡萄牙语(巴西)',
    description: '磁性男声，适合纪录片',
  ),

  // ==========================================
  // 6. 亚洲及其他
  // ==========================================
  const EdgeTTSVoice(
    name: 'ja-JP-NanamiNeural',
    gender: '女性',
    language: '日语',
    description: '甜美女声',
  ),
  const EdgeTTSVoice(
    name: 'ja-JP-KeitaNeural',
    gender: '男性',
    language: '日语',
    description: '温润男声',
  ),
  const EdgeTTSVoice(
    name: 'ko-KR-SunHiNeural',
    gender: '女性',
    language: '韩语',
    description: '活泼女声',
  ),
  const EdgeTTSVoice(
    name: 'ko-KR-InJoonNeural',
    gender: '男性',
    language: '韩语',
    description: '标准男声',
  ),
  const EdgeTTSVoice(
    name: 'ar-EG-SalmaNeural',
    gender: '女性',
    language: '阿拉伯语',
    description: '埃及地区女声',
  ),
  const EdgeTTSVoice(
    name: 'ar-SA-HamedNeural',
    gender: '男性',
    language: '阿拉伯语',
    description: '沙特地区男声',
  ),
];

class LanguageVoiceMapping {
  final String langCode;

  const LanguageVoiceMapping({required this.langCode});
}

const List<LanguageVoiceMapping> supportedLanguages = [
  LanguageVoiceMapping(langCode: 'en'),
  LanguageVoiceMapping(langCode: 'zh'),
  LanguageVoiceMapping(langCode: 'jp'),
  LanguageVoiceMapping(langCode: 'ko'),
  LanguageVoiceMapping(langCode: 'fr'),
  LanguageVoiceMapping(langCode: 'de'),
  LanguageVoiceMapping(langCode: 'es'),
  LanguageVoiceMapping(langCode: 'it'),
  LanguageVoiceMapping(langCode: 'ru'),
  LanguageVoiceMapping(langCode: 'pt'),
  LanguageVoiceMapping(langCode: 'ar'),
  LanguageVoiceMapping(langCode: 'text'),
];

final Map<String, List<GoogleTTSVoice>> googleTTSVoicesByLanguage = {
  'en': googleTTSVoices
      .where((v) => v.language.contains('英语') && v.language.contains('美国'))
      .toList(),
  'zh': googleTTSVoices.where((v) => v.language.contains('中文')).toList(),
  'jp': googleTTSVoices.where((v) => v.language.contains('日语')).toList(),
  'ko': googleTTSVoices.where((v) => v.language.contains('韩语')).toList(),
  'fr': googleTTSVoices.where((v) => v.language.contains('法语')).toList(),
  'de': googleTTSVoices.where((v) => v.language.contains('德语')).toList(),
  'es': googleTTSVoices.where((v) => v.language.contains('西班牙语')).toList(),
  'it': googleTTSVoices.where((v) => v.language.contains('意大利语')).toList(),
  'ru': googleTTSVoices.where((v) => v.language.contains('俄语')).toList(),
  'pt': googleTTSVoices.where((v) => v.language.contains('葡萄牙')).toList(),
  'ar': googleTTSVoices.where((v) => v.language.contains('阿拉伯')).toList(),
};

final Map<String, List<EdgeTTSVoice>> edgeTTSVoicesByLanguage = {
  'en': edgeTTSVoices.where((v) => v.language.contains('英语')).toList(),
  'zh': edgeTTSVoices.where((v) => v.language.contains('中文')).toList(),
  'jp': edgeTTSVoices.where((v) => v.language.contains('日语')).toList(),
  'ko': edgeTTSVoices.where((v) => v.language.contains('韩语')).toList(),
  'fr': edgeTTSVoices.where((v) => v.language.contains('法语')).toList(),
  'de': edgeTTSVoices.where((v) => v.language.contains('德语')).toList(),
  'es': edgeTTSVoices.where((v) => v.language.contains('西班牙')).toList(),
  'it': edgeTTSVoices.where((v) => v.language.contains('意大利')).toList(),
  'ru': edgeTTSVoices.where((v) => v.language.contains('俄语')).toList(),
  'pt': edgeTTSVoices.where((v) => v.language.contains('葡萄牙')).toList(),
  'ar': edgeTTSVoices.where((v) => v.language.contains('阿拉伯')).toList(),
};

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
  final double _dictionaryContentScale = FontLoaderService()
      .getDictionaryContentScale();
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
  TTSProvider _ttsProvider = TTSProvider.edge;

  // ValueNotifiers for dropdown_button2 3.0.0 compatibility
  late ValueNotifier<LLMProvider?> _fastProviderNotifier;
  late ValueNotifier<LLMProvider?> _standardProviderNotifier;
  late ValueNotifier<TTSProvider?> _ttsProviderNotifier;
  final Map<String, ValueNotifier<String?>> _voiceNotifiers = {};

  // Google TTS 音色配置
  GoogleTTSVoice? _selectedGoogleVoice;

  bool _isLoading = true;
  bool _obscureFastApiKey = true;
  bool _obscureStandardApiKey = true;
  bool _obscureTtsApiKey = true;

  bool _isTestingFast = false;
  bool _isTestingStandard = false;
  bool _isTestingTts = false;

  bool _standardEnableThinking = false;

  String? _testResultFast;
  bool? _testSuccessFast;
  String? _testResultStandard;
  bool? _testSuccessStandard;
  String? _testResultTts;
  bool? _testSuccessTts;

  /// 快速模型默认名 (2026 更新版)：极致响应速度、超低成本、适合简单 Agent 任务
  static const Map<LLMProvider, String> _fastDefaultModels = {
    LLMProvider.openAI: 'gpt-5-mini',
    LLMProvider.anthropic: 'claude-haiku-4-5',
    LLMProvider.gemini: 'gemini-3-flash',
    LLMProvider.deepseek: 'deepseek-chat',
    LLMProvider.moonshot: 'kimi-k2.5-instant',
    LLMProvider.zhipu: 'glm-5-flash',
    LLMProvider.ali: 'qwen-flash',
    LLMProvider.custom: '',
  };

  /// 标准模型默认名 (2026 更新版)：卓越推理能力、复杂任务规划、长文本深度分析
  static const Map<LLMProvider, String> _standardDefaultModels = {
    LLMProvider.openAI: 'gpt-5-chat-latest',
    LLMProvider.anthropic: 'claude-opus-4-6',
    LLMProvider.gemini: 'gemini-3-pro',
    LLMProvider.deepseek: 'deepseek-reasoner',
    LLMProvider.moonshot: 'kimi-k2.5-thinking',
    LLMProvider.zhipu: 'glm-5',
    LLMProvider.ali: 'qwen-max',
    LLMProvider.custom: '',
  };

  static const Map<TTSProvider, String> _defaultTtsModels = {
    TTSProvider.edge: '',
    TTSProvider.azure: 'azure-tts',
    TTSProvider.google: '',
  };

  static const Map<TTSProvider, String> _defaultTtsVoices = {
    TTSProvider.edge: 'zh-CN-XiaoxiaoNeural',
    TTSProvider.azure: 'zh-CN-XiaoxiaoNeural',
    TTSProvider.google: 'en-US-Neural2-F',
  };

  final Map<String, String> _languageVoiceSettings = {};
  String? _currentEditingLanguage;
  List<String> _availableLanguages = [];
  StreamSubscription<DictionariesChangedEvent>? _dictsChangedSubscription;
  StreamSubscription<LanguageOrderChangedEvent>? _langOrderSubscription;

  Future<List<String>> _getAvailableLanguages() async {
    final dictManager = DictionaryManager();
    final allMetadata = await dictManager.getEnabledDictionariesMetadata();
    final languageSet = <String>{};

    for (final metadata in allMetadata) {
      if (metadata.sourceLanguage.isNotEmpty) {
        final lang = LanguageUtils.normalizeSourceLanguage(
          metadata.sourceLanguage,
        );
        if (supportedLanguages.any((l) => l.langCode == lang)) {
          languageSet.add(lang);
        }
      }
      for (final targetLang in metadata.targetLanguages) {
        if (targetLang.isNotEmpty) {
          final lang = LanguageUtils.normalizeSourceLanguage(targetLang);
          if (supportedLanguages.any((l) => l.langCode == lang)) {
            languageSet.add(lang);
          }
        }
      }
    }

    final rawLanguages = languageSet.toList();
    final savedOrder = await AdvancedSearchSettingsService().getLanguageOrder();
    return AdvancedSearchSettingsService.sortLanguagesByOrder(
      rawLanguages,
      savedOrder,
    );
  }

  /// 词典启用状态变化时，重新加载可用语言列表
  Future<void> _reloadAvailableLanguages() async {
    if (!mounted) return;
    final languages = await _getAvailableLanguages();
    final effectiveLangs = languages.isEmpty ? ['zh', 'en'] : languages;
    if (!mounted) return;
    setState(() {
      _availableLanguages = effectiveLangs;
      // 补充新语言的默认音色配置
      for (final lang in effectiveLangs) {
        if (!_languageVoiceSettings.containsKey(lang)) {
          if (_ttsProvider == TTSProvider.google) {
            final voices = googleTTSVoicesByLanguage[lang];
            _languageVoiceSettings[lang] = voices != null && voices.isNotEmpty
                ? voices.first.name
                : '';
          } else {
            final voices = edgeTTSVoicesByLanguage[lang];
            _languageVoiceSettings[lang] = voices != null && voices.isNotEmpty
                ? voices.first.name
                : '';
          }
        }
      }
      _syncAllVoiceNotifiers();
    });
  }

  @override
  void initState() {
    super.initState();
    // Initialize ValueNotifiers
    _fastProviderNotifier = ValueNotifier<LLMProvider?>(_fastProvider);
    _standardProviderNotifier = ValueNotifier<LLMProvider?>(_standardProvider);
    _ttsProviderNotifier = ValueNotifier<TTSProvider?>(_ttsProvider);

    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _dictsChangedSubscription = EntryEventBus().dictionariesChanged.listen((_) {
      _reloadAvailableLanguages();
    });
    _langOrderSubscription = EntryEventBus().languageOrderChanged.listen((_) {
      _reloadAvailableLanguages();
    });
  }

  @override
  void dispose() {
    _dictsChangedSubscription?.cancel();
    _langOrderSubscription?.cancel();
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
    _fastProviderNotifier.dispose();
    _standardProviderNotifier.dispose();
    _ttsProviderNotifier.dispose();
    for (final n in _voiceNotifiers.values) {
      n.dispose();
    }

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
        prefs.getString('fast_llm_model') ??
        (_fastDefaultModels[_fastProvider] ?? '');

    final standardProviderIndex = prefs.getInt('standard_llm_provider') ?? 0;
    _standardProvider = LLMProvider.values[standardProviderIndex];
    _standardApiKeyController.text =
        prefs.getString('standard_llm_api_key') ?? '';
    _standardBaseUrlController.text =
        prefs.getString('standard_llm_base_url') ??
        _standardProvider.defaultBaseUrl;
    _standardModelController.text =
        prefs.getString('standard_llm_model') ??
        (_standardDefaultModels[_standardProvider] ?? '');

    _standardEnableThinking =
        prefs.getBool('standard_llm_enable_thinking') ?? false;

    final ttsProviderIndex = prefs.getInt('tts_provider');
    if (ttsProviderIndex != null &&
        ttsProviderIndex < TTSProvider.values.length) {
      _ttsProvider = TTSProvider.values[ttsProviderIndex];
    } else {
      _ttsProvider = TTSProvider.edge;
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

    // 加载已有词典涉及的语言
    _availableLanguages = await _getAvailableLanguages();

    // 如果没有已有词典，至少显示一个默认语言
    if (_availableLanguages.isEmpty) {
      _availableLanguages = ['zh', 'en'];
    }

    // 加载语言音色设置（只加载已有词典涉及的语言）
    for (final langCode in _availableLanguages) {
      final lang = supportedLanguages.firstWhere(
        (l) => l.langCode == langCode,
        orElse: () => supportedLanguages.first,
      );
      final voiceKey = 'voice_${lang.langCode}';
      final savedVoice = prefs.getString(voiceKey);
      if (savedVoice != null && savedVoice.isNotEmpty) {
        _languageVoiceSettings[lang.langCode] = savedVoice;
      } else {
        // 使用音色列表中第一个
        if (_ttsProvider == TTSProvider.google) {
          final voices = googleTTSVoicesByLanguage[lang.langCode];
          _languageVoiceSettings[lang.langCode] =
              voices != null && voices.isNotEmpty ? voices.first.name : '';
        } else {
          final voices = edgeTTSVoicesByLanguage[lang.langCode];
          _languageVoiceSettings[lang.langCode] =
              voices != null && voices.isNotEmpty ? voices.first.name : '';
        }
      }
    }

    setState(() {
      _isLoading = false;
      _fastProviderNotifier.value = _fastProvider;
      _standardProviderNotifier.value = _standardProvider;
      _ttsProviderNotifier.value = _ttsProvider;
      _syncAllVoiceNotifiers();
    });
  }

  void _showSavedSnackBar() {
    showToast(context, context.t.ai.configSaved);
  }

  Future<void> _saveFastConfig() async {
    if (!_fastFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = path.join(appDir.path, 'shared_preferences.json');
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
    final fastModelText = _fastModelController.text.trim();
    await prefs.setString('fast_llm_model', fastModelText);
    Logger.i('  fast_llm_model: $fastModelText', tag: 'LLMConfig');

    _showSavedSnackBar();
  }

  Future<void> _saveStandardConfig() async {
    if (!_standardFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = path.join(appDir.path, 'shared_preferences.json');
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
    final standardModelText = _standardModelController.text.trim();
    await prefs.setString('standard_llm_model', standardModelText);
    Logger.i('  standard_llm_model: $standardModelText', tag: 'LLMConfig');
    await prefs.setBool(
      'standard_llm_enable_thinking',
      _standardEnableThinking,
    );

    _showSavedSnackBar();
  }

  Future<void> _saveTtsConfig() async {
    if (!_ttsFormKey.currentState!.validate()) return;

    final appDir = await getApplicationSupportDirectory();
    final prefsPath = path.join(appDir.path, 'shared_preferences.json');
    Logger.i('保存 TTS 配置到 SharedPreferences', tag: 'LLMConfig');
    Logger.i('  文件路径: $prefsPath', tag: 'LLMConfig');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tts_provider', _ttsProvider.index);
    await prefs.setString(
      'tts_api_key',
      _ttsProvider == TTSProvider.edge ? '' : _ttsApiKeyController.text.trim(),
    );
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

    // 保存语言音色设置
    for (final entry in _languageVoiceSettings.entries) {
      await prefs.setString('voice_${entry.key}', entry.value);
    }

    _showSavedSnackBar();
  }

  void _onFastProviderChanged(LLMProvider? provider) {
    if (provider == null) return;
    _fastProviderNotifier.value = provider;
    setState(() {
      _fastProvider = provider;
      _fastBaseUrlController.text = provider.defaultBaseUrl;
      _fastModelController.text = _fastDefaultModels[provider] ?? '';
      _testResultFast = null;
      _testSuccessFast = null;
    });
  }

  void _onStandardProviderChanged(LLMProvider? provider) {
    if (provider == null) return;
    _standardProviderNotifier.value = provider;
    setState(() {
      _standardProvider = provider;
      _standardBaseUrlController.text = provider.defaultBaseUrl;
      _standardModelController.text = _standardDefaultModels[provider] ?? '';
      _testResultStandard = null;
      _testSuccessStandard = null;
    });
  }

  void _onTtsProviderChanged(TTSProvider? provider) {
    if (provider == null) return;

    // 切换 Provider 时，更新语言音色设置为新 Provider 的默认值
    for (final lang in _availableLanguages) {
      if (provider == TTSProvider.google) {
        final voices = googleTTSVoicesByLanguage[lang];
        _languageVoiceSettings[lang] = voices != null && voices.isNotEmpty
            ? voices.first.name
            : '';
      } else {
        final voices = edgeTTSVoicesByLanguage[lang];
        _languageVoiceSettings[lang] = voices != null && voices.isNotEmpty
            ? voices.first.name
            : '';
      }
    }

    _ttsProviderNotifier.value = provider;
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
      _syncAllVoiceNotifiers();
    });
  }

  /// Sync all language voice notifiers from [_languageVoiceSettings].
  void _syncAllVoiceNotifiers() {
    for (final entry in _languageVoiceSettings.entries) {
      final notifier = _voiceNotifiers[entry.key];
      if (notifier != null) {
        notifier.value = entry.value;
      }
    }
  }

  /// Return (and lazily create) the ValueNotifier for [langCode].
  ValueNotifier<String?> _voiceNotifierFor(String langCode) {
    return _voiceNotifiers.putIfAbsent(
      langCode,
      () => ValueNotifier<String?>(_languageVoiceSettings[langCode]),
    );
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
        _testResultFast = context.t.ai.testApiKeyRequired;
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
          _testResultFast = context.t.ai.testFailedWithError(error: '$e');
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
        _testResultStandard = context.t.ai.testApiKeyRequired;
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
          _testResultStandard = context.t.ai.testFailedWithError(error: '$e');
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
        _testResultTts = context.t.ai.testApiKeyRequired;
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
        _testResultTts = context.t.ai.ttsSaved;
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
        return ApiTestResult(success: true, message: context.t.ai.testSuccess);
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['error']?['message'] ??
            errorBody['message'] ??
            'HTTP ${response.statusCode}';
        return ApiTestResult(
          success: false,
          message: context.t.ai.testError(message: errorMessage),
        );
      }
    } on TimeoutException {
      return ApiTestResult(success: false, message: context.t.ai.testTimeout);
    } catch (e) {
      return ApiTestResult(
        success: false,
        message: context.t.ai.testFailed(message: '$e'),
      );
    }
  }

  Widget _buildTextModelConfig({
    required String title,
    required String subtitle,
    required GlobalKey<FormState> formKey,
    required LLMProvider provider,
    required ValueNotifier<LLMProvider?> providerNotifier,
    required Map<LLMProvider, String> defaultModels,
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
    // 深度思考选项（仅标准模型显示）
    bool? enableThinking,
    void Function(bool)? onToggleEnableThinking,
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
            valueListenable: providerNotifier,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.t.ai.providerLabel,
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              prefixIcon: const Icon(Icons.cloud_outlined),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 0, 16),
            ),
            buttonStyleData: const FormFieldButtonStyleData(
              padding: EdgeInsets.zero,
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
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              maxHeight: 300,
              offset: const Offset(0, -4),
            ),
            menuItemStyleData: const MenuItemStyleData(
              padding: EdgeInsets.symmetric(horizontal: 16),
            ),
            items: LLMProvider.values.map((p) {
              return DropdownItem<LLMProvider>(
                value: p,
                child: Text(
                  p.localizedName(context.t),
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              prefixIcon: const Icon(Icons.key_outlined),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: Icon(
                    obscureApiKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 52,
                minHeight: 48,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return context.t.ai.apiKeyRequired;
              }
              return null;
            },
          ),

          const SizedBox(height: 16),
          TextFormField(
            controller: baseUrlController,
            decoration: InputDecoration(
              labelText: context.t.ai.baseUrlLabel,
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              prefixIcon: const Icon(Icons.link_outlined),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              hintText: context.t.ai.baseUrlHint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.t.ai.baseUrlNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: modelController,
            decoration: InputDecoration(
              labelText: context.t.ai.modelLabel,
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              prefixIcon: const Icon(Icons.model_training_outlined),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              hintText: '',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return context.t.ai.modelRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            context.t.ai.defaultModel(model: defaultModels[provider] ?? ''),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          // 深度思考开关（仅标准模型）
          if (enableThinking != null && onToggleEnableThinking != null) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: SwitchListTile(
                title: Text(context.t.ai.deepThinkingTitle),
                subtitle: Text(
                  context.t.ai.deepThinkingSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                value: enableThinking,
                onChanged: onToggleEnableThinking,
                secondary: Icon(
                  Icons.psychology_outlined,
                  color: enableThinking
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onSave,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(context.t.common.saveConfig),
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
                    child: Text(
                      isTesting
                          ? context.t.common.testing
                          : context.t.common.testConnection,
                    ),
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
            context.t.ai.ttsTitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField2<TTSProvider>(
            valueListenable: _ttsProviderNotifier,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.t.ai.providerLabel,
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
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              prefixIcon: const Icon(Icons.record_voice_over_outlined),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 16, 0, 16),
            ),
            buttonStyleData: const FormFieldButtonStyleData(
              padding: EdgeInsets.zero,
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
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              maxHeight: 300,
              offset: const Offset(0, -4),
            ),
            menuItemStyleData: const MenuItemStyleData(
              padding: EdgeInsets.symmetric(horizontal: 16),
            ),
            items: TTSProvider.values.map((p) {
              return DropdownItem<TTSProvider>(
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
          if (_ttsProvider != TTSProvider.edge) ...[
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
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                prefixIcon: const Icon(Icons.key_outlined),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
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
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 52,
                  minHeight: 48,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.t.ai.apiKeyRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text(
              _ttsProvider == TTSProvider.google
                  ? context.t.ai.ttsGoogleNote
                  : context.t.ai.ttsAzureNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ] else ...[
            Text(
              context.t.ai.ttsEdgeNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (_ttsProvider != TTSProvider.edge) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _ttsBaseUrlController,
              decoration: InputDecoration(
                labelText: context.t.ai.baseUrlLabel,
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
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                prefixIcon: const Icon(Icons.link_outlined),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                hintText: _ttsProvider == TTSProvider.google
                    ? context.t.ai.ttsBaseUrlHintGoogle
                    : context.t.ai.baseUrlHint,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            context.t.ai.ttsVoiceSettings,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.t.ai.ttsVoiceSettingsSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          // 按 _availableLanguages 的顺序（即词典管理页设定的语言顺序）渲染
          ..._availableLanguages
              .map(
                (code) => supportedLanguages
                    .where((l) => l.langCode == code)
                    .firstOrNull,
              )
              .whereType<LanguageVoiceMapping>()
              .map((lang) => _buildLanguageVoiceSetting(lang)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saveTtsConfig,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(context.t.common.saveConfig),
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
                    child: Text(
                      _isTestingTts
                          ? context.t.common.testing
                          : context.t.common.testConnection,
                    ),
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
    final body = _isLoading
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
                      title: context.t.ai.fastModel,
                      subtitle: context.t.ai.fastModelSubtitle,
                      formKey: _fastFormKey,
                      provider: _fastProvider,
                      providerNotifier: _fastProviderNotifier,
                      defaultModels: _fastDefaultModels,
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
                      title: context.t.ai.standardModel,
                      subtitle: context.t.ai.standardModelSubtitle,
                      formKey: _standardFormKey,
                      provider: _standardProvider,
                      providerNotifier: _standardProviderNotifier,
                      defaultModels: _standardDefaultModels,
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
                      enableThinking: _standardEnableThinking,
                      onToggleEnableThinking: (val) {
                        setState(() => _standardEnableThinking = val);
                      },
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
          );

    final content = Scaffold(
      appBar: AppBar(
        title: Text(context.t.ai.title),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.t.ai.tabFast),
            Tab(text: context.t.ai.tabStandard),
            Tab(text: context.t.ai.tabAudio),
          ],
        ),
      ),
      body: body,
    );

    if (_dictionaryContentScale == 1.0) {
      return content;
    }

    return PageScaleWrapper(scale: _dictionaryContentScale, child: content);
  }

  Widget _buildLanguageVoiceSetting(LanguageVoiceMapping lang) {
    List<GoogleTTSVoice> googleVoices = [];
    List<EdgeTTSVoice> edgeVoices = [];

    if (_ttsProvider == TTSProvider.google) {
      googleVoices = googleTTSVoicesByLanguage[lang.langCode] ?? [];
    } else {
      edgeVoices = edgeTTSVoicesByLanguage[lang.langCode] ?? [];
    }

    final currentVoice =
        _languageVoiceSettings[lang.langCode] ??
        (_ttsProvider == TTSProvider.google
            ? (googleVoices.isNotEmpty ? googleVoices.first.name : '')
            : (edgeVoices.isNotEmpty ? edgeVoices.first.name : ''));

    List<DropdownItem<String>> voiceItems = [];

    if (_ttsProvider == TTSProvider.google) {
      voiceItems = googleVoices.map((voice) {
        return DropdownItem<String>(
          value: voice.name,
          child: Row(
            children: [
              Icon(
                voice.gender == '女性' ? Icons.female : Icons.male,
                size: 18,
                color: voice.gender == '女性'
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(voice.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList();
    } else {
      voiceItems = edgeVoices.map((voice) {
        return DropdownItem<String>(
          value: voice.name,
          child: Row(
            children: [
              Icon(
                voice.gender == '女性' ? Icons.female : Icons.male,
                size: 18,
                color: voice.gender == '女性'
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(voice.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList();
    }

    if (voiceItems.isEmpty) {
      voiceItems.add(
        DropdownItem<String>(
          value: currentVoice,
          child: Text(
            currentVoice.isEmpty ? context.t.ai.ttsNoVoice : currentVoice,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            LanguageUtils.getDisplayName(lang.langCode, context.t),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField2<String>(
              valueListenable: _voiceNotifierFor(lang.langCode),
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              buttonStyleData: const FormFieldButtonStyleData(
                padding: EdgeInsets.zero,
              ),
              iconStyleData: IconStyleData(
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                maxHeight: 250,
                offset: const Offset(0, -4),
              ),
              menuItemStyleData: const MenuItemStyleData(
                padding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: voiceItems,
              onChanged: (voice) {
                if (voice != null) {
                  _languageVoiceSettings[lang.langCode] = voice;
                  _voiceNotifierFor(lang.langCode).value = voice;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
