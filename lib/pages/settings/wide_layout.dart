import 'package:flutter/material.dart';
import 'menu_item.dart';
import 'menu_panel.dart';
import 'content_panel.dart';

/// 统一设置布局
/// 宽屏模式：左侧固定宽度菜单 + 右侧自适应内容
/// 窄屏模式：仅显示右侧内容区（隐藏左侧菜单）
class WideSettingsLayout extends StatelessWidget {
  /// 菜单项列表
  final List<SettingsMenuItem> menuItems;

  /// 菜单分组列表
  final List<SettingsMenuGroup> menuGroups;

  /// 当前选中的菜单索引（-1 表示未选中，宽屏模式下右侧留空）
  final int selectedIndex;

  /// 菜单选中回调
  final ValueChanged<int> onMenuSelected;

  /// 内容缩放通知器
  final ValueNotifier<double>? contentScaleNotifier;

  /// 是否显示左侧菜单（宽屏模式）
  final bool showMenuPanel;

  /// 宽屏布局阈值
  static const double wideLayoutThreshold = 800.0;

  const WideSettingsLayout({
    super.key,
    required this.menuItems,
    required this.menuGroups,
    required this.selectedIndex,
    required this.onMenuSelected,
    this.contentScaleNotifier,
    this.showMenuPanel = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 获取当前菜单项（如果索引有效）
    final currentItem = selectedIndex >= 0 && selectedIndex < menuItems.length
        ? menuItems[selectedIndex]
        : null;

    return Scaffold(
      body: Row(
        children: [
          // 左侧菜单栏 - 仅宽屏模式显示
          if (showMenuPanel) ...[
            SizedBox(
              width: 280,
              child: SettingsMenuPanel(
                menuItems: menuItems,
                menuGroups: menuGroups,
                selectedIndex: selectedIndex,
                onSelected: onMenuSelected,
              ),
            ),

            // 分隔线
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ],

          // 右侧内容区 - 自适应宽度
          Expanded(
            child: currentItem != null
                ? SettingsContentPanel(
                    currentItem: currentItem,
                    contentScaleNotifier: contentScaleNotifier,
                    menuItems: menuItems,
                    menuGroups: menuGroups,
                    onMenuSelected: onMenuSelected,
                    showMenuPanel: showMenuPanel,
                  )
                : _buildEmptyPlaceholder(context),
          ),
        ],
      ),
    );
  }

  /// 构建空白占位
  Widget _buildEmptyPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings,
            size: 64,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '请从左侧选择设置项',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
