import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easydict/components/component_renderer.dart';

void main() {
  group('Ruby Text Parsing in component_renderer.dart', () {
    test('parseFormattedText should parse Ruby syntax [漢](:かん)', () {
      const text = '[漢](:かん)';
      const baseStyle = TextStyle(fontSize: 14);

      final result = parseFormattedText(text, baseStyle, context: null);

      // 验证结果
      expect(result.spans.length, 1);
      expect(result.plainTexts.length, 1);
      expect(result.plainTexts.first, '漢');
    });

    test('parseFormattedText should handle mixed Ruby and normal text', () {
      const text = '这是[漢](:かん)字测试';
      const baseStyle = TextStyle(fontSize: 14);

      final result = parseFormattedText(text, baseStyle, context: null);

      // 验证结果 - 应该有3个段落：前缀文本、Ruby、后缀文本
      expect(result.spans.length, 3);
      expect(result.plainTexts.length, 3);
      expect(result.plainTexts[0], '这是');
      expect(result.plainTexts[1], '漢');
      expect(result.plainTexts[2], '字测试');
    });

    test('parseFormattedText should handle multiple Ruby segments', () {
      const text = '[漢](:かん)[字](:じ)';
      const baseStyle = TextStyle(fontSize: 14);

      final result = parseFormattedText(text, baseStyle, context: null);

      // 验证结果
      expect(result.spans.length, 2);
      expect(result.plainTexts.length, 2);
      expect(result.plainTexts[0], '漢');
      expect(result.plainTexts[1], '字');
    });

    test('parseFormattedText should handle Ruby with normal formatting', () {
      const text = '[漢](bold) and [字](:じ)';
      const baseStyle = TextStyle(fontSize: 14);

      final result = parseFormattedText(text, baseStyle, context: null);

      // 验证结果
      expect(result.spans.length, 3); // bold格式、纯文本、Ruby
      expect(result.plainTexts.length, 3);
      expect(result.plainTexts[0], '漢');
      expect(result.plainTexts[1], ' and ');
      expect(result.plainTexts[2], '字');
    });
  });
}
