import 'package:flutter/material.dart';

void showToast(BuildContext context, String message, {SnackBarAction? action}) {
  final colorScheme = Theme.of(context).colorScheme;

  // 检测是否在 EntryDetailPage 中，如果是，增加底部边距以避开浮动工具栏
  bool isEntryDetailPage = false;
  if (context.widget.runtimeType.toString() == 'EntryDetailPage') {
    isEntryDetailPage = true;
  } else {
    context.visitAncestorElements((element) {
      if (element.widget.runtimeType.toString() == 'EntryDetailPage') {
        isEntryDetailPage = true;
        return false;
      }
      return true;
    });
  }

  // 浮动工具栏高度约 60-70，加上安全距离，设置 90
  final double bottomMargin = isEntryDetailPage ? 80 : 8;

  // 移除当前可能存在的 SnackBar，避免堆叠
  ScaffoldMessenger.of(context).removeCurrentSnackBar();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: colorScheme.onSurface)),
      backgroundColor: colorScheme.surfaceContainerHighest,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
      action: action,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
    ),
  );
}
