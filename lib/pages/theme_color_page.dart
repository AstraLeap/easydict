import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme_provider.dart';
import '../core/utils/dpi_utils.dart';
import '../services/font_loader_service.dart';
import '../components/scale_layout_wrapper.dart';
import '../components/global_scale_wrapper.dart';

class ThemeColorPage extends StatefulWidget {
  const ThemeColorPage({super.key});

  @override
  State<ThemeColorPage> createState() => _ThemeColorPageState();
}

class _ThemeColorPageState extends State<ThemeColorPage> {
  final double _dictionaryContentScale = FontLoaderService()
      .getDictionaryContentScale();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    final body = LayoutBuilder(
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
            SizedBox(height: DpiUtils.scale(context, 6)),
            _buildThemeModeSection(context, themeProvider),
            SizedBox(height: DpiUtils.scale(context, 16)),
            _buildSectionTitle(context, '主题颜色'),
            SizedBox(height: DpiUtils.scale(context, 6)),
            _buildColorGrid(context, themeProvider),
            SizedBox(height: DpiUtils.scale(context, 16)),
            _buildSectionTitle(context, '预览效果'),
            SizedBox(height: DpiUtils.scale(context, 6)),
            _buildPreviewCard(context, themeProvider),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(scale: _dictionaryContentScale, child: body),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DpiUtils.scale(context, 4)),
      child: Text(
        title,
        style: TextStyle(
          fontSize: DpiUtils.scaleFontSize(context, 12),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(DpiUtils.scale(context, 12)),
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
          SizedBox(width: DpiUtils.scale(context, 8)),
          Expanded(
            child: _buildThemeModeOption(
              context,
              themeProvider,
              ThemeModeOption.light,
              '浅色模式',
              Icons.light_mode_outlined,
            ),
          ),
          SizedBox(width: DpiUtils.scale(context, 8)),
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
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: DpiUtils.scale(context, 10)),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
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
              size: DpiUtils.scaleIconSize(context, 18),
            ),
            SizedBox(height: DpiUtils.scale(context, 4)),
            Text(
              label,
              style: TextStyle(
                fontSize: DpiUtils.scaleFontSize(context, 11),
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
            spacing: DpiUtils.scale(context, 10),
            runSpacing: DpiUtils.scale(context, 10),
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
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: DpiUtils.scale(context, 32),
        height: DpiUtils.scale(context, 32),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: colorScheme.onSurface, width: 2)
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: _getContrastColor(color),
                size: DpiUtils.scaleIconSize(context, 16),
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
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: DpiUtils.scale(context, 32),
        height: DpiUtils.scale(context, 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue, Colors.purple, Colors.pink, Colors.orange],
          ),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: colorScheme.onSurface, width: 2)
              : Border.all(color: Colors.transparent, width: 1),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: previewScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: previewScheme.surface,
        child: Padding(
          padding: EdgeInsets.all(DpiUtils.scale(context, 12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: DpiUtils.scale(context, 8),
                      vertical: DpiUtils.scale(context, 4),
                    ),
                    decoration: BoxDecoration(
                      color: previewScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '标题',
                      style: TextStyle(
                        fontSize: DpiUtils.scaleFontSize(context, 12),
                        fontWeight: FontWeight.w600,
                        color: previewScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  SizedBox(width: DpiUtils.scale(context, 8)),
                  Text(
                    '普通文本示例',
                    style: TextStyle(
                      fontSize: DpiUtils.scaleFontSize(context, 12),
                      color: previewScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SizedBox(height: DpiUtils.scale(context, 10)),
              Text(
                '这是一段普通文本的显示效果，可以展示主题色在正文中的应用。文字颜色、背景色都会根据选择的主题进行适配。',
                style: TextStyle(
                  fontSize: DpiUtils.scaleFontSize(context, 12),
                  color: previewScheme.onSurface,
                  height: 1.5,
                ),
              ),
              SizedBox(height: DpiUtils.scale(context, 10)),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: DpiUtils.scale(context, 10),
                      vertical: DpiUtils.scale(context, 6),
                    ),
                    decoration: BoxDecoration(
                      color: previewScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '主要按钮',
                      style: TextStyle(
                        fontSize: DpiUtils.scaleFontSize(context, 11),
                        fontWeight: FontWeight.w500,
                        color: previewScheme.onPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: DpiUtils.scale(context, 8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: DpiUtils.scale(context, 10),
                      vertical: DpiUtils.scale(context, 6),
                    ),
                    decoration: BoxDecoration(
                      color: previewScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '次要按钮',
                      style: TextStyle(
                        fontSize: DpiUtils.scaleFontSize(context, 11),
                        fontWeight: FontWeight.w500,
                        color: previewScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
