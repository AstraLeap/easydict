import 'package:flutter/material.dart';

import 'global_text_selection.dart';

/// 文本选择使用示例
///
/// 这个示例展示了如何使用全局文本选择功能
///
/// ## 核心原理
///
/// 1. GlobalTextSelectionScope 在顶层使用 Listener 监听所有指针事件
/// 2. SelectableTextSegment 只负责显示文本和选择高亮，不处理手势
/// 3. GlobalTextSelectionManager 遍历所有注册的文本段，找到点击位置对应的字符偏移量
///
/// 这样设计的好处是：
/// - 手势监听在顶层，不会被内部的 GestureDetector 拦截
/// - 每个文本段只需要注册自己，不需要处理手势
/// - 支持跨多个文本段的选择

class TextSelectionExample extends StatefulWidget {
  const TextSelectionExample({super.key});

  @override
  State<TextSelectionExample> createState() => _TextSelectionExampleState();
}

class _TextSelectionExampleState extends State<TextSelectionExample> {
  final GlobalTextSelectionManager _selectionManager =
      GlobalTextSelectionManager();
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _selectionManager.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selectionManager.removeListener(_onSelectionChanged);
    _selectionManager.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    setState(() {
      _selectedText = _selectionManager.selectedText ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlobalTextSelectionScope(
      manager: _selectionManager,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('文本选择示例'),
          actions: [
            if (_selectionManager.hasSelection)
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  _selectionManager.copyToClipboard();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                },
              ),
            if (_selectionManager.hasSelection)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _selectionManager.clearSelection();
                },
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一个文本段
              SelectableTextSegment(
                segmentId: 'segment_0',
                globalStartOffset: 0,
                textSpan: const TextSpan(
                  text: '这是一段示例文本，展示了如何在 Flutter 中实现自定义文本选择功能。',
                  style: TextStyle(fontSize: 16),
                ),
                plainText: '这是一段示例文本，展示了如何在 Flutter 中实现自定义文本选择功能。',
              ),
              const SizedBox(height: 16),

              // 包含 WidgetSpan 的富文本
              SelectableTextSegment(
                segmentId: 'segment_1',
                globalStartOffset: 34, // 上一段的长度
                textSpan: TextSpan(
                  children: [
                    const TextSpan(
                      text: '这段文本包含 ',
                      style: TextStyle(fontSize: 16),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('WidgetSpan'),
                      ),
                    ),
                    const TextSpan(
                      text: ' 组件，系统默认的选择功能无法正常工作。',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                plainText: '这段文本包含 WidgetSpan 组件，系统默认的选择功能无法正常工作。',
              ),
              const SizedBox(height: 16),

              // 第三个文本段
              SelectableTextSegment(
                segmentId: 'segment_2',
                globalStartOffset: 34 + 32, // 前两段的长度
                textSpan: const TextSpan(
                  text: '但是使用自定义的选择组件，可以正确处理跨段选择。',
                  style: TextStyle(fontSize: 16),
                ),
                plainText: '但是使用自定义的选择组件，可以正确处理跨段选择。',
              ),
              const SizedBox(height: 32),

              // 显示选中的文本
              if (_selectedText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选中的文本：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedText,
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                ),

              // 使用说明
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用说明：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('• 按住鼠标左键拖动可选择文本'),
                    Text('• 支持跨多个文本段选择'),
                    Text('• 支持包含 WidgetSpan 的富文本'),
                    Text('• 点击右上角复制按钮可复制选中文本'),
                    Text('• 点击关闭按钮可清除选择'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ## 集成到 ComponentRenderer 的步骤
///
/// ### 1. 在 ComponentRendererState 中添加选择管理器
///
/// ```dart
/// class ComponentRendererState extends State<ComponentRenderer> {
///   final GlobalTextSelectionManager _selectionManager = GlobalTextSelectionManager();
///   int _currentGlobalOffset = 0;
/// }
/// ```
///
/// ### 2. 在 build 方法中包裹 GlobalTextSelectionScope
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return GlobalTextSelectionScope(
///     manager: _selectionManager,
///     child: YourOriginalContent(),
///   );
/// }
/// ```
///
/// ### 3. 将 Text.rich 替换为 SelectableTextSegment
///
/// ```dart
/// SelectableTextSegment(
///   segmentId: 'segment_$segmentIndex',
///   globalStartOffset: _currentGlobalOffset,
///   textSpan: textSpan,
///   plainText: plainText,
/// )
/// ```
///
/// ### 4. 更新全局偏移量
///
/// ```dart
/// _currentGlobalOffset += plainText.length;
/// ```
