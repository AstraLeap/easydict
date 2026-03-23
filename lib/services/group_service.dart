import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/logger.dart';
import '../data/models/group_model.dart';
import 'dictionary_manager.dart';

/// 组服务类，提供组的 CRUD 操作
class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  final DictionaryManager _dictManager = DictionaryManager();

  /// 检查词典是否支持 groups 表
  Future<bool> hasGroupsTable(String dictId) async {
    try {
      final db = await _dictManager.openDictionaryDatabase(dictId);
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='groups'",
      );
      return result.isNotEmpty;
    } catch (e) {
      Logger.e('检查 groups 表失败: $e', tag: 'GroupService');
      return false;
    }
  }

  /// 确保 groups 表存在（如果不存在则创建）
  Future<void> ensureGroupsTable(String dictId) async {
    try {
      final db = await _dictManager.openDictionaryDatabase(dictId);
      await db.execute('''
        CREATE TABLE IF NOT EXISTS groups (
          group_id INTEGER PRIMARY KEY,
          parent_id INTEGER,
          name TEXT NOT NULL,
          description TEXT,
          item_list TEXT DEFAULT '[]',
          sub_group_count INTEGER DEFAULT 0,
          item_count INTEGER DEFAULT 0,
          FOREIGN KEY (parent_id) REFERENCES groups(group_id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_groups_parent ON groups(parent_id)',
      );
      Logger.i('groups 表已创建或已存在: $dictId', tag: 'GroupService');
    } catch (e) {
      Logger.e('创建 groups 表失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 获取所有根组（parent_id 为 NULL 的组）
  Future<List<DictionaryGroup>> getRootGroups(String dictId) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final results = await db.query(
        'groups',
        where: 'parent_id IS NULL',
        orderBy: 'name ASC',
      );
      return results.map((map) => DictionaryGroup.fromMap(map)).toList();
    } catch (e) {
      Logger.e('获取根组失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 获取子组
  Future<List<DictionaryGroup>> getSubGroups(
    String dictId,
    int parentId,
  ) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final results = await db.query(
        'groups',
        where: 'parent_id = ?',
        whereArgs: [parentId],
        orderBy: 'name ASC',
      );
      return results.map((map) => DictionaryGroup.fromMap(map)).toList();
    } catch (e) {
      Logger.e('获取子组失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 获取组详情
  Future<DictionaryGroup?> getGroup(String dictId, int groupId) async {
    Logger.d('getGroup: dictId=$dictId, groupId=$groupId', tag: 'GroupService');
    try {
      final hasTable = await hasGroupsTable(dictId);
      Logger.d('getGroup: hasGroupsTable=$hasTable', tag: 'GroupService');
      if (!hasTable) return null;

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final results = await db.query(
        'groups',
        where: 'group_id = ?',
        whereArgs: [groupId],
        limit: 1,
      );
      Logger.d('getGroup: query results count=${results.length}', tag: 'GroupService');
      if (results.isEmpty) return null;
      return DictionaryGroup.fromMap(results.first);
    } catch (e, stackTrace) {
      Logger.e('获取组详情失败: $e', tag: 'GroupService', stackTrace: stackTrace);
      return null;
    }
  }

  /// 获取组层级路径（用于面包屑导航）
  Future<List<DictionaryGroup>> getGroupPath(String dictId, int groupId) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final path = <DictionaryGroup>[];
      int? currentId = groupId;

      while (currentId != null) {
        final results = await db.query(
          'groups',
          where: 'group_id = ?',
          whereArgs: [currentId],
          limit: 1,
        );
        if (results.isEmpty) break;

        final group = DictionaryGroup.fromMap(results.first);
        path.insert(0, group);
        currentId = group.parentId;
      }

      return path;
    } catch (e) {
      Logger.e('获取组路径失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 批量获取多个组的层级路径（用于面包屑导航）
  /// 返回 Map<int, GroupPath>，key 为 group_id
  Future<Map<int, GroupPath>> getGroupPathsByGroupIds(
    String dictId,
    List<int> groupIds,
  ) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return {};

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final result = <int, GroupPath>{};

      // 批量查询所有需要的组
      if (groupIds.isEmpty) return result;

      final placeholders = groupIds.map((_) => '?').join(',');
      final groups = await db.query(
        'groups',
        where: 'group_id IN ($placeholders)',
        whereArgs: groupIds,
      );

      // 构建 group_id -> group 映射
      final groupMap = <int, DictionaryGroup>{};
      for (final map in groups) {
        final group = DictionaryGroup.fromMap(map);
        if (group.groupId != null) {
          groupMap[group.groupId!] = group;
        }
      }

      // 为每个 groupId 获取完整路径
      for (final groupId in groupIds) {
        final path = <DictionaryGroup>[];
        int? currentId = groupId;

        while (currentId != null) {
          final group = groupMap[currentId];
          if (group == null) {
            // 如果不在已查询的组中，需要单独查询（父组可能不在初始列表中）
            final results = await db.query(
              'groups',
              where: 'group_id = ?',
              whereArgs: [currentId],
              limit: 1,
            );
            if (results.isEmpty) break;
            final g = DictionaryGroup.fromMap(results.first);
            path.insert(0, g);
            groupMap[currentId] = g; // 缓存起来
            currentId = g.parentId;
          } else {
            path.insert(0, group);
            currentId = group.parentId;
          }
        }

        if (path.isNotEmpty) {
          result[groupId] = GroupPath(path);
        }
      }

      return result;
    } catch (e) {
      Logger.e('批量获取组路径失败: $e', tag: 'GroupService');
      return {};
    }
  }

  /// 查找 entry 所属的组
  /// 返回包含该 entry_id 的所有组
  Future<List<DictionaryGroup>> findGroupsByEntryId(
    String dictId,
    int entryId,
  ) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      // 由于 item_list 是 JSON 字符串，需要使用 LIKE 查询
      // 查找 item_list 中包含 "e":entryId 的记录
      final results = await db.query(
        'groups',
        where: 'item_list LIKE ?',
        whereArgs: ['%"e":$entryId%'],
      );

      // 过滤出真正包含该 entryId 的组
      final groups = <DictionaryGroup>[];
      for (final map in results) {
        final group = DictionaryGroup.fromMap(map);
        if (group.itemList.any((item) => item.entryId == entryId)) {
          groups.add(group);
        }
      }

      return groups;
    } catch (e) {
      Logger.e('查找 entry 所属组失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 查找 entry 特定 anchor 所属的组
  /// anchor 为空字符串表示整个词条
  Future<List<(DictionaryGroup, GroupItem)>> findGroupsByEntryIdAndAnchor(
    String dictId,
    int entryId, {
    String? anchor,
  }) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final results = await db.query(
        'groups',
        where: 'item_list LIKE ?',
        whereArgs: ['%"e":$entryId%'],
      );

      final groupsWithItems = <(DictionaryGroup, GroupItem)>[];
      for (final map in results) {
        final group = DictionaryGroup.fromMap(map);
        for (final item in group.itemList) {
          if (item.entryId == entryId) {
            // 如果 anchor 为空，匹配整个词条
            // 如果 anchor 不为空，匹配特定 anchor
            if (anchor == null || anchor.isEmpty) {
              if (item.anchor == null || item.anchor!.isEmpty) {
                groupsWithItems.add((group, item));
              }
            } else {
              if (item.anchor == anchor) {
                groupsWithItems.add((group, item));
              }
            }
          }
        }
      }

      return groupsWithItems;
    } catch (e) {
      Logger.e('查找 entry anchor 所属组失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 创建组
  Future<int> createGroup(String dictId, DictionaryGroup group) async {
    try {
      await ensureGroupsTable(dictId);
      final db = await _dictManager.openDictionaryDatabase(dictId);

      final id = await db.insert('groups', group.toMap());

      // 如果有父组，更新父组的 sub_group_count
      if (group.parentId != null) {
        await _updateParentSubGroupCount(db, group.parentId!);
      }

      Logger.i('创建组成功: $id', tag: 'GroupService');
      return id;
    } catch (e) {
      Logger.e('创建组失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 更新组
  Future<void> updateGroup(String dictId, DictionaryGroup group) async {
    try {
      if (group.groupId == null) {
        throw ArgumentError('group_id 不能为空');
      }

      final db = await _dictManager.openDictionaryDatabase(dictId);

      // 获取旧的组信息
      final oldGroup = await getGroup(dictId, group.groupId!);
      final oldParentId = oldGroup?.parentId;

      await db.update(
        'groups',
        group.toMap(),
        where: 'group_id = ?',
        whereArgs: [group.groupId],
      );

      // 如果父组发生变化，更新相关父组的 sub_group_count
      if (oldParentId != group.parentId) {
        if (oldParentId != null) {
          await _updateParentSubGroupCount(db, oldParentId);
        }
        if (group.parentId != null) {
          await _updateParentSubGroupCount(db, group.parentId!);
        }
      }

      Logger.i('更新组成功: ${group.groupId}', tag: 'GroupService');
    } catch (e) {
      Logger.e('更新组失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 删除组
  Future<void> deleteGroup(String dictId, int groupId) async {
    try {
      final db = await _dictManager.openDictionaryDatabase(dictId);

      // 获取要删除的组信息
      final group = await getGroup(dictId, groupId);
      final parentId = group?.parentId;

      // 删除组（CASCADE 会自动删除子组）
      await db.delete('groups', where: 'group_id = ?', whereArgs: [groupId]);

      // 更新父组的 sub_group_count
      if (parentId != null) {
        await _updateParentSubGroupCount(db, parentId);
      }

      Logger.i('删除组成功: $groupId', tag: 'GroupService');
    } catch (e) {
      Logger.e('删除组失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 添加项目到组
  Future<void> addItemsToGroup(
    String dictId,
    int groupId,
    List<GroupItem> items,
  ) async {
    try {
      final group = await getGroup(dictId, groupId);
      if (group == null) {
        throw ArgumentError('组不存在: $groupId');
      }

      final newItemList = [...group.itemList];
      for (final item in items) {
        if (!newItemList.contains(item)) {
          newItemList.add(item);
        }
      }

      final db = await _dictManager.openDictionaryDatabase(dictId);
      await db.update(
        'groups',
        {
          'item_list': jsonEncode(newItemList.map((e) => e.toJson()).toList()),
          'item_count': newItemList.length,
        },
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      Logger.i('添加项目到组成功: $groupId', tag: 'GroupService');
    } catch (e) {
      Logger.e('添加项目到组失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 从组中移除项目
  Future<void> removeItemsFromGroup(
    String dictId,
    int groupId,
    List<GroupItem> items,
  ) async {
    try {
      final group = await getGroup(dictId, groupId);
      if (group == null) {
        throw ArgumentError('组不存在: $groupId');
      }

      final newItemList = group.itemList
          .where((item) => !items.contains(item))
          .toList();

      final db = await _dictManager.openDictionaryDatabase(dictId);
      await db.update(
        'groups',
        {
          'item_list': jsonEncode(newItemList.map((e) => e.toJson()).toList()),
          'item_count': newItemList.length,
        },
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      Logger.i('从组中移除项目成功: $groupId', tag: 'GroupService');
    } catch (e) {
      Logger.e('从组中移除项目失败: $e', tag: 'GroupService');
      rethrow;
    }
  }

  /// 更新父组的 sub_group_count
  Future<void> _updateParentSubGroupCount(Database db, int parentId) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM groups WHERE parent_id = ?', [
        parentId,
      ]),
    );
    await db.update(
      'groups',
      {'sub_group_count': count ?? 0},
      where: 'group_id = ?',
      whereArgs: [parentId],
    );
  }

  /// 获取组内的词条 headword 列表
  /// 返回 Map`<entryId, headword>`
  Future<Map<int, String>> getGroupEntryHeadwords(
    String dictId,
    List<GroupItem> items,
  ) async {
    try {
      final db = await _dictManager.openDictionaryDatabase(dictId);
      final entryIds = items.map((e) => e.entryId).toSet().toList();

      if (entryIds.isEmpty) return {};

      final placeholders = List.filled(entryIds.length, '?').join(',');
      final results = await db.rawQuery(
        'SELECT entry_id, json_data FROM entries WHERE entry_id IN ($placeholders)',
        entryIds,
      );

      final headwords = <int, String>{};
      for (final row in results) {
        final entryId = row['entry_id'] as int;
        // json_data 是压缩的，需要解压
        // 这里简化处理，从 indices 表获取 headword
      }

      // 从 indices 表获取 headword
      final indexResults = await db.rawQuery(
        'SELECT DISTINCT entry_id, headword FROM indices WHERE entry_id IN ($placeholders)',
        entryIds,
      );

      for (final row in indexResults) {
        final entryId = row['entry_id'] as int;
        final headword = row['headword'] as String?;
        if (headword != null) {
          headwords[entryId] = headword;
        }
      }

      return headwords;
    } catch (e) {
      Logger.e('获取组内词条 headword 失败: $e', tag: 'GroupService');
      return {};
    }
  }

  /// 获取所有组（用于管理界面）
  Future<List<DictionaryGroup>> getAllGroups(String dictId) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) return [];

      final db = await _dictManager.openDictionaryDatabase(dictId);
      final results = await db.query(
        'groups',
        orderBy: 'parent_id ASC, name ASC',
      );
      return results.map((map) => DictionaryGroup.fromMap(map)).toList();
    } catch (e) {
      Logger.e('获取所有组失败: $e', tag: 'GroupService');
      return [];
    }
  }

  /// 获取组的统计信息
  Future<Map<String, int>> getGroupStats(String dictId) async {
    try {
      final hasTable = await hasGroupsTable(dictId);
      if (!hasTable) {
        return {'totalGroups': 0, 'rootGroups': 0, 'totalItems': 0};
      }

      final db = await _dictManager.openDictionaryDatabase(dictId);

      final totalGroups =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM groups'),
          ) ??
          0;

      final rootGroups =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM groups WHERE parent_id IS NULL',
            ),
          ) ??
          0;

      final totalItems =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT SUM(item_count) FROM groups'),
          ) ??
          0;

      return {
        'totalGroups': totalGroups,
        'rootGroups': rootGroups,
        'totalItems': totalItems,
      };
    } catch (e) {
      Logger.e('获取组统计信息失败: $e', tag: 'GroupService');
      return {'totalGroups': 0, 'rootGroups': 0, 'totalItems': 0};
    }
  }
}
