import 'dart:convert';

/// 组内项目
class GroupItem {
  final int entryId;
  final String? anchor; // JSON Path锚点，为空表示整个词条

  const GroupItem({required this.entryId, this.anchor});

  factory GroupItem.fromJson(Map<String, dynamic> json) {
    return GroupItem(entryId: json['e'] as int, anchor: json['a'] as String?);
  }

  Map<String, dynamic> toJson() => {
    'e': entryId,
    if (anchor != null && anchor!.isNotEmpty) 'a': anchor,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupItem &&
        other.entryId == entryId &&
        other.anchor == anchor;
  }

  @override
  int get hashCode => Object.hash(entryId, anchor);

  @override
  String toString() => 'GroupItem(entryId: $entryId, anchor: $anchor)';
}

/// 组模型
class DictionaryGroup {
  final int? groupId;
  final int? parentId;
  final String name;
  final String? description; // JSON字符串，存储组件列表
  final List<GroupItem> itemList;
  final int subGroupCount;
  final int itemCount;

  const DictionaryGroup({
    this.groupId,
    this.parentId,
    required this.name,
    this.description,
    this.itemList = const [],
    this.subGroupCount = 0,
    this.itemCount = 0,
  });

  factory DictionaryGroup.fromMap(Map<String, dynamic> map) {
    final itemListJson = map['item_list'] as String? ?? '[]';
    final itemList = (jsonDecode(itemListJson) as List)
        .map((e) => GroupItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return DictionaryGroup(
      groupId: map['group_id'] as int?,
      parentId: map['parent_id'] as int?,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      itemList: itemList,
      subGroupCount: map['sub_group_count'] as int? ?? 0,
      itemCount: map['item_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    final itemListJson = jsonEncode(itemList.map((e) => e.toJson()).toList());
    return {
      if (groupId != null) 'group_id': groupId,
      'parent_id': parentId,
      'name': name,
      'description': description,
      'item_list': itemListJson,
      'sub_group_count': subGroupCount,
      'item_count': itemList.length,
    };
  }

  /// 创建副本
  DictionaryGroup copyWith({
    int? groupId,
    int? parentId,
    String? name,
    String? description,
    List<GroupItem>? itemList,
    int? subGroupCount,
    int? itemCount,
  }) {
    return DictionaryGroup(
      groupId: groupId ?? this.groupId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      description: description ?? this.description,
      itemList: itemList ?? this.itemList,
      subGroupCount: subGroupCount ?? this.subGroupCount,
      itemCount: itemCount ?? this.itemCount,
    );
  }

  /// 是否为根组
  bool get isRoot => parentId == null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DictionaryGroup &&
        other.groupId == groupId &&
        other.parentId == parentId &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(groupId, parentId, name, description);

  @override
  String toString() {
    return 'DictionaryGroup(groupId: $groupId, parentId: $parentId, name: $name, itemCount: ${itemList.length})';
  }
}

/// 组的层级路径信息
class GroupPath {
  final List<DictionaryGroup> path;

  const GroupPath(this.path);

  /// 是否为空
  bool get isEmpty => path.isEmpty;

  /// 是否不为空
  bool get isNotEmpty => path.isNotEmpty;

  /// 获取完整路径名称
  String get fullPathName => path.map((g) => g.name).join(' > ');

  /// 获取根组
  DictionaryGroup? get root => path.isNotEmpty ? path.first : null;

  /// 获取当前组（最后一个）
  DictionaryGroup? get current => path.isNotEmpty ? path.last : null;

  @override
  String toString() => 'GroupPath($fullPathName)';
}
