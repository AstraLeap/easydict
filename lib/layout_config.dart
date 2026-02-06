import 'package:flutter/material.dart';

class LayoutComponent {
  final String type;
  final String? id;
  final Map<String, dynamic> properties;
  final List<LayoutComponent>? children;

  LayoutComponent({
    required this.type,
    this.id,
    Map<String, dynamic>? properties,
    this.children,
  }) : properties = properties ?? {};

  factory LayoutComponent.fromJson(Map<String, dynamic> json) {
    return LayoutComponent(
      type: json['type'] as String,
      id: json['id'] as String?,
      properties: json['properties'] as Map<String, dynamic>? ?? {},
      children: json['children'] != null
          ? (json['children'] as List<dynamic>)
                .map((e) => LayoutComponent.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (id != null) 'id': id,
      'properties': properties,
      if (children != null)
        'children': children!.map((e) => e.toJson()).toList(),
    };
  }

  double? getDoubleProperty(String key, [double defaultValue = 0]) {
    final value = properties[key];
    if (value == null) return defaultValue;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return defaultValue;
  }

  int? getIntProperty(String key, [int defaultValue = 0]) {
    final value = properties[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return defaultValue;
  }

  String? getStringProperty(String key, [String? defaultValue]) {
    final value = properties[key]?.toString();
    return value ?? defaultValue;
  }

  bool getBoolProperty(String key, [bool defaultValue = false]) {
    final value = properties[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    return defaultValue;
  }

  Color? getColorProperty(String key) {
    final value = properties[key];
    if (value == null) return null;
    if (value is String) {
      final colorStr = value;
      if (colorStr.startsWith('#')) {
        return Color(int.parse(colorStr.replaceAll('#', '0xFF')));
      }
      return _parseNamedColor(colorStr);
    }
    return null;
  }

  Color? _parseNamedColor(String colorName) {
    final opacity = _extractOpacity(colorName);
    final baseColor = _getBaseColor(colorName);
    if (baseColor != null) {
      return baseColor.withOpacity(opacity);
    }
    return null;
  }

  double _extractOpacity(String colorName) {
    final match = RegExp(r'(\d+)').firstMatch(colorName);
    if (match != null) {
      final value = int.tryParse(match.group(1) ?? '0');
      return (value ?? 0) / 100.0;
    }
    return 1.0;
  }

  Color? _getBaseColor(String colorName) {
    final name = colorName.replaceAll(RegExp(r'\d+'), '').toLowerCase();
    switch (name) {
      case 'white':
        return Colors.white;
      case 'black':
        return Colors.black;
      case 'gray':
      case 'grey':
        return Colors.grey;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'cyan':
        return Colors.cyan;
      case 'teal':
        return Colors.teal;
      case 'amber':
        return Colors.amber;
      case 'indigo':
        return Colors.indigo;
      case 'brown':
        return Colors.brown;
      default:
        return null;
    }
  }

  TextAlign? getTextAlign() {
    final value = getStringProperty('textAlign');
    switch (value) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      case 'start':
        return TextAlign.start;
      case 'end':
        return TextAlign.end;
      default:
        return null;
    }
  }

  TextOverflow? getTextOverflow() {
    final value = getStringProperty('textOverflow');
    switch (value) {
      case 'clip':
        return TextOverflow.clip;
      case 'ellipsis':
        return TextOverflow.ellipsis;
      case 'fade':
        return TextOverflow.fade;
      case 'visible':
        return TextOverflow.visible;
      default:
        return null;
    }
  }

  TextDecoration? getTextDecoration() {
    final value = getStringProperty('textDecoration');
    switch (value) {
      case 'none':
        return TextDecoration.none;
      case 'underline':
        return TextDecoration.underline;
      case 'overline':
        return TextDecoration.overline;
      case 'lineThrough':
      case 'line-through':
        return TextDecoration.lineThrough;
      default:
        return null;
    }
  }

  BoxBorder? getBoxBorder() {
    final borderColor = getColorProperty('borderColor');
    final borderWidth = getDoubleProperty('borderWidth', 0);
    if (borderColor == null || borderWidth == 0) return null;

    final borderStyle = getStringProperty('borderStyle', 'solid');
    final color = borderColor;
    final width = borderWidth!;
    switch (borderStyle) {
      case 'solid':
        return Border.all(color: color, width: width);
      case 'dashed':
        return Border.all(color: color, width: width, style: BorderStyle.solid);
      default:
        return Border.all(color: color, width: width);
    }
  }

  BorderRadius? getBorderRadius() {
    final radius = getDoubleProperty('borderRadius');
    if (radius == null || radius == 0) return null;
    return BorderRadius.circular(radius);
  }

  EdgeInsets? getPadding() {
    return _parseSpacing('padding');
  }

  EdgeInsets? getMargin() {
    return _parseSpacing('margin');
  }

  EdgeInsets? _parseSpacing(String key) {
    final value = getStringProperty(key);
    if (value == null) return null;

    final parts = value.split(',');
    if (parts.length == 1) {
      final val = double.tryParse(parts[0]);
      if (val != null) return EdgeInsets.all(val);
    }
    if (parts.length == 2) {
      final horizontal = double.tryParse(parts[0]);
      final vertical = double.tryParse(parts[1]);
      if (horizontal != null && vertical != null) {
        return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
      }
    }
    if (parts.length == 4) {
      final values = parts.map((e) => double.tryParse(e)).toList();
      if (values.every((e) => e != null)) {
        return EdgeInsets.only(
          left: values[0]!,
          top: values[1]!,
          right: values[2]!,
          bottom: values[3]!,
        );
      }
    }
    return null;
  }

  MainAxisAlignment? getMainAxisAlignment() {
    final value = getStringProperty('mainAxisAlignment');
    switch (value) {
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'center':
        return MainAxisAlignment.center;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return null;
    }
  }

  CrossAxisAlignment? getCrossAxisAlignment() {
    final value = getStringProperty('crossAxisAlignment');
    switch (value) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'center':
        return CrossAxisAlignment.center;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'baseline':
        return CrossAxisAlignment.baseline;
      default:
        return null;
    }
  }

  Alignment? getAlignment() {
    final value = getStringProperty('alignment');
    switch (value) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'centerLeft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerRight':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return null;
    }
  }

  BoxShape? getBoxShape() {
    final value = getStringProperty('boxShape');
    switch (value) {
      case 'circle':
        return BoxShape.circle;
      case 'rectangle':
        return BoxShape.rectangle;
      default:
        return null;
    }
  }
}
