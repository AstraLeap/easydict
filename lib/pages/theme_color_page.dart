import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme_provider.dart';
import '../services/font_loader_service.dart';
import '../components/global_scale_wrapper.dart';

class _SuperEllipsePainter extends CustomPainter {
  final Color color;

  _SuperEllipsePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = _createRoundedPentagonPath(size, size.width * 0.08);

    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  Path _createRoundedPentagonPath(Size size, double radius) {
    final path = Path();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final r = size.width / 2 * 0.85;

    const sides = 5;
    const angleOffset = -90.0;

    final points = <Offset>[];
    for (int i = 0; i < sides; i++) {
      final angle = (angleOffset + i * 360 / sides) * math.pi / 180;
      points.add(
        Offset(centerX + r * math.cos(angle), centerY + r * math.sin(angle)),
      );
    }

    for (int i = 0; i < sides; i++) {
      final p0 = points[i];
      final p1 = points[(i + 1) % sides];
      final midX = (p0.dx + p1.dx) / 2;
      final midY = (p0.dy + p1.dy) / 2;

      if (i == 0) {
        path.moveTo(midX, midY);
      } else {
        path.lineTo(midX, midY);
      }
      path.quadraticBezierTo(
        p1.dx,
        p1.dy,
        (midX + points[(i + 2) % sides].dx) / 2,
        (midY + points[(i + 2) % sides].dy) / 2,
      );
    }
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant _SuperEllipsePainter oldDelegate) => false;
}

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

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 800
            ? 800.0
            : constraints.maxWidth;
        final horizontalPadding = (constraints.maxWidth - contentWidth) / 2;
        return ListView(
          padding: EdgeInsets.only(
            left: horizontalPadding + 16,
            right: horizontalPadding + 16,
            top: 16,
            bottom: 16,
          ),
          children: [
            _buildSectionTitle(context, '外观模式'),
            const SizedBox(height: 8),
            _buildThemeModeSection(context, themeProvider),
            const SizedBox(height: 24),
            _buildSectionTitle(context, '主题颜色'),
            const SizedBox(height: 8),
            _buildColorGrid(context, themeProvider),
            const SizedBox(height: 24),
            _buildSectionTitle(context, '预览效果'),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _buildThemeModeSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return Row(
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
        const SizedBox(width: 8),
        Expanded(
          child: _buildThemeModeOption(
            context,
            themeProvider,
            ThemeModeOption.light,
            '浅色模式',
            Icons.light_mode_outlined,
          ),
        ),
        const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
            spacing: 12,
            runSpacing: 12,
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
        width: 44,
        height: 44,
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
            ? Icon(Icons.check, color: _getContrastColor(color), size: 20)
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
        width: 44,
        height: 44,
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

    final previewScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildColorCircle(context, previewScheme.primary, '主色'),
            _buildColorCircle(context, previewScheme.primaryContainer, '主容器'),
            _buildColorCircle(context, previewScheme.secondary, '辅色'),
            _buildColorCircle(context, previewScheme.tertiary, '强调'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSmallColorDot(
                previewScheme.surface,
                previewScheme.onSurface,
                '背景',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSmallColorDot(
                previewScheme.surfaceContainerHighest,
                previewScheme.onSurface,
                '卡片',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSmallColorDot(
                previewScheme.error,
                previewScheme.onError,
                '错误',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildOutlineColorDot(
                previewScheme.outline,
                previewScheme.surface,
                '边框',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: previewScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '这是一段示例文字，展示应用的主题效果预览。',
            style: TextStyle(
              fontSize: 14,
              color: previewScheme.onSurface.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCircle(BuildContext context, Color bgColor, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(48, 48),
          painter: _SuperEllipsePainter(color: bgColor),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallColorDot(Color bgColor, Color textColor, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: bgColor.computeLuminance() > 0.5
            ? Border.all(color: Colors.grey.shade300)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineColorDot(
    Color borderColor,
    Color insideColor,
    String label,
  ) {
    final dotColor = borderColor.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: borderColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
