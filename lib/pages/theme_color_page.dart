import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../utils/dpi_utils.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 800
              ? 800.0
              : constraints.maxWidth;
          final horizontalPadding = (constraints.maxWidth - contentWidth) / 2;
          return ListView(
            padding: EdgeInsets.only(
              left: horizontalPadding + DpiUtils.scale(context, 16),
              right: horizontalPadding + DpiUtils.scale(context, 16),
              top: DpiUtils.scale(context, 16),
              bottom: DpiUtils.scale(context, 16),
            ),
            children: [
              _buildSectionTitle(context, '外观模式'),
              SizedBox(height: DpiUtils.scale(context, 8)),
              _buildThemeModeSection(context, themeProvider),
              SizedBox(height: DpiUtils.scale(context, 24)),
              _buildSectionTitle(context, '主题颜色'),
              SizedBox(height: DpiUtils.scale(context, 8)),
              _buildColorGrid(context, themeProvider),
              SizedBox(height: DpiUtils.scale(context, 24)),
              _buildSectionTitle(context, '预览效果'),
              SizedBox(height: DpiUtils.scale(context, 8)),
              _buildPreviewCard(context, themeProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DpiUtils.scale(context, 4)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: DpiUtils.scaleFontSize(context, 14),
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(DpiUtils.scale(context, 16)),
        child: child,
      ),
    );
  }

  Widget _buildThemeModeSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return _buildSectionCard(
      context,
      child: Row(
        children: [
          Expanded(
            child: _buildThemeModeOption(
              context,
              themeProvider,
              ThemeModeOption.system,
              '跟随系统',
              Icons.settings_suggest_outlined,
            ),
          ),
          SizedBox(width: DpiUtils.scale(context, 12)),
          Expanded(
            child: _buildThemeModeOption(
              context,
              themeProvider,
              ThemeModeOption.light,
              '浅色模式',
              Icons.light_mode_outlined,
            ),
          ),
          SizedBox(width: DpiUtils.scale(context, 12)),
          Expanded(
            child: _buildThemeModeOption(
              context,
              themeProvider,
              ThemeModeOption.dark,
              '深色模式',
              Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeProvider themeProvider,
    ThemeModeOption mode,
    String label,
    IconData icon,
  ) {
    final isSelected = themeProvider.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        themeProvider.setThemeMode(mode);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: DpiUtils.scale(context, 12)),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              size: DpiUtils.scaleIconSize(context, 20),
            ),
            SizedBox(height: DpiUtils.scale(context, 6)),
            Text(
              label,
              style: TextStyle(
                fontSize: DpiUtils.scaleFontSize(context, 12),
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorGrid(BuildContext context, ThemeProvider themeProvider) {
    return _buildSectionCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DpiUtils.scale(context, 12),
            runSpacing: DpiUtils.scale(context, 12),
            children: [
              _buildSystemColorItem(context, themeProvider),
              ...ThemeProvider.predefinedColors.map((color) {
                return _buildColorItem(context, themeProvider, color);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorItem(
    BuildContext context,
    ThemeProvider themeProvider,
    Color color,
  ) {
    final isSelected = themeProvider.seedColor.toARGB32() == color.toARGB32();
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        themeProvider.setSeedColor(color);
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: DpiUtils.scale(context, 40),
        height: DpiUtils.scale(context, 40),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: colorScheme.onSurface, width: 2.5)
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: _getContrastColor(color),
                size: DpiUtils.scaleIconSize(context, 20),
              )
            : null,
      ),
    );
  }

  Color _getContrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  Widget _buildSystemColorItem(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final isSelected =
        themeProvider.seedColor.toARGB32() ==
        ThemeProvider.systemAccentColor.toARGB32();
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        themeProvider.setSeedColor(ThemeProvider.systemAccentColor);
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: DpiUtils.scale(context, 40),
        height: DpiUtils.scale(context, 40),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue, Colors.purple, Colors.pink, Colors.orange],
          ),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: colorScheme.onSurface, width: 2.5)
              : Border.all(color: Colors.transparent, width: 1),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, ThemeProvider themeProvider) {
    final seedColor = themeProvider.seedColor;
    final currentMode = themeProvider.getThemeMode();
    final brightness = currentMode == ThemeMode.dark
        ? Brightness.dark
        : currentMode == ThemeMode.light
        ? Brightness.light
        : MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final previewScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: previewScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: previewScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模拟 AppBar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: DpiUtils.scale(context, 16),
                vertical: DpiUtils.scale(context, 10),
              ),
              color: previewScheme.surface,
              child: Row(
                children: [
                  Icon(
                    Icons.menu,
                    color: previewScheme.onSurface,
                    size: DpiUtils.scaleIconSize(context, 20),
                  ),
                  SizedBox(width: DpiUtils.scale(context, 16)),
                  Text(
                    '预览界面',
                    style: TextStyle(
                      fontSize: DpiUtils.scaleFontSize(context, 16),
                      fontWeight: FontWeight.w500,
                      color: previewScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.search,
                    color: previewScheme.onSurface,
                    size: DpiUtils.scaleIconSize(context, 20),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: previewScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            // 模拟内容
            Padding(
              padding: EdgeInsets.all(DpiUtils.scale(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 模拟卡片
                  Container(
                    padding: EdgeInsets.all(DpiUtils.scale(context, 12)),
                    decoration: BoxDecoration(
                      color: previewScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: DpiUtils.scale(context, 36),
                          height: DpiUtils.scale(context, 36),
                          decoration: BoxDecoration(
                            color: previewScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.star,
                            color: previewScheme.onPrimaryContainer,
                            size: DpiUtils.scaleIconSize(context, 20),
                          ),
                        ),
                        SizedBox(width: DpiUtils.scale(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '主要内容区域',
                                style: TextStyle(
                                  fontSize: DpiUtils.scaleFontSize(context, 13),
                                  fontWeight: FontWeight.w600,
                                  color: previewScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: DpiUtils.scale(context, 4)),
                              Text(
                                '这是主题色的应用效果预览',
                                style: TextStyle(
                                  fontSize: DpiUtils.scaleFontSize(context, 11),
                                  color: previewScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: DpiUtils.scale(context, 16)),
                  // 模拟按钮
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: DpiUtils.scale(context, 36),
                          decoration: BoxDecoration(
                            color: previewScheme.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '主要按钮',
                            style: TextStyle(
                              color: previewScheme.onPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: DpiUtils.scaleFontSize(context, 13),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: DpiUtils.scale(context, 12)),
                      Expanded(
                        child: Container(
                          height: DpiUtils.scale(context, 36),
                          decoration: BoxDecoration(
                            color: previewScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '次要按钮',
                            style: TextStyle(
                              color: previewScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w500,
                              fontSize: DpiUtils.scaleFontSize(context, 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: DpiUtils.scale(context, 16)),
                  // 模拟 FloatingActionButton
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: DpiUtils.scale(context, 44),
                      height: DpiUtils.scale(context, 44),
                      decoration: BoxDecoration(
                        color: previewScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.add,
                        color: previewScheme.onTertiaryContainer,
                        size: DpiUtils.scaleIconSize(context, 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
