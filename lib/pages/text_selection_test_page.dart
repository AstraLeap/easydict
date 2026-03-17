import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../components/global_text_selection.dart';

/// 文本选择测试页面
/// 用于验证文本选择功能是否正常工作
class TextSelectionTestPage extends StatefulWidget {
  const TextSelectionTestPage({super.key});

  @override
  State<TextSelectionTestPage> createState() => _TextSelectionTestPageState();
}

class _TextSelectionTestPageState extends State<TextSelectionTestPage> {
  final GlobalTextSelectionManager _selectionManager =
      GlobalTextSelectionManager();
  String _selectedText = '';
  String _debugLog = '';

  @override
  void initState() {
    super.initState();
    _selectionManager.addListener(_onSelectionChanged);
    _addLog('页面初始化完成');
  }

  @override
  void dispose() {
    _selectionManager.removeListener(_onSelectionChanged);
    _selectionManager.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final text = _selectionManager.selectedText ?? '';
    _addLog('选择变化: "$text"');
    setState(() {
      _selectedText = text;
    });
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    setState(() {
      _debugLog = '[$timestamp] $message\n$_debugLog';
      // 限制日志行数
      final lines = _debugLog.split('\n');
      if (lines.length > 50) {
        _debugLog = lines.take(50).join('\n');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlobalTextSelectionScope(
      manager: _selectionManager,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('文本选择测试 - 所有格式'),
          actions: [
            if (_selectionManager.hasSelection)
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  _selectionManager.copyToClipboard();
                  _addLog('已复制到剪贴板');
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
                  _addLog('选择已清除');
                },
              ),
          ],
        ),
        body: Column(
          children: [
            // 文本内容区域
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '测试说明：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('按住鼠标左键拖动可选择文本'),
                    const Text('蓝色边框 = TextSpan 样式（无需映射）'),
                    const Text('绿色边框 = WidgetSpan（需要映射）'),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // ========== TextSpan 样式测试 ==========
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TextSpan 样式（无需映射）',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // segment_0: 基础样式
                          SelectableTextSegment(
                            segmentId: 'segment_0',
                            globalStartOffset: 0,
                            textSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: '删除线',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '下划线',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '双下划线',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.combine([
                                      TextDecoration.underline,
                                      TextDecoration.underline,
                                    ]),
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '波浪线',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.underline,
                                    decorationStyle: TextDecorationStyle.wavy,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '加粗',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '斜体',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const TextSpan(
                                  text: '。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            plainText: '删除线、下划线、双下划线、波浪线、加粗、斜体。',
                          ),
                          const SizedBox(height: 8),
                          // segment_1: 颜色样式
                          SelectableTextSegment(
                            segmentId: 'segment_1',
                            globalStartOffset: 16, // 上一段长度
                            textSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: '主题色',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '特殊样式',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.blue,
                                  ),
                                ),
                                const TextSpan(
                                  text: '、',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: 'AI内容',
                                  style: TextStyle(
                                    fontSize: 16,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withAlpha(115),
                                  ),
                                ),
                                const TextSpan(
                                  text: '。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            plainText: '主题色、特殊样式、AI内容。',
                          ),
                          const SizedBox(height: 8),
                          // segment_2: 上标下标 - 使用 FontFeature 实现
                          SelectableTextSegment(
                            segmentId: 'segment_2',
                            globalStartOffset: 16 + 13, // 前两段长度
                            textSpan: const TextSpan(
                              children: [
                                TextSpan(
                                  text: '化学公式 H',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '2',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFeatures: [FontFeature.subscripts()],
                                  ),
                                ),
                                TextSpan(
                                  text: 'O，数学公式 x',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '2',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFeatures: [FontFeature.superscripts()],
                                  ),
                                ),
                                TextSpan(
                                  text: ' + y',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '2',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFeatures: [FontFeature.superscripts()],
                                  ),
                                ),
                                TextSpan(
                                  text: ' = z',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '2',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFeatures: [FontFeature.superscripts()],
                                  ),
                                ),
                                TextSpan(
                                  text: '。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            // 使用 FontFeature 后，plainText 就是实际文本
                            plainText: '化学公式 H2O，数学公式 x2 + y2 = z2。',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ========== WidgetSpan 测试 ==========
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WidgetSpan（需要映射）',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // segment_3: Label 标签
                          SelectableTextSegment(
                            segmentId: 'segment_3',
                            globalStartOffset: 16 + 13 + 19, // 前三段长度
                            textSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: '这是一个',
                                  style: TextStyle(fontSize: 16),
                                ),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withAlpha(13),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline.withAlpha(140),
                                        width: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '标签',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ),
                                const TextSpan(
                                  text: '组件。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            // "这是一个" = 4 字符
                            // \uFFFC (位置 4) = 标签
                            // "组件。" = 3 字符
                            // 总共 8 字符
                            plainText: '这是一个\uFFFC组件。',
                            widgetSpanMappings: [
                              WidgetSpanMapping(
                                placeholderIndex: 4,
                                content: '标签',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ========== 链接测试 ==========
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.orange.shade700,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '链接（TextSpan + TapGestureRecognizer）',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // segment_4: 链接
                          SelectableTextSegment(
                            segmentId: 'segment_4',
                            globalStartOffset: 16 + 13 + 19 + 8, // 前四段长度
                            textSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: '点击',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '查词链接',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      _addLog('点击了查词链接');
                                    },
                                ),
                                const TextSpan(
                                  text: '或',
                                  style: TextStyle(fontSize: 16),
                                ),
                                TextSpan(
                                  text: '精确跳转',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      _addLog('点击了精确跳转');
                                    },
                                ),
                                const TextSpan(
                                  text: '。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            plainText: '点击查词链接或精确跳转。',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ========== 混合测试 ==========
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.purple, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '混合格式测试',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // segment_5: 混合格式
                          SelectableTextSegment(
                            segmentId: 'segment_5',
                            globalStartOffset: 16 + 13 + 19 + 8 + 10, // 前五段长度
                            textSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: '这是',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '加粗斜体',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const TextSpan(
                                  text: '文本，包含',
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
                                  text: '组件和',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const TextSpan(
                                  text: '删除线',
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const TextSpan(
                                  text: '样式。',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            // "这是" = 2
                            // "加粗斜体" = 4
                            // "文本，包含" = 5
                            // \uFFFC (位置 11) = WidgetSpan
                            // "组件和" = 3
                            // "删除线" = 3
                            // "样式。" = 3
                            // 总共 20 字符
                            plainText: '这是加粗斜体文本，包含\uFFFC组件和删除线样式。',
                            widgetSpanMappings: [
                              WidgetSpanMapping(
                                placeholderIndex: 11,
                                content: 'WidgetSpan',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 选中的文本显示
            if (_selectedText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '选中的文本：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedText,
                      style: const TextStyle(color: Colors.blue),
                    ),
                  ],
                ),
              ),

            // 调试日志
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                color: Colors.grey.shade100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Text(
                            '调试日志：',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _debugLog = '';
                              });
                            },
                            child: const Text('清除'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _debugLog.isEmpty ? '暂无日志' : _debugLog,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
