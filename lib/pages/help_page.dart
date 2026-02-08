import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用帮助'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(context, '多词典同时显示', Icons.layers, [
            '支持同时启用多个词典，在单词详情页查看不同词典的释义',
            '在"设置 → 词典管理"中调整词典优先级顺序',
          ]),
          _buildSection(context, '词典跳转', Icons.link, [
            '点击释义中的链接词可快速跳转查看该词的详细释义',
            '支持跨词典跳转，探索更多相关词汇',
          ]),
          _buildSection(context, '单词本分组', Icons.folder_open, [
            '支持创建多个词表，按主题或学习阶段组织单词',
            '点击"管理词表"按钮创建、编辑或删除词表',
            '单词可以同时属于多个词表',
          ]),
          _buildSection(context, '分页加载', Icons.unfold_more, [
            '单词本采用分页加载，滑动到底部自动加载更多单词',
            '避免一次性加载过多数据，提升性能',
          ]),
          _buildSection(context, '在线订阅', Icons.cloud_download, [
            '支持在线词典源，自动下载和更新词典',
            '在"设置 → 词典管理 → 词典来源"中添加订阅地址',
            '下载后的词典无需网络即可查询',
          ]),
          _buildSection(context, 'AI 智能问答', Icons.psychology, [
            '与 AI 探讨单词的用法、搭配、同义词等',
            'AI 会结合词典释义给出详细解释',
            '支持追问，深入探讨相关知识点',
          ]),
          _buildSection(context, '查词历史', Icons.history, [
            '自动记录查词历史，方便回顾',
            '点击历史记录可快速重新查词',
            '支持删除单条或清空全部历史',
          ]),
          _buildSection(context, '音标与例句', Icons.record_voice_over, [
            '部分词典提供英美音标，帮助掌握发音',
            '丰富的例句展示单词的实际用法',
          ]),
          _buildSection(context, '词源信息', Icons.menu_book, [
            '了解单词的历史演变和词根词缀',
            '帮助记忆和理解单词的构成',
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'EasyDict v1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<String> contents,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.3),
            ),
            ...contents.map(
              (content) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  content,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
