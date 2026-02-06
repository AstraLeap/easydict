import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用帮助'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(context, '欢迎使用 EasyDict', Icons.waving_hand, [
            'EasyDict 是一款功能强大的词典应用，支持离线查词和 AI 智能问答。',
            '无论是学习英语、查阅专业术语，还是深度理解词义，EasyDict 都能满足您的需求。',
          ]),
          _buildSection(context, '快速开始', Icons.rocket_launch, [
            '1. 查词：在首页搜索框输入单词，按回车即可查看释义',
            '2. 收藏：点击单词详情页的收藏按钮，将单词加入生词本',
            '3. AI 问答：在单词详情页点击 AI 图标，与 AI 探讨词义用法',
            '4. 管理词典：在设置中配置和管理您的词典来源',
          ]),
          _buildSection(context, '查词功能', Icons.search, [
            '• 支持模糊搜索，输入部分字母也能找到相关单词',
            '• 支持词典跳转，点击释义中的链接词可快速查看',
            '• 音标显示，部分词典提供英美音标',
            '• 例句展示，帮助理解单词的实际用法',
            '• 词源信息，深入了解单词的历史演变',
          ]),
          _buildSection(context, '生词本', Icons.bookmark, [
            '• 收藏的单词会自动保存到生词本',
            '• 在底部导航栏点击"生词本"图标即可查看',
            '• 支持搜索已收藏的单词',
            '• 可以随时取消收藏，从生词本中移除',
            '• 生词本数据会持久保存，不用担心丢失',
          ]),
          _buildSection(context, 'AI 智能问答', Icons.auto_awesome, [
            '• 在单词详情页点击 AI 图标，开启智能问答',
            '• 可以询问单词的用法、搭配、同义词等',
            '• AI 会结合上下文给出详细解释',
            '• 支持追问，深入探讨相关知识点',
            '• 需要先在设置中配置 AI API 密钥',
          ]),
          _buildSection(context, '词典管理', Icons.library_books, [
            '• 词典来源：在"设置 → 词典管理"中查看和管理词典',
            '• 在线订阅：添加在线词典源，自动下载和更新词典',
            '• 词典启用：选择要使用的词典，支持同时使用多个词典',
            '• 离线使用：下载后的词典无需网络即可查询',
          ]),
          _buildSection(context, 'AI 配置', Icons.psychology, [
            '• 支持多种 AI 服务：OpenAI、DeepSeek、Moonshot 等',
            '• 在"设置 → AI 配置"中添加您的 API 密钥',
            '• 可分别配置快速查询和标准模式',
            '• 支持自定义 API 地址，适配各种代理服务',
          ]),
          _buildSection(context, '主题设置', Icons.palette, [
            '• 浅色模式：明亮清晰，适合白天使用',
            '• 深色模式：柔和护眼，适合夜间使用',
            '• 跟随系统：自动适配系统主题设置',
            '• 在"设置"页面点击"主题模式"即可切换',
          ]),
          _buildSection(context, '聊天记录管理', Icons.chat_bubble_outline, [
            '• 所有 AI 对话记录会自动保存',
            '• 在"设置 → 杂项设置"中查看记录数量',
            '• 可设置自动清理，定期删除过期记录',
            '• 支持一键清除所有聊天记录',
          ]),
          _buildSection(context, '常见问题', Icons.help_outline, [
            'Q: 为什么有些单词查不到？',
            'A: 请检查是否已安装包含该单词的词典，或尝试使用在线订阅功能添加更多词典。',
            '',
            'Q: AI 问答没有响应？',
            'A: 请检查 AI 配置中的 API 密钥是否正确，以及网络连接是否正常。',
            '',
            'Q: 如何备份我的数据？',
            'A: 词典文件、生词本和聊天记录都存储在应用数据目录中，可以手动备份该目录。',
            '',
            'Q: 可以离线使用吗？',
            'A: 查词功能完全支持离线使用。AI 问答需要网络连接。',
            '',
            'Q: 如何添加更多词典？',
            'A: 在"设置 → 词典管理 → 词典来源"中添加在线订阅源，或导入本地词典。',
          ]),
          _buildSection(context, '使用技巧', Icons.lightbulb_outline, [
            '• 使用快捷键：在搜索框按回车快速查词',
            '• 多词典对比：同时启用多个词典，查看不同释义',
            '• 收藏复习：定期查看生词本，巩固记忆',
            '• AI 深度学：对难词使用 AI 问答，获取详细讲解',
          ]),
          _buildSection(context, '注意事项', Icons.info_outline, [
            '• 首次使用建议配置 AI 服务，获得更好的学习体验',
            '• 在线订阅词典需要网络连接，下载后可离线使用',
            '• 定期清理聊天记录，释放存储空间',
            '• 重要数据建议定期备份',
          ]),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(
                  'EasyDict',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '让学习更高效',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '版本 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
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
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
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
