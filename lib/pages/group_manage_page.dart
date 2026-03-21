import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../data/models/group_model.dart';
import '../i18n/strings.g.dart';
import '../services/dictionary_manager.dart';
import '../services/font_loader_service.dart';
import '../services/group_service.dart';
import 'group_page.dart';

/// 组管理页面
class GroupManagePage extends StatefulWidget {
  final String dictId;
  final String dictName;

  const GroupManagePage({
    super.key,
    required this.dictId,
    required this.dictName,
  });

  @override
  State<GroupManagePage> createState() => _GroupManagePageState();
}

class _GroupManagePageState extends State<GroupManagePage> {
  final GroupService _groupService = GroupService();
  final DictionaryManager _dictManager = DictionaryManager();

  List<DictionaryGroup> _rootGroups = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _hasGroupsTable = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _hasGroupsTable = await _groupService.hasGroupsTable(widget.dictId);

      if (_hasGroupsTable) {
        _rootGroups = await _groupService.getRootGroups(widget.dictId);
        _stats = await _groupService.getGroupStats(widget.dictId);
      } else {
        _rootGroups = [];
        _stats = {'totalGroups': 0, 'rootGroups': 0, 'totalItems': 0};
      }
    } catch (e) {
      Logger.e('加载组数据失败: $e', tag: 'GroupManagePage');
      if (mounted) {
        showToast(context, context.t.groups.loadFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createGroup({int? parentId}) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.groups.createGroup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.t.groups.groupName,
                  hintText: context.t.groups.groupNameHint,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: context.t.groups.description,
                  hintText: context.t.groups.descriptionHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.save),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, context.t.groups.groupNameHint);
      return;
    }

    try {
      await _groupService.createGroup(
        widget.dictId,
        DictionaryGroup(
          name: name,
          parentId: parentId,
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
        ),
      );

      if (mounted) {
        showToast(context, context.t.groups.groupCreated);
        await _loadData();
      }
    } catch (e) {
      Logger.e('创建组失败: $e', tag: 'GroupManagePage');
      if (mounted) {
        showToast(context, context.t.groups.createFailed);
      }
    }
  }

  Future<void> _editGroup(DictionaryGroup group) async {
    final nameController = TextEditingController(text: group.name);
    final descriptionController = TextEditingController(
      text: group.description ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.groups.editGroup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.t.groups.groupName,
                  hintText: context.t.groups.groupNameHint,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: context.t.groups.description,
                  hintText: context.t.groups.descriptionHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.common.save),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, context.t.groups.groupNameHint);
      return;
    }

    try {
      await _groupService.updateGroup(
        widget.dictId,
        group.copyWith(
          name: name,
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
        ),
      );

      if (mounted) {
        showToast(context, context.t.groups.groupUpdated);
        await _loadData();
      }
    } catch (e) {
      Logger.e('更新组失败: $e', tag: 'GroupManagePage');
      if (mounted) {
        showToast(context, context.t.groups.updateFailed);
      }
    }
  }

  Future<void> _deleteGroup(DictionaryGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.groups.deleteGroup),
        content: Text(context.t.groups.deleteGroupConfirm(name: group.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.t.common.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _groupService.deleteGroup(widget.dictId, group.groupId!);

      if (mounted) {
        showToast(context, context.t.groups.groupDeleted);
        await _loadData();
      }
    } catch (e) {
      Logger.e('删除组失败: $e', tag: 'GroupManagePage');
      if (mounted) {
        showToast(context, context.t.groups.deleteFailed);
      }
    }
  }

  void _navigateToGroup(DictionaryGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            GroupPage(dictId: widget.dictId, groupId: group.groupId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = FontLoaderService().getDictionaryContentScale();

    Widget content = Scaffold(
      appBar: AppBar(
        title: Text(context.t.groups.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _createGroup(),
            tooltip: context.t.groups.createGroup,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(),
        icon: const Icon(Icons.add),
        label: Text(context.t.groups.createGroup),
      ),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 统计信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.t.groups.statsInfo(
                        groups: _stats['totalGroups'] ?? 0,
                        items: _stats['totalItems'] ?? 0,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 组列表
          Text(
            context.t.groups.subGroups,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          if (_rootGroups.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_off_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.t.groups.noGroups,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._rootGroups.map((group) => _buildGroupCard(group)),
        ],
      ),
    );
  }

  Widget _buildGroupCard(DictionaryGroup group) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToGroup(group),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.subGroupCount} ${context.t.groups.subGroups.toLowerCase()} · ${group.itemCount} ${context.t.groups.entries.toLowerCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editGroup(group);
                      break;
                    case 'delete':
                      _deleteGroup(group);
                      break;
                    case 'add_subgroup':
                      _createGroup(parentId: group.groupId);
                      break;
                  }
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
                    value: 'add_subgroup',
                    child: Row(
                      children: [
                        const Icon(Icons.create_new_folder_outlined),
                        const SizedBox(width: 8),
                        Text(context.t.groups.createGroup),
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
        ),
      ),
    );
  }
}
