import 'package:flutter/material.dart';
import 'package:easydict/i18n/strings.g.dart';
import 'menu_item.dart';
import 'menu_panel.dart';
import 'content_panel.dart';

/// 统一设置布局
/// 宽屏模式：左侧固定宽度菜单 + 右侧自适应内容
/// 窄屏模式：仅显示右侧内容区（隐藏左侧菜单）
class WideSettingsLayout extends StatefulWidget {
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
  State<WideSettingsLayout> createState() => _WideSettingsLayoutState();
}

class _WideSettingsLayoutState extends State<WideSettingsLayout> {
  /// 上一次选中的菜单 ID（用于判断动画方向）
  String? _previousItemId;

  @override
  void didUpdateWidget(WideSettingsLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 更新上一次的 ID
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final oldItem = oldWidget.selectedIndex >= 0 &&
              oldWidget.selectedIndex < widget.menuItems.length
          ? widget.menuItems[oldWidget.selectedIndex]
          : null;
      _previousItemId = oldItem?.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 获取当前菜单项（如果索引有效）
    final currentItem = widget.selectedIndex >= 0 &&
            widget.selectedIndex < widget.menuItems.length
        ? widget.menuItems[widget.selectedIndex]
        : null;

    return Scaffold(
      body: Row(
        children: [
          // 左侧菜单栏 - 仅宽屏模式显示
          if (widget.showMenuPanel) ...[
            SizedBox(
              width: 280,
              child: SettingsMenuPanel(
                menuItems: widget.menuItems,
                menuGroups: widget.menuGroups,
                selectedIndex: widget.selectedIndex,
                onSelected: widget.onMenuSelected,
              ),
            ),

            // 分隔线
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ],

          // 右侧内容区 - 自适应宽度，使用 AnimatedSwitcher 实现页面切换动画
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              layoutBuilder: (currentChild, previousChildren) {
                // 使用 Stack 布局以支持预见性返回动画
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                // 窄屏模式使用滑动动画，宽屏模式使用淡入淡出
                if (!widget.showMenuPanel) {
                  // 判断动画方向：
                  // - 进入子页面：从右向左
                  // - 返回主页：从左向右
                  final isReturning = currentItem?.id == 'home' ||
                      _previousItemId != null && currentItem?.id == 'home';

                  final offsetAnimation = Tween<Offset>(
                    begin: isReturning
                        ? const Offset(-1.0, 0.0) // 返回：从左侧滑入
                        : const Offset(1.0, 0.0), // 进入：从右侧滑入
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ));

                  final fadeAnimation = Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
                  ));

                  return FadeTransition(
                    opacity: fadeAnimation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                } else {
                  // 宽屏模式：仅淡入淡出
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                }
              },
              child: currentItem != null
                  ? SettingsContentPanel(
                      key: ValueKey(currentItem.id),
                      currentItem: currentItem,
                      contentScaleNotifier: widget.contentScaleNotifier,
                      menuItems: widget.menuItems,
                      menuGroups: widget.menuGroups,
                      onMenuSelected: widget.onMenuSelected,
                      showMenuPanel: widget.showMenuPanel,
                    )
                  : _buildEmptyPlaceholder(context),
            ),
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
            t.settings.selectFromLeftSidebar,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
