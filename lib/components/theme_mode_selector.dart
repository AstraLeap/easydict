import 'package:flutter/material.dart';
import '../theme_provider.dart';

class ThemeModeSelector extends StatelessWidget {
  final ThemeModeOption themeMode;
  final ValueChanged<ThemeModeOption> onThemeChanged;

  const ThemeModeSelector({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 120, // Fixed width for the selector
      height: 32,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.transparent
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: colorScheme.outline.withOpacity(0.2))
            : null,
      ),
      padding: isDark ? const EdgeInsets.all(1) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final itemWidth = width / 3;

          return Stack(
            children: [
              AnimatedAlign(
                alignment: _getAlignment(themeMode),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Container(
                  width: itemWidth,
                  height: 28,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHigh
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _buildOption(
                    context,
                    ThemeModeOption.light,
                    Icons.wb_sunny_outlined,
                  ),
                  _buildOption(
                    context,
                    ThemeModeOption.dark,
                    Icons.dark_mode_outlined,
                  ),
                  _buildOption(
                    context,
                    ThemeModeOption.system,
                    Icons.brightness_auto_outlined,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    ThemeModeOption option,
    IconData icon,
  ) {
    final isSelected = themeMode == option;
    return Expanded(
      child: GestureDetector(
        onTap: () => onThemeChanged(option),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedTheme(
            data: Theme.of(context),
            child: Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Alignment _getAlignment(ThemeModeOption mode) {
    switch (mode) {
      case ThemeModeOption.light:
        return Alignment.centerLeft;
      case ThemeModeOption.dark:
        return Alignment.center;
      case ThemeModeOption.system:
        return Alignment.centerRight;
    }
  }
}
