# 振假名（Ruby Text）布局需求

## 概述

振假名（Ruby Text / Furigana）是日语中用于标注汉字读音的假名，通常显示在汉字上方。本文档描述了振假名在 EasyDict 应用中的布局需求。

## 语法格式

振假名的语法格式为：`[漢](:かん)`

- `漢` 是基础文本（base text），即汉字
- `かん` 是振假名（ruby text），即假名

## 布局要求

### 1. 基线对齐（核心问题）

**当前问题：** 振假名 widget 的基线位置计算不正确，导致假名部分与周围文本基线对齐，而不是汉字与基线对齐。

**正确行为：**

- **汉字（base text）的基线**应该与周围文本的基线对齐
- 假名（ruby text）位于汉字上方，不应影响基线位置
- Widget 的基线应该基于最后一个子元素（汉字），而不是整个 column

### 2. 假名位置

- 假名应水平居中显示在对应汉字上方
- 假名与汉字之间应有适当间距（建议 1-2 像素）
- 假名应使用较小的字体（建议为基础字体的 50%）

### 3. 行高影响

- 振假名 widget 的总高度应包含假名高度
- 行高应自动增加以容纳假名
- 不应影响其他行的布局

### 4. 样式要求

- 假名颜色：使用淡灰色（`Colors.grey.shade600`）
- 假名字体大小：基础字体的 50%
- 假名行高：1.0（紧凑）

## 技术挑战

### Flutter 中的基线计算

Flutter 的 `Padding` widget 在计算基线时会将 top padding 计入基线距离：

```dart
// Padding 的基线计算（简化）
double? computeDistanceToActualBaseline(TextBaseline baseline) {
  return childBaseline + topPadding; // 这导致基线位置偏移
}
```

这导致当使用 `WidgetSpan` 的 `PlaceholderAlignment.baseline` 对齐时，整个 widget 的基线位置会向下偏移 topPadding 的距离。

### 可能的解决方案

1. **自定义 RenderObject**
   创建自定义的 RenderObject，在 `computeDistanceToActualBaseline` 中返回子元素的基线位置（不加 topPadding），同时在布局时将子元素向下偏移。

2. **使用 Baseline widget**
   在 Stack 内部使用 `Baseline` widget 来强制指定基线位置。

3. **使用 Column + CrossAxisAlignment**
   使用 `Column` 并设置 `crossAxisAlignment: CrossAxisAlignment.baseline`，但需要正确处理基线位置。

## 相关文件

- `lib/components/rendering/formatted_text_parser.dart` - `visitRuby` 方法
- `lib/components/component_renderer.dart` - `_RubyTextLayout` 类

## 参考资料

- [HTML Ruby Element](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/ruby)
- [CSS Ruby Layout](https://drafts.csswg.org/css-ruby/)
- [Flutter Baseline Widget](https://api.flutter.dev/flutter/widgets/Baseline-class.html)
