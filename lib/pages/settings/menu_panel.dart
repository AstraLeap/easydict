import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';
import 'menu_item.dart';

/// 设置菜单面板 (左侧)
class SettingsMenuPanel extends StatelessWidget {
  /// 所有菜单项列表
  final List<SettingsMenuItem> menuItems;

  /// 菜单分组列表
  final List<SettingsMenuGroup> menuGroups;

  /// 当前选中的菜单索引
  final int selectedIndex;

  /// 菜单选中回调
  final ValueChanged<int> onSelected;

  const SettingsMenuPanel({
    super.key,
    required this.menuItems,
    required this.menuGroups,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;

    // 过滤掉设置主页分组（仅窄屏模式需要）
    final filteredGroups = menuGroups.where((g) => g.id != 'home').toList();

    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // 顶部内边距
          const SizedBox(height: 16),
          // 菜单列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filteredGroups.length,
              itemBuilder: (context, groupIndex) {
                final group = filteredGroups[groupIndex];
                return _buildMenuGroup(context, group, t, colorScheme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGroup(
    BuildContext context,
    SettingsMenuGroup group,
    Translations t,
    ColorScheme colorScheme,
  ) {
    // 过滤不可见的菜单项
    final visibleItems = group.items.where((item) => item.isVisible()).toList();

    // 如果分组内没有可见项，则不显示该分组
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 菜单项
        ...visibleItems.map((item) {
          final globalIndex = menuItems.indexOf(item);
          final isSelected = globalIndex == selectedIndex;

          return _SettingsMenuTile(
            item: item,
            isSelected: isSelected,
            onTap: () => onSelected(globalIndex),
          );
        }),
        // 分组分隔线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Divider(
            height: 1,
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}

/// 菜单项组件
class _SettingsMenuTile extends StatelessWidget {
  final SettingsMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsMenuTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;
    final badgeCount = item.getBadgeCount();

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withOpacity(0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.getTitle(t),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ),

              // 角标
              if (badgeCount != null && badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
