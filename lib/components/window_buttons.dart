import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../utils/dpi_utils.dart';

const Color windowBorderColor = Color(0xFFCCCCCC);
const Color lightWindowBackground = Color(0xFFE5E5E5);
const Color darkWindowBackground = Color(0xFF2D2D2D);

class WindowTitleBar extends StatelessWidget {
  final String title;
  final Widget? child;

  const WindowTitleBar({super.key, required this.title, this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? darkWindowBackground
        : lightWindowBackground;
    final borderColor = isDark ? const Color(0xFF3D3D3D) : windowBorderColor;

    return Column(
      children: [
        WindowTitleBarBox(
          child: Container(
            color: backgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: MoveWindow(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: DpiUtils.scale(context, 16),
                        top: DpiUtils.scale(context, 8),
                        bottom: DpiUtils.scale(context, 8),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: DpiUtils.scaleFontSize(context, 13),
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                WindowControlButtons(
                  backgroundColor: backgroundColor,
                  borderColor: borderColor,
                ),
              ],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class WindowControlButtons extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;

  const WindowControlButtons({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MinimizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.black87,
            iconMouseOver: Colors.black87,
            mouseOver: const Color(0xFFE5E5E5),
            mouseDown: const Color(0xFFCCCCCC),
          ),
        ),
        MaximizeWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.black87,
            iconMouseOver: Colors.black87,
            mouseOver: const Color(0xFFE5E5E5),
            mouseDown: const Color(0xFFCCCCCC),
          ),
        ),
        CloseWindowButton(
          colors: WindowButtonColors(
            iconNormal: Colors.black87,
            iconMouseOver: Colors.white,
            mouseOver: const Color(0xFFE81123),
            mouseDown: const Color(0xFFE81123),
          ),
        ),
      ],
    );
  }
}
