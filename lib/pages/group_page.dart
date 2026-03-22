import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../data/models/group_model.dart';
import '../i18n/strings.g.dart';
import '../services/dictionary_manager.dart';
import '../services/font_loader_service.dart';
import '../services/group_service.dart';

/// 词条导航信息
class EntryNavigationInfo {
  final String dictId;
  final int entryId;
  final String? anchor;

  const EntryNavigationInfo({
    required this.dictId,
    required this.entryId,
    this.anchor,
  });
}

/// 组详情页面
class GroupPage extends StatefulWidget {
  final String dictId;
  final int groupId;

  /// 词条点击回调，用于通知父页面切换词条
  final void Function(EntryNavigationInfo info)? onNavigateToEntry;

  const GroupPage({
    super.key,
    required this.dictId,
    required this.groupId,
    this.onNavigateToEntry,
  });

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final GroupService _groupService = GroupService();
  final DictionaryManager _dictManager = DictionaryManager();

  DictionaryGroup? _group;
  List<DictionaryGroup> _subGroups = [];
  List<DictionaryGroup> _breadcrumb = [];
  Map<int, String> _entryHeadwords = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 加载组信息
      _group = await _groupService.getGroup(widget.dictId, widget.groupId);

      if (_group == null) {
        if (mounted) {
          showToast(context, context.t.groups.loadFailed);
          Navigator.pop(context);
        }
        return;
      }

      // 并行加载子组、面包屑和词条 headwords
      final results = await Future.wait([
        _groupService.getSubGroups(widget.dictId, widget.groupId),
        _groupService.getGroupPath(widget.dictId, widget.groupId),
        _groupService.getGroupEntryHeadwords(widget.dictId, _group!.itemList),
      ]);

      _subGroups = results[0] as List<DictionaryGroup>;
      _breadcrumb = results[1] as List<DictionaryGroup>;
      _entryHeadwords = results[2] as Map<int, String>;
    } catch (e) {
      Logger.e('加载组数据失败: $e', tag: 'GroupPage');
      if (mounted) {
        showToast(context, context.t.groups.loadFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateToSubGroup(DictionaryGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupPage(
          dictId: widget.dictId,
          groupId: group.groupId!,
          onNavigateToEntry: widget.onNavigateToEntry,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _navigateToEntry(GroupItem item) async {
    Logger.d(
      '导航到词条: ${item.entryId}, anchor: ${item.anchor}',
      tag: 'GroupPage',
    );

    // 如果有回调，使用回调通知父页面切换词条
    if (widget.onNavigateToEntry != null) {
      widget.onNavigateToEntry!(
        EntryNavigationInfo(
          dictId: widget.dictId,
          entryId: item.entryId,
          anchor: item.anchor,
        ),
      );
      Navigator.pop(context);
      return;
    }

    // 没有回调时显示提示
    if (mounted) {
      showToast(context, '跳转到词条 #${item.entryId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = FontLoaderService().getDictionaryContentScale();

    Widget content = Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? context.t.groups.title),
        actions: [
          if (_group != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                // TODO: 实现编辑和删除功能
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined),
                      const SizedBox(width: 8),
                      Text(context.t.groups.editGroup),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        context.t.groups.deleteGroup,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );

    if (scale != 1.0) {
      content = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: content,
      );
    }

    return content;
  }

  Widget _buildBody() {
    if (_group == null) {
      return Center(child: Text(context.t.groups.loadFailed));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 面包屑导航
          if (_breadcrumb.isNotEmpty) ...[
            _buildBreadcrumb(),
            const SizedBox(height: 16),
          ],

          // 组描述
          if (_group!.description != null &&
              _group!.description!.isNotEmpty) ...[
            _buildDescription(),
            const SizedBox(height: 16),
          ],

          // 子组列表
          _buildSubGroupsSection(),
          const SizedBox(height: 16),

          // 词条列表
          _buildEntriesSection(),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (int i = 0; i < _breadcrumb.length; i++) ...[
                  if (i > 0)
                    Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: colorScheme.outline,
                    ),
                  InkWell(
                    onTap: i == _breadcrumb.length - 1
                        ? null
                        : () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupPage(
                                  dictId: widget.dictId,
                                  groupId: _breadcrumb[i].groupId!,
                                ),
                              ),
                            );
                          },
                    child: Text(
                      _breadcrumb[i].name,
                      style: TextStyle(
                        fontSize: 12,
                        color: i == _breadcrumb.length - 1
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontWeight: i == _breadcrumb.length - 1
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final colorScheme = Theme.of(context).colorScheme;

    // 尝试解析 description 为 JSON 组件列表
    List<dynamic>? components;
    try {
      if (_group!.description != null) {
        components = jsonDecode(_group!.description!) as List<dynamic>?;
      }
    } catch (e) {
      Logger.w('解析 description 失败: $e', tag: 'GroupPage');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.t.groups.description,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (components != null && components.isNotEmpty)
              // 使用 ComponentRenderer 渲染描述内容
              _buildDescriptionComponents(components)
            else
              Text(
                _group!.description ?? '',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionComponents(List<dynamic> components) {
    // 简化处理：直接显示 JSON 文本
    // TODO: 后续可以集成 ComponentRenderer 进行渲染
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        const JsonEncoder.withIndent('  ').convert(components),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildSubGroupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              context.t.groups.subGroups,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_subGroups.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_subGroups.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_subGroups.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  context.t.groups.noSubGroups,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
          )
        else
          ..._subGroups.map((group) => _buildSubGroupCard(group)),
      ],
    );
  }

  Widget _buildSubGroupCard(DictionaryGroup group) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToSubGroup(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.subGroupCount} ${context.t.groups.subGroups.toLowerCase()} · ${group.itemCount} ${context.t.groups.entries.toLowerCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntriesSection() {
    final items = _group?.itemList ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.article_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              context.t.groups.entries,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  context.t.groups.noEntries,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
          )
        else
          ...items.map((item) => _buildEntryCard(item)),
      ],
    );
  }

  Widget _buildEntryCard(GroupItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final headword = _entryHeadwords[item.entryId] ?? '#${item.entryId}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToEntry(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.text_snippet_outlined, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headword,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.anchor != null && item.anchor!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.anchor!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
