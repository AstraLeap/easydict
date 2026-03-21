import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/logger.dart';
import '../core/utils/language_utils.dart';
import '../services/chinese_convert_service.dart';
import '../services/dictionary_manager.dart';
import '../services/english_search_service.dart';
import '../services/zstd_service.dart';
import 'models/dictionary_metadata.dart';
import 'services/database_initializer.dart';

/// 日语文本标准化函数
/// 移植自 build_db_from_jsonl.py 的 normalize_japanese()
/// 包含：罗马音转平假名、片假名转平假名、去浊音符号、长音转换、小文字转大文字
String _normalizeJapanese(String text) {
  text = text.toLowerCase();

  // -----------------------------------------------------
  // 1. 罗马音转平假名 (修正版)
  // -----------------------------------------------------
  // 修复 tch 逻辑: 让 ch 保留给后续匹配
  text = text.replaceAll('tch', 'っch');
  // 修复 Hepburn 传统 m 处理 (如 shimbun -> しんぶん)
  text = text.replaceAllMapped(RegExp(r'm(?=[bpm])'), (match) => 'ん');
  // 修复双辅音促音
  text = text.replaceAllMapped(
    RegExp(r'([bcdfghjklmpqrstvwxyz])\1'),
    (match) => 'っ${match.group(1)}',
  );
  // 修复词尾或辅音前的 n
  text = text.replaceAllMapped(RegExp(r'n(?=[^aeiouy]|$)'), (match) => 'ん');

  // 罗马音映射表（按长度降序排列以确保最长匹配优先）
  const romajiMap = {
    'kya': 'きゃ',
    'kyu': 'きゅ',
    'kyo': 'きょ',
    'sha': 'しゃ',
    'shi': 'し',
    'shu': 'しゅ',
    'she': 'しぇ',
    'sho': 'しょ',
    'cha': 'ちゃ',
    'chi': 'ち',
    'chu': 'ちゅ',
    'che': 'ちぇ',
    'cho': 'ちょ',
    'nya': 'にゃ',
    'nyu': 'にゅ',
    'nyo': 'にょ',
    'hya': 'ひゃ',
    'hyu': 'ひゅ',
    'hyo': 'ひょ',
    'mya': 'みゃ',
    'myu': 'みゅ',
    'myo': 'みょ',
    'rya': 'りゃ',
    'ryu': 'りゅ',
    'ryo': 'りょ',
    'gya': 'ぎゃ',
    'gyu': 'ぎゅ',
    'gyo': 'ぎょ',
    'ja': 'じゃ',
    'ji': 'じ',
    'ju': 'じゅ',
    'je': 'じぇ',
    'jo': 'じょ',
    'bya': 'びゃ',
    'byu': 'びゅ',
    'byo': 'びょ',
    'pya': 'ぴゃ',
    'pyu': 'ぴゅ',
    'pyo': 'ぴょ',
    'ka': 'か',
    'ki': 'き',
    'ku': 'く',
    'ke': 'け',
    'ko': 'こ',
    'sa': 'さ',
    'su': 'す',
    'se': 'せ',
    'so': 'そ',
    'ta': 'た',
    'te': 'て',
    'to': 'と',
    'tsu': 'つ',
    'na': 'な',
    'ni': 'に',
    'nu': 'ぬ',
    'ne': 'ね',
    'no': 'の',
    'ha': 'は',
    'hi': 'ひ',
    'fu': 'ふ',
    'hu': 'ふ',
    'he': 'へ',
    'ho': 'ほ',
    'ma': 'ま',
    'mi': 'み',
    'mu': 'む',
    'me': 'め',
    'mo': 'も',
    'ya': 'や',
    'yu': 'ゆ',
    'yo': 'よ',
    'ra': 'ら',
    'ri': 'り',
    'ru': 'る',
    're': 'れ',
    'ro': 'ろ',
    'wa': 'わ',
    'wi': 'ゐ',
    'we': 'ゑ',
    'wo': 'を',
    'ga': 'が',
    'gi': 'ぎ',
    'gu': 'ぐ',
    'ge': 'げ',
    'go': 'ご',
    'za': 'ざ',
    'zu': 'ず',
    'ze': 'ぜ',
    'zo': 'ぞ',
    'da': 'だ',
    'di': 'ぢ',
    'du': 'づ',
    'de': 'で',
    'do': 'ど',
    'ba': 'ば',
    'bi': 'び',
    'bu': 'ぶ',
    'be': 'べ',
    'bo': 'ぼ',
    'pa': 'ぱ',
    'pi': 'ぴ',
    'pu': 'ぷ',
    'pe': 'ぺ',
    'po': 'ぽ',
    'a': 'あ',
    'i': 'い',
    'u': 'う',
    'e': 'え',
    'o': 'お',
    'ā': 'ああ',
    'ī': 'いい',
    'ū': 'うう',
    'ē': 'ええ',
    'ō': 'おお',
  };

  // 按长度降序排序，确保最长匹配优先
  final sortedRomaji = romajiMap.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final romaji in sortedRomaji) {
    text = text.replaceAll(romaji, romajiMap[romaji]!);
  }

  // -----------------------------------------------------
  // 2 & 3 & 4: 清洗与片转平、去浊音逻辑
  // -----------------------------------------------------
  text = text.replaceAll(RegExp(r'[\s　]+'), '');
  text = text.replaceAll(RegExp(r"[’・－\-]"), '');

  // 片假名转平假名 (Unicode 偏移转换)
  final codeUnits = text.codeUnits;
  final hiraganaBuffer = StringBuffer();
  for (final codeUnit in codeUnits) {
    if (codeUnit >= 0x30A1 && codeUnit <= 0x30F6) {
      // 片假名范围: 0x30A1-0x30F6 -> 平假名: 0x3041-0x3096
      hiraganaBuffer.writeCharCode(codeUnit - 0x60);
    } else {
      hiraganaBuffer.writeCharCode(codeUnit);
    }
  }
  text = hiraganaBuffer.toString();

  // 去浊音符号 (NFD 分解后去除)
  text = text
      .replaceAll('\u3099', '') // 组合浊音符号
      .replaceAll('\u309A', ''); // 组合半浊音符号

  // -----------------------------------------------------
  // 5. 长音 "ー" 转换
  // -----------------------------------------------------
  const vowelMap = {
    'あ': 'あ',
    'か': 'あ',
    'さ': 'あ',
    'た': 'あ',
    'な': 'あ',
    'は': 'あ',
    'ま': 'あ',
    'や': 'あ',
    'ら': 'あ',
    'わ': 'あ',
    'ぁ': 'あ',
    'ゃ': 'あ',
    'ゎ': 'あ',
    'い': 'い',
    'き': 'い',
    'し': 'い',
    'ち': 'い',
    'に': 'い',
    'ひ': 'い',
    'み': 'い',
    'り': 'い',
    'ゐ': 'い',
    'ぃ': 'い',
    'う': 'う',
    'く': 'う',
    'す': 'う',
    'つ': 'う',
    'ぬ': 'う',
    'ふ': 'う',
    'む': 'う',
    'ゆ': 'う',
    'る': 'う',
    'ぅ': 'う',
    'ゅ': 'う',
    'え': 'え',
    'け': 'え',
    'せ': 'え',
    'て': 'え',
    'ね': 'え',
    'へ': 'え',
    'め': 'え',
    'れ': 'え',
    'ゑ': 'え',
    'ぇ': 'え',
    'お': 'お',
    'こ': 'お',
    'そ': 'お',
    'と': 'お',
    'の': 'お',
    'ほ': 'お',
    'も': 'お',
    'よ': 'お',
    'ろ': 'お',
    'を': 'お',
    'ぉ': 'お',
    'ょ': 'お',
  };

  final resChoonpu = <String>[];
  String? currentVowel;

  for (final c in text.split('')) {
    if (c == 'ー') {
      // 如果前面存在有效母音，则转换为该母音，否则保留
      if (currentVowel != null) {
        resChoonpu.add(currentVowel);
      } else {
        resChoonpu.add(c);
      }
    } else {
      resChoonpu.add(c);
      // 动态更新当前母音环境
      if (vowelMap.containsKey(c)) {
        currentVowel = vowelMap[c];
      } else {
        currentVowel = null;
      }
    }
  }
  text = resChoonpu.join();

  // -----------------------------------------------------
  // 6. 小文字转大文字
  // -----------------------------------------------------
  const smallToLarge = {
    'ぁ': 'あ',
    'ぃ': 'い',
    'ぅ': 'う',
    'ぇ': 'え',
    'ぉ': 'お',
    'ゃ': 'や',
    'ゅ': 'ゆ',
    'ょ': 'よ',
    'ゎ': 'わ',
    'っ': 'つ',
  };
  smallToLarge.forEach((small, large) {
    text = text.replaceAll(small, large);
  });

  return text;
}

/// 判断是否需要繁体转简体
/// 根据 langCode 判断，与 Python 版本保持一致
bool _shouldConvertToSimplified(String? langCode) {
  if (langCode == null) return false;
  final normalized = langCode.toLowerCase();
  return ['zh-tw', 'zh-hk', 'zh-mo', 'zh-hant'].contains(normalized);
}

/// 递归搜索 JSON 对象，提取所有 [text](anchor) 格式的标签
/// 返回: Map，key 为 headword（提取的 text），value 为 anchor（JSON 路径）
Map<String, String> _extractAnchorsFromJson(
  dynamic data, [
  String currentPath = '',
]) {
  final result = <String, String>{};

  if (data is Map) {
    data.forEach((key, value) {
      final newPath = currentPath.isNotEmpty
          ? '$currentPath.$key'
          : key.toString();
      result.addAll(_extractAnchorsFromJson(value, newPath));
    });
  } else if (data is List) {
    for (int i = 0; i < data.length; i++) {
      final newPath = currentPath.isNotEmpty ? '$currentPath.$i' : i.toString();
      result.addAll(_extractAnchorsFromJson(data[i], newPath));
    }
  } else if (data is String) {
    // 匹配 [text](anchor) 格式
    final pattern = RegExp(r'\[([^\]]+)\]\(anchor\)');
    final matches = pattern.allMatches(data);
    for (final match in matches) {
      final text = match.group(1);
      if (text != null && text.isNotEmpty) {
        result[text] = currentPath;
      }
    }
  }

  return result;
}

/// 从 JSON 数据中提取所有 headword 及其对应的 anchor
/// 返回: Map，key 为 headword，value 为 anchor
Map<String, String> _extractHeadwordAnchorMap(Map<String, dynamic> data) {
  final result = <String, String>{};

  // 1. 优先从 headword 字段提取
  if (data.containsKey('headword')) {
    final hw = data['headword']?.toString();
    if (hw != null && hw.isNotEmpty) {
      result[hw] = '';
    }
  }

  // 2. 从 links 字段提取词头
  // links 可以是 string 或 list of string
  final links = data['links'];
  if (links != null) {
    if (links is String && links.isNotEmpty) {
      result[links] = '';
    } else if (links is List) {
      for (final link in links) {
        if (link is String && link.isNotEmpty) {
          result[link] = '';
        }
      }
    }
  }

  // 3. 递归搜索整个 JSON，提取 [text](anchor) 格式
  result.addAll(_extractAnchorsFromJson(data));

  return result;
}

Map<String, dynamic> _parseJsonInIsolate(String jsonStr) {
  return Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
}

/// 解析 pronunciation 字段，兼容 List / Map / String 三种形式
List<Map<String, dynamic>> _parsePronunciations(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    return value
        .map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          // 字符串形式：当作 phonetic 字段
          if (e is String) return <String, dynamic>{'phonetic': e};
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }
  if (value is Map) {
    return [Map<String, dynamic>.from(value)];
  }
  if (value is String) {
    return [
      <String, dynamic>{'phonetic': value},
    ];
  }
  return [];
}

/// 解析 groups 字段，兼容 int / List<int> 两种形式
List<int> _parseGroups(dynamic value) {
  if (value == null) return [];
  // 单个数字
  if (value is int) return [value];
  // 数字列表
  if (value is List) {
    return value
        .map((e) {
          if (e is int) return e;
          if (e is String) return int.tryParse(e);
          return null;
        })
        .whereType<int>()
        .toList();
  }
  return [];
}

class JsonParseParams {
  final String jsonStr;
  final String dictId;
  final Map<String, dynamic> row;
  final bool exactMatch;
  final bool isBiaoyi;
  final String originalWord;
  final List<(String, String)> matchedAnchors;

  JsonParseParams({
    required this.jsonStr,
    required this.dictId,
    required this.row,
    required this.exactMatch,
    this.isBiaoyi = false,
    required this.originalWord,
    this.matchedAnchors = const [],
  });
}

/// 检查 headword 是否匹配原始搜索词（精确匹配）
/// 精确匹配就是直接比较 headword 和 originalWord，不做任何转换
/// - 表音文字（如英语）：大小写敏感，headword 必须与 originalWord 完全相同
/// - 表意文字（如中文）：简繁敏感，headword 必须与 originalWord 完全相同
bool _headwordMatchesExact(
  String headword,
  String originalWord,
  bool isBiaoyi,
) {
  // 精确匹配：直接比较，不做任何转换
  return headword == originalWord;
}

DictionaryEntry? _parseEntryInIsolate(JsonParseParams params) {
  final jsonData = jsonDecode(params.jsonStr) as Map<String, dynamic>;

  // 精确匹配检查：统一处理表音文字（大小写敏感）和表意文字（简繁不敏感）
  if (params.exactMatch) {
    final headword = jsonData['headword'] as String? ?? '';
    if (!_headwordMatchesExact(
      headword,
      params.originalWord,
      params.isBiaoyi,
    )) {
      return null;
    }
  }

  String entryId = jsonData['id']?.toString() ?? '';
  if (entryId.isEmpty) {
    final rawEntryId = params.row['entry_id'];
    final entryIdStr = rawEntryId?.toString() ?? '';
    entryId = '${params.dictId}_$entryIdStr';
    jsonData['id'] = entryId;
    jsonData['entry_id'] = entryId;
  } else if (!entryId.startsWith('${params.dictId}_')) {
    entryId = '${params.dictId}_$entryId';
    jsonData['id'] = entryId;
    jsonData['entry_id'] = entryId;
  }

  return DictionaryEntry.fromJson(
    jsonData,
    matchedAnchors: params.matchedAnchors,
  );
}

/// 搜索结果，包含 entries 和关系信息
class SearchResult {
  final List<DictionaryEntry> entries;
  final String originalWord;
  final Map<String, List<SearchRelation>> relations;

  SearchResult({
    required this.entries,
    required this.originalWord,
    this.relations = const {},
  });

  bool get hasRelations => relations.isNotEmpty;
}

class DictionaryEntry {
  final String id;
  final String? dictId;
  final String? version;
  final String headword;
  final String? headline; // 标题字段，优先显示
  final String entryType;
  final String? page;
  final String? section;
  final List<String> tags;
  final List<String> certifications;
  final Map<String, dynamic> frequency;
  final dynamic etymology;
  final List<Map<String, dynamic>> pronunciations;
  final List<Map<String, dynamic>> sense;
  final List<String> phrase;
  final List<Map<String, dynamic>> senseGroup;
  final List<String> hiddenLanguages;
  final List<int> groups; // 所属分组ID列表
  final Map<String, dynamic> _rawJson;

  /// 匹配的 headword 及其对应的 anchor 列表
  /// 每个元素是 (headword, anchor) 的记录
  /// anchor 是 JSON 路径，如 "$.sense[0]"
  final List<(String headword, String anchor)> matchedAnchors;

  DictionaryEntry({
    required this.id,
    this.dictId,
    this.version,
    required this.headword,
    this.headline,
    required this.entryType,
    this.page,
    this.section,
    required this.tags,
    required this.certifications,
    required this.frequency,
    this.etymology,
    required this.pronunciations,
    required this.sense,
    this.phrase = const [],
    this.senseGroup = const [],
    this.hiddenLanguages = const [],
    this.groups = const [],
    this.matchedAnchors = const [],
    Map<String, dynamic>? rawJson,
  }) : _rawJson = rawJson ?? {};

  factory DictionaryEntry.fromJson(
    Map<String, dynamic> json, {
    List<(String, String)>? matchedAnchors,
  }) {
    try {
      return DictionaryEntry(
        id: json['entry_id']?.toString() ?? json['id']?.toString() ?? '',
        dictId: json['dict_id']?.toString(),
        version: json['version']?.toString(),
        headword:
            json['headword']?.toString() ?? json['word']?.toString() ?? '',
        headline: json['headline']?.toString(),
        entryType: json['entry_type'] as String? ?? 'word',
        page: json['page']?.toString(),
        section: json['section']?.toString(),
        tags: json['tags'] != null
            ? (json['tags'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        certifications: json['certifications'] != null
            ? (json['certifications'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        frequency: json['frequency'] is Map<String, dynamic>
            ? json['frequency'] as Map<String, dynamic>
            : {},
        etymology: json['etymology'],
        pronunciations: _parsePronunciations(json['pronunciation']),
        groups: _parseGroups(json['groups']),
        sense: json['sense'] != null
            ? (json['sense'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        phrase: () {
          // 只支持 'phrases' 字段（唯一正确形式）
          final p = json['phrases'];
          if (p == null || p == '') return <String>[];
          if (p is String) {
            // 字符串形式：按逗号分隔
            return p
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          if (p is! List) return <String>[];
          return (p)
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }(),
        senseGroup: json['sense_group'] != null
            ? (json['sense_group'] as List<dynamic>)
                  .map((e) => e as Map<String, dynamic>?)
                  .where((e) => e != null)
                  .map((e) => e!)
                  .toList()
            : [],
        hiddenLanguages: json['hidden_languages'] != null
            ? (json['hidden_languages'] as List<dynamic>)
                  .map((e) => e?.toString() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
            : [],
        matchedAnchors: matchedAnchors ?? [],
        rawJson: json,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 从复合ID中提取纯数字entry_id（去掉dict_id前缀）
  String get _pureEntryId {
    if (id.contains('_')) {
      final parts = id.split('_');
      if (parts.length >= 2) {
        final lastPart = parts.last;
        if (int.tryParse(lastPart) != null) {
          return lastPart;
        }
      }
    }
    return id;
  }

  /// 从复合ID中提取纯数字entry_id作为整型（去掉dict_id前缀）
  int get _pureEntryIdAsInt {
    final pureId = _pureEntryId;
    return int.tryParse(pureId) ?? 0;
  }

  /// 原始 JSON 中的 pronunciation 字段是否为单个对象（而非列表）
  bool get pronunciationIsSingleObject {
    final raw = _rawJson['pronunciation'];
    return raw != null && raw is Map;
  }

  Map<String, dynamic> toJson() {
    if (_rawJson.isNotEmpty) {
      final result = Map<String, dynamic>.from(_rawJson);
      // 保存时使用纯数字的entry_id，去掉dict_id前缀，并转换为整型
      result['entry_id'] = _pureEntryIdAsInt;
      return result;
    }
    return {
      'entry_id': _pureEntryIdAsInt,
      if (dictId != null) 'dict_id': dictId,
      'headword': headword,
      if (headline != null) 'headline': headline,
      'entry_type': entryType,
      'page': page,
      'section': section,
      'tags': tags,
      'certifications': certifications,
      'frequency': frequency,
      'etymology': etymology,
      'pronunciation': pronunciations,
      'sense': sense,
      'phrase': phrase,
      'sense_group': senseGroup,
    };
  }
}

/// 从数据库字段中提取JSON字符串（不使用字典）
/// 支持普通字符串和zstd压缩的blob数据
String? extractJsonFromField(dynamic fieldValue) {
  if (fieldValue == null) {
    return null;
  }

  // 如果已经是字符串，直接返回
  if (fieldValue is String) {
    return fieldValue;
  }

  // 如果是字节数组（blob），尝试zstd解压
  if (fieldValue is Uint8List) {
    try {
      final zstdService = ZstdService();
      final decompressed = zstdService.decompressWithoutDict(fieldValue);
      return utf8.decode(decompressed);
    } catch (e) {
      Logger.e('Zstd解压失败: $e', tag: 'DatabaseService');
      // 如果解压失败，尝试直接作为UTF8解码（可能是未压缩的blob）
      try {
        return utf8.decode(fieldValue);
      } catch (_) {
        return null;
      }
    }
  }

  // 其他类型，尝试转字符串
  try {
    return fieldValue.toString();
  } catch (_) {
    return null;
  }
}

/// 使用指定字典从数据库字段中提取JSON字符串
/// 支持普通字符串和zstd压缩的blob数据
String? extractJsonFromFieldWithDict(dynamic fieldValue, Uint8List? dictBytes) {
  if (fieldValue == null) {
    return null;
  }

  // 如果已经是字符串，直接返回
  if (fieldValue is String) {
    return fieldValue;
  }

  // 如果是字节数组（blob），尝试zstd解压（使用字典）
  if (fieldValue is Uint8List) {
    try {
      final zstdService = ZstdService();
      final decompressed = zstdService.decompress(fieldValue, dictBytes);
      return utf8.decode(decompressed);
    } catch (e) {
      Logger.e('Zstd解压失败: $e', tag: 'DatabaseService');
      // 如果解压失败，尝试直接作为UTF8解码（可能是未压缩的blob）
      try {
        return utf8.decode(fieldValue);
      } catch (_) {
        return null;
      }
    }
  }

  // 其他类型，尝试转字符串
  try {
    return fieldValue.toString();
  } catch (_) {
    return null;
  }
}

/// 将JSON对象压缩为zstd格式的blob数据（不使用字典）
/// 使用压缩级别3，返回Uint8List
Uint8List compressJsonToBlob(Map<String, dynamic> jsonData) {
  // 1. 转换为紧凑JSON字符串（无换行、无多余空格）
  final jsonString = jsonEncode(jsonData);

  // 2. 转换为UTF8字节
  final jsonBytes = utf8.encode(jsonString);

  // 3. 使用zstd压缩，级别3
  final zstdService = ZstdService();
  return zstdService.compressWithoutDict(
    Uint8List.fromList(jsonBytes),
    level: 3,
  );
}

/// 使用指定字典将JSON对象压缩为zstd格式的blob数据
/// 使用压缩级别3，返回Uint8List
Uint8List compressJsonToBlobWithDict(
  Map<String, dynamic> jsonData,
  Uint8List? dictBytes,
) {
  // 1. 转换为紧凑JSON字符串（无换行、无多余空格）
  final jsonString = jsonEncode(jsonData);

  // 2. 转换为UTF8字节
  final jsonBytes = utf8.encode(jsonString);

  // 3. 使用zstd压缩（使用字典），级别3
  final zstdService = ZstdService();
  return zstdService.compress(
    Uint8List.fromList(jsonBytes),
    dictBytes,
    level: 3,
  );
}

/// 查询操作符模式：根据用户输入文本自动检测
enum _QueryMode { normal, like, glob }

/// 根据查询文本自动检测操作符模式：
/// - 含 % 或 _ → LIKE
/// - 含 * ? [ ] ^ → GLOB
/// - 否则 → 普通精确/前缀匹配
_QueryMode _detectQueryMode(String query) {
  if (query.contains('%') || query.contains('_')) return _QueryMode.like;
  if (query.contains('*') ||
      query.contains('?') ||
      query.contains('[') ||
      query.contains(']') ||
      query.contains('^')) {
    return _QueryMode.glob;
  }
  return _QueryMode.normal;
}

/// 边打边搜候选词的内部数据结构。
/// [headword] 展示用原文；[sortKey] 用于跨词典排序（表意=phonetic，表音=''）；[rank] 用于表音分级。
class _Candidate {
  final String headword;
  final String sortKey;
  final int rank;
  const _Candidate(this.headword, this.sortKey, this.rank);
}

/// 标准化搜索词的结果，按语言预计算。
/// [headword] 用于检索 headword_normalized 字段
/// [phonetic] 用于检索 phonetic 字段（仅表意语言有值）
class _NormalizedQuery {
  final String headword;
  final String? phonetic;

  const _NormalizedQuery({required this.headword, this.phonetic});
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // 静态 RegExp 常量，避免每次调用时重新创建对象
  static final RegExp _diacriticsRegExp = RegExp(r'[\u0300-\u036f]');
  static final RegExp _chineseRegExp = RegExp(r'[\u4e00-\u9fa5]');
  static final RegExp _japaneseRegExp = RegExp(r'[\u3040-\u309f\u30a0-\u30ff]');
  static final RegExp _koreanRegExp = RegExp(r'[\uac00-\ud7af]');

  /// 判断文本是否含有表意文字（汉字 / 假名 / 谚文）
  static bool containsIdeographic(String text) {
    return _chineseRegExp.hasMatch(text) ||
        _japaneseRegExp.hasMatch(text) ||
        _koreanRegExp.hasMatch(text);
  }

  final DictionaryManager _dictManager = DictionaryManager();
  Database? _database;
  String? _currentDictionaryId;
  String? _cachedDatabasePath;

  // 缓存各词典是否为表意（biaoyi）模式（含 phonetic 列即为表意，含 headword_normalized 与否均可）
  final Map<String, bool> _dictHasPhoneticsCache = {};

  Future<String> get currentDictionaryId async {
    if (_currentDictionaryId != null) return _currentDictionaryId!;

    final installedDicts = await _dictManager.getInstalledDictionaries();
    if (installedDicts.isEmpty) {
      _currentDictionaryId = 'default';
    } else {
      _currentDictionaryId = installedDicts.first;
    }

    return _currentDictionaryId!;
  }

  Future<void> setCurrentDictionary(String dictionaryId) async {
    if (_currentDictionaryId == dictionaryId) return;

    await close();
    _currentDictionaryId = dictionaryId;
    _cachedDatabasePath = null;
    // DictionaryManager 会在关闭数据库时自动清除 zstd 字典缓存
  }

  Future<String> get databasePath async {
    if (_cachedDatabasePath != null) return _cachedDatabasePath!;

    final dictId = await currentDictionaryId;
    final dbPath = await _dictManager.getDictionaryDbPath(dictId);

    if (!await File(dbPath).exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    _cachedDatabasePath = dbPath;
    return _cachedDatabasePath!;
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase(readOnly: true);
    return _database!;
  }

  /// 获取可写的数据库实例（用于编辑）
  Future<Database> get writableDatabase async {
    final String dbPath = await databasePath;
    final File dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    Logger.d('writableDatabase: 打开可写数据库: $dbPath', tag: 'DatabaseService');

    return await openDatabase(
      dbPath,
      version: 1,
      readOnly: false,
      onCreate: (db, version) {
        Logger.d('Creating database schema...', tag: 'DatabaseService');
      },
    );
  }

  Future<Database> _initDatabase({bool readOnly = true}) async {
    final String dbPath = await databasePath;
    final File dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found at: $dbPath');
    }

    // 使用统一的数据库初始化器
    DatabaseInitializer().initialize();

    Logger.d(
      '_initDatabase: 打开数据库 (readOnly=$readOnly): $dbPath',
      tag: 'DatabaseService',
    );

    // 只读模式下不设置 version 和 onCreate，避免触发写入操作
    if (readOnly) {
      return await openDatabase(dbPath, readOnly: true);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      readOnly: readOnly,
      onCreate: (db, version) {
        Logger.d('Creating database schema...', tag: 'DatabaseService');
      },
    );
  }

  /// 规范化搜索词（与 build_db_from_jsonl.py 的 normalize_text() 保持一致）：
  /// 1. RFC 3986 百分号编码解码（如 %20 → 空格，%E4%B8%AD%E6%96%87 → 中文）
  /// 2. 根据语言代码处理：
  ///    - 繁体中文（zh-tw/zh-hk/zh-mo/zh-hant）转简体
  ///    - 日语发音（isPhonetic=true）进行标准化处理
  /// 3. 小写化
  /// 4. 去除音调符号（Unicode 组合字符）
  /// 5. 去除两端空格
  /// 6. isPhonetic 时去除所有空格
  String _normalizeSearchWord(
    String word, {
    String? langCode,
    bool isPhonetic = false,
  }) {
    // RFC 3986: 解码百分号编码（URI/URL 编码）
    // 例如：%20 → 空格，%C3%A9 → é，%E4%B8%AD%E6%96%87 → 中文
    if (word.contains('%')) {
      try {
        word = Uri.decodeComponent(word);
      } catch (e) {
        // 解码失败（如无效的百分号编码），保持原文本
        Logger.d('URI解码失败，保持原文本: $e', tag: 'DatabaseService');
      }
    }

    // isPhonetic 时先去除所有空格
    if (isPhonetic) {
      word = word.replaceAll(' ', '');
    }

    // 繁体中文转简体（根据 langCode 判断）
    if (_shouldConvertToSimplified(langCode)) {
      word = ChineseConvertService().convertToSimplified(word);
    }

    // 日语发音标准化（仅当 isPhonetic 且语言为日语时）
    final normalizedLangCode = langCode?.toLowerCase();
    if (isPhonetic &&
        (normalizedLangCode == 'ja' || normalizedLangCode == 'jp')) {
      word = _normalizeJapanese(word);
    }

    // 小写化
    String normalized = word.toLowerCase();
    // 去除音调符号（Unicode组合字符）
    normalized = normalized.replaceAll(_diacriticsRegExp, '');
    // 去除两端空格
    normalized = normalized.trim();

    return normalized;
  }

  /// 预计算各语言的标准化查询结果。
  /// 对于每种语言，计算 headword 标准化结果；
  /// 对于表意语言（中/日/韩），额外计算 phonetic 标准化结果。
  Map<String, _NormalizedQuery> _precomputeNormalizedQueries(
    String word,
    Set<String> languageCodes,
  ) {
    final result = <String, _NormalizedQuery>{};
    const logographic = {'zh', 'ja', 'ko'};

    for (final langCode in languageCodes) {
      final normalizedLang = LanguageUtils.normalizeSourceLanguage(langCode);

      // 计算 headword 标准化结果
      final headwordNorm = _normalizeSearchWord(word, langCode: normalizedLang);

      // 表意语言额外计算 phonetic 标准化结果
      String? phoneticNorm;
      if (logographic.contains(normalizedLang)) {
        phoneticNorm = _normalizeSearchWord(
          word,
          langCode: normalizedLang,
          isPhonetic: true,
        );
      }

      result[normalizedLang] = _NormalizedQuery(
        headword: headwordNorm,
        phonetic: phoneticNorm,
      );
    }

    return result;
  }

  /// 自动模式下检测输入文本可能属于的语言列表。
  /// 返回 null 表示未检测到特定表意文字脚本，应搜索所有表音文字词典。
  List<String>? _detectPossibleLanguages(String text) {
    final hasKana = _japaneseRegExp.hasMatch(text);
    final hasCJK = _chineseRegExp.hasMatch(text);
    final hasHangul = _koreanRegExp.hasMatch(text);

    if (hasHangul) return ['ko'];
    if (hasKana) return ['ja']; // 有假名（含汉字）→ 日语
    if (hasCJK) return ['zh', 'ja']; // 纯汉字 → 中文或日文均可
    return null; // 拉丁字母等表音文字 → 搜索所有非表意词典
  }

  Future<SearchResult> getAllEntries(
    String word, {
    bool exactMatch = false,
    bool usePhoneticSearch = false,
    String? sourceLanguage,
    String? dictId,
  }) async {
    var entries = <DictionaryEntry>[];
    var relations = <String, List<SearchRelation>>{};

    entries = await _searchEntriesInternal(
      word,
      exactMatch: exactMatch,
      usePhoneticSearch: usePhoneticSearch,
      sourceLanguage: sourceLanguage,
      dictId: dictId,
    );

    if (entries.isEmpty &&
        _detectQueryMode(word) == _QueryMode.normal &&
        !usePhoneticSearch) {
      // 判断是否需要调用英语关系词搜索
      bool shouldSearchEnglish;
      if (sourceLanguage == 'auto') {
        final possibleLangs = _detectPossibleLanguages(word);
        // possibleLangs == null 表示表音文字（可能含英语）；包含 'en' 则明确含英语
        shouldSearchEnglish = possibleLangs == null;
      } else {
        shouldSearchEnglish =
            sourceLanguage == null ||
            LanguageUtils.normalizeSourceLanguage(sourceLanguage) == 'en';
      }

      if (shouldSearchEnglish) {
        Logger.d(
          'DatabaseService: 检测到英语，调用 EnglishSearchService',
          tag: 'EnglishDB',
        );
        final englishService = EnglishSearchService();

        try {
          Logger.d('DatabaseService: 开始搜索关系: $word', tag: 'EnglishDB');
          relations = await englishService
              .searchWithRelations(
                word,
                maxRelatedWords: 10,
                maxRelationsPerWord: 3,
              )
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () {
                  Logger.w('DatabaseService: 关系词搜索超时', tag: 'EnglishDB');
                  return <String, List<SearchRelation>>{};
                },
              );
          Logger.d('DatabaseService: 搜索结果: $relations', tag: 'EnglishDB');

          final relatedWords = relations.keys.toList();
          final limitedWords = relatedWords.take(10).toList();
          final futures = limitedWords.map((relatedWord) {
            return _searchEntriesInternal(
              relatedWord,
              exactMatch: exactMatch,
              usePhoneticSearch: false,
              sourceLanguage: sourceLanguage,
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () => <DictionaryEntry>[],
            );
          }).toList();

          final results = await Future.wait(futures).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              Logger.w('DatabaseService: 关联词查询超时', tag: 'EnglishDB');
              return <List<DictionaryEntry>>[];
            },
          );
          for (final result in results) {
            entries.addAll(result);
          }
        } catch (e) {
          Logger.e(
            'DatabaseService: EnglishSearchService 错误: $e',
            tag: 'EnglishDB',
          );
        }
      }
    }

    return SearchResult(
      entries: entries,
      originalWord: word,
      relations: relations,
    );
  }

  Future<List<DictionaryEntry>> _searchEntriesInternal(
    String word, {
    required bool exactMatch,
    bool usePhoneticSearch = false,
    String? sourceLanguage,
    String? dictId,
  }) async {
    final dictManager = DictionaryManager();
    final enabledDicts = await dictManager.getEnabledDictionariesMetadata();

    // 如果指定了 dictId，只搜索该词典
    if (dictId != null && dictId.isNotEmpty) {
      Logger.i('直接搜索指定词典: $dictId', tag: 'DatabaseService');
      DictionaryMetadata? targetDict;
      for (final dict in enabledDicts) {
        if (dict.id == dictId) {
          targetDict = dict;
          break;
        }
      }
      if (targetDict == null) {
        Logger.w('指定的词典未找到或未启用: $dictId', tag: 'DatabaseService');
        return [];
      }
      // 预计算该词典语言的标准化结果
      final langCode = LanguageUtils.normalizeSourceLanguage(
        targetDict.sourceLanguage,
      );
      final normQuery = _precomputeNormalizedQueries(word, {
        langCode,
      })[langCode]!;
      final result = await _searchInDictionary(
        dictId,
        word,
        normQuery,
        exactMatch: exactMatch,
        usePhoneticSearch: usePhoneticSearch,
      );
      return result;
    }

    Logger.i(
      '搜索单词: "$word", 启用的词典数量: ${enabledDicts.length}',
      tag: 'DatabaseService',
    );
    for (final dict in enabledDicts) {
      Logger.i(
        '  - 启用的词典: ${dict.name} (${dict.id}), 语言: ${dict.sourceLanguage}',
        tag: 'DatabaseService',
      );
    }

    String? targetLang = sourceLanguage;

    if (targetLang == 'auto') {
      Logger.i('自动模式: 搜索所有已启用的词典，不按语言过滤', tag: 'DatabaseService');
    } else {
      Logger.i('指定语言: $targetLang', tag: 'DatabaseService');
    }

    // auto 模式：搜索所有已启用的词典，不按语言过滤
    // 指定语言模式：只搜索匹配该语言的词典
    final filteredDicts = enabledDicts.where((metadata) {
      if (targetLang == 'auto') {
        // auto 模式：搜索所有已启用的词典（表音 + 表意），不按语言过滤
        return true;
      } else if (targetLang != null &&
          LanguageUtils.normalizeSourceLanguage(targetLang) !=
              LanguageUtils.normalizeSourceLanguage(metadata.sourceLanguage)) {
        Logger.i(
          '  过滤掉词典 ${metadata.name}: 语言不匹配 (${metadata.sourceLanguage} != $targetLang)',
          tag: 'DatabaseService',
        );
        return false;
      }
      return true;
    }).toList();

    Logger.i('将要搜索的词典数量: ${filteredDicts.length}', tag: 'DatabaseService');
    for (final dict in filteredDicts) {
      Logger.i('  - 将搜索: ${dict.name} (${dict.id})', tag: 'DatabaseService');
    }

    // 预计算所有涉及语言的标准化结果
    final languageCodes = filteredDicts
        .map((m) => LanguageUtils.normalizeSourceLanguage(m.sourceLanguage))
        .toSet();
    final normQueries = _precomputeNormalizedQueries(word, languageCodes);

    final futures = filteredDicts.map((metadata) async {
      final langCode = LanguageUtils.normalizeSourceLanguage(
        metadata.sourceLanguage,
      );
      final normQuery = normQueries[langCode]!;
      return await _searchInDictionary(
        metadata.id,
        word,
        normQuery,
        exactMatch: exactMatch,
        usePhoneticSearch: usePhoneticSearch,
      );
    }).toList();

    final results = await Future.wait(futures);
    final allEntries = results.expand((list) => list).toList();
    Logger.i('搜索完成，找到 ${allEntries.length} 条结果', tag: 'DatabaseService');
    return allEntries;
  }

  /// 检查词典是否为表意（biaoyi）模式：有 phonetic 列（无论是否含 headword_normalized 均判定为表意）
  Future<bool> _isBiaoyiDict(String dictId, Database db) async {
    if (_dictHasPhoneticsCache.containsKey(dictId)) {
      return _dictHasPhoneticsCache[dictId]!;
    }
    // 以 sourceLanguage 元数据为准：只有中文/日文/韩文才是表意文字词典。
    // 不再用 phonetic 列是否存在判断——表音文字词典（如英语）也可能有 phonetic 列用于存储音标。
    try {
      final meta = await _dictManager.getDictionaryMetadata(dictId);
      const logographic = {'zh', 'ja', 'jp', 'cn'};
      final normalizedLang = LanguageUtils.normalizeSourceLanguage(
        meta?.sourceLanguage ?? '',
      );
      final isbiaoyi = logographic.contains(normalizedLang);
      _dictHasPhoneticsCache[dictId] = isbiaoyi;
      return isbiaoyi;
    } catch (e) {
      _dictHasPhoneticsCache[dictId] = false;
      return false;
    }
  }

  Future<List<DictionaryEntry>> _searchInDictionary(
    String dictId,
    String word,
    _NormalizedQuery normQuery, {
    required bool exactMatch,
    bool usePhoneticSearch = false,
  }) async {
    final entries = <DictionaryEntry>[];

    try {
      Logger.i(
        '正在搜索词典: $dictId, exactMatch=$exactMatch',
        tag: 'DatabaseService',
      );
      final db = await _dictManager.openDictionaryDatabase(dictId);
      Logger.i('成功打开词典数据库: $dictId', tag: 'DatabaseService');

      // 获取该词典的 zstd 字典用于解压
      final zstdDict = await _dictManager.getZstdDictionary(dictId);

      final isbiaoyi = await _isBiaoyiDict(dictId, db);

      String whereClause;
      List<dynamic> whereArgs;

      final qMode = _detectQueryMode(word);
      // 使用预计算的标准化结果
      final headwordNorm = normQuery.headword;
      final phoneticNorm = normQuery.phonetic;

      // ── 新结构：在 indices 表查询 ────────────────────────────────────────
      // 第一步：在 indices 表中查询符合条件的 entry_id 和 headword
      if (isbiaoyi) {
        // 表意文字词典：同时检索 headword 和 phonetic 字段
        if (usePhoneticSearch && phoneticNorm != null) {
          // 读音搜索：使用 phonetic 标准化结果
          if (qMode == _QueryMode.like) {
            whereClause = 'phonetic LIKE ?';
            whereArgs = [phoneticNorm];
          } else if (qMode == _QueryMode.glob) {
            whereClause = 'phonetic GLOB ?';
            whereArgs = [phoneticNorm];
          } else {
            whereClause = 'phonetic = ?';
            whereArgs = [phoneticNorm];
          }
        } else {
          // 默认：同时匹配 headword_normalized 和 phonetic
          // headword_normalized 使用 headwordNorm，phonetic 使用 phoneticNorm
          final phNorm = phoneticNorm ?? headwordNorm;
          if (qMode == _QueryMode.like) {
            whereClause = '(headword_normalized LIKE ? OR phonetic LIKE ?)';
            whereArgs = [headwordNorm, phNorm];
          } else if (qMode == _QueryMode.glob) {
            whereClause = '(headword_normalized GLOB ? OR phonetic GLOB ?)';
            whereArgs = [headwordNorm, phNorm];
          } else {
            whereClause = '(headword_normalized = ? OR phonetic = ?)';
            whereArgs = [headwordNorm, phNorm];
          }
        }
      } else {
        // 表音文字词典：只检索 headword_normalized 字段
        if (qMode == _QueryMode.like) {
          whereClause = 'headword_normalized LIKE ?';
          whereArgs = [headwordNorm];
        } else if (qMode == _QueryMode.glob) {
          whereClause = 'headword_normalized GLOB ?';
          whereArgs = [headwordNorm];
        } else {
          whereClause = 'headword_normalized = ?';
          whereArgs = [headwordNorm];
        }
      }

      // 从 indices 表获取 entry_id 列表（包含 anchor 字段）
      final indexResults = await db.query(
        'indices',
        columns: ['entry_id', 'headword', 'anchor'],
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: isbiaoyi ? 'phonetic ASC, headword ASC' : 'entry_id ASC',
      );

      if (indexResults.isEmpty) {
        return entries;
      }

      // 提取 entry_id 列表
      final entryIds = indexResults.map((r) => r['entry_id'] as int).toList();
      final headwordMap = <int, String>{};
      // 构建 entry_id -> List<(headword, anchor)> 映射
      final anchorMap = <int, List<(String, String)>>{};
      for (final r in indexResults) {
        final entryId = r['entry_id'] as int;
        final headword = r['headword'] as String? ?? '';
        final anchor = r['anchor'] as String? ?? '';
        headwordMap[entryId] = headword;
        // 添加 anchor 信息（去重）
        if (!anchorMap.containsKey(entryId)) {
          anchorMap[entryId] = [];
        }
        // 检查是否已存在相同的 (headword, anchor)
        if (!anchorMap[entryId]!.any(
          (item) => item.$1 == headword && item.$2 == anchor,
        )) {
          anchorMap[entryId]!.add((headword, anchor));
        }
      }

      // 第二步：从 entries 表批量获取 json_data
      final placeholders = List.filled(entryIds.length, '?').join(',');
      final jsonResults = await db.rawQuery(
        'SELECT entry_id, json_data FROM entries WHERE entry_id IN ($placeholders)',
        entryIds,
      );

      // 构建 entry_id -> json_data 映射
      final jsonDataMap = <int, Uint8List>{};
      for (final r in jsonResults) {
        final entryId = r['entry_id'] as int;
        final jsonData = r['json_data'];
        if (jsonData is Uint8List) {
          jsonDataMap[entryId] = jsonData;
        }
      }

      Logger.d(
        '_searchInDictionary: indices查询返回 ${indexResults.length} 条, entries查询返回 ${jsonDataMap.length} 条',
        tag: 'DatabaseService',
      );

      // 按照 entryIds 顺序处理结果
      int filteredCount = 0;
      for (final entryId in entryIds) {
        final jsonData = jsonDataMap[entryId];
        if (jsonData == null) continue;

        final jsonStr = extractJsonFromFieldWithDict(jsonData, zstdDict);
        if (jsonStr == null) {
          Logger.w('无法解析行数据的json_data字段', tag: 'DatabaseService');
          continue;
        }

        DictionaryEntry? entry;
        final row = {'entry_id': entryId, 'headword': headwordMap[entryId]};
        // 获取该 entry 的 anchor 列表
        final anchors = anchorMap[entryId] ?? [];

        if (kIsWeb) {
          final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (exactMatch) {
            final headword = jsonMap['headword'] as String? ?? '';
            if (!_headwordMatchesExact(headword, word, isbiaoyi)) continue;
          }
          _ensureEntryId(jsonMap, row, dictId);
          entry = DictionaryEntry.fromJson(jsonMap, matchedAnchors: anchors);
        } else {
          try {
            entry = await compute(
              _parseEntryInIsolate,
              JsonParseParams(
                jsonStr: jsonStr,
                dictId: dictId,
                row: row,
                exactMatch: exactMatch,
                isBiaoyi: isbiaoyi,
                originalWord: word,
                matchedAnchors: anchors,
              ),
            );
          } catch (e) {
            Logger.w('compute 解析失败，回退到主线程解析: $e', tag: 'DatabaseService');
            try {
              final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (exactMatch) {
                final headword = jsonMap['headword'] as String? ?? '';
                if (!_headwordMatchesExact(headword, word, isbiaoyi)) continue;
              }
              _ensureEntryId(jsonMap, row, dictId);
              entry = DictionaryEntry.fromJson(
                jsonMap,
                matchedAnchors: anchors,
              );
            } catch (e2) {
              Logger.e('回退解析也失败，跳过此条目: $e2', tag: 'DatabaseService');
              continue;
            }
          }
        }

        if (entry != null) {
          entries.add(entry);
        } else {
          filteredCount++;
          Logger.d(
            '_searchInDictionary: entry_id=$entryId 被过滤掉 (headword=${headwordMap[entryId]})',
            tag: 'DatabaseService',
          );
        }
      }
      Logger.d(
        '_searchInDictionary: 处理完成, 成功=${entries.length}, 被过滤=$filteredCount',
        tag: 'DatabaseService',
      );
    } catch (e) {
      Logger.e('_searchInDictionary 整体失败: $e', tag: 'DatabaseService');
    }

    return entries;
  }

  /// 确保条目ID包含词典ID前缀
  void _ensureEntryId(
    Map<String, dynamic> jsonData,
    Map<String, dynamic> row,
    String dictId,
  ) {
    String entryId = jsonData['id']?.toString() ?? '';
    if (entryId.isEmpty) {
      final rawEntryId = row['entry_id'];
      final entryIdStr = rawEntryId?.toString() ?? '';
      entryId = '${dictId}_$entryIdStr';
      jsonData['id'] = entryId;
      jsonData['entry_id'] = entryId;
    } else if (!entryId.startsWith('${dictId}_')) {
      entryId = '${dictId}_$entryId';
      jsonData['id'] = entryId;
      jsonData['entry_id'] = entryId;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 边打边搜候选词
  // ─────────────────────────────────────────────────────────────────

  /// 统一的边打边搜候选词入口。
  ///
  /// [sourceLanguage] 可以是具体语言代码或 'auto'。
  /// 返回已排序、去重、不超过 [limit] 条的候选 headword 列表。
  Future<List<String>> getPreSearchCandidates(
    String query, {
    required String sourceLanguage,
    bool exactMatch = false,
    bool usePhoneticSearch = false,
    bool biaoyiExactMatch = false,
    int limit = 8,
  }) async {
    // query 保留原始输入（含大小写、尾部空格），用于 Dart 层 startsWith 比较。
    // SQL 使用预计算的标准化结果进行索引查找。
    Logger.i(
      'getPreSearchCandidates 开始: query=|$query| lang=$sourceLanguage exactMatch=$exactMatch '
      'usePhoneticSearch=$usePhoneticSearch biaoyiExactMatch=$biaoyiExactMatch limit=$limit',
      tag: 'PrefixSearch',
    );

    if (query.isEmpty) {
      Logger.d('getPreSearchCandidates: 查询为空，返回空列表', tag: 'PrefixSearch');
      return [];
    }

    final enabledDicts = await _dictManager.getEnabledDictionariesMetadata();
    Logger.i(
      'getPreSearchCandidates: 启用的词典数量=${enabledDicts.length}',
      tag: 'PrefixSearch',
    );

    // ── 过滤要搜索的词典 ────────────────────────────────────────────
    // auto 模式：搜索所有启用词典（表音 + 表意），不按语言过滤
    final filteredDicts = sourceLanguage == 'auto'
        ? enabledDicts
        : enabledDicts
              .where(
                (m) =>
                    LanguageUtils.normalizeSourceLanguage(m.sourceLanguage) ==
                    LanguageUtils.normalizeSourceLanguage(sourceLanguage),
              )
              .toList();

    Logger.i(
      'getPreSearchCandidates: sourceLanguage=$sourceLanguage 过滤后词典数量=${filteredDicts.length}',
      tag: 'PrefixSearch',
    );

    for (final m in filteredDicts) {
      Logger.d('  - 将搜索词典: ${m.id} (${m.sourceLanguage})', tag: 'PrefixSearch');
    }

    if (filteredDicts.isEmpty) {
      Logger.w('getPreSearchCandidates: 过滤后无词典可搜索，返回空列表', tag: 'PrefixSearch');
      return [];
    }

    // ── 预计算所有涉及语言的标准化结果 ──────────────────────────────────────
    final languageCodes = filteredDicts
        .map((m) => LanguageUtils.normalizeSourceLanguage(m.sourceLanguage))
        .toSet();
    final normQueries = _precomputeNormalizedQueries(query, languageCodes);

    Logger.d(
      'getPreSearchCandidates: 预计算 ${languageCodes.length} 种语言的标准化结果',
      tag: 'PrefixSearch',
    );

    // ── 并行搜索各词典 ──────────────────────────────────────────────
    final futures = filteredDicts.map((metadata) async {
      try {
        final db = await _dictManager.openDictionaryDatabase(metadata.id);
        final isbiaoyi = await _isBiaoyiDict(metadata.id, db);
        final langCode = LanguageUtils.normalizeSourceLanguage(
          metadata.sourceLanguage,
        );
        final normQuery = normQueries[langCode]!;

        Logger.d(
          'dict=${metadata.id}(${metadata.sourceLanguage}) isbiaoyi=$isbiaoyi sourceLanguage=$sourceLanguage',
          tag: 'PrefixSearch',
        );

        if (sourceLanguage == 'auto') {
          // auto 模式：表意词典搜 headword_normalized + phonetic；表音词典搜 headword_normalized
          return isbiaoyi
              ? _prefixFromBiaoyiDictAuto(
                  db,
                  query,
                  normQuery,
                  biaoyiExactMatch: biaoyiExactMatch,
                  limit: limit,
                )
              : _prefixFromPhoneticDictAuto(
                  db,
                  query,
                  normQuery,
                  exactMatch: exactMatch,
                  limit: limit,
                );
        } else if (isbiaoyi) {
          return _prefixFromBiaoyiDict(
            db,
            query,
            normQuery,
            usePhoneticSearch: usePhoneticSearch,
            biaoyiExactMatch: biaoyiExactMatch,
            limit: limit,
          );
        } else {
          // 表音词典：query 保留原始输入用于 startsWith 大小写/空格比较
          return _prefixFromPhoneticDict(
            db,
            query,
            normQuery,
            exactMatch: exactMatch,
            limit: limit,
          );
        }
      } catch (e, st) {
        Logger.e(
          'dict=${metadata.id} 搜索异常: $e',
          tag: 'PrefixSearch',
          error: e,
          stackTrace: st,
        );
        return <_Candidate>[];
      }
    }).toList();

    final allCandidates = await Future.wait(futures);

    // ── 合并、按 headword 去重、排序 ──────────────────────────────
    final seen = <String>{};
    final merged = <_Candidate>[];
    for (final candidates in allCandidates) {
      for (final c in candidates) {
        if (seen.add(c.headword)) {
          merged.add(c);
        }
      }
    }

    if (sourceLanguage == 'auto') {
      // auto 模式：统一按 headword 小写后升序
      merged.sort(
        (a, b) => a.headword.toLowerCase().compareTo(b.headword.toLowerCase()),
      );
    } else {
      const logographic = {'zh', 'ja', 'ko'};
      if (logographic.contains(
        LanguageUtils.normalizeSourceLanguage(sourceLanguage),
      )) {
        // 表意语言：sortKey = normalize_text(phonetic)，即去声调的拼音/假名字母，
        // compareTo 字典序等价于该语言的语音顺序（中文拼音序，日文五十音序，韩文字母序）。
        merged.sort((a, b) {
          final sk = a.sortKey.compareTo(b.sortKey);
          if (sk != 0) return sk;
          return a.headword.compareTo(b.headword);
        });
      } else {
        merged.sort((a, b) {
          final rankCmp = a.rank.compareTo(b.rank);
          if (rankCmp != 0) return rankCmp;
          final lenCmp = a.headword.length.compareTo(b.headword.length);
          if (lenCmp != 0) return lenCmp;
          return a.headword.toLowerCase().compareTo(b.headword.toLowerCase());
        });
      }
    }

    return merged.take(limit).map((c) => c.headword).toList();
  }

  /// 表意文字词典（biaoyi）的前缀候选词搜索（指定语言模式）。
  /// 同时在 headword_normalized（索引字段）和 phonetic（去声调拼音/假名等）上前缀匹配，
  /// 用 UNION ALL 拆分以分别利用覆盖索引：
  ///   idx_headword(headword_normalized, phonetic, headword)
  ///   idx_phonetic(phonetic, headword_normalized, headword)
  /// GROUP BY headword 去重，携带 MIN(phonetic) 作为 sortKey 返回，
  /// 供 Dart 层跨词典按语音序归并排序。
  Future<List<_Candidate>> _prefixFromBiaoyiDict(
    Database db,
    String query,
    _NormalizedQuery normQuery, {
    bool usePhoneticSearch = false,
    bool biaoyiExactMatch = false,
    required int limit,
  }) async {
    final qMode = _detectQueryMode(query);
    final headwordNorm = normQuery.headword;
    final phoneticNorm = normQuery.phonetic;

    if (usePhoneticSearch && phoneticNorm != null) {
      // 读音搜索：仅在 phonetic 字段上搜索，使用 phonetic 标准化结果
      // 利用覆盖索引 idx_phonetic(phonetic, headword_normalized, headword)
      final String phoneticWhere;
      final List<dynamic> phoneticArgs;
      if (qMode == _QueryMode.like) {
        phoneticWhere = 'phonetic LIKE ?';
        phoneticArgs = [phoneticNorm];
      } else if (qMode == _QueryMode.glob) {
        phoneticWhere = 'phonetic GLOB ?';
        phoneticArgs = [phoneticNorm];
      } else {
        phoneticWhere = 'phonetic LIKE ?';
        phoneticArgs = ['$phoneticNorm%'];
      }
      final rows = await db.rawQuery(
        'SELECT headword, MIN(phonetic) AS phonetic FROM indices'
        ' WHERE $phoneticWhere'
        ' GROUP BY headword'
        ' ORDER BY MIN(phonetic) ASC, headword ASC'
        ' LIMIT ?',
        [...phoneticArgs, limit],
      );
      return rows
          .where((r) => (r['headword'] as String?)?.isNotEmpty == true)
          .map(
            (r) => _Candidate(
              r['headword'] as String,
              r['phonetic'] as String? ?? '',
              1,
            ),
          )
          .toList();
    } else {
      // 普通/简繁区分模式。
      // 为了让「简繁区分」的 startsWith 过滤仅作用于 headword_normalized 臂而不影响
      // phonetic 臂（用户通过拼音/假名输入找到的字符串不应被 headword 前缀约束），
      // 两臂分别查询，再在 Dart 层合并去重。
      // headword_normalized 使用 headwordNorm，phonetic 使用 phoneticNorm
      final phNorm = phoneticNorm ?? headwordNorm;
      final String hwWhere, phWhere;
      final List<dynamic> hwArgs, phArgs;
      final int fetchLimit = biaoyiExactMatch ? limit * 2 : limit;
      if (qMode == _QueryMode.like) {
        hwWhere = 'headword_normalized LIKE ?';
        hwArgs = [headwordNorm];
        phWhere = 'phonetic LIKE ?';
        phArgs = [phNorm];
      } else if (qMode == _QueryMode.glob) {
        hwWhere = 'headword_normalized GLOB ?';
        hwArgs = [headwordNorm];
        phWhere = 'phonetic GLOB ?';
        phArgs = [phNorm];
      } else {
        hwWhere = 'headword_normalized LIKE ?';
        hwArgs = ['$headwordNorm%'];
        phWhere = 'phonetic LIKE ?';
        phArgs = ['$phNorm%'];
      }

      // headword_normalized 臂：简繁区分时对结果应用 startsWith 过滤
      final hwRows = await db.rawQuery(
        'SELECT headword, MIN(phonetic) AS phonetic FROM indices'
        ' WHERE $hwWhere'
        ' GROUP BY headword'
        ' ORDER BY MIN(phonetic) ASC, headword ASC'
        ' LIMIT ?',
        [...hwArgs, fetchLimit],
      );
      var hwCandidates = hwRows
          .where((r) => (r['headword'] as String?)?.isNotEmpty == true)
          .map(
            (r) => _Candidate(
              r['headword'] as String,
              r['phonetic'] as String? ?? '',
              1,
            ),
          )
          .toList();
      if (biaoyiExactMatch && qMode == _QueryMode.normal) {
        final trimmedForExact = query.trim();
        hwCandidates = hwCandidates
            .where((c) => c.headword.startsWith(trimmedForExact))
            .toList();
      }

      // phonetic 臂：不参与简繁区分筛选
      final phRows = await db.rawQuery(
        'SELECT headword, MIN(phonetic) AS phonetic FROM indices'
        ' WHERE $phWhere'
        ' GROUP BY headword'
        ' ORDER BY MIN(phonetic) ASC, headword ASC'
        ' LIMIT ?',
        [...phArgs, fetchLimit],
      );
      final phCandidates = phRows
          .where((r) => (r['headword'] as String?)?.isNotEmpty == true)
          .map(
            (r) => _Candidate(
              r['headword'] as String,
              r['phonetic'] as String? ?? '',
              1,
            ),
          )
          .toList();

      // Dart 层合并去重，headword_normalized 臂优先
      final seen = <String>{};
      final merged = <_Candidate>[];
      for (final c in [...hwCandidates, ...phCandidates]) {
        if (seen.add(c.headword)) merged.add(c);
      }
      merged.sort((a, b) {
        final sk = a.sortKey.compareTo(b.sortKey);
        if (sk != 0) return sk;
        return a.headword.compareTo(b.headword);
      });
      return merged.take(limit).toList();
    }
  }

  /// Auto 模式下的表音词典前缀候选词搜索（简单前缀，无分级排名）。
  /// 利用覆盖索引 (headword_normalized, headword)，按 LOWER(headword) ASC 去重返回。
  Future<List<_Candidate>> _prefixFromPhoneticDictAuto(
    Database db,
    String query,
    _NormalizedQuery normQuery, {
    bool exactMatch = false,
    required int limit,
  }) async {
    final headwordNorm = normQuery.headword;
    final qMode = _detectQueryMode(headwordNorm);
    final String whereStr;
    final List<dynamic> whereArgsList;
    if (qMode == _QueryMode.like) {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = [headwordNorm];
    } else if (qMode == _QueryMode.glob) {
      whereStr = 'headword_normalized GLOB ?';
      whereArgsList = [headwordNorm];
    } else {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = ['$headwordNorm%'];
    }

    // LIKE/GLOB 通配符模式下直接使用 SQL 结果，不做额外 Dart 层过滤。
    final bool isNormalMode = qMode == _QueryMode.normal;
    final int fetchLimit = (exactMatch && isNormalMode) ? limit * 2 : limit;
    final rows = await db.rawQuery(
      'SELECT headword FROM indices'
      ' WHERE $whereStr'
      ' GROUP BY headword'
      ' ORDER BY LOWER(headword) ASC'
      ' LIMIT ?',
      [...whereArgsList, fetchLimit],
    );

    final headwords = rows
        .map((r) => r['headword'] as String?)
        .where((h) => h != null && h.isNotEmpty)
        .cast<String>()
        .toList();

    Logger.d(
      '[exactSearch][auto] query=|$query| headwordNorm=|$headwordNorm| qMode=$qMode '
      'SQL raw(${headwords.length})=${headwords.take(20).toList()}',
      tag: 'PrefixSearch',
    );

    if (exactMatch && isNormalMode) {
      final filtered = headwords
          .where((h) => h.startsWith(query))
          .take(limit)
          .toList();
      Logger.d(
        '[exactSearch][auto] filtered(${filtered.length})=$filtered',
        tag: 'PrefixSearch',
      );
      return filtered.map((h) => _Candidate(h, '', 1)).toList();
    }

    return headwords.take(limit).map((h) => _Candidate(h, '', 1)).toList();
  }

  /// Auto 模式下的表意词典前缀候选词搜索。
  /// 同时在 headword_normalized（索引字段）和 phonetic（拼音/假名输入）上前缀匹配，
  /// 用 UNION ALL 拆分以分别利用覆盖索引：
  ///   idx_headword(headword_normalized, phonetic, headword)
  ///   idx_phonetic(phonetic, headword_normalized, headword)
  /// GROUP BY headword 去重，携带 MIN(phonetic) 作为 sortKey 返回。
  Future<List<_Candidate>> _prefixFromBiaoyiDictAuto(
    Database db,
    String query,
    _NormalizedQuery normQuery, {
    bool biaoyiExactMatch = false,
    required int limit,
  }) async {
    final headwordNorm = normQuery.headword;
    final phoneticNorm = normQuery.phonetic;
    final qMode = _detectQueryMode(headwordNorm);
    final bool isNormalMode = qMode == _QueryMode.normal;
    final int fetchLimit = (biaoyiExactMatch && isNormalMode)
        ? limit * 2
        : limit;

    // ── headword_normalized 臂 ──────────────────────────────────────
    final String hwWhere;
    final List<dynamic> hwArgs;
    if (qMode == _QueryMode.like) {
      hwWhere = 'headword_normalized LIKE ?';
      hwArgs = [headwordNorm];
    } else if (qMode == _QueryMode.glob) {
      hwWhere = 'headword_normalized GLOB ?';
      hwArgs = [headwordNorm];
    } else {
      hwWhere = 'headword_normalized LIKE ?';
      hwArgs = ['$headwordNorm%'];
    }

    final hwRows = await db.rawQuery(
      'SELECT headword, MIN(phonetic) AS phonetic FROM indices'
      ' WHERE $hwWhere'
      ' GROUP BY headword'
      ' ORDER BY MIN(phonetic) ASC, headword ASC'
      ' LIMIT ?',
      [...hwArgs, fetchLimit],
    );
    var hwCandidates = hwRows
        .where((r) => (r['headword'] as String?)?.isNotEmpty == true)
        .map(
          (r) => _Candidate(
            r['headword'] as String,
            r['phonetic'] as String? ?? '',
            1,
          ),
        )
        .toList();
    // 简繁区分仅在普通前缀模式下生效
    if (biaoyiExactMatch && isNormalMode) {
      hwCandidates = hwCandidates
          .where((c) => c.headword.startsWith(query))
          .toList();
    }

    // ── phonetic 臂（不参与简繁区分筛选）──────────────────────────
    // 使用 phonetic 标准化结果
    final phNorm = phoneticNorm ?? headwordNorm;
    final String phWhere;
    final List<dynamic> phArgs;
    if (qMode == _QueryMode.like) {
      phWhere = 'phonetic LIKE ?';
      phArgs = [phNorm];
    } else if (qMode == _QueryMode.glob) {
      phWhere = 'phonetic GLOB ?';
      phArgs = [phNorm];
    } else {
      phWhere = 'phonetic LIKE ?';
      phArgs = ['$phNorm%'];
    }

    final phRows = await db.rawQuery(
      'SELECT headword, MIN(phonetic) AS phonetic FROM indices'
      ' WHERE $phWhere'
      ' GROUP BY headword'
      ' ORDER BY MIN(phonetic) ASC, headword ASC'
      ' LIMIT ?',
      [...phArgs, fetchLimit],
    );
    final phCandidates = phRows
        .where((r) => (r['headword'] as String?)?.isNotEmpty == true)
        .map(
          (r) => _Candidate(
            r['headword'] as String,
            r['phonetic'] as String? ?? '',
            1,
          ),
        )
        .toList();

    // Dart 层合并去重，headword_normalized 臂优先
    final seen = <String>{};
    final merged = <_Candidate>[];
    for (final c in [...hwCandidates, ...phCandidates]) {
      if (seen.add(c.headword)) merged.add(c);
    }
    return merged;
  }

  /// 表音字母文字词典的前缀候选词搜索，支持精确匹配和自动通配符检测。
  ///
  /// 借助覆盖索引 idx_headword(headword_normalized, headword) 一次完成：
  /// • 普通模式：`LIKE 'prefix%'` 前缀匹配
  /// • 精确模式（普通）：`headword_normalized LIKE 'prefix%' AND headword LIKE 'prefix%'`
  ///   headword 为索引末列，过滤全在索引内完成，无需回表
  /// • LIKE 模式：`headword_normalized LIKE ?`
  /// • GLOB 模式：`headword_normalized GLOB ?`
  /// 结果按 `LOWER(headword) ASC` 去重排序。
  Future<List<_Candidate>> _prefixFromPhoneticDict(
    Database db,
    String query,
    _NormalizedQuery normQuery, {
    bool exactMatch = false,
    required int limit,
  }) async {
    final headwordNorm = normQuery.headword;
    final qMode = _detectQueryMode(query);

    final String whereStr;
    final List<dynamic> whereArgsList;
    if (qMode == _QueryMode.like) {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = [headwordNorm];
    } else if (qMode == _QueryMode.glob) {
      whereStr = 'headword_normalized GLOB ?';
      whereArgsList = [headwordNorm];
    } else {
      whereStr = 'headword_normalized LIKE ?';
      whereArgsList = ['$headwordNorm%'];
    }

    // LIKE/GLOB 通配符模式下直接使用 SQL 结果，不做额外 Dart 层过滤；
    // 只有普通前缀模式 + 精确搜索时才需要 fetchLimit 翻倍 + startsWith 过滤。
    final bool isNormalMode = qMode == _QueryMode.normal;
    final int fetchLimit = (exactMatch && isNormalMode) ? limit * 2 : limit;

    final rows = await db.rawQuery(
      'SELECT headword FROM indices'
      ' WHERE $whereStr'
      ' GROUP BY headword'
      ' ORDER BY LOWER(headword) ASC'
      ' LIMIT ?',
      [...whereArgsList, fetchLimit],
    );

    final headwords = rows
        .map((r) => r['headword'] as String?)
        .where((h) => h != null && h.isNotEmpty)
        .cast<String>()
        .toList();

    Logger.d(
      '[exactSearch] query=|$query| headwordNorm=|$headwordNorm| qMode=$qMode '
      'SQL raw(${headwords.length})=${headwords.take(20).toList()}',
      tag: 'PrefixSearch',
    );

    if (exactMatch && isNormalMode) {
      final filtered = headwords
          .where((h) => h.startsWith(query))
          .take(limit)
          .toList();
      Logger.d(
        '[exactSearch] filtered(${filtered.length})=$filtered',
        tag: 'PrefixSearch',
      );
      return filtered.map((h) => _Candidate(h, '', 1)).toList();
    }

    return headwords.map((h) => _Candidate(h, '', 1)).toList();
  }

  // ─────────────────────────────────────────────────────────────────

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  /// 创建 commits 表（如果不存在）并运行迁移升级
  Future<void> _createCommitsTableIfNotExists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commits (
        id TEXT PRIMARY KEY,
        headword TEXT NOT NULL,
        update_time INTEGER NOT NULL,
        operation_type TEXT NOT NULL DEFAULT 'update'
      )
    ''');
    // 迁移：对旧数据库添加 operation_type 列
    try {
      final tableInfo = await db.rawQuery('PRAGMA table_info(commits)');
      final hasOpType = tableInfo.any((col) => col['name'] == 'operation_type');
      if (!hasOpType) {
        await db.execute(
          "ALTER TABLE commits ADD COLUMN operation_type TEXT NOT NULL DEFAULT 'update'",
        );
        // 将旧记录中 is_delete=1 的映射为 'delete'
        try {
          await db.rawUpdate(
            "UPDATE commits SET operation_type='delete' WHERE is_delete=1",
          );
        } catch (_) {}
      }
    } catch (e) {
      Logger.d('迁移 commits 表失败: $e', tag: 'DatabaseService');
    }
  }

  /// 在 commits 表中记录操作（operationType: 'insert' | 'update' | 'delete'）
  Future<void> _recordUpdate(
    Database db,
    String entryId,
    String headword, {
    String operationType = 'update',
  }) async {
    try {
      await _createCommitsTableIfNotExists(db);
      await db.insert('commits', {
        'id': entryId,
        'headword': headword,
        'update_time': DateTime.now().millisecondsSinceEpoch,
        'operation_type': operationType,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      Logger.e('记录更新操作失败: $e', tag: 'DatabaseService', error: e);
    }
  }

  /// 获取指定条目在 commits 表中的当前操作类型，不存在返回 null。
  Future<String?> _getExistingCommitType(Database db, String entryId) async {
    try {
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) return null;
      final rows = await db.query(
        'commits',
        columns: ['operation_type'],
        where: 'id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['operation_type'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 更新词典条目
  Future<bool> updateEntry(
    DictionaryEntry entry, {
    bool skipCommit = false,
  }) async {
    try {
      final dictId = entry.dictId;
      if (dictId == null) {
        return false;
      }

      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      final json = entry.toJson();
      json.remove('id');

      // 获取该词典的 zstd 字典并使用字典压缩
      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final compressedBlob = compressJsonToBlobWithDict(json, zstdDict);

      final String idStr = entry.id;
      int? entryId;

      entryId = int.tryParse(idStr);

      if (entryId == null && idStr.contains('_')) {
        final parts = idStr.split('_');
        if (parts.length >= 2) {
          entryId = int.tryParse(parts.last);
        }
      }

      if (entryId == null) {
        return false;
      }

      // 判断是否为表意词典（中/日/韩），决定是否更新 phonetic 列
      final isbiaoyi = await _isBiaoyiDict(dictId, db);

      // 更新 entries 表
      final result = await db.update(
        'entries',
        {'json_data': compressedBlob},
        where: 'entry_id = ?',
        whereArgs: [entryId],
      );

      // 同时更新 indices 表
      if (result > 0) {
        // 获取词典的源语言代码
        final metadata = _dictManager.getCachedMetadata(dictId);
        final langCode = metadata?.sourceLanguage;

        final headwordNormalized = _normalizeSearchWord(
          entry.headword,
          langCode: langCode,
        );

        // 表意词典：从 JSON 根节点读取 phonetic 字段并规范化
        String? phoneticNormalized;
        if (isbiaoyi) {
          final rawJson = entry.toJson();
          final phoneticRaw = rawJson['phonetic']?.toString() ?? '';
          if (phoneticRaw.isNotEmpty) {
            phoneticNormalized = _normalizeSearchWord(
              phoneticRaw,
              langCode: langCode,
              isPhonetic: true,
            );
          }
        }

        await db.update(
          'indices',
          {
            'headword': entry.headword,
            'headword_normalized': headwordNormalized,
            if (isbiaoyi && phoneticNormalized != null)
              'phonetic': phoneticNormalized,
            'entry_type': entry.entryType,
            'page': entry.page,
            'section': entry.section,
          },
          where: 'entry_id = ?',
          whereArgs: [entryId],
        );
      }

      // 如果更新成功，记录到 commits 表
      if (result > 0 && !skipCommit) {
        // 保留已有 insert 记录（不能把未进入服务器的 insert 覆盖为 update）
        final existingType = await _getExistingCommitType(db, entry.id);
        final operationType = existingType == 'insert' ? 'insert' : 'update';
        await _recordUpdate(
          db,
          entry.id,
          entry.headword,
          operationType: operationType,
        );
      }

      return result > 0;
    } catch (e) {
      Logger.e('更新词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 插入或更新词典条目
  /// 同时更新 entries 表和 indices 表
  Future<bool> insertOrUpdateEntry(
    DictionaryEntry entry, {
    bool skipCommit = false,
  }) async {
    try {
      final dictId = entry.dictId;
      if (dictId == null) {
        return false;
      }

      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      final json = entry.toJson();
      json.remove('id');

      // 直接从 JSON 根节点获取 entry_id
      final entryId = json['entry_id'];
      if (entryId == null) {
        Logger.e('entry_id 字段不存在', tag: 'DatabaseService');
        return false;
      }

      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final compressedBlob = compressJsonToBlobWithDict(json, zstdDict);

      // 在 INSERT 之前检查条目是否已存在，用于区分 insert 和 update
      final existingRows = await db.query(
        'entries',
        columns: ['entry_id'],
        where: 'entry_id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      final isNewEntry = existingRows.isEmpty;

      // 更新 entries 表
      await db.insert('entries', {
        'entry_id': entryId,
        'json_data': compressedBlob,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // ── 更新 indices 表 ─────────────────────────────────────────────────────
      // 获取词典的源语言代码
      final metadata = dictManager.getCachedMetadata(dictId);
      final langCode = metadata?.sourceLanguage;

      // 判断是否为表意词典（中/日/韩）
      final isbiaoyi = await _isBiaoyiDict(dictId, db);

      // 处理 phonetic 字段
      final phoneticRaw = json['phonetic']?.toString() ?? '';
      final phoneticNorm = isbiaoyi && phoneticRaw.isNotEmpty
          ? _normalizeSearchWord(
              phoneticRaw,
              langCode: langCode,
              isPhonetic: true,
            )
          : null;

      // 提取 headword 和 anchor
      final headwordAnchorMap = _extractHeadwordAnchorMap(json);

      // 如果没有任何 headword，使用 entry.headword 作为默认值
      if (headwordAnchorMap.isEmpty && entry.headword.isNotEmpty) {
        headwordAnchorMap[entry.headword] = '';
      }

      // 获取 entry_type
      final entryType = json['entry_type']?.toString() ?? entry.entryType;

      // 先删除该 entry_id 的旧索引记录
      await db.delete('indices', where: 'entry_id = ?', whereArgs: [entryId]);

      // 为每个 headword 插入新的索引记录
      for (final hwEntry in headwordAnchorMap.entries) {
        final hw = hwEntry.key;
        final anchor = hwEntry.value;
        final hwNorm = _normalizeSearchWord(hw, langCode: langCode);

        await db.insert('indices', {
          'headword': hw,
          'headword_normalized': hwNorm,
          if (phoneticNorm != null) 'phonetic': phoneticNorm,
          'entry_type': entryType,
          'entry_id': entryId,
          'anchor': anchor,
        });
      }

      if (!skipCommit) {
        // 若已有 insert 记录（尚未推送）则保持 insert；
        // 若是全新条目，记为 insert；否则记为 update
        final existingType = await _getExistingCommitType(db, entry.id);
        final operationType = (isNewEntry || existingType == 'insert')
            ? 'insert'
            : 'update';
        await _recordUpdate(
          db,
          entry.id,
          entry.headword,
          operationType: operationType,
        );
      }

      return true;
    } catch (e) {
      Logger.e('插入词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 从 commits 表获取所有更新记录
  Future<List<Map<String, dynamic>>> getUpdateRecords(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      // 检查表是否存在
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return [];
      }

      final results = await db.query(
        'commits',
        columns: ['id', 'headword', 'update_time', 'operation_type'],
        orderBy: 'update_time DESC',
      );
      return results;
    } catch (e) {
      Logger.e('获取更新记录失败: $e', tag: 'DatabaseService', error: e);
      return [];
    }
  }

  /// 按词头规范化搜索指定词典，返回最多 [limit] 条原始 JSON。
  /// 使用与建库时相同的 _normalizeSearchWord 规范化，查询 indices 表的 headword_normalized 字段。
  /// [isPhonetic] 为 true 时按发音字段搜索（用于日语罗马音等场景）
  Future<List<Map<String, dynamic>>> searchEntriesByHeadword(
    String dictId,
    String headword, {
    int limit = 20,
    bool isPhonetic = false,
  }) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);
      final zstdDict = await dictManager.getZstdDictionary(dictId);

      // 获取词典的源语言代码
      final metadata = dictManager.getCachedMetadata(dictId);
      final langCode = metadata?.sourceLanguage;

      final normalized = _normalizeSearchWord(
        headword,
        langCode: langCode,
        isPhonetic: isPhonetic,
      );

      // 第一步：从 indices 表获取 entry_id 列表
      final indexRows = await db.query(
        'indices',
        columns: ['entry_id'],
        where: 'headword_normalized = ?',
        whereArgs: [normalized],
        limit: limit,
      );

      if (indexRows.isEmpty) {
        return [];
      }

      // 第二步：从 entries 表获取 json_data
      final entryIds = indexRows.map((r) => r['entry_id'] as int).toList();
      final placeholders = List.filled(entryIds.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT json_data FROM entries WHERE entry_id IN ($placeholders)',
        entryIds,
      );

      final entries = <Map<String, dynamic>>[];
      for (final row in rows) {
        final data = row['json_data'];
        if (data == null) continue;
        final jsonStr = extractJsonFromFieldWithDict(data, zstdDict);
        if (jsonStr == null) continue;
        entries.add(jsonDecode(jsonStr) as Map<String, dynamic>);
      }
      return entries;
    } catch (e) {
      Logger.e('按词头搜索失败: $e', tag: 'DatabaseService', error: e);
      return [];
    }
  }

  Future<Map<String, dynamic>?> getEntryJsonById(
    String dictId,
    String entryId,
  ) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      int? entryIdInt;
      entryIdInt = int.tryParse(entryId);
      if (entryIdInt == null && entryId.contains('_')) {
        final parts = entryId.split('_');
        if (parts.length >= 2) {
          entryIdInt = int.tryParse(parts.last);
        }
      }

      if (entryIdInt == null) {
        return null;
      }

      final results = await db.query(
        'entries',
        columns: ['json_data'],
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
      );

      if (results.isEmpty) {
        return null;
      }

      final jsonData = results.first['json_data'];
      if (jsonData == null) {
        return null;
      }

      // 获取 zstd 字典并解压
      final zstdDict = await dictManager.getZstdDictionary(dictId);
      final jsonStr = extractJsonFromFieldWithDict(jsonData, zstdDict);
      if (jsonStr == null) {
        return null;
      }

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      Logger.e('获取条目JSON失败: $e', tag: 'DatabaseService', error: e);
      return null;
    }
  }

  /// 删除 commits 表中指定条目的记录
  Future<bool> deleteUpdateRecord(String dictId, String entryId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return true;
      }

      await db.delete('commits', where: 'id = ?', whereArgs: [entryId]);
      return true;
    } catch (e) {
      Logger.e('删除更新记录失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 删除词典条目（同时在 commits 表中记录删除操作）
  /// 注意：由于外键约束 ON DELETE CASCADE，删除 entries 表记录时会自动删除 indices 表对应记录
  Future<bool> deleteEntryById(String dictId, String entryId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      int? entryIdInt = int.tryParse(entryId);
      if (entryIdInt == null && entryId.contains('_')) {
        final parts = entryId.split('_');
        if (parts.length >= 2) {
          entryIdInt = int.tryParse(parts.last);
        }
      }

      if (entryIdInt == null) {
        Logger.e('无效 entry_id: $entryId', tag: 'DatabaseService');
        return false;
      }

      // 先从 indices 表获取 headword，用于 commit 记录
      final indexRows = await db.query(
        'indices',
        columns: ['headword'],
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
        limit: 1,
      );

      if (indexRows.isEmpty) {
        Logger.e('未找到 entry_id=$entryId 的条目', tag: 'DatabaseService');
        return false;
      }

      final headword = indexRows.first['headword'] as String? ?? '';

      // 删除 entries 表条目（外键约束会自动删除 indices 表对应记录）
      await db.delete(
        'entries',
        where: 'entry_id = ?',
        whereArgs: [entryIdInt],
      );

      // 处理 commits 记录：
      // - 若该条目的 commit 类型是 'insert'（尚未推送服务器），直接移除记录即可
      // - 否则记录为 'delete'，等待推送
      final existingCommitType = await _getExistingCommitType(db, entryId);
      if (existingCommitType == 'insert') {
        await db.delete('commits', where: 'id = ?', whereArgs: [entryId]);
      } else {
        await _recordUpdate(db, entryId, headword, operationType: 'delete');
      }

      return true;
    } catch (e) {
      Logger.e('删除词条失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }

  /// 清除 commits 表中的所有记录
  Future<bool> clearUpdateRecords(String dictId) async {
    try {
      final dictManager = DictionaryManager();
      final db = await dictManager.openDictionaryDatabase(dictId);

      // 检查表是否存在
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='commits'",
      );
      if (tableExists.isEmpty) {
        return true;
      }

      await db.delete('commits');
      return true;
    } catch (e) {
      Logger.e('清除更新记录失败: $e', tag: 'DatabaseService', error: e);
      return false;
    }
  }
}
