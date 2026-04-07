import 'dart:convert';

/// JSON Path 解析工具类
class JsonPathUtils {
  /// 根据路径获取 JSON 中的值
  ///
  /// 支持的路径格式：
  /// - `key.subkey` - Map 访问
  /// - `0`, `1` 等数字 - List 索引访问
  /// - `[0]`, `[1]` 等方括号格式 - List 索引访问
  ///
  /// 示例：
  /// ```dart
  /// final json = {'sense_group': [{'sense': [{'example': [{'text': 'Hello'}]}]}]};
  /// final value = getValueByPath(json, 'sense_group.0.sense.0.example.0.text');
  /// // value = 'Hello'
  /// ```
  static dynamic getValueByPath(dynamic json, String path) {
    if (path.isEmpty) return json;

    final pathParts = path.split('.');
    dynamic currentValue = json;

    for (final part in pathParts) {
      if (currentValue == null) return null;

      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        final index = _parseArrayIndex(part);
        if (index != null && index >= 0 && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return currentValue;
  }

  /// 解析数组索引
  static int? _parseArrayIndex(String part) {
    if (part.startsWith('[') && part.endsWith(']')) {
      return int.tryParse(part.substring(1, part.length - 1));
    }
    return int.tryParse(part);
  }

  /// 格式化值用于显示
  ///
  /// - String: 直接返回
  /// - Map/List: 格式化为缩进 JSON
  /// - 其他: 转换为字符串
  static String formatValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value.toString();
  }
}