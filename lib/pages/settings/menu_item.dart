import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';

/// 设置菜单内容类型
enum SettingsContentType {
  /// 子页面类型 - 嵌入子页面内容
  subPage,

  /// 对话框类型 - 点击弹出对话框
  dialog,

  /// 内嵌类型 - 直接显示内容
  embedded,

  /// 设置主页类型 - 显示设置列表（窄屏模式下的主页）
  homePage,
}

/// 设置菜单项数据结构
class SettingsMenuItem {
  /// 唯一标识
  final String id;

  /// 显示标题构建器
  final String Function(Translations t) titleBuilder;

  /// 图标
  final IconData icon;

  /// 菜单类型
  final SettingsContentType type;

  /// 子页面内容构建器 (type == subPage 时使用)
  /// onBack: 返回按钮回调
  final Widget Function({VoidCallback? onBack})? subPageBuilder;

  /// 对话框显示回调 (type == dialog 时使用)
  final void Function(BuildContext context)? showDialog;

  /// 内嵌内容构建器 (type == embedded 时使用)
  final Widget Function(BuildContext context)? embeddedBuilder;

  /// 角标数量提供者
  final int? Function()? badgeCountProvider;

  /// 所属分组
  final String group;

  /// 是否可见的条件判断函数（返回 true 表示显示该项）
  final bool Function()? visibilityCondition;

  const SettingsMenuItem({
    required this.id,
    required this.titleBuilder,
    required this.icon,
    required this.type,
    this.subPageBuilder,
    this.showDialog,
    this.embeddedBuilder,
    this.badgeCountProvider,
    required this.group,
    this.visibilityCondition,
  });

  /// 获取标题
  String getTitle(Translations t) => titleBuilder(t);

  /// 获取角标数量
  int? getBadgeCount() => badgeCountProvider?.call();

  /// 检查是否可见
  bool isVisible() => visibilityCondition?.call() ?? true;
}

/// 菜单分组信息
class SettingsMenuGroup {
  /// 分组标识
  final String id;

  /// 分组标题 (可选，为空则不显示分组标题)
  final String Function(Translations t)? titleBuilder;

  /// 分组内的菜单项
  final List<SettingsMenuItem> items;

  const SettingsMenuGroup({
    required this.id,
    this.titleBuilder,
    required this.items,
  });

  /// 获取分组标题
  String? getTitle(Translations t) => titleBuilder?.call(t);
}
