import 'package:flutter/material.dart';

void showToast(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;
  // 移除当前可能存在的 SnackBar，避免堆叠
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: colorScheme.onSurface)),
      backgroundColor: colorScheme.surfaceContainerHighest,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
