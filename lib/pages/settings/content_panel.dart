import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../i18n/strings.g.dart';
import '../../core/locale_provider.dart';
import '../../services/dict_update_check_service.dart';
import '../../services/app_update_service.dart';
import '../../services/font_loader_service.dart';
import '../../components/global_scale_wrapper.dart';
import 'menu_item.dart';

/// 设置内容面板 (右侧)
class SettingsContentPanel extends StatefulWidget {
  /// 当前菜单项
  final SettingsMenuItem currentItem;

  /// 内容缩放通知器
  final ValueNotifier<double>? contentScaleNotifier;

  /// 所有菜单项（用于主页显示）
  final List<SettingsMenuItem>? menuItems;

  /// 菜单分组列表（用于主页显示）
  final List<SettingsMenuGroup>? menuGroups;

  /// 菜单选中回调
  final ValueChanged<int>? onMenuSelected;

  /// 是否显示左侧菜单（宽屏模式）
  final bool showMenuPanel;

  const SettingsContentPanel({
    super.key,
    required this.currentItem,
    this.contentScaleNotifier,
    this.menuItems,
    this.menuGroups,
    this.onMenuSelected,
    this.showMenuPanel = true,
  });

  @override
  State<SettingsContentPanel> createState() => _SettingsContentPanelState();
}

class _SettingsContentPanelState extends State<SettingsContentPanel> {
  /// 缓存的子页面 widget，用于在布局切换时保持子页面状态
  Widget? _cachedSubPage;

  /// 当前缓存对应的菜单项 ID
  String? _cachedItemId;

  @override
  void didUpdateWidget(SettingsContentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当菜单项 ID 变化时，清除缓存
    if (oldWidget.currentItem.id != widget.currentItem.id) {
      _cachedSubPage = null;
      _cachedItemId = null;
    }
  }

  void _handleOnBack() {
    // 动态获取当前的 showMenuPanel 值
    widget.onMenuSelected?.call(widget.showMenuPanel ? -2 : 0);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.currentItem.type) {
      case SettingsContentType.subPage:
        // 子页面类型：直接显示完整页面（子页面有自己的 AppBar）
        // 宽屏模式返回时显示空白占位，窄屏模式返回时显示主页
        // 只在菜单项变化时重新构建子页面，布局切换时保持状态
        if (_cachedSubPage == null || _cachedItemId != widget.currentItem.id) {
          _cachedSubPage = widget.currentItem.subPageBuilder?.call(
            onBack: _handleOnBack,
          );
          _cachedItemId = widget.currentItem.id;
        }
        return _cachedSubPage ?? const SizedBox.shrink();

      case SettingsContentType.embedded:
        // 内嵌类型：直接显示内容
        return widget.currentItem.embeddedBuilder?.call(context) ??
            const SizedBox.shrink();

      case SettingsContentType.homePage:
        // 设置主页：显示设置列表
        return _SettingsHomePageContent(
          menuItems: widget.menuItems,
          menuGroups: widget.menuGroups,
          onMenuSelected: widget.onMenuSelected,
        );

      case SettingsContentType.dialog:
        // 对话框类型在菜单点击时已处理，此处显示提示
        return _buildDialogPlaceholder(context);
    }
  }

  /// 对话框类型的占位内容
  Widget _buildDialogPlaceholder(BuildContext context) {
    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.currentItem.icon,
            size: 64,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            widget.currentItem.getTitle(t),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// 设置主页内容（设置列表）
/// 与宽屏左侧菜单共用同一套菜单项配置
class _SettingsHomePageContent extends StatelessWidget {
  final List<SettingsMenuItem>? menuItems;
  final List<SettingsMenuGroup>? menuGroups;
  final ValueChanged<int>? onMenuSelected;

  const _SettingsHomePageContent({this.menuItems, this.menuGroups, this.onMenuSelected});

  @override
  Widget build(BuildContext context) {
    final updateCheckService = context.watch<DictUpdateCheckService>();
    final appUpdateService = context.watch<AppUpdateService>();
    context.watch<LocaleProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final contentScale = FontLoaderService().getDictionaryContentScale();

    // 过滤掉主页菜单项，只显示实际设置项
    final displayItems = menuItems?.where((item) => item.id != 'home').toList() ?? [];

    return Scaffold(
      body: PageScaleWrapper(
        scale: contentScale,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    _buildMenuGroups(context, displayItems, colorScheme, updateCheckService, appUpdateService),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuGroups(
    BuildContext context,
    List<SettingsMenuItem> items,
    ColorScheme colorScheme,
    DictUpdateCheckService updateCheckService,
    AppUpdateService appUpdateService,
  ) {
    // 过滤掉主页分组
    final filteredGroups = menuGroups?.where((g) => g.id != 'home').toList() ?? [];

    // 按分组组织菜单项
    final itemsByGroup = <String, List<SettingsMenuItem>>{};
    for (final item in items) {
      itemsByGroup.putIfAbsent(item.group, () => []).add(item);
    }

    final widgets = <Widget>[];

    for (final group in filteredGroups) {
      final groupItems = itemsByGroup[group.id];
      if (groupItems == null || groupItems.isEmpty) continue;

      // 过滤不可见的菜单项
      final visibleItems = groupItems.where((item) => item.isVisible()).toList();
      if (visibleItems.isEmpty) continue;

      widgets.add(_buildSettingsGroup(
        context,
        children: visibleItems.map((item) => _buildSettingsTile(
          context,
          item: item,
          colorScheme: colorScheme,
        )).toList(),
      ));
      widgets.add(const SizedBox(height: 16));
    }

    // 移除最后一个多余的 SizedBox
    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }

    return widgets;
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required SettingsMenuItem item,
    required ColorScheme colorScheme,
  }) {
    final t = context.t;
    final badgeCount = item.getBadgeCount();
    final showArrow = item.type == SettingsContentType.subPage;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(item.icon, color: colorScheme.primary, size: 24),
      title: Text(
        item.getTitle(t),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeCount != null && badgeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  color: colorScheme.onError,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (showArrow)
            Icon(Icons.chevron_right, color: colorScheme.outline, size: 20),
        ],
      ),
      onTap: () {
        if (item.type == SettingsContentType.dialog) {
          // 对话框类型：直接弹出对话框
          item.showDialog?.call(context);
        } else {
          // 其他类型：切换到对应页面
          final index = menuItems?.indexOf(item) ?? -1;
          if (index >= 0 && onMenuSelected != null) {
            onMenuSelected!(index);
          }
        }
      },
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: _addDividers(children, colorScheme.outlineVariant.withOpacity(0.3)),
      ),
    );
  }

  List<Widget> _addDividers(List<Widget> children, Color dividerColor) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(Divider(height: 1, indent: 52, color: dividerColor));
      }
    }
    return result;
  }
}
