import 'package:easydict/services/t2s_map.dart';

/// 中文繁转简服务（单例，纯 Dart 实现，无 native-assets 依赖）。
///
/// 使用嵌入的 OpenCC STCharacters 字符级映射表（由 Python opencc-python-reimplemented
/// 自动生成，覆盖 CJK 统一表意文字 U+4E00-U+9FFF 及扩展区），
/// 与数据库构建脚本（build_db_from_jsonl.py）中 `opencc.OpenCC('t2s').convert(text)`
/// 的字符级行为保持一致。
class ChineseConvertService {
  static final ChineseConvertService _instance =
      ChineseConvertService._internal();
  factory ChineseConvertService() => _instance;
  ChineseConvertService._internal();

  /// 将文本中的繁体中文字符逐字转换为简体中文。
  ///
  /// 仅替换在 kT2SMap 映射表中存在的字符；其余字符（拉丁字母、假名、谚文等）原样保留。
  String convertToSimplified(String text) {
    if (text.isEmpty) return text;
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final simplified = kT2SMap[rune];
      buf.writeCharCode(simplified ?? rune);
    }
    return buf.toString();
  }
}
