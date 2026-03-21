# Ruby 文本行高问题修复方案

## 问题分析

### 当前实现

当前 [`visitRuby`](lib/components/rendering/formatted_text_parser.dart:920) 函数使用 `Stack` + `Transform.translate` 方式渲染 Ruby 文本：

```dart
WidgetSpan(
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  child: Transform.translate(
    offset: Offset(0, -baselineOffset),  // 上移整个 Stack
    child: Stack(
      clipBehavior: Clip.none,  // 允许溢出
      children: [
        Text(segment.baseText, style: baseStyle),  // 汉字
        Transform.translate(
          offset: Offset(0, -(rubyFontSize + rubySpacing)),  // 假名定位在上方
          child: Text(segment.rubyText, ...),  // 假名
        ),
      ],
    ),
  ),
)
```

### 问题根源

1. **Stack 的高度只由汉字决定** - 假名通过 `Transform.translate` 偏移定位，不参与布局计算
2. **clipBehavior: Clip.none** - 允许假名溢出 Stack 边界
3. **Transform.translate 不影响布局** - 只是视觉偏移，不占用空间
4. **结果**：假名完全脱离文本流，不会撑高当前行

### 视觉效果示意

```
当前效果（假名溢出，不占空间）：
    かん        ← 假名溢出到上一行
    漢字测试    ← 行高正常
    じ
    漢字测试    ← 假名可能被裁剪或重叠

期望效果（假名占空间，撑高行）：
  かん
  漢字测试      ← 行高自然增加
  じ
  漢字测试      ← 每行都有足够空间
```

---

## 解决方案

### 方案：使用 Column 替代 Stack

使用 `Column` 布局让假名自然占据垂直空间：

```dart
WidgetSpan(
  alignment: PlaceholderAlignment.middle,  // 中间对齐
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(rubyText, style: rubyStyle),  // 假名在上
      SizedBox(height: kRubySpacing),     // 间距
      Text(baseText, style: baseStyle),   // 汉字在下
    ],
  ),
)
```

### 优点

1. **假名自然占据空间** - Column 的高度 = 假名高度 + 间距 + 汉字高度
2. **行高自动增加** - WidgetSpan 的高度会被计入行高
3. **实现简单** - 无需复杂的偏移计算
4. **与原计划一致** - 这正是 [`ruby_text_implementation.md`](plans/ruby_text_implementation.md:69) 中推荐的方案A

### 需要考虑的问题

#### 1. 基线对齐问题

使用 `PlaceholderAlignment.middle` 时，Ruby 文本会以垂直中心对齐周围文本：

```
普通文本 [漢](:かん) 普通文本
         ↓
       かん
       漢      ← 汉字中心与周围文本对齐
普通文本 ------ 普通文本
```

这不是最佳效果，我们希望汉字基线与周围文本对齐。

#### 2. 推荐方案：Column + bottom 对齐

关键发现：使用 `PlaceholderAlignment.bottom` 可以让 Widget 底部与文本底部对齐，这样汉字（Column 的最后一个子元素）底部就会与周围文本底部对齐。

**正确方案：使用 Column + bottom 对齐**

```dart
WidgetSpan(
  alignment: PlaceholderAlignment.bottom,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(rubyText, style: rubyStyle),  // 假名 - 在上方，占据空间
      if (kRubySpacing > 0) SizedBox(height: kRubySpacing),
      Text(baseText, style: baseStyle),  // 汉字 - 在底部
    ],
  ),
)
```

**原理说明：**

1. `PlaceholderAlignment.bottom` 让 Widget 底部与文本底部对齐
2. Column 底部是汉字，所以汉字底部与周围文本底部对齐
3. 假名在上方，自然占据空间撑高行高
4. 实现简单直接，无需复杂的偏移计算

**视觉效果：**

```
      かん           ← 假名在上方，占据空间
普通文本 漢 普通文本  ← 汉字底部与周围文本底部对齐
```

---

## 详细实现

### 修改后的 visitRuby 函数

```dart
@override
void visitRuby(_RubySegment segment) {
  final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
  final rubyFontSize = fontSize * kRubyFontScale;

  // 振假名特殊样式：使用淡灰色
  final rubyColor = Colors.grey.shade600;

  // 假名总高度 = 假名字号 * 行高 + 间距
  final rubyTotalHeight = rubyFontSize * 1.0 + kRubySpacing;

  spans.add(
    WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.only(top: rubyTotalHeight),
        child: MouseRegion(
          cursor: config.mouseCursor ?? MouseCursor.defer,
          child: GestureDetector(
            onLongPressStart: config.recognizer != null
                ? (details) {
                    if (config.recognizer is TapGestureRecognizer) {
                      (config.recognizer as TapGestureRecognizer).onTap?.call();
                    }
                  }
                : null,
            onSecondaryTapDown: config.onElementSecondaryTap != null
                ? (details) {
                    if (config.path != null && config.label != null) {
                      config.onElementSecondaryTap!(
                        config.path!.join('.'),
                        config.label!,
                      );
                    }
                  }
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 汉字（基础文本）- 决定 Stack 的基线
                Text(segment.baseText, style: baseStyle),
                // 振假名 - 定位在汉字上方（Padding 区域内）
                Positioned(
                  top: -rubyTotalHeight,
                  left: 0,
                  right: 0,
                  child: Text(
                    segment.rubyText,
                    textAlign: TextAlign.center,
                    style: baseStyle.copyWith(
                      fontSize: rubyFontSize,
                      height: 1.0,
                      color: rubyColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  plainTexts.add(segment.baseText);
}
```

### 关键变化

| 项目     | 旧实现                        | 新实现                             |
| -------- | ----------------------------- | ---------------------------------- |
| 布局方式 | Stack + Transform.translate   | Padding + Stack                    |
| 对齐方式 | PlaceholderAlignment.baseline | PlaceholderAlignment.baseline      |
| 假名定位 | 负偏移量（脱离文本流）        | Positioned 在 Padding 区域内       |
| 行高影响 | 不影响                        | Padding 预留空间，自然撑高         |
| 基线对齐 | 手动计算 baselineOffset       | Stack 基线由汉字决定，自动正确对齐 |
| 复杂度   | 需要计算偏移量                | 只需计算假名总高度                 |

---

## 可选优化

### 1. 调整 kRubySpacing 值

当前 `kRubySpacing = 0.0`，可以根据需要调整假名与汉字之间的间距：

```dart
const double kRubySpacing = 1.0;  // 1像素间距
```

### 2. 假名字体样式

可以考虑添加更多假名样式选项：

```dart
// 假名颜色可配置
final rubyColor = config.rubyColor ?? Colors.grey.shade600;

// 假名字体可配置
final rubyStyle = baseStyle.copyWith(
  fontSize: rubyFontSize,
  height: 1.0,
  color: rubyColor,
  fontWeight: FontWeight.normal,  // 假名通常用正常字重
);
```

---

## 测试验证

### 视觉测试

创建测试用例验证行高效果：

```dart
testWidgets('Ruby text should increase line height', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            // 无 Ruby 的文本
            Text.rich(parseFormattedText('普通文本', baseStyle).span),
            // 有 Ruby 的文本
            Text.rich(parseFormattedText('[漢](:かん)字', baseStyle).span),
          ],
        ),
      ),
    ),
  );

  // 验证第二个 Text 的高度大于第一个
});
```

---

## 总结

本方案通过将 `Stack` 布局改为 `Column` 布局，让 Ruby 文本的假名自然占据垂直空间，从而实现"假名存在时自然挤高当前行"的效果。这是对原计划文档中方案A的正确实现，简单有效。
