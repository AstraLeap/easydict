import 'dart:io';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// 为 re_editor 提供平台适配的选择菜单。
/// - 桌面端：返回 null，使用 re_editor 默认行为
/// - 移动端：使用系统风格选择菜单（复制/剪切/粘贴/全选）
SelectionToolbarController? buildReEditorSelectionToolbarController() {
  // 桌面端使用默认行为
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return null;
  }

  // 移动端使用自定义的移动端风格菜单
  return MobileSelectionToolbarController(
    builder:
        ({
          required BuildContext context,
          required TextSelectionToolbarAnchors anchors,
          required CodeLineEditingController controller,
          required VoidCallback onDismiss,
          required VoidCallback onRefresh,
        }) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: anchors,
            buttonItems: [
              ContextMenuButtonItem(
                type: ContextMenuButtonType.cut,
                onPressed: () {
                  controller.cut();
                  onDismiss();
                },
              ),
              ContextMenuButtonItem(
                type: ContextMenuButtonType.copy,
                onPressed: () {
                  controller.copy();
                  onDismiss();
                },
              ),
              ContextMenuButtonItem(
                type: ContextMenuButtonType.paste,
                onPressed: () {
                  controller.paste();
                  onDismiss();
                },
              ),
              ContextMenuButtonItem(
                type: ContextMenuButtonType.selectAll,
                onPressed: () {
                  controller.selectAll();
                  onDismiss();
                },
              ),
            ],
          );
        },
  );
}
