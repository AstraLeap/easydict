import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../data/database_service.dart';
import 'board_widget.dart';
import 'dictionary_interaction_scope.dart';
import '../core/logger.dart';
import '../services/dictionary_manager.dart';
import '../services/preferences_service.dart';
import '../services/font_loader_service.dart';
import '../services/ai_service.dart';
import '../services/advanced_search_settings_service.dart';
import '../services/media_kit_manager.dart';
import '../services/entry_event_bus.dart';
import '../data/models/dictionary_entry_group.dart';
import '../pages/entry_detail_page.dart';
import '../services/search_history_service.dart';
import '../core/utils/toast_utils.dart';
import '../core/utils/language_utils.dart';
import 'global_scale_wrapper.dart';

class FormattedTextResult {
  final List<InlineSpan> spans;
  final List<String> plainTexts;
  final bool hidden;

  FormattedTextResult(this.spans, this.plainTexts, {this.hidden = false});
}

// 颜色映射表
const double _senseLeftIndent = 30;

const Map<String, Color> _colorMap = {
  'red': Colors.red,
  'green': Colors.green,
  'blue': Colors.blue,
  'yellow': Colors.yellow,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'grey': Colors.grey,
  'gray': Colors.grey,
  'black': Colors.black,
  'white': Colors.white,
};

class _PathData {
  final List<String> path;
  final String label;

  _PathData(this.path, this.label);
}

/// 待处理的滚动请求
class _PendingScrollRequest {
  final String path;
  final int retryCount;

  _PendingScrollRequest(this.path, this.retryCount);
}

/// 支持多种手势的识别器，用于同时处理点击和右键事件
class _MultiGestureRecognizer extends OneSequenceGestureRecognizer {
  final TapGestureRecognizer tapRecognizer;
  final _SecondaryTapGestureRecognizer secondaryTapRecognizer;
  final LongPressGestureRecognizer? longPressRecognizer;
  final DoubleTapGestureRecognizer? doubleTapRecognizer;

  _MultiGestureRecognizer({
    required this.tapRecognizer,
    required this.secondaryTapRecognizer,
    this.longPressRecognizer,
    this.doubleTapRecognizer,
  });

  @override
  void addPointer(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      secondaryTapRecognizer.addPointer(event);
    } else {
      tapRecognizer.addPointer(event);
      longPressRecognizer?.addPointer(event);
      doubleTapRecognizer?.addPointer(event);
    }
  }

  @override
  String get debugDescription => '_MultiGestureRecognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void handleEvent(PointerEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      secondaryTapRecognizer.handleEvent(event);
    } else {
      tapRecognizer.handleEvent(event);
      longPressRecognizer?.handleEvent(event);
      // DoubleTapGestureRecognizer 不需要在这里处理事件
      // 它会在 addPointer 时自动开始跟踪
    }
  }
}

/// 自定义右键手势识别器
class _SecondaryTapGestureRecognizer extends OneSequenceGestureRecognizer {
  GestureTapUpCallback? onSecondaryTapUp;

  PointerDeviceKind? _kind;

  @override
  void addPointer(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      startTrackingPointer(event.pointer);
      _kind = event.kind;
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent && event.buttons == 0) {
      if (onSecondaryTapUp != null) {
        onSecondaryTapUp!(
          TapUpDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
            kind: _kind ?? PointerDeviceKind.mouse,
          ),
        );
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => '_SecondaryTapGestureRecognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {
    _kind = null;
  }
}

class PathScope extends InheritedWidget {
  final List<String> path;

  const PathScope({super.key, required this.path, required super.child});

  static List<String> of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PathScope>();
    return scope?.path ?? [];
  }

  static Widget append(
    BuildContext context, {
    required String key,
    required Widget child,
  }) {
    final parentPath = PathScope.of(context);
    // 如果 key 包含点号，说明这是一个复合路径，需要拆分
    final List<String> newParts;
    if (key.contains('.')) {
      newParts = key.split('.');
    } else {
      newParts = [key];
    }
    return PathScope(path: [...parentPath, ...newParts], child: child);
  }

  @override
  bool updateShouldNotify(PathScope oldWidget) {
    // 简单的列表比较，实际应用中可能需要更高效的比较
    if (path.length != oldWidget.path.length) return true;
    for (int i = 0; i < path.length; i++) {
      if (path[i] != oldWidget.path[i]) return true;
    }
    return false;
  }
}

/// 高亮闪烁包装器 - 用于滚动到目标元素时显示闪烁效果
class _HighlightWrapper extends StatefulWidget {
  final bool isHighlighting;
  final Widget child;

  const _HighlightWrapper({required this.isHighlighting, required this.child});

  @override
  State<_HighlightWrapper> createState() => _HighlightWrapperState();
}

class _HighlightWrapperState extends State<_HighlightWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1.5),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 3.5),
    ]).animate(_controller);

    if (widget.isHighlighting) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_HighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighting != oldWidget.isHighlighting) {
      if (widget.isHighlighting) {
        _controller.forward(from: 0.0);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = colorScheme.primaryContainer.withValues(alpha: 0.4);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: widget.isHighlighting
                ? Color.lerp(
                    Colors.transparent,
                    highlightColor,
                    _animation.value,
                  )
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _TappableWrapper extends SingleChildRenderObjectWidget {
  final _PathData pathData;

  const _TappableWrapper({required this.pathData, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTappable(pathData);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTappable renderObject) {
    renderObject.pathData = pathData;
  }
}

class _RenderTappable extends RenderProxyBox {
  _PathData pathData;

  _RenderTappable(this.pathData);
}

String _getDecorationType(String type) {
  switch (type.toLowerCase()) {
    case 'strike':
    case '中划线':
      return 'strike';
    case 'underline':
    case '下划线':
      return 'underline';
    case 'double_underline':
    case '下双划线':
      return 'double_underline';
    case 'wavy':
    case '下波浪线':
      return 'wavy';
    case 'bold':
    case '加粗':
      return 'bold';
    case 'italic':
    case '斜体':
      return 'italic';
    case 'sup':
    case '上标':
      return 'sup';
    case 'sub':
    case '下标':
      return 'sub';
    case 'special':
      return 'special';
    default:
      return '';
  }
}

/// 去除文本格式，将 [text](style) 转换为 text
String _removeFormatting(String text) {
  final RegExp pattern = RegExp(r'\[([^\]]*?)\]\([^\)]*?\)');
  return text.replaceAllMapped(pattern, (match) => match.group(1) ?? '');
}

String? _extractTextToCopy(dynamic value) {
  String textToCopy = '';
  if (value is String) {
    textToCopy = _removeFormatting(value);
  } else if (value is Map) {
    textToCopy = value['text'] ?? value['word'] ?? value['content'] ?? '';
    textToCopy = _removeFormatting(textToCopy);
  } else if (value != null) {
    textToCopy = value.toString();
  }
  return textToCopy.isNotEmpty ? textToCopy : null;
}

String _convertPathToString(List<String> path) {
  return path.join('.');
}

void _handlePathTap(
  List<String> path,
  String label,
  void Function(String, String) callback,
) {
  final pathStr = _convertPathToString(path);
  callback(pathStr, label);
}

String? _determineEffectiveLanguage({
  String? language,
  List<String>? path,
  String? sourceLanguage,
}) {
  if (language != null && language.isNotEmpty) {
    return language;
  } else if (path != null && path.isNotEmpty) {
    final firstKey = path.first;
    if (firstKey.isNotEmpty) {
      return firstKey;
    } else {
      return sourceLanguage;
    }
  } else {
    return sourceLanguage;
  }
}

FormattedTextResult parseFormattedText(
  String text,
  TextStyle baseStyle, {
  BuildContext? context,
  List<String>? path,
  String? label,
  void Function(String path, String label)? onElementTap,
  void Function(String path, String label)? onElementSecondaryTap,
  GestureRecognizer? recognizer,
  bool hidden = false,
  String? language,
  String? sourceLanguage,
  Map<String, Map<String, double>>? fontScales,
  bool isSerif = false,
  bool isBold = false,
}) {
  // 如果被隐藏，返回空的 spans
  if (hidden) {
    return FormattedTextResult([], [], hidden: true);
  }

  // 应用自定义字体和缩放
  TextStyle effectiveBaseStyle = baseStyle;

  final effectiveLanguage = _determineEffectiveLanguage(
    language: language,
    path: path,
    sourceLanguage: sourceLanguage,
  );

  if (effectiveLanguage != null) {
    final fontService = FontLoaderService();
    final fontInfo = fontService.getFontInfo(
      effectiveLanguage,
      isSerif: isSerif,
      isBold: isBold,
    );

    final fontScale =
        fontScales?[effectiveLanguage]?[isSerif ? 'serif' : 'sans'] ?? 1.0;

    // 只有当 baseStyle 没有指定 fontFamily 时，才应用自定义字体
    if (fontInfo != null && baseStyle.fontFamily == null) {
      effectiveBaseStyle = effectiveBaseStyle.copyWith(
        fontFamily: fontInfo.fontFamily,
      );
    }

    if (fontScale != 1.0 && effectiveBaseStyle.fontSize != null) {
      effectiveBaseStyle = effectiveBaseStyle.copyWith(
        fontSize: effectiveBaseStyle.fontSize! * fontScale,
      );
    }
  }

  // 强制所有样式使用简体中文 Locale
  effectiveBaseStyle = effectiveBaseStyle.copyWith(
    locale: const Locale('zh', 'CN'),
  );

  final RegExp pattern = RegExp(r'\[([^\]]*?)\]\(([^)]*?)\)');
  final List<InlineSpan> spans = [];
  final List<String> plainTexts = [];
  int lastIndex = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > lastIndex) {
      final normalText = text.substring(lastIndex, match.start);
      spans.add(
        TextSpan(
          text: normalText,
          style: effectiveBaseStyle,
          recognizer: recognizer,
        ),
      );
      plainTexts.add(normalText);
    }

    final formattedText = match.group(1) ?? '';
    final typesStr = match.group(2) ?? '';
    final types = typesStr.split(',').map((t) => t.trim()).toList();

    TextStyle style = effectiveBaseStyle;
    List<TextDecoration> decorations = [];
    bool isSup = false;
    bool isSub = false;
    Color? customColor;
    String? linkTarget;
    String? exactJumpTarget;

    for (final type in types) {
      // 检查是否是颜色
      if (_colorMap.containsKey(type.toLowerCase())) {
        customColor = _colorMap[type.toLowerCase()];
        continue;
      }

      // 检查是否是查词链接 (->word)
      if (type.startsWith('->')) {
        linkTarget = type.substring(2).trim();
        continue;
      }

      // 检查是否是精确跳转 (==entry_id.path)
      if (type.startsWith('==')) {
        exactJumpTarget = type.substring(2).trim();
        continue;
      }

      final decorationType = _getDecorationType(type);
      switch (decorationType) {
        case 'strike':
          decorations.add(TextDecoration.lineThrough);
          break;
        case 'underline':
          decorations.add(TextDecoration.underline);
          break;
        case 'double_underline':
          style = style.copyWith(
            decoration: TextDecoration.combine([
              TextDecoration.underline,
              TextDecoration.underline,
            ]),
            decorationColor: effectiveBaseStyle.color,
          );
          break;
        case 'wavy':
          style = style.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: effectiveBaseStyle.color,
          );
          break;
        case 'bold':
          style = style.copyWith(fontWeight: FontWeight.bold);
          break;
        case 'italic':
          style = style.copyWith(fontStyle: FontStyle.italic);
          break;
        case 'sup':
          isSup = true;
          break;
        case 'sub':
          isSub = true;
          break;
        case 'special':
          style = style.copyWith(
            fontStyle: FontStyle.italic,
            color: context != null
                ? Theme.of(context).colorScheme.primary
                : null,
          );
          break;
      }
    }

    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: effectiveBaseStyle.color,
      );
    }

    if (customColor != null) {
      style = style.copyWith(color: customColor);
    }

    // 处理链接跳转（优先级更高）
    if (linkTarget != null && context != null) {
      style = style.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );
      spans.add(
        TextSpan(
          text: formattedText,
          style: style,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              _handleLinkTap(context, linkTarget!);
            },
        ),
      );
    } else if (exactJumpTarget != null && context != null) {
      style = style.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
      );
      spans.add(
        TextSpan(
          text: formattedText,
          style: style,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              _handleExactJump(context, exactJumpTarget!);
            },
        ),
      );
    } else if (isSup) {
      spans.add(
        WidgetSpan(
          child: Transform.translate(
            offset: Offset(0, -effectiveBaseStyle.fontSize! * 0.1),
            child: Text(
              formattedText,
              style: style.copyWith(
                fontSize: effectiveBaseStyle.fontSize != null
                    ? effectiveBaseStyle.fontSize! * 0.7
                    : null,
              ),
            ),
          ),
          alignment: PlaceholderAlignment.middle,
        ),
      );
    } else if (isSub) {
      spans.add(
        WidgetSpan(
          child: Transform.translate(
            offset: Offset(0, effectiveBaseStyle.fontSize! * 0.3),
            child: Text(
              formattedText,
              style: style.copyWith(
                fontSize: effectiveBaseStyle.fontSize != null
                    ? effectiveBaseStyle.fontSize! * 0.7
                    : null,
              ),
            ),
          ),
          alignment: PlaceholderAlignment.middle,
        ),
      );
    } else {
      spans.add(
        TextSpan(text: formattedText, style: style, recognizer: recognizer),
      );
    }
    plainTexts.add(formattedText);
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    final remainingText = text.substring(lastIndex);
    spans.add(
      TextSpan(
        text: remainingText,
        style: effectiveBaseStyle,
        recognizer: recognizer,
      ),
    );
    plainTexts.add(remainingText);
  }

  return FormattedTextResult(spans, plainTexts, hidden: hidden);
}

Future<void> _handleLinkTap(BuildContext context, String word) async {
  if (word.isEmpty) return;

  final dbService = DatabaseService();
  final historyService = SearchHistoryService();

  final result = await dbService.getAllEntries(word);

  if (result.entries.isNotEmpty) {
    final entryGroup = DictionaryEntryGroup.groupEntries(result.entries);
    await historyService.addSearchRecord(word);

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              EntryDetailPage(entryGroup: entryGroup, initialWord: word),
        ),
      );
    }
  } else {
    if (context.mounted) {
      showToast(context, '未找到单词: $word');
    }
  }
}

Future<void> _handleExactJump(BuildContext context, String target) async {
  // target format: entry_id.path (e.g., 25153.senses.0)
  final parts = target.split('.');
  if (parts.length < 2) return;

  final entryId = parts[0];
  // 剩余部分作为路径
  // final path = parts.sublist(1).join('.');

  final dictManager = DictionaryManager();

  // 1. 获取当前启用的词典
  final enabledDicts = await dictManager.getEnabledDictionariesMetadata();

  // 2. 在所有启用词典中查找该 entryId
  DictionaryEntry? targetEntry;

  for (final metadata in enabledDicts) {
    try {
      final db = await dictManager.openDictionaryDatabase(metadata.id);

      // 尝试查找 entry
      // entry_id 可能是纯数字，也可能是 dictId_数字
      // 我们需要根据 entryId 查找

      // 尝试直接匹配 entry_id 字段 (int)
      final entryIdInt = int.tryParse(entryId);
      if (entryIdInt != null) {
        final results = await db.query(
          'entries',
          where: 'entry_id = ?',
          whereArgs: [entryIdInt],
          limit: 1,
        );

        if (results.isNotEmpty) {
          final jsonStr = extractJsonFromField(results.first['json_data']);
          if (jsonStr == null) {
            Logger.e('无法解析json_data字段', tag: 'ComponentRenderer');
            await db.close();
            continue;
          }
          final jsonData = Map<String, dynamic>.from(
            // ignore: unnecessary_cast
            (jsonDecode(jsonStr) as Map<String, dynamic>),
          );

          // 确保 ID 格式正确
          String fullId = jsonData['id']?.toString() ?? '';
          if (fullId.isEmpty) {
            fullId = '${metadata.id}_$entryId';
            jsonData['id'] = fullId;
          } else if (!fullId.startsWith('${metadata.id}_')) {
            fullId = '${metadata.id}_$fullId';
            jsonData['id'] = fullId;
          }

          targetEntry = DictionaryEntry.fromJson(jsonData);
          await db.close();
          break;
        }
      }

      await db.close();
    } catch (e) {
      // Error handling without debug output
    }
  }

  if (targetEntry != null) {
    if (context.mounted) {
      // 跳转到详情页
      // 注意：这里我们构造一个临时的 DictionaryEntryGroup
      // 实际上 EntryDetailPage 需要完整的上下文，但这里我们只能提供单个 entry
      // 更好的做法可能是让 EntryDetailPage 支持定位到特定 entry

      final entryGroup = DictionaryEntryGroup.groupEntries([targetEntry]);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EntryDetailPage(
            entryGroup: entryGroup,
            initialWord: targetEntry!.headword,
          ),
        ),
      );

      // TODO: 在页面加载完成后滚动到指定路径
      // 这需要 EntryDetailPage 支持接收初始路径参数
      // 目前先只跳转到 entry
    }
  } else {
    if (context.mounted) {
      showToast(context, '未找到条目: $entryId');
    }
  }
}

/// 用于管理隐藏语言状态的通知器
class HiddenLanguagesNotifier extends ValueNotifier<List<String>> {
  HiddenLanguagesNotifier(super.initialValue);

  void toggle(String path) {
    if (value.contains(path)) {
      value = List<String>.from(value)..remove(path);
    } else {
      value = List<String>.from(value)..add(path);
    }
  }

  bool contains(String path) => value.contains(path);

  /// 强制通知监听器，用于数据更新后触发重建
  void forceNotify() {
    notifyListeners();
  }
}

/// 用于在组件树中传递 HiddenLanguagesNotifier
class HiddenLanguagesScope extends InheritedWidget {
  final HiddenLanguagesNotifier notifier;

  const HiddenLanguagesScope({
    super.key,
    required this.notifier,
    required super.child,
  });

  static HiddenLanguagesNotifier of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<HiddenLanguagesScope>();
    assert(scope != null, 'HiddenLanguagesScope not found in context');
    return scope!.notifier;
  }

  @override
  bool updateShouldNotify(HiddenLanguagesScope oldWidget) {
    return oldWidget.notifier != notifier;
  }
}

/// 仅当 selector 返回的值发生变化时才重建的组件
class HiddenLanguagesSelector<T> extends StatefulWidget {
  final T Function(List<String> hiddenLanguages) selector;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const HiddenLanguagesSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
  });

  @override
  State<HiddenLanguagesSelector<T>> createState() =>
      _HiddenLanguagesSelectorState<T>();
}

class _HiddenLanguagesSelectorState<T>
    extends State<HiddenLanguagesSelector<T>> {
  late T _value;
  HiddenLanguagesNotifier? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newNotifier = HiddenLanguagesScope.of(context);
    if (_notifier != newNotifier) {
      _notifier?.removeListener(_onValueChanged);
      _notifier = newNotifier;
      _notifier!.addListener(_onValueChanged);
      _value = widget.selector(_notifier!.value);
    }
  }

  @override
  void didUpdateWidget(HiddenLanguagesSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_notifier != null) {
      final newValue = widget.selector(_notifier!.value);
      if (newValue != _value) {
        setState(() {
          _value = newValue;
        });
      }
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_onValueChanged);
    super.dispose();
  }

  void _onValueChanged() {
    final newValue = widget.selector(_notifier!.value);
    if (newValue != _value) {
      setState(() {
        _value = newValue;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value, widget.child);
  }
}

class ComponentRenderer extends StatefulWidget {
  final DictionaryEntry entry;
  final void Function(String path, String label)? onElementTap;
  final void Function(String path, String label)? onEditElement;
  final void Function(String path, String label)? onAiAsk;
  final void Function(String path, DictionaryEntry newEntry)?
  onTranslationInsert;

  const ComponentRenderer({
    super.key,
    required this.entry,
    this.onElementTap,
    this.onEditElement,
    this.onAiAsk,
    this.onTranslationInsert,
  });

  @override
  State<ComponentRenderer> createState() => ComponentRendererState();
}

class ComponentRendererState extends State<ComponentRenderer> {
  final List<GestureRecognizer> _recognizers = [];
  final List<StreamSubscription> _streamSubscriptions = [];
  DateTime? _lastTapTime;
  int? _lastTapButton;
  Offset? _lastTapPosition;
  DateTime? _lastTtsTime; // TTS防抖时间戳
  late HiddenLanguagesNotifier _hiddenLanguagesNotifier;
  late DictionaryEntry _localEntry;

  // 用于存储元素 Key 的 Map，用于精确滚动
  final Map<String, GlobalKey> _elementKeys = {};
  // 待处理的滚动请求队列
  final List<_PendingScrollRequest> _pendingScrollRequests = [];

  StreamSubscription? _scrollSubscription;
  StreamSubscription? _translationInsertSubscription;
  StreamSubscription? _toggleHiddenSubscription;
  StreamSubscription? _batchToggleHiddenSubscription;

  // 用于存储正在闪烁的元素路径
  final Set<String> _highlightingPaths = {};
  // 闪烁动画控制器
  final Map<String, AnimationController> _highlightControllers = {};

  // 懒加载相关
  bool _isVisible = false;
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _localEntry = widget.entry;
    _hiddenLanguagesNotifier = HiddenLanguagesNotifier([]);
    _initSourceLanguage();
    _loadClickAction();
    _fontScales = FontLoaderService().getFontScales();
    _listenToEvents();
  }

  void _initSourceLanguage() {
    final dictId = _localEntry.dictId;
    if (dictId != null && dictId.isNotEmpty) {
      final cachedMetadata = DictionaryManager().getCachedMetadata(dictId);
      if (cachedMetadata != null) {
        _sourceLanguage = cachedMetadata.sourceLanguage;
        _targetLanguages = cachedMetadata.targetLanguages;
      }
    }
    _loadSourceLanguage();
  }

  void _listenToEvents() {
    final eventBus = EntryEventBus();
    _scrollSubscription = eventBus.scrollToElement.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        scrollToElement(event.path);
      }
    });
    _translationInsertSubscription = eventBus.translationInsert.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        handleTranslationInsert(
          event.path,
          DictionaryEntry.fromJson(event.newEntry),
        );
      }
    });
    _toggleHiddenSubscription = eventBus.toggleHiddenLanguage.listen((event) {
      if (event.entryId == widget.entry.id && mounted) {
        toggleHiddenLanguage(event.languageKey);
      }
    });
    _batchToggleHiddenSubscription = eventBus.batchToggleHidden.listen((event) {
      if (mounted) {
        batchToggleHiddenLanguages(
          pathsToHide: event.pathsToHide,
          pathsToShow: event.pathsToShow,
        );
      }
    });
  }

  @override
  void didUpdateWidget(ComponentRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _localEntry = widget.entry;
      _hiddenLanguagesNotifier.value = [];
      _elementKeys.clear();
      _pendingScrollRequests.clear();
      _isVisible = false;
      _hasBeenVisible = false;
      _initSourceLanguage();
    }
  }

  /// 滚动到指定路径的元素
  void scrollToElement(String path, {int retryCount = 0}) {
    // 如果组件还没有可见，将请求加入队列等待处理
    if (!_hasBeenVisible) {
      Logger.d(
        'Component not visible yet, queuing scroll request for path: $path',
        tag: 'ComponentRenderer',
      );
      _pendingScrollRequests.add(_PendingScrollRequest(path, retryCount));
      return;
    }

    // 直接执行滚动，GlobalKey 会在 _getElementKey 中按需创建
    _executeScrollToElement(path, retryCount: retryCount);
  }

  /// 执行实际的滚动操作
  void _executeScrollToElement(String path, {int retryCount = 0}) {
    final key = _elementKeys[path];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.1,
      ).then((_) {
        // 滚动完成后触发闪烁效果
        if (mounted) {
          _triggerHighlight(path);
        }
      });
    } else if (retryCount < 3) {
      Logger.d(
        'Element key not found or context null for path: $path, retrying... ($retryCount)',
        tag: 'ComponentRenderer',
      );
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _executeScrollToElement(path, retryCount: retryCount + 1);
        }
      });
    } else {
      Logger.w(
        'Element key not found or context null for path: $path after $retryCount retries',
        tag: 'ComponentRenderer',
      );
    }
  }

  /// 处理待处理的滚动请求
  void _processPendingScrollRequests() {
    if (_pendingScrollRequests.isEmpty) return;

    Logger.d(
      'Processing ${_pendingScrollRequests.length} pending scroll requests',
      tag: 'ComponentRenderer',
    );

    // 只处理最后一个请求（最新的）
    final lastRequest = _pendingScrollRequests.last;
    _pendingScrollRequests.clear();

    scrollToElement(lastRequest.path, retryCount: lastRequest.retryCount);
  }

  /// 触发元素的闪烁效果
  void _triggerHighlight(String path) {
    setState(() {
      _highlightingPaths.add(path);
    });

    // 2秒后移除闪烁效果
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightingPaths.remove(path);
        });
      }
    });
  }

  /// 检查元素是否正在闪烁
  bool _isHighlighting(String path) {
    return _highlightingPaths.contains(path);
  }

  /// 判断路径是否需要生成 GlobalKey（只有释义条目、phrase和board需要）
  bool _shouldGenerateGlobalKey(String path) {
    // 释义条目路径: sense_groups.x.senses.y 或 senses.x
    if (path.contains('sense_groups') && path.contains('senses')) return true;
    if (RegExp(r'^senses\.\d+$').hasMatch(path)) return true;

    // phrases
    if (path == 'phrases') return true;

    // board 元素（不在 _renderedKeys 中的顶层 key）
    // board 路径通常是直接的 key 名，如 "etymology", "notes" 等
    final parts = path.split('.');
    if (parts.length == 1 && !_isRenderedKey(parts[0])) return true;

    return false;
  }

  /// 检查 key 是否是已单独渲染的 key
  bool _isRenderedKey(String key) {
    return _renderedKeys.contains(key);
  }

  /// 获取或创建元素的 GlobalKey - 只为需要滚动的元素创建
  /// 策略：组件可见后直接创建，无需状态控制
  GlobalKey? _getElementKey(String path) {
    // 检查是否需要为此路径生成 GlobalKey
    if (!_shouldGenerateGlobalKey(path)) {
      return null;
    }

    // 组件可见后直接创建 GlobalKey，无需等待 setState
    if (!_hasBeenVisible) {
      return null;
    }

    return _elementKeys.putIfAbsent(path, () => GlobalKey());
  }

  Widget _buildTappableWidget({
    required BuildContext context,
    required _PathData pathData,
    required Widget child,
    String? text,
    TextStyle? textStyle,
    GlobalKey? customTextKey,
  }) {
    final textKey = customTextKey ?? GlobalKey();
    final pathStr = _convertPathToString(pathData.path);

    // 延迟加载 GlobalKey：只有在需要精确滚动时才创建
    final elementKey = _getElementKey(pathStr);

    // 检查是否正在闪烁
    final isHighlighting = _isHighlighting(pathStr);

    return GestureDetector(
      key: elementKey, // 绑定 Key
      behavior: HitTestBehavior.translucent,
      onTapDown: text != null && textStyle != null
          ? (details) {
              _lastTapPosition = details.globalPosition;
            }
          : null,
      onTap: () {
        // 单击立即生效
        _handleElementTap(pathStr, pathData.label);

        if (text == null || textStyle == null) {
          return;
        }

        final now = DateTime.now();
        final isDoubleTap =
            _lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300) &&
            _lastTapButton == 0;

        if (isDoubleTap && _lastTapPosition != null) {
          Logger.d('双击触发', tag: 'DoubleTapWord');
          _handleDoubleTapOnText(
            _lastTapPosition!,
            text,
            textStyle,
            textKey,
            context,
          );
          _lastTapTime = null;
          _lastTapButton = null;
          _lastTapPosition = null;
        } else {
          _lastTapTime = now;
          _lastTapButton = 0;
        }
      },
      onSecondaryTapUp: (details) {
        final pathStr = _convertPathToString(pathData.path);
        _handleElementSecondaryTap(
          pathStr,
          pathData.label,
          context,
          details.globalPosition,
        );
      },
      onLongPressStart: (details) {
        final pathStr = _convertPathToString(pathData.path);
        _handleElementSecondaryTap(
          pathStr,
          pathData.label,
          context,
          details.globalPosition,
        );
      },
      child: _HighlightWrapper(
        isHighlighting: isHighlighting,
        child: _TappableWrapper(
          pathData: pathData,
          child: customTextKey != null
              ? child
              : Builder(key: textKey, builder: (context) => child),
        ),
      ),
    );
  }

  void _handleDoubleTapOnText(
    Offset globalPosition,
    String text,
    TextStyle textStyle,
    GlobalKey textKey,
    BuildContext context, {
    int startOffset = 0,
  }) {
    Logger.d('双击触发，全局坐标: $globalPosition', tag: 'DoubleTapWord');
    Logger.d('文本内容: $text', tag: 'DoubleTapWord');
    Logger.d('起始偏移量: $startOffset', tag: 'DoubleTapWord');

    final renderObject = textKey.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph) {
      Logger.d('renderObject 不是 RenderParagraph', tag: 'DoubleTapWord');
      return;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    Logger.d('本地坐标: $localPosition', tag: 'DoubleTapWord');

    // 直接使用 RenderParagraph 获取点击位置的全局字符偏移量
    final textPosition = renderObject.getPositionForOffset(localPosition);
    final globalOffset = textPosition.offset;
    Logger.d('全局字符偏移量: $globalOffset', tag: 'DoubleTapWord');

    // 使用 parseFormattedText 解析文本，以获取纯文本内容
    final result = _parseFormattedText(text, textStyle, context: context);
    final plainText = result.spans.fold<String>(
      '',
      (prev, span) => prev + span.toPlainText(),
    );

    // 计算相对于当前文本段的局部偏移量
    final localOffset = globalOffset - startOffset;
    Logger.d('局部字符偏移量: $localOffset', tag: 'DoubleTapWord');

    // 检查偏移量是否在当前文本段范围内
    if (localOffset >= 0 && localOffset < plainText.length) {
      final tappedWord = _extractWordAtOffset(plainText, localOffset);

      if (tappedWord.isNotEmpty) {
        Logger.d('双击识别的单词: $tappedWord', tag: 'DoubleTapWord');
        // 执行查词
        _performDoubleTapSearch(tappedWord, context);
      } else {
        Logger.d('未识别到单词', tag: 'DoubleTapWord');
      }
    } else {
      Logger.d('点击位置超出当前文本段范围', tag: 'DoubleTapWord');
    }
  }

  /// 执行双击查词
  Future<void> _performDoubleTapSearch(
    String word,
    BuildContext context,
  ) async {
    Logger.d('双击查词: $word', tag: 'DoubleTapWord');

    // 获取当前语言的默认搜索选项
    final advancedSettingsService = AdvancedSearchSettingsService();
    final defaultOptions = advancedSettingsService.getDefaultOptionsForLanguage(
      _sourceLanguage,
    );

    // 查询词典
    final dbService = DatabaseService();
    final searchResult = await dbService.getAllEntries(
      word,
      useFuzzySearch: defaultOptions.useFuzzySearch,
      exactMatch: defaultOptions.exactMatch,
      sourceLanguage: _sourceLanguage,
    );

    if (searchResult.entries.isNotEmpty) {
      final entryGroup = DictionaryEntryGroup.groupEntries(
        searchResult.entries,
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EntryDetailPage(
              entryGroup: entryGroup,
              initialWord: word,
              searchRelations: searchResult.hasRelations
                  ? searchResult.relations
                  : null,
            ),
          ),
        );
      }
    } else {
      if (context.mounted) {
        showToast(context, '未找到单词: $word');
      }
    }
  }

  void handleTranslationInsert(String path, DictionaryEntry newEntry) {
    // 确保该路径不被隐藏（即显示）
    if (_hiddenLanguagesNotifier.value.contains(path)) {
      _hiddenLanguagesNotifier.toggle(path);
    }

    setState(() {
      _localEntry = newEntry;
    });

    // 触发 HiddenLanguagesNotifier 通知监听器，强制重建 HiddenLanguagesSelector
    // 这对于 AI 翻译后显示新添加的翻译是必要的
    _hiddenLanguagesNotifier.forceNotify();
  }

  /// 切换指定路径的隐藏状态（仅本地状态，不保存到数据库）
  void toggleHiddenLanguage(String path) {
    _hiddenLanguagesNotifier.toggle(path);
  }

  /// 批量设置隐藏状态（仅本地状态，不保存到数据库）
  /// [pathsToHide] 要隐藏的路径列表
  /// [pathsToShow] 要显示的路径列表
  void batchToggleHiddenLanguages({
    required List<String> pathsToHide,
    required List<String> pathsToShow,
  }) {
    final currentHidden = List<String>.from(_hiddenLanguagesNotifier.value);

    // 移除要显示的路径
    for (final path in pathsToShow) {
      currentHidden.remove(path);
    }

    // 添加要隐藏的路径
    for (final path in pathsToHide) {
      if (!currentHidden.contains(path)) {
        currentHidden.add(path);
      }
    }

    _hiddenLanguagesNotifier.value = currentHidden;
  }

  String _extractWordAtOffset(String text, int offset) {
    if (offset < 0 || offset >= text.length) return '';

    int start = offset;
    int end = offset;

    while (start > 0 && text[start - 1].startsWith(RegExp(r'[a-zA-Z]'))) {
      start--;
    }

    while (end < text.length && text[end].startsWith(RegExp(r'[a-zA-Z]'))) {
      end++;
    }

    return text.substring(start, end);
  }

  Widget _buildExampleItem({
    required BuildContext context,
    required List<MapEntry<String, String>> texts,
    required String usage,
    double leftMargin = 0,
    required List<String> basePath,
    required void Function(String path, String label) onElementTap,
    void Function(String path, String label, Offset position)?
    onElementSecondaryTapWithPosition,
    Map<String, Map<String, double>>? fontScales,
    String? sourceLanguage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final spans = <InlineSpan>[];
    int currentTextOffset = 0;

    final usageFontScale = fontScales?[sourceLanguage ?? 'en']?['sans'] ?? 1.0;
    final usageFontSize = 12 * usageFontScale;

    // 获取 usage 的自定义字体 (使用 sans)
    final fontService = FontLoaderService();
    final usageFontInfo = sourceLanguage != null
        ? fontService.getFontInfo(sourceLanguage, isSerif: false)
        : null;

    if (usage.isNotEmpty) {
      final usagePath = [...basePath, 'usage'];
      final usagePathData = _PathData(usagePath, 'Example Usage');

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () {
              onElementTap(usagePath.join('.'), usagePathData.label);
            },
            onSecondaryTapUp: (details) {
              if (onElementSecondaryTapWithPosition != null) {
                onElementSecondaryTapWithPosition(
                  usagePath.join('.'),
                  usagePathData.label,
                  details.globalPosition,
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                usage,
                style: TextStyle(
                  fontSize: usageFontSize,
                  color: colorScheme.onSecondaryContainer,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  fontFamily: usageFontInfo?.fontFamily,
                ),
              ),
            ),
          ),
        ),
      );
      currentTextOffset += 1;
    }

    final exampleTextKey = GlobalKey();

    for (int i = 0; i < texts.length; i++) {
      final textEntry = texts[i];
      final text = textEntry.value;
      final key = textEntry.key;

      // 不同语言的 example 之间添加间距
      if (i > 0) {
        spans.add(WidgetSpan(child: SizedBox(width: 12)));
        currentTextOffset += 1; // WidgetSpan 占 1 个字符
      } else if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: ' '));
        currentTextOffset += 1; // 空格占 1 个字符
      }

      final startOffset = currentTextOffset;
      currentTextOffset += text.length;

      final path = key.isEmpty ? basePath : [...basePath, key];
      final pathData = _PathData(path, 'Example Text ($key)');

      final hiddenPath = path.join('.');
      // 使用 notifier 的当前值，这样当状态变化时会重建
      final hidden = _hiddenLanguagesNotifier.value.contains(hiddenPath);

      // 确定有效语言并应用字体倍率
      final effectiveLanguageForExample = _determineEffectiveLanguage(
        language: key.isEmpty ? null : key,
        path: path,
        sourceLanguage: _sourceLanguage,
      );
      final exampleFontScale =
          fontScales?[effectiveLanguageForExample]?['sans'] ?? 1.0;
      final exampleFontSize = 14 * exampleFontScale;

      var exampleTextStyle = TextStyle(
        fontSize: exampleFontSize,
        color: colorScheme.onSurface.withValues(alpha: 0.85),
        height: 1.5,
        fontStyle:
            key == 'ja' ||
                key == 'zh' ||
                key.startsWith('zh_') ||
                key.startsWith('ja_')
            ? FontStyle.normal
            : FontStyle.italic,
      );

      // 获取 example 的自定义字体 (使用 sans)
      final fontService = FontLoaderService();
      final fontInfo = effectiveLanguageForExample != null
          ? fontService.getFontInfo(effectiveLanguageForExample, isSerif: false)
          : null;
      if (fontInfo != null) {
        exampleTextStyle = exampleTextStyle.copyWith(
          fontFamily: fontInfo.fontFamily,
        );
      }

      // 创建手势识别器以支持点击和右键菜单
      final tapRecognizer = TapGestureRecognizer()
        ..onTapDown = (details) {
          _lastTapPosition = details.globalPosition;
        }
        ..onTap = () {
          // 单击立即生效
          onElementTap(_convertPathToString(path), pathData.label);

          // 检测双击
          final now = DateTime.now();
          final isDoubleTap =
              _lastTapTime != null &&
              now.difference(_lastTapTime!) <
                  const Duration(milliseconds: 300) &&
              _lastTapButton == 0;

          if (isDoubleTap && _lastTapPosition != null) {
            Logger.d('双击触发', tag: 'DoubleTapWord');
            _handleDoubleTapOnText(
              _lastTapPosition!,
              text,
              exampleTextStyle,
              exampleTextKey,
              context,
              startOffset: startOffset,
            );
            _lastTapTime = null;
            _lastTapButton = null;
            _lastTapPosition = null;
          } else {
            _lastTapTime = now;
            _lastTapButton = 0;
          }
        };

      final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
        ..onSecondaryTapUp = (details) {
          _lastTapPosition = details.globalPosition;
          if (onElementSecondaryTapWithPosition != null) {
            onElementSecondaryTapWithPosition(
              _convertPathToString(path),
              pathData.label,
              details.globalPosition,
            );
          }
        };

      final longPressRecognizer = LongPressGestureRecognizer()
        ..onLongPressStart = (details) {
          _lastTapPosition = details.globalPosition;
          if (onElementSecondaryTapWithPosition != null) {
            onElementSecondaryTapWithPosition(
              _convertPathToString(path),
              pathData.label,
              details.globalPosition,
            );
          }
        };

      _recognizers.addAll([
        tapRecognizer,
        secondaryTapRecognizer,
        longPressRecognizer,
      ]);

      // 使用 MultiGestureRecognizer 来同时支持点击、右键和长按
      final multiRecognizer = _MultiGestureRecognizer(
        tapRecognizer: tapRecognizer,
        secondaryTapRecognizer: secondaryTapRecognizer,
        longPressRecognizer: longPressRecognizer,
        doubleTapRecognizer: null,
      );

      // 判断是否为日语或汉语（key 为 'ja' 或 'zh' 或包含这些标识）
      final isCJK =
          key == 'ja' ||
          key == 'zh' ||
          key.startsWith('zh_') ||
          key.startsWith('ja_');

      final result = _parseFormattedText(
        text,
        exampleTextStyle,
        context: context,
        path: path,
        label: 'Example Text ($key)',
        recognizer: multiRecognizer,
        hidden: hidden,
      );

      // 直接使用 TextSpan 而不是 WidgetSpan，以实现文本接着换行的效果
      spans.addAll(result.spans);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6, left: leftMargin),
      child: Builder(
        key: exampleTextKey,
        builder: (context) => RichText(text: TextSpan(children: spans)),
      ),
    );
  }

  final Map<int, GlobalKey> _sectionKeys = {};
  String? _sourceLanguage;
  Map<String, Map<String, double>> _fontScales = {};
  List<String> _targetLanguages = [];
  String _clickAction = PreferencesService.actionAiTranslate;

  OverlayEntry? _currentOverlayEntry;
  OverlayEntry? _currentBarrierEntry;
  OverlayEntry? _phraseOverlayEntry;
  OverlayEntry? _phraseBarrierEntry;

  Future<void> _loadClickAction() async {
    final action = await PreferencesService().getClickAction();
    if (mounted) {
      setState(() {
        _clickAction = action;
      });
    }
  }

  Future<void> _loadSourceLanguage() async {
    final dictId = _localEntry.dictId;
    if (dictId != null && dictId.isNotEmpty) {
      final metadata = await DictionaryManager().getDictionaryMetadata(dictId);
      if (mounted && metadata != null) {
        setState(() {
          _sourceLanguage = metadata.sourceLanguage;
          _targetLanguages = metadata.targetLanguages;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _scrollToSection(int sectionIndex) {
    final key = _sectionKeys[sectionIndex];
    if (key != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  FormattedTextResult _parseFormattedText(
    String text,
    TextStyle baseStyle, {
    BuildContext? context,
    List<String>? path,
    String? label,
    void Function(String path, String label)? onElementTap,
    void Function(String path, String label)? onElementSecondaryTap,
    GestureRecognizer? recognizer,
    bool hidden = false,
    String? language,
    bool isSerif = false,
    bool isBold = false,
  }) {
    return parseFormattedText(
      text,
      baseStyle,
      context: context,
      path: path,
      label: label,
      onElementTap: onElementTap,
      onElementSecondaryTap: onElementSecondaryTap,
      recognizer: recognizer,
      hidden: hidden,
      language: language,
      sourceLanguage: _sourceLanguage,
      fontScales: _fontScales,
      isSerif: isSerif,
      isBold: isBold,
    );
  }

  dynamic _getValueByPath(dynamic json, List<String> pathParts) {
    dynamic currentValue = json;
    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return currentValue;
  }

  /// 执行 AI 翻译/切换翻译显示
  /// 这是原来的单击功能，现在提取为可复用方法
  void _performAiTranslate(String path, String label) {
    // 检查是否是语言切换操作（路径以语言代码结尾）
    final pathParts = path.split('.');
    if (pathParts.isNotEmpty) {
      final lastKey = pathParts.last;
      final isLanguageCode =
          LanguageUtils.getLanguageDisplayName(lastKey) !=
          lastKey.toUpperCase();
      if (isLanguageCode) {
        Logger.d(
          '点击语言代码: path=$path, lastKey=$lastKey, sourceLanguage=$_sourceLanguage',
          tag: 'LanguageToggle',
        );

        final parentPath = pathParts.sublist(0, pathParts.length - 1);
        final parentValue = _getValueByPath(_localEntry.toJson(), parentPath);

        String? currentSourceLang = _sourceLanguage;

        // 如果未加载源语言，尝试推断
        if (currentSourceLang == null && parentValue is Map) {
          if (parentValue.containsKey('en')) {
            currentSourceLang = 'en';
          } else if (parentValue.containsKey('ja')) {
            currentSourceLang = 'ja';
          } else if (parentValue.containsKey('zh')) {
            currentSourceLang = 'zh';
          }
        }

        // 如果点击的是源语言
        if (currentSourceLang != null && lastKey == currentSourceLang) {
          if (parentValue is Map) {
            bool hasTranslation = false;
            // 检查是否有任何目标语言翻译
            if (_targetLanguages.isNotEmpty) {
              for (final targetLang in _targetLanguages) {
                if (targetLang == currentSourceLang) continue; // 剔除源语言

                if (parentValue.containsKey(targetLang)) {
                  hasTranslation = true;
                  break;
                }
              }
            } else {
              // 如果没有加载到目标语言信息，尝试推断
              for (final key in parentValue.keys) {
                if (key != currentSourceLang &&
                    LanguageUtils.getLanguageDisplayName(key) !=
                        key.toUpperCase()) {
                  // 这是一个语言代码，且不是源语言
                  hasTranslation = true;
                  break;
                }
              }
            }

            // 无论是否有翻译，都通知父组件
            // 如果有翻译，父组件会切换显示状态
            // 如果没有翻译，父组件会触发翻译
            widget.onElementTap?.call(path, label);
            return;
          }
        } else {
          // 点击的是非源语言（目标语言），通知父组件切换显示状态
          widget.onElementTap?.call(path, label);
          return;
        }
      }
    }

    // 非语言代码路径，直接调用 onElementTap
    widget.onElementTap?.call(path, label);
  }

  /// 根据点击动作设置执行对应的动作
  void _handleElementTap(String path, String label) {
    // 使用缓存的点击动作，避免异步延迟
    final action = _clickAction;

    switch (action) {
      case PreferencesService.actionAiTranslate:
        _performAiTranslate(path, label);
        break;
      case PreferencesService.actionCopy:
        _performCopy(path, label);
        break;
      case PreferencesService.actionAskAi:
        widget.onAiAsk?.call(path, label);
        break;
      case PreferencesService.actionEdit:
        widget.onEditElement?.call(path, label);
        break;
      case PreferencesService.actionSpeak:
        _performSpeak(path, label);
        break;
      default:
        _performAiTranslate(path, label);
    }
  }

  void _performCopy(String path, String label) {
    final pathParts = path.split('.');
    final json = _localEntry.toJson();
    dynamic currentValue = json;

    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          currentValue = null;
          break;
        }
      } else {
        currentValue = null;
        break;
      }
    }

    final textToCopy = _extractTextToCopy(currentValue);
    if (textToCopy != null) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      showToast(context, '文本已复制');
    } else {
      showToast(context, '无法提取文本内容');
    }
  }

  void _performSpeak(String path, String label) async {
    // TTS防抖：每秒最多调用1次
    final now = DateTime.now();
    if (_lastTtsTime != null &&
        now.difference(_lastTtsTime!) < const Duration(seconds: 1)) {
      showToast(context, '请稍后再试');
      return;
    }
    _lastTtsTime = now;

    final pathParts = path.split('.');
    final json = _localEntry.toJson();
    dynamic currentValue = json;

    for (final part in pathParts) {
      if (currentValue is Map) {
        currentValue = currentValue[part];
      } else if (currentValue is List) {
        int? index;
        if (part.startsWith('[') && part.endsWith(']')) {
          index = int.tryParse(part.substring(1, part.length - 1));
        } else {
          index = int.tryParse(part);
        }
        if (index != null && index < currentValue.length) {
          currentValue = currentValue[index];
        } else {
          currentValue = null;
          break;
        }
      } else {
        currentValue = null;
        break;
      }
    }

    final textToSpeak = _extractTextToCopy(currentValue);
    if (textToSpeak == null || textToSpeak.isEmpty) {
      showToast(context, '无法提取文本内容');
      return;
    }

    try {
      showToast(context, '正在生成音频...');
      Logger.d('开始TTS: $textToSpeak', tag: '_performSpeak');

      final audioData = await AIService().textToSpeech(textToSpeak);

      Logger.d('TTS音频生成成功，长度: ${audioData.length} bytes', tag: '_performSpeak');

      await _playTtsAudio(audioData);
    } catch (e) {
      Logger.e('TTS失败: $e', tag: '_performSpeak', error: e);
      showToast(context, '朗读失败: $e');
    }
  }

  Future<void> _playTtsAudio(List<int> audioData) async {
    try {
      await _currentPlayer?.stop();
      await _currentPlayer?.dispose();

      final player = Player();
      _currentPlayer = player;

      // 注册到管理器以便热重启时清理
      MediaKitManager().registerPlayer(player);

      final tempDir = await Directory.systemTemp.createTemp();
      final audioFile = File('${tempDir.path}/tts_audio.mp3');
      await audioFile.writeAsBytes(audioData);

      Logger.d('播放TTS音频: ${audioFile.path}', tag: '_playTtsAudio');

      // 确保文件存在且有内容
      if (!await audioFile.exists()) {
        Logger.e('TTS音频文件不存在', tag: '_playTtsAudio');
        return;
      }
      final fileSize = await audioFile.length();
      Logger.d('TTS音频文件大小: $fileSize bytes', tag: '_playTtsAudio');

      await player.open(Media(audioFile.path), play: true);

      // 监听播放状态 - 使用弱引用避免热重启时回调错误
      StreamSubscription? completionSub;
      completionSub = player.stream.completed.listen((completed) {
        if (completed) {
          Logger.d('TTS音频播放完成', tag: '_playTtsAudio');
          // 取消订阅避免内存泄漏
          completionSub?.cancel();
          _streamSubscriptions.remove(completionSub);
          // 延迟删除，确保播放完全结束
          Future.delayed(const Duration(seconds: 1), () {
            try {
              tempDir.delete(recursive: true);
            } catch (e) {
              // ignore
            }
          });
        }
      });
      _streamSubscriptions.add(completionSub);

      Logger.d('TTS音频播放已启动', tag: '_playTtsAudio');
    } catch (e, stackTrace) {
      Logger.e('播放TTS音频失败: $e', tag: '_playTtsAudio', error: e);
      Logger.e('堆栈跟踪: $stackTrace', tag: '_playTtsAudio', error: stackTrace);
      rethrow;
    }
  }

  void _handleElementSecondaryTap(
    String path,
    String label,
    BuildContext context,
    Offset position,
  ) {
    Logger.d(
      'Right-click on element: path=$path, label=$label',
      tag: 'ComponentRenderer',
    );

    final pathParts = path.split('.');
    final pathData = _PathData(pathParts, label);

    _showContextMenu(context, position, pathData);
  }

  void _showContextMenu(
    BuildContext context,
    Offset? position,
    _PathData? pathData,
  ) async {
    // 关闭之前的菜单
    _removeCurrentOverlay();

    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    late OverlayEntry barrierEntry;

    // 全屏透明遮罩，点击外部关闭菜单
    barrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _removeCurrentOverlay();
          },
          onSecondaryTapDown: (_) {
            _removeCurrentOverlay();
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    // Ensure position is within bounds
    final screenSize = MediaQuery.of(context).size;
    double dx = position?.dx ?? screenSize.width / 2;
    double dy = position?.dy ?? screenSize.height / 2;

    // Simple boundary check (menu width approx 200, height approx 150)
    if (dx + 200 > screenSize.width) {
      dx = screenSize.width - 210;
    }
    if (dy + 160 > screenSize.height) {
      dy = screenSize.height - 170;
    }

    final order = await PreferencesService().getClickActionOrder();

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: dx,
          top: dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < order.length; i++) ...[
                    Builder(
                      builder: (context) {
                        final action = order[i];
                        switch (action) {
                          case PreferencesService.actionAiTranslate:
                            return ListTile(
                              leading: const Icon(Icons.translate, size: 20),
                              title: const Text('切换翻译'),
                              dense: true,
                              onTap: () {
                                _removeCurrentOverlay();
                                if (pathData != null) {
                                  _performAiTranslate(
                                    pathData.path.join('.'),
                                    pathData.label,
                                  );
                                }
                              },
                            );
                          case PreferencesService.actionEdit:
                            return ListTile(
                              leading: const Icon(Icons.edit, size: 20),
                              title: const Text('编辑'),
                              dense: true,
                              onTap: () {
                                _removeCurrentOverlay();
                                if (pathData != null) {
                                  widget.onEditElement?.call(
                                    pathData.path.join('.'),
                                    pathData.label,
                                  );
                                }
                              },
                            );
                          case PreferencesService.actionAskAi:
                            return ListTile(
                              leading: const Icon(Icons.auto_awesome, size: 20),
                              title: const Text('询问AI'),
                              dense: true,
                              onTap: () {
                                _removeCurrentOverlay();
                                if (pathData != null) {
                                  widget.onAiAsk?.call(
                                    pathData.path.join('.'),
                                    pathData.label,
                                  );
                                }
                              },
                            );
                          case PreferencesService.actionCopy:
                            return ListTile(
                              leading: const Icon(Icons.copy, size: 20),
                              title: const Text('复制文本'),
                              dense: true,
                              onTap: () {
                                _removeCurrentOverlay();
                                if (pathData != null) {
                                  _performCopy(
                                    pathData.path.join('.'),
                                    pathData.label,
                                  );
                                }
                              },
                            );
                          case PreferencesService.actionSpeak:
                            return ListTile(
                              leading: const Icon(Icons.volume_up, size: 20),
                              title: const Text('朗读'),
                              dense: true,
                              onTap: () {
                                _removeCurrentOverlay();
                                if (pathData != null) {
                                  _performSpeak(
                                    pathData.path.join('.'),
                                    pathData.label,
                                  );
                                }
                              },
                            );
                          default:
                            return const SizedBox.shrink();
                        }
                      },
                    ),
                    if (i == 0 && order.length > 1)
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(barrierEntry);
    overlay.insert(overlayEntry);
    _currentOverlayEntry = overlayEntry;
    _currentBarrierEntry = barrierEntry;
  }

  void _removeCurrentOverlay() {
    try {
      _currentOverlayEntry?.remove();
      _currentBarrierEntry?.remove();
    } catch (e) {
      // 忽略已经移除的entry
    } finally {
      _currentOverlayEntry = null;
      _currentBarrierEntry = null;
    }
  }

  void _removePhraseOverlay() {
    try {
      _phraseOverlayEntry?.remove();
      _phraseBarrierEntry?.remove();
    } catch (e) {
      // 忽略已经移除的entry
    } finally {
      _phraseOverlayEntry = null;
      _phraseBarrierEntry = null;
    }
  }

  void _handlePhraseTap(String phrase, Offset position) async {
    _removePhraseOverlay();

    final plainPhrase = _removeFormatting(phrase);
    Logger.d('Phrase tapped: $plainPhrase', tag: 'PhraseTap');

    final dbService = DatabaseService();
    final searchResult = await dbService.getAllEntries(
      plainPhrase,
      useFuzzySearch: false,
      exactMatch: true,
      sourceLanguage: _sourceLanguage,
    );

    if (searchResult.entries.isEmpty) {
      if (mounted) {
        showToast(context, '未找到短语: $plainPhrase');
      }
      return;
    }

    final entryGroup = DictionaryEntryGroup.groupEntries(searchResult.entries);
    if (mounted) {
      _showPhraseOverlay(
        entryGroup,
        searchResult.entries,
        plainPhrase,
        position,
      );
    }
  }

  void _showPhraseOverlay(
    DictionaryEntryGroup entryGroup,
    List<DictionaryEntry> entries,
    String phrase,
    Offset position,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);

    final fontScale = _fontScales[_sourceLanguage ?? 'en']?['serif'] ?? 1.0;
    final dictionaryContentScale = FontLoaderService()
        .getDictionaryContentScale();
    final titleFontSize = 15 * fontScale * dictionaryContentScale;
    final iconSize = 18 * fontScale * dictionaryContentScale;

    final screenSize = MediaQuery.of(context).size;
    final overlayWidth = 420.0 * dictionaryContentScale.clamp(0.8, 1.2);
    final maxHeight = screenSize.height * 0.6;

    double dx = position.dx;
    double dy = position.dy + 20;

    if (dx + overlayWidth > screenSize.width) {
      dx = screenSize.width - overlayWidth - 16;
    }
    if (dx < 16) {
      dx = 16;
    }
    if (dy + maxHeight > screenSize.height) {
      dy = position.dy - maxHeight - 10;
    }

    _phraseBarrierEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _removePhraseOverlay();
          },
          onSecondaryTapDown: (_) {
            _removePhraseOverlay();
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );

    _phraseOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: dx,
          top: dy,
          width: overlayWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 * fontScale * dictionaryContentScale,
                        vertical: 10 * fontScale * dictionaryContentScale,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer,
                            colorScheme.primaryContainer.withValues(
                              alpha: 0.85,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(
                              6 * fontScale * dictionaryContentScale,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.format_quote,
                              size: iconSize,
                              color: colorScheme.primary,
                            ),
                          ),
                          SizedBox(
                            width: 12 * fontScale * dictionaryContentScale,
                          ),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: parseFormattedText(
                                  phrase,
                                  TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  sourceLanguage: _sourceLanguage,
                                  fontScales: _fontScales,
                                  isSerif: true,
                                  isBold: true,
                                ).spans,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 8 * fontScale * dictionaryContentScale,
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                _removePhraseOverlay();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EntryDetailPage(
                                      entryGroup: entryGroup,
                                      initialWord: phrase,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.all(
                                  8 * fontScale * dictionaryContentScale,
                                ),
                                child: Icon(
                                  Icons.open_in_new,
                                  size: iconSize,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(
                          12 * fontScale * dictionaryContentScale,
                        ),
                        child: PageScaleWrapper(
                          child: ComponentRenderer(
                            entry: entryGroup.currentEntry ?? entries.first,
                            onElementTap: (path, label) {
                              Logger.d(
                                'Phrase overlay element tapped: $path',
                                tag: 'PhraseOverlay',
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_phraseBarrierEntry!);
    overlay.insert(_phraseOverlayEntry!);
  }

  @override
  void dispose() {
    _scrollSubscription?.cancel();
    _translationInsertSubscription?.cancel();
    _toggleHiddenSubscription?.cancel();
    _batchToggleHiddenSubscription?.cancel();
    _hiddenLanguagesNotifier.dispose();
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    for (final subscription in _streamSubscriptions) {
      subscription.cancel();
    }
    _streamSubscriptions.clear();
    _removeCurrentOverlay();
    _removePhraseOverlay();
    _cleanupPlayer();
    // 清理闪烁动画控制器
    for (final controller in _highlightControllers.values) {
      controller.dispose();
    }
    _highlightControllers.clear();
    super.dispose();
  }

  /// 安全清理音频播放器
  void _cleanupPlayer() {
    try {
      final player = _currentPlayer;
      if (player != null) {
        // 从管理器中注销
        MediaKitManager().unregisterPlayer(player);
        // 先停止播放
        player.stop();
        // 释放资源
        player.dispose();
        _currentPlayer = null;
      }
    } catch (e) {
      // 忽略清理过程中的错误
      Logger.d('清理播放器时出错: $e', tag: 'ComponentRenderer');
    }
  }

  String _getPage() {
    final entry = _localEntry;
    try {
      final jsonStr = entry.toString();
      if (jsonStr.contains('"page"')) {
        final RegExp pageRegExp = RegExp(r'"page"\s*:\s*"([^"]+)"');
        final match = pageRegExp.firstMatch(jsonStr);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    } catch (e) {
      return '';
    }
    return '';
  }

  List<String> _getSections() {
    final entry = _localEntry;
    final sections = entry.senses
        .map((sense) {
          final section = sense['section'] as String?;
          return section ?? '';
        })
        .where((s) => s.isNotEmpty)
        .toSet() // 去重
        .toList();

    // 如果只有一个section，则不显示
    if (sections.length <= 1) {
      return [];
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _localEntry;
    final page = _getPage();
    final sections = _getSections();

    // 使用 VisibilityDetector 实现懒加载
    return VisibilityDetector(
      key: ValueKey('component_renderer_${entry.id}'),
      onVisibilityChanged: (visibilityInfo) {
        final visibleFraction = visibilityInfo.visibleFraction;
        final wasVisible = _isVisible;
        _isVisible = visibleFraction > 0;

        // 当组件首次可见时
        if (_isVisible && !wasVisible && !_hasBeenVisible) {
          Logger.d(
            'ComponentRenderer became visible for entry: ${entry.headword}',
            tag: 'ComponentRenderer',
          );
          // 设置标志并触发重建，确保 GlobalKey 被创建
          setState(() {
            _hasBeenVisible = true;
          });
          // 在下一帧处理待处理的滚动请求（等待 GlobalKey 创建完成）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _processPendingScrollRequests();
            }
          });
        }
      },
      child: HiddenLanguagesScope(
        notifier: _hiddenLanguagesNotifier,
        child: DictionaryInteractionScope(
          onElementTap: widget.onElementTap,
          onElementSecondaryTap: _handleElementSecondaryTap,
          child: PathScope(
            path: const ['entry'],
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (page.isNotEmpty) ...[
                    _buildPageDisplay(context, page),
                    const SizedBox(height: 16),
                  ],
                  if (sections.isNotEmpty) ...[
                    _buildSectionNavigation(context, sections),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildWord(context),
                      if (entry.frequency.isNotEmpty ||
                          entry.pronunciations.isNotEmpty) ...[
                        if (entry.frequency.isNotEmpty)
                          _buildFrequencyStars(context),
                        if (entry.pronunciations.isNotEmpty)
                          _buildPronunciations(context),
                      ],
                      if (entry.certifications.isNotEmpty) ...[
                        ..._buildCertificationsInline(context),
                      ],
                    ],
                  ),
                  // 渲染 datas（在 senses 之前）
                  _buildDatasIfExist(context),
                  if (entry.senses.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSenses(context),
                  ],
                  if (entry.senseGroups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildSenseGroups(context),
                  ],
                  // 渲染 phrases
                  _buildPhrases(context),
                  // 渲染所有未渲染的 key 为 board
                  _buildRemainingBoards(context),
                ],
              ),
            ),
          ),
        ),
      ),
    ); // 注意这里：闭合 VisibilityDetector 和 HiddenLanguagesScope 并以分号结束
  }

  Widget _buildWord(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    final word = entry.headword;
    final pos = entry.senses.isNotEmpty
        ? (entry.senses[0]['pos'] as String? ?? '')
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        PathScope.append(
          context,
          key: 'headword',
          child: Builder(
            builder: (context) {
              return _buildTappableWidget(
                context: context,
                pathData: _PathData(PathScope.of(context), 'Headword'),
                child: RichText(
                  text: TextSpan(
                    children: _parseFormattedText(
                      word,
                      TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.0,
                      ),
                      context: context,
                      isSerif: true,
                      isBold: true,
                    ).spans,
                  ),
                ),
              );
            },
          ),
        ),
        if (pos.isNotEmpty) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PathScope.append(
              context,
              key: 'senses.0.pos',
              child: Builder(
                builder: (context) {
                  return _buildPosElement(context, pos);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFrequencyStars(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;
    final frequency = entry.frequency;

    final starsValue = frequency['stars'] as String? ?? '';
    if (starsValue.isEmpty) return const SizedBox.shrink();

    final parts = starsValue.split('/');
    if (parts.length != 2) return const SizedBox.shrink();

    final filledCount = int.tryParse(parts[0]) ?? 0;
    final totalCount = int.tryParse(parts[1]) ?? 5;

    final level = frequency['level'] as String? ?? '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (level.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              level,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSecondaryContainer,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalCount, (index) {
            final isFilled = index < filledCount;
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: isFilled
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildExample(
    BuildContext context,
    dynamic value, {
    double leftMargin = 0,
    List<String>? path,
  }) {
    String usage = '';
    List<MapEntry<String, String>> texts = [];

    if (value is String) {
      texts.add(MapEntry('', value));
    } else if (value is Map<String, dynamic>) {
      usage = value['usage'] as String? ?? '';
      final sourceLang = _sourceLanguage ?? 'en';

      for (final entry in value.entries) {
        final key = entry.key;
        final val = entry.value;

        if (key == 'usage' || key == 'source' || key == 'audios') continue;

        if (val is String && val.isNotEmpty) {
          texts.add(MapEntry(key, val));
        }
      }

      if (texts.isEmpty) {
        return const SizedBox.shrink();
      }

      texts.sort((a, b) {
        if (a.key == sourceLang) return -1;
        if (b.key == sourceLang) return 1;
        return 0;
      });
    }

    final examplePath = path ?? PathScope.of(context);
    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<String>(
      selector: (hiddenLanguages) {
        final relevantHidden = <String>[];
        for (final entry in texts) {
          final key = entry.key;
          final path = key.isEmpty ? examplePath : [...examplePath, key];
          final pathStr = path.join('.');
          if (hiddenLanguages.contains(pathStr)) {
            relevantHidden.add(pathStr);
          }
        }
        relevantHidden.sort();
        return relevantHidden.join(',');
      },
      builder: (context, hiddenPathsStr, child) {
        // Logger.d(
        //   '重建 Example: path=${examplePath.join('.')}, hiddenPaths=$hiddenPathsStr',
        //   tag: 'Rebuild',
        // );
        return _buildExampleItem(
          context: context,
          texts: texts,
          usage: usage,
          leftMargin: leftMargin,
          basePath: examplePath,
          onElementTap: _handleElementTap,
          onElementSecondaryTapWithPosition: (path, label, position) {
            _handleElementSecondaryTap(path, label, context, position);
          },
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      },
    );
  }

  Widget _buildDatas(
    BuildContext context,
    Map<String, dynamic> value, {
    List<String>? path,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final keys = value.keys.toList();

    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DatasTabWidget(
      keys: keys,
      value: value,
      path: path ?? PathScope.of(context),
      colorScheme: colorScheme,
      contentBuilder: (board, p) => _buildBoardContent(context, board, p),
      onElementTap: _handleElementTap,
      sourceLanguage: _sourceLanguage,
      fontScales: _fontScales,
    );
  }

  Widget _buildnote(
    BuildContext context,
    Map<String, dynamic> value, {
    List<String>? path,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final note = value['note'] as String? ?? '';

    if (note.isEmpty) {
      return const SizedBox.shrink();
    }

    final notePath = path ?? PathScope.of(context);
    return _buildTappableWidget(
      context: context,
      pathData: _PathData(notePath, 'note'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: _parseFormattedText(
                    note,
                    TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    context: context,
                  ).spans,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageDisplay(BuildContext context, String page) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          children: _parseFormattedText(
            page[0].toUpperCase() + page.substring(1),
            TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
            context: context,
          ).spans,
        ),
      ),
    );
  }

  Widget _buildSectionNavigation(BuildContext context, List<String> sections) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;

          return _buildTappableWidget(
            context: context,
            pathData: _PathData([
              'entry',
              'senses',
              '$index',
              'section',
            ], 'Section'),
            child: GestureDetector(
              onTap: () => _scrollToSection(index),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RichText(
                  text: TextSpan(
                    children: _parseFormattedText(
                      section,
                      TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      context: context,
                    ).spans,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPronunciations(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    return PathScope.append(
      context,
      key: 'pronunciation',
      child: Builder(
        builder: (context) {
          final dictManager = DictionaryManager();
          return FutureBuilder<List<String>>(
            future: dictManager.getEnabledDictionaries(),
            builder: (context, snapshot) {
              final enabledDicts = snapshot.data ?? [];
              final currentDictId = enabledDicts.isNotEmpty
                  ? enabledDicts.first
                  : '';

              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: entry.pronunciations.asMap().entries.map((entryMap) {
                  final index = entryMap.key;
                  final pronunciation = entryMap.value;
                  final region = pronunciation['region'] as String? ?? '';
                  final notation = pronunciation['notation'] as String? ?? '';
                  final audioFile =
                      pronunciation['audio_file'] as String? ?? '';

                  if (notation.isEmpty && audioFile.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return PathScope.append(
                    context,
                    key: '$index',
                    child: Builder(
                      builder: (context) {
                        final path = PathScope.of(context);
                        final pathData = _PathData(path, 'Pronunciation');

                        return Material(
                          color: Colors.transparent,
                          child: GestureDetector(
                            onSecondaryTapUp: (details) {
                              _handleElementSecondaryTap(
                                _convertPathToString(path),
                                pathData.label,
                                context,
                                details.globalPosition,
                              );
                            },
                            onLongPressStart: (details) {
                              _handleElementSecondaryTap(
                                _convertPathToString(path),
                                pathData.label,
                                context,
                                details.globalPosition,
                              );
                            },
                            child: InkWell(
                              onTap: audioFile.isNotEmpty
                                  ? () {
                                      _playAudio(currentDictId, audioFile);
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              splashColor: audioFile.isNotEmpty
                                  ? colorScheme.primary.withValues(alpha: 0.1)
                                  : null,
                              mouseCursor: audioFile.isNotEmpty
                                  ? SystemMouseCursors.click
                                  : SystemMouseCursors.basic,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: audioFile.isNotEmpty
                                      ? colorScheme.surfaceContainerHighest
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                  border: audioFile.isNotEmpty
                                      ? null
                                      : Border.all(
                                          color: colorScheme.outlineVariant,
                                          width: 1,
                                        ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (region.isNotEmpty)
                                      PathScope.append(
                                        context,
                                        key: 'region',
                                        child: Builder(
                                          builder: (context) {
                                            return _buildPronunciationRegionElement(
                                              context,
                                              region,
                                              hasAudio: audioFile.isNotEmpty,
                                            );
                                          },
                                        ),
                                      ),
                                    if (notation.isNotEmpty)
                                      PathScope.append(
                                        context,
                                        key: 'notation',
                                        child: Builder(
                                          builder: (context) {
                                            return _buildPronunciationPhoneticElement(
                                              context,
                                              notation,
                                              hasAudio: audioFile.isNotEmpty,
                                            );
                                          },
                                        ),
                                      ),
                                    if (audioFile.isNotEmpty) ...[
                                      const SizedBox(width: 5),
                                      Icon(
                                        Icons.volume_up,
                                        size: 13,
                                        color: colorScheme.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildCertificationsInline(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    return entry.certifications.asMap().entries.map((entryMap) {
      final index = entryMap.key;
      final cert = entryMap.value;
      return _buildTappableWidget(
        context: context,
        pathData: _PathData([
          'entry',
          'certifications',
          '$index',
        ], 'Certification'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: colorScheme.tertiary.withValues(alpha: 0.3),
            ),
          ),
          child: RichText(
            text: TextSpan(
              children: _parseFormattedText(
                cert,
                TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.tertiary,
                  letterSpacing: 0.3,
                ),
                context: context,
              ).spans,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _renderIndex(BuildContext context, String indexStr) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(PathScope.of(context), 'Index'),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: RichText(
          text: TextSpan(
            children: _parseFormattedText(
              indexStr,
              TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
              context: context,
            ).spans,
          ),
        ),
      ),
    );
  }

  Widget _renderPos(BuildContext context, String pos) {
    final colorScheme = Theme.of(context).colorScheme;

    if (pos.isEmpty) return const SizedBox.shrink();

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(PathScope.of(context), 'Part of Speech'),
      child: RichText(
        text: TextSpan(
          children: _parseFormattedText(
            pos,
            TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
            context: context,
          ).spans,
        ),
      ),
    );
  }

  Widget _buildPosElement(BuildContext context, String pos) {
    if (pos.isEmpty) return const SizedBox.shrink();

    return PathScope.append(
      context,
      key: 'pos',
      child: Builder(builder: (context) => _renderPos(context, pos)),
    );
  }

  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  Widget _buildPronunciationRegionElement(
    BuildContext context,
    String region, {
    bool hasAudio = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final text = RichText(
      text: TextSpan(
        children: _parseFormattedText(
          '$region ',
          TextStyle(
            fontSize: 11,
            color: colorScheme.outline,
            fontWeight: FontWeight.w500,
          ),
          context: context,
        ).spans,
      ),
    );

    return hasAudio
        ? text
        : _buildTappableWidget(
            context: context,
            pathData: _PathData(PathScope.of(context), 'Region'),
            child: text,
          );
  }

  Widget _buildPronunciationPhoneticElement(
    BuildContext context,
    String phonetic, {
    bool hasAudio = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final text = RichText(
      text: TextSpan(
        children: _parseFormattedText(
          phonetic,
          TextStyle(
            fontSize: 13,
            fontFamily: 'Monospace',
            color: hasAudio
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          context: context,
        ).spans,
      ),
    );

    return hasAudio
        ? text
        : _buildTappableWidget(
            context: context,
            pathData: _PathData(PathScope.of(context), 'Phonetic'),
            child: text,
          );
  }

  Widget _buildSenseContent({
    required BuildContext context,
    required String pos,
    required Map<String, dynamic>? label,
    List<MapEntry<String, String>>? definitions,
    String? sourceLanguage,
    required List<String> targetLanguages,
    Map<String, Map<String, double>>? fontScales,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    int currentTextOffset = 0;

    if (pos.isNotEmpty) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: PathScope.append(
            context,
            key: 'label.pos',
            child: Builder(
              builder: (context) {
                return _buildTappableWidget(
                  context: context,
                  pathData: _PathData(PathScope.of(context), 'Part of Speech'),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8, top: 4),
                    child: Text(
                      pos.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      currentTextOffset += 1; // WidgetSpan 占 1 个字符
    }

    final labelSpans = _buildLabelInlineSpans(context, label);
    for (final span in labelSpans) {
      spans.add(span);
      if (span is WidgetSpan) {
        currentTextOffset += 1; // WidgetSpan 占 1 个字符
      } else if (span is TextSpan) {
        currentTextOffset += span.toPlainText().length;
      }
    }

    final definitionTextKey = GlobalKey();

    if (definitions != null) {
      for (int i = 0; i < definitions.length; i++) {
        final definition = definitions[i];
        if (definition.value.isNotEmpty) {
          // 不同语言的 definition 之间添加间距
          if (i > 0) {
            spans.add(WidgetSpan(child: SizedBox(width: 12)));
            currentTextOffset += 1; // WidgetSpan 占 1 个字符
          } else if (spans.isNotEmpty) {
            spans.add(const TextSpan(text: ' '));
            currentTextOffset += 1; // 空格占 1 个字符
          }

          final startOffset = currentTextOffset;
          currentTextOffset += definition.value.length;

          final path = [...PathScope.of(context), definition.key];
          final pathData = _PathData(path, 'Definition (${definition.key})');

          final hiddenPath = path.join('.');
          // 使用 notifier 的当前值，这样当状态变化时会重建
          final hidden = _hiddenLanguagesNotifier.value.contains(hiddenPath);

          // 确定有效语言并应用字体倍率
          final defKey = definition.key;
          final defLang = defKey.startsWith('definition.')
              ? defKey.substring('definition.'.length)
              : defKey;
          final effectiveLanguageForDef = _determineEffectiveLanguage(
            language: defLang.isEmpty ? null : defLang,
            path: path,
            sourceLanguage: _sourceLanguage,
          );
          final defFontScale =
              fontScales?[effectiveLanguageForDef]?['sans'] ?? 1.0;
          final defFontSize = 15 * defFontScale;

          var definitionTextStyle = TextStyle(
            fontSize: defFontSize,
            color: colorScheme.onSurface,
            height: 1.6,
          );

          // 获取 definition 的自定义字体 (使用 sans)
          final fontService = FontLoaderService();
          final fontInfo = effectiveLanguageForDef != null
              ? fontService.getFontInfo(effectiveLanguageForDef, isSerif: false)
              : null;
          if (fontInfo != null) {
            definitionTextStyle = definitionTextStyle.copyWith(
              fontFamily: fontInfo.fontFamily,
            );
          }

          // 创建手势识别器以支持点击和右键菜单
          final tapRecognizer = TapGestureRecognizer()
            ..onTapDown = (details) {
              _lastTapPosition = details.globalPosition;
            }
            ..onTap = () {
              // 单击立即生效
              _handleElementTap(_convertPathToString(path), pathData.label);

              // 检测双击
              final now = DateTime.now();
              final isDoubleTap =
                  _lastTapTime != null &&
                  now.difference(_lastTapTime!) <
                      const Duration(milliseconds: 300) &&
                  _lastTapButton == 0;

              if (isDoubleTap && _lastTapPosition != null) {
                Logger.d('双击触发', tag: 'DoubleTapWord');
                _handleDoubleTapOnText(
                  _lastTapPosition!,
                  definition.value,
                  definitionTextStyle,
                  definitionTextKey,
                  context,
                  startOffset: startOffset,
                );
                _lastTapTime = null;
                _lastTapButton = null;
                _lastTapPosition = null;
              } else {
                _lastTapTime = now;
                _lastTapButton = 0;
              }
            };

          final secondaryTapRecognizer = _SecondaryTapGestureRecognizer()
            ..onSecondaryTapUp = (details) {
              _lastTapPosition = details.globalPosition;
              _handleElementSecondaryTap(
                _convertPathToString(path),
                pathData.label,
                context,
                details.globalPosition,
              );
            };

          final longPressRecognizer = LongPressGestureRecognizer()
            ..onLongPressStart = (details) {
              _lastTapPosition = details.globalPosition;
              _handleElementSecondaryTap(
                _convertPathToString(path),
                pathData.label,
                context,
                details.globalPosition,
              );
            };

          _recognizers.addAll([
            tapRecognizer,
            secondaryTapRecognizer,
            longPressRecognizer,
          ]);

          // 使用 MultiGestureRecognizer 来同时支持点击、右键和长按
          final multiRecognizer = _MultiGestureRecognizer(
            tapRecognizer: tapRecognizer,
            secondaryTapRecognizer: secondaryTapRecognizer,
            longPressRecognizer: longPressRecognizer,
            doubleTapRecognizer: null,
          );

          final result = _parseFormattedText(
            definition.value,
            definitionTextStyle,
            context: context,
            path: path,
            label: 'Definition (${definition.key})',
            recognizer: multiRecognizer,
            hidden: hidden,
          );

          // 直接使用 TextSpan 而不是 WidgetSpan，以实现文本接着换行的效果
          spans.addAll(result.spans);
        }
      }
    }

    return Builder(
      key: definitionTextKey,
      builder: (context) => RichText(text: TextSpan(children: spans)),
    );
  }

  List<InlineSpan> _buildLabelInlineSpans(
    BuildContext context,
    Map<String, dynamic>? label,
  ) {
    if (label == null || label.isEmpty) return [];

    final spans = <InlineSpan>[];

    final order = [
      'pattern',
      'grammar',
      'register',
      'region',
      'usage',
      'tone',
      'topic',
      'unclassified',
    ];

    for (final key in order) {
      final value = label[key];
      if (value == null || key == 'pos') continue;

      final hasBackground = key != 'pattern' && key != 'pos';
      final displayValue = _capitalizeFirst(value is String ? value : '$value');

      if (value is List<dynamic>) {
        for (int i = 0; i < value.length; i++) {
          final item = value[i];
          final itemValue = item is String ? item : '$item';
          final labelWidget = _buildLabelWidget(
            context,
            itemValue,
            key,
            hasBackground,
            index: i,
          );
          // 将Widget包装为WidgetSpan
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: labelWidget,
            ),
          );
        }
      } else {
        final labelWidget = _buildLabelWidget(
          context,
          displayValue,
          key,
          hasBackground,
        );
        // 将Widget包装为WidgetSpan
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: labelWidget,
          ),
        );
      }
    }

    return spans;
  }

  Widget _buildLabelWidget(
    BuildContext context,
    String text,
    String key,
    bool hasBackground, {
    int? index,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final pathKey = index != null ? 'label.$key.$index' : 'label.$key';
    final textKey = GlobalKey();

    TextStyle textStyle;
    if (!hasBackground) {
      textStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: colorScheme.primary,
      );
    } else {
      final onSurface = colorScheme.onSurface;
      textStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
        height: 1.2,
      );
    }

    final result = _parseFormattedText(text, textStyle, context: context);
    final richText = RichText(text: TextSpan(children: result.spans));

    Widget child;
    if (!hasBackground) {
      child = Container(
        margin: const EdgeInsets.only(right: 8, top: 4),
        child: Builder(key: textKey, builder: (context) => richText),
      );
    } else {
      final onSurface = colorScheme.onSurface;
      final onSurfaceVariant = colorScheme.onSurfaceVariant;

      child = Container(
        margin: const EdgeInsets.only(right: 6, left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.08),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 0.7,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Builder(key: textKey, builder: (context) => richText),
      );
    }

    // 使用PathScope和_TappableWrapper包裹
    return PathScope.append(
      context,
      key: pathKey,
      child: Builder(
        builder: (context) {
          return _buildTappableWidget(
            context: context,
            pathData: _PathData(PathScope.of(context), _capitalizeFirst(key)),
            text: text,
            textStyle: textStyle,
            customTextKey: textKey,
            child: child,
          );
        },
      ),
    );
  }

  // 公共的 sense 渲染键列表
  static const List<String> _renderedSenseKeys = [
    'index',
    'pos',
    'definition',
    'label',
    'example',
    'sub_senses',
    'note',
    'image',
  ];

  /// 渲染单个 sense 项
  Widget _buildSenseWidget(
    BuildContext context,
    Map<String, dynamic> sense,
    String indexStr,
  ) {
    final senselabel = sense['label'] as Map<String, dynamic>?;
    final pos = senselabel?['pos'] as String? ?? '';
    final definitionObj = sense['definition'] as Map<String, dynamic>?;
    final example = sense['example'] as List<dynamic>?;
    final subSenses = sense['sub_senses'] as List<dynamic>?;
    final note = sense['note'] as String?;
    final image = sense['image'] as Map<String, dynamic>?;

    List<MapEntry<String, String>> definitions = [];
    if (definitionObj != null) {
      for (final entry in definitionObj.entries) {
        if (entry.value is String && entry.value.isNotEmpty) {
          definitions.add(
            MapEntry('definition.${entry.key}', entry.value as String),
          );
        }
      }
    }

    final extraKeys = sense.keys
        .where((k) => !_renderedSenseKeys.contains(k))
        .toList();

    final extraWidgets = <Widget>[];
    for (final key in extraKeys) {
      final value = sense[key];
      if (value == null) continue;
      final widget = PathScope.append(
        context,
        key: key,
        child: Builder(
          builder: (context) {
            return renderJsonElement(
              context,
              key,
              value,
              PathScope.of(context),
            );
          },
        ),
      );
      extraWidgets.add(widget);
    }

    return Container(
      margin: const EdgeInsets.only(left: _senseLeftIndent),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(-_senseLeftIndent, 0),
            child: PathScope.append(
              context,
              key: 'index',
              child: Builder(
                builder: (context) => _renderIndex(context, indexStr),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
                    child: HiddenLanguagesSelector<String>(
                      selector: (hiddenLanguages) {
                        final relevantHidden = <String>[];
                        for (final def in definitions) {
                          final path = [...PathScope.of(context), def.key];
                          final pathStr = path.join('.');
                          if (hiddenLanguages.contains(pathStr)) {
                            relevantHidden.add(pathStr);
                          }
                        }
                        relevantHidden.sort();
                        return relevantHidden.join(',');
                      },
                      builder: (context, hiddenPathsStr, child) {
                        // Logger.d(
                        //   '重建 SenseContent: pos=$pos, definitions=$definitions, hiddenPaths=$hiddenPathsStr',
                        //   tag: 'Rebuild',
                        // );
                        return _buildSenseContent(
                          context: context,
                          pos: pos,
                          label: senselabel,
                          definitions: definitions,
                          sourceLanguage: _sourceLanguage,
                          targetLanguages: _targetLanguages,
                          fontScales: _fontScales,
                        );
                      },
                    ),
                  ),
                  if (image != null && image.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final imageFile = image['image_file'] as String?;
                        if (imageFile == null || imageFile.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _buildImageElement(
                          context,
                          image,
                          _localEntry.dictId,
                          'image',
                          imageFile,
                        );
                      },
                    ),
                ],
              ),
              if (example != null && example.isNotEmpty) ...[
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: example
                      .asMap()
                      .entries
                      .map(
                        (exampleEntry) => PathScope.append(
                          context,
                          key: 'example.${exampleEntry.key}',
                          child: Builder(
                            builder: (context) {
                              return _buildExample(
                                context,
                                exampleEntry.value,
                                leftMargin: 0,
                              );
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (note != null && note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildnote(context, {'note': note}),
                ),
              if (extraWidgets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: extraWidgets,
                  ),
                ),
              if (subSenses != null && subSenses.isNotEmpty) ...[
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: subSenses.asMap().entries.expand((subEntry) {
                    final subIndexValue = subEntry.value['index'];
                    final subIndexStr = subIndexValue is String
                        ? subIndexValue
                        : '${subEntry.key + 1}';
                    final widgets = <Widget>[
                      PathScope.append(
                        context,
                        key: 'sub_senses.${subEntry.key}',
                        child: Builder(
                          builder: (context) {
                            final subSensePath = PathScope.of(context);
                            final subSensePathStr = _convertPathToString(
                              subSensePath,
                            );
                            final isHighlighting = _isHighlighting(
                              subSensePathStr,
                            );
                            return _HighlightWrapper(
                              isHighlighting: isHighlighting,
                              child: Container(
                                key: _getElementKey(subSensePathStr),
                                child: _buildSenseWidget(
                                  context,
                                  subEntry.value as Map<String, dynamic>,
                                  subIndexStr,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ];
                    if (subEntry.key < subSenses.length - 1) {
                      widgets.add(const SizedBox(height: 12));
                    }
                    return widgets;
                  }).toList(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSenses(BuildContext context) {
    final entry = _localEntry;

    return PathScope.append(
      context,
      key: 'senses',
      child: Builder(
        builder: (context) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entry.senses.asMap().entries.map((entryData) {
              final sense = entryData.value;
              final indexValue = sense['index'];
              final indexStr = indexValue is int
                  ? '$indexValue'
                  : (indexValue as String? ?? '${entryData.key + 1}');

              return PathScope.append(
                context,
                key: '${entryData.key}',
                child: Builder(
                  builder: (context) {
                    final sensePath = PathScope.of(context);
                    final sensePathStr = _convertPathToString(sensePath);
                    final isHighlighting = _isHighlighting(sensePathStr);
                    return _HighlightWrapper(
                      isHighlighting: isHighlighting,
                      child: Container(
                        key: _getElementKey(sensePathStr),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSenseWidget(context, sense, indexStr),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildSenseGroups(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entry = _localEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entry.senseGroups.asMap().entries.map((groupEntry) {
        final groupIndex = groupEntry.key;
        final group = groupEntry.value;
        final groupName = group['group_name'] as String? ?? '';
        final senses = group['senses'] as List<dynamic>? ?? [];

        return Column(
          key: _sectionKeys[groupIndex],
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groupName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RichText(
                  text: TextSpan(
                    children: _parseFormattedText(
                      groupName,
                      TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                        letterSpacing: 1.0,
                      ),
                      context: context,
                    ).spans,
                  ),
                ),
              ),
            if (senses.isNotEmpty)
              PathScope.append(
                context,
                key: 'sense_groups.$groupIndex.senses',
                child: Builder(
                  builder: (context) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: senses.asMap().entries.map((senseEntry) {
                        final sense = senseEntry.value;
                        final indexValue = sense['index'];
                        final indexStr = indexValue is int
                            ? '$indexValue'
                            : (indexValue as String? ??
                                  '${senseEntry.key + 1}');

                        return PathScope.append(
                          context,
                          key: '${senseEntry.key}',
                          child: Builder(
                            builder: (context) {
                              final sensePath = PathScope.of(context);
                              final sensePathStr = _convertPathToString(
                                sensePath,
                              );
                              final isHighlighting = _isHighlighting(
                                sensePathStr,
                              );
                              return _HighlightWrapper(
                                isHighlighting: isHighlighting,
                                child: Container(
                                  key: _getElementKey(sensePathStr),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSenseWidget(
                                        context,
                                        sense as Map<String, dynamic>,
                                        indexStr,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  // 已单独渲染的 key 列表，这些 key 不会出现在 _buildRemainingBoards 中
  static const List<String> _renderedKeys = [
    'id',
    'entry_id',
    'dict_id',
    'version',
    'headword',
    'entry_type',
    'page',
    'section',
    'tags',
    'certifications',
    'frequency',
    'pronunciation',
    'senses',
    'sense_groups',
    'phrases',
    'datas', // datas 单独渲染
  ];

  /// 渲染 datas（如果存在），在 senses 之前显示
  Widget _buildDatasIfExist(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    if (!entryJson.containsKey('datas')) return const SizedBox.shrink();

    final value = entryJson['datas'];
    if (value is! Map<String, dynamic> || value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildDatas(context, value, path: ['datas']),
      ],
    );
  }

  Widget _buildPhrases(BuildContext context) {
    final entry = _localEntry;
    final phrases = entry.phrases;

    if (phrases.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final fontScale = _fontScales[_sourceLanguage ?? 'en']?['serif'] ?? 1.0;
    final titleFontSize = 13 * fontScale;
    final phraseFontSize = 14 * fontScale;

    // 获取 phrases 的 GlobalKey 用于滚动定位
    final phrasesKey = _getElementKey('phrases');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        PathScope.append(
          context,
          key: 'phrases',
          child: Builder(
            builder: (context) {
              return Container(
                key: phrasesKey, // 绑定 GlobalKey 用于滚动定位
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote,
                          size: 16 * fontScale,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'phrases',
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...phrases.asMap().entries.map((entry) {
                      final index = entry.key;
                      final phrase = entry.value;
                      return PathScope.append(
                        context,
                        key: '$index',
                        child: Builder(
                          builder: (context) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                _handlePhraseTap(
                                  phrase,
                                  details.globalPosition,
                                );
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  margin: EdgeInsets.only(
                                    bottom: index < phrases.length - 1 ? 6 : 0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                  child: RichText(
                                    text: TextSpan(
                                      children: parseFormattedText(
                                        phrase,
                                        TextStyle(
                                          fontSize: phraseFontSize,
                                          color: colorScheme.onSurface,
                                        ),
                                        sourceLanguage: _sourceLanguage,
                                        fontScales: _fontScales,
                                        isSerif: true,
                                        isBold: true,
                                      ).spans,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 渲染所有未单独渲染的 key 为 board
  Widget _buildRemainingBoards(BuildContext context) {
    final entry = _localEntry;
    final entryJson = entry.toJson();

    final widgets = <Widget>[];

    for (final entry in entryJson.entries) {
      final key = entry.key;
      final value = entry.value;

      // 跳过已单独渲染的 key
      if (_renderedKeys.contains(key)) continue;

      // 跳过 null 值
      if (value == null) continue;

      // 跳过空列表
      if (value is List && value.isEmpty) continue;

      final path = [key];
      // 获取 board 的 GlobalKey 用于滚动定位
      final boardKey = _getElementKey(key);

      Widget boardWidget;
      if (value is Map<String, dynamic>) {
        final title = value['title'] as String? ?? key;
        final display = value['display'] as String? ?? '00';
        final boardData = {...value, 'title': title, 'display': display};

        boardWidget = BoardWidget(
          board: boardData,
          contentBuilder: (board, path) =>
              _buildBoardContent(context, board, path),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      } else if (value is List<dynamic>) {
        boardWidget = renderJsonElement(context, key, value, path);
      } else {
        // 其他类型（字符串、数字等）也包装为 board
        final boardData = {'title': key, 'text': value.toString()};
        boardWidget = BoardWidget(
          board: boardData,
          contentBuilder: (board, path) =>
              _buildBoardContent(context, board, path),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      }

      // 使用 Container 包装并绑定 GlobalKey 用于滚动定位
      widgets.add(Container(key: boardKey, child: boardWidget));
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SizedBox(height: 12), ...widgets],
    );
  }

  Widget _buildBoardContent(
    BuildContext context,
    Map<String, dynamic> board,
    List<String> path,
  ) {
    final keys = board.keys
        .where((k) => k != 'title' && k != 'display')
        .toList();

    if (keys.isEmpty) {
      return const SizedBox.shrink();
    }

    // 分离 datas key，它将在最后渲染
    final hasDatas = keys.contains('datas');
    final normalKeys = keys.where((k) => k != 'datas').toList();
    final datasValue = hasDatas ? board['datas'] : null;

    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<String>(
      selector: (hiddenLanguages) {
        final relevantHidden = <String>[];
        for (final key in normalKeys) {
          final isLanguageCode =
              LanguageUtils.getLanguageDisplayName(key) != key.toUpperCase();
          if (isLanguageCode) {
            final pathStr = [...path, key].join('.');
            if (hiddenLanguages.contains(pathStr)) {
              relevantHidden.add(pathStr);
            }
          }
        }
        relevantHidden.sort();
        return relevantHidden.join(',');
      },
      builder: (context, hiddenPathsStr, child) {
        // Logger.d(
        //   '重建 BoardContent: path=${path.join('.')}, keys=$keys, hiddenPaths=$hiddenPathsStr',
        //   tag: 'Rebuild',
        // );
        final widgets = <Widget>[];
        final hiddenLanguages = _hiddenLanguagesNotifier.value;

        for (final key in normalKeys) {
          final value = board[key];
          final keyPath = [...path, key];

          // 检查是否是语言代码且被隐藏
          final isLanguageCode =
              LanguageUtils.getLanguageDisplayName(key) != key.toUpperCase();
          if (isLanguageCode) {
            final hiddenPath = keyPath.join('.');
            if (hiddenLanguages.contains(hiddenPath)) {
              // 跳过被隐藏的语言
              continue;
            }
          }

          if (value is Map<String, dynamic>) {
            widgets.add(
              BoardWidget(
                board: value,
                contentBuilder: (board, path) =>
                    _buildBoardContent(context, board, path),
                path: keyPath,
                fontScales: _fontScales,
                sourceLanguage: _sourceLanguage,
              ),
            );
          } else if (value is List<dynamic>) {
            widgets.add(renderJsonElement(context, key, value, keyPath));
          } else {
            final text = value is String ? value : (value?.toString() ?? '');
            if (isLanguageCode) {
              widgets.add(_buildPlainTextItem(context, text, keyPath));
            } else {
              widgets.add(_buildContentItem(context, text, keyPath));
            }
          }
        }

        // 在最后渲染 datas（如果存在）
        if (datasValue is Map<String, dynamic> && datasValue.isNotEmpty) {
          widgets.add(
            _buildDatas(context, datasValue, path: [...path, 'datas']),
          );
        }

        if (widgets.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }

  Widget _buildContentItem(
    BuildContext context,
    String text,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onSurfaceVariant,
      height: 1.6,
      letterSpacing: 0.2,
    );

    final textKey = GlobalKey();

    return _buildTappableWidget(
      context: context,
      pathData: _PathData(path, 'Content Item'),
      text: text,
      textStyle: textStyle,
      customTextKey: textKey,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.75),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDoubleTapText(
                context: context,
                text: text,
                style: textStyle,
                textKey: textKey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlainTextItem(
    BuildContext context,
    String text,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onSurfaceVariant,
      height: 1.6,
      letterSpacing: 0.2,
    );

    final textKey = GlobalKey();
    final hiddenPath = path.join('.');

    // 使用 HiddenLanguagesSelector 仅在相关路径的隐藏状态变化时重建
    return HiddenLanguagesSelector<bool>(
      selector: (hiddenLanguages) => hiddenLanguages.contains(hiddenPath),
      builder: (context, hidden, child) {
        // Logger.d(
        //   '重建 PlainTextItem: path=${path.join('.')}, hidden=$hidden',
        //   tag: 'Rebuild',
        // );
        return _buildTappableWidget(
          context: context,
          pathData: _PathData(path, 'Plain Text Item'),
          text: text,
          textStyle: textStyle,
          customTextKey: textKey,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildDoubleTapText(
              context: context,
              text: text,
              style: textStyle,
              textKey: textKey,
              hidden: hidden,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDoubleTapText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    GlobalKey? textKey,
    bool hidden = false,
  }) {
    final result = _parseFormattedText(
      text,
      style,
      context: context,
      hidden: hidden,
    );
    final richText = RichText(text: TextSpan(children: result.spans));

    if (textKey != null) {
      return Builder(key: textKey, builder: (context) => richText);
    }
    return richText;
  }

  Widget _buildInlineContentItem(
    BuildContext context,
    String text,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildTappableWidget(
      context: context,
      pathData: _PathData(path, 'Inline Item'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: RichText(
          text: TextSpan(
            children: _parseFormattedText(
              text,
              TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                letterSpacing: 0.15,
              ),
              context: context,
            ).spans,
          ),
        ),
      ),
    );
  }

  Player? _currentPlayer;

  /// 检查是否为 opus 格式音频
  bool _isOpusFormat(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ext == 'opus' || ext == 'ogg';
  }

  /// 检查当前平台是否为 Apple 平台（iOS/macOS）
  bool get _isApplePlatform {
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (e) {
      // 如果在不支持的平台（如 Web）上，返回 false
      return false;
    }
  }

  void _playAudio(String dictionaryId, String audioFileName) async {
    if (dictionaryId.isEmpty || audioFileName.isEmpty) return;

    unawaited(_playAudioInternal(dictionaryId, audioFileName));
  }

  Future<void> _playAudioInternal(
    String dictionaryId,
    String audioFileName,
  ) async {
    if (dictionaryId.isEmpty || audioFileName.isEmpty) return;

    Player? player;

    try {
      final dictManager = DictionaryManager();

      String? audioSource;
      bool isLocal = false;

      // 优先从 media.db 读取音频
      final audioBytes = await dictManager.getAudioBytes(
        dictionaryId,
        audioFileName,
      );

      if (audioBytes != null && audioBytes.isNotEmpty) {
        final tempDir = await dictManager.getTempDirectory();
        final tempFile = File(path.join(tempDir, audioFileName));
        await tempFile.writeAsBytes(audioBytes);
        audioSource = tempFile.path;
        isLocal = true;
        Logger.d('从media.db读取本地音频成功: $audioSource', tag: '_playAudio');
      }

      if (audioSource == null) {
        // 尝试从 zip 读取
        final dictDir = await dictManager.getDictionaryDir(dictionaryId);
        final zipPath = path.join(dictDir, 'audios.zip');
        final zipFile = File(zipPath);

        Logger.d('从zip读取音频: $zipPath', tag: '_playAudio');

        if (await zipFile.exists()) {
          final audioBytesFromZip = await dictManager.readFromUncompressedZip(
            zipPath,
            'audios/$audioFileName',
          );

          Logger.d(
            '从zip读取结果: ${audioBytesFromZip?.length ?? 0} bytes',
            tag: '_playAudio',
          );

          if (audioBytesFromZip != null && audioBytesFromZip.isNotEmpty) {
            final tempDir = await dictManager.getTempDirectory();
            final tempFile = File(path.join(tempDir, audioFileName));
            await tempFile.writeAsBytes(audioBytesFromZip);
            audioSource = tempFile.path;
            isLocal = true;
            Logger.d('从zip读取本地音频成功: $audioSource', tag: '_playAudio');
          }
        }
      }

      if (audioSource == null) {
        final domain = await dictManager.onlineSubscriptionUrl;
        if (domain.isEmpty) {
          Logger.e('无法获取订阅网站地址', tag: '_playAudio');
          return;
        }

        final cleanDomain = domain.trim().replaceAll(RegExp(r'/$'), '');
        audioSource =
            '$cleanDomain/audio/$dictionaryId/${Uri.encodeComponent(audioFileName)}';
        isLocal = false;
        Logger.d('使用在线音频: $audioSource', tag: '_playAudio');
      }

      // 清理旧播放器
      _cleanupPlayer();

      player = Player();
      _currentPlayer = player;

      // 注册到管理器以便热重启时清理
      MediaKitManager().registerPlayer(player);

      Logger.d('播放音频: ${isLocal ? "本地" : "在线"}', tag: '_playAudio');
      await player.open(Media(audioSource), play: true);

      // 监听播放完成，自动清理资源
      StreamSubscription? completionSub;
      completionSub = player.stream.completed.listen((completed) {
        if (completed) {
          completionSub?.cancel();
          _streamSubscriptions.remove(completionSub);
          _cleanupPlayer();
        }
      });
      _streamSubscriptions.add(completionSub);

      await Future.delayed(const Duration(milliseconds: 200));

      Logger.d('音频播放已启动: $audioFileName', tag: '_playAudio');
    } catch (e, stackTrace) {
      Logger.e('播放音频失败: $e', tag: '_playAudio', error: e);
      Logger.e('堆栈跟踪: $stackTrace', tag: '_playAudio');

      try {
        await player?.dispose();
      } catch (_) {}

      _currentPlayer = null;

      if (_isOpusFormat(audioFileName) && _isApplePlatform) {
        Logger.w('opus 格式在 iOS/macOS 上可能需要额外的配置支持', tag: '_playAudio');
      }
    }
  }

  static const Map<String, String> predefinedRenderers = {
    'headword': 'word',
    'frequency': 'frequency',
    'pronunciation': 'pronunciation',
    'certifications': 'certification',
    'senses': 'sense',
    'example': 'example',
    'datas': 'datas',
    'note': 'note',
    'image': 'image',
  };

  Widget _buildStringListAsRow(
    BuildContext context,
    List<String> strings,
    List<String> path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.75),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: strings.asMap().entries.map((entry) {
                final itemPath = [...path, '${entry.key}'];
                return _buildTappableWidget(
                  context: context,
                  pathData: _PathData(itemPath, 'Inline Item'),
                  child: RichText(
                    text: TextSpan(
                      children: _parseFormattedText(
                        entry.value,
                        TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                          letterSpacing: 0.15,
                        ),
                        context: context,
                      ).spans,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget renderJsonElement(
    BuildContext context,
    String key,
    dynamic value,
    List<String> path,
  ) {
    final isNumericKey = RegExp(r'^\d+$').hasMatch(key);

    // 1. 如果key不是数字，表明是一个键值对
    if (!isNumericKey) {
      // 1.1 如果key在预定义列表中
      if (predefinedRenderers.containsKey(key)) {
        // 1.1.1 如果value不是list，使用预定义方法渲染
        if (value is! List) {
          return _renderWithPredefinedMethod(context, key, value, path);
        }
        // 1.1.2 如果value是list，渲染一个widget容器，对于list的每个元素，都使用key所定义的渲染函数渲染
        if (value.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: value.asMap().entries.map((entry) {
              final itemPath = [...path, '${entry.key}'];
              return _renderWithPredefinedMethod(
                context,
                key,
                entry.value,
                itemPath,
              );
            }).toList(),
          );
        }
        return const SizedBox.shrink();
      }

      // 1.2 如果key不在预定义列表中，则渲染为一个board，标题为key
      // 1.2.1 如果value是map，则按照board里的排序，调用renderJsonElement自身渲染各个map里的key1:value1
      if (value is Map<String, dynamic>) {
        return BoardWidget(
          board: {'title': key, ...value},
          contentBuilder: (board, p) => _buildBoardContent(context, board, p),
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      }

      // 1.2.2 如果value是一个list
      if (value is List) {
        if (value.isEmpty) return const SizedBox.shrink();
        // 渲染为 BoardWidget（标题为 key）
        return BoardWidget(
          board: {'title': key, 'content': value},
          contentBuilder: (board, p) {
            final content = board['content'] as List;
            // 1.2.2.1 如果value是一个list<string>，则使用_buildStringListAsRow渲染value
            if (content.every((e) => e is String)) {
              return _buildStringListAsRow(
                context,
                content.cast<String>(),
                path,
              );
            }
            // 1.2.2.2 其它情况，则迭代调用renderJsonElement自身渲染value中的每一个元素
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content.asMap().entries.map((entry) {
                final itemPath = [...path, '${entry.key}'];
                return renderJsonElement(
                  context,
                  '${entry.key}',
                  entry.value,
                  itemPath,
                );
              }).toList(),
            );
          },
          path: path,
          fontScales: _fontScales,
          sourceLanguage: _sourceLanguage,
        );
      }
    }

    // 2. 如果key是数字，表明value是list中的一个元素
    if (isNumericKey) {
      // 2.1 如果value是一个list<string>，则使用_buildStringListAsRow渲染value
      if (value is List &&
          value.isNotEmpty &&
          value.every((e) => e is String)) {
        return _buildStringListAsRow(context, value.cast<String>(), path);
      }
      // 2.2 如果value是一个list<list>，则迭代调用renderJsonElement自身渲染value中的每一个子list
      if (value is List && value.isNotEmpty && value.every((e) => e is List)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.asMap().entries.map((entry) {
            final itemPath = [...path, '${entry.key}'];
            return renderJsonElement(
              context,
              '${entry.key}',
              entry.value,
              itemPath,
            );
          }).toList(),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _renderWithPredefinedMethod(
    BuildContext context,
    String key,
    dynamic value,
    List<String> path,
  ) {
    final renderer = predefinedRenderers[key] ?? '';

    if (value is Map<String, dynamic>) {
      return _renderMapWithPredefinedMethod(context, renderer, value, path);
    }

    if (value is List<dynamic>) {
      return renderJsonElement(context, key, value, path);
    }

    return const SizedBox.shrink();
  }

  Widget _renderMapWithPredefinedMethod(
    BuildContext context,
    String renderer,
    Map<String, dynamic> value,
    List<String> path,
  ) {
    switch (renderer) {
      case 'word':
        return _buildWord(context);
      case 'frequency':
        return _buildFrequencyStars(context);
      case 'example':
        return _buildExample(context, value, path: path);
      case 'datas':
        return _buildDatas(context, value, path: path);
      case 'note':
        return _buildnote(context, value, path: path);
      case 'image':
        final imageFile = value['image_file'] as String?;
        if (imageFile == null || imageFile.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildImageElement(
          context,
          value,
          _localEntry.dictId,
          path.join('.'),
          imageFile,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _renderAsBoard(
    BuildContext context,
    String key,
    Map<String, dynamic> value,
    List<String> path,
  ) {
    return BoardWidget(
      board: value,
      contentBuilder: (board, path) => _buildBoardContent(context, board, path),
      path: path,
      fontScales: _fontScales,
      sourceLanguage: _sourceLanguage,
    );
  }

  Widget _buildImageElement(
    BuildContext context,
    Map<String, dynamic> imageData,
    String? dictId,
    String path,
    String imageFile,
  ) {
    if (imageFile.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSvg = imageFile.toLowerCase().endsWith('.svg');

    final cacheKey = '${dictId}_$imageFile';

    return _LazyImageLoader(
      key: ValueKey(cacheKey),
      dictId: dictId,
      imageFile: imageFile,
      isSvg: isSvg,
      onImageLoaded: (bytes) =>
          _buildImageWidget(context, bytes, isSvg, imageFile),
    );
  }

  // 小图尺寸
  static const double _thumbnailSize = 100;

  String _cleanSvgString(String svgString) {
    return svgString;
  }

  Uint8List? _extractBase64Image(String svgString) {
    try {
      final base64Pattern = RegExp(
        r'data:image/([a-zA-Z]+);base64,([A-Za-z0-9+/=\s]+)',
        dotAll: true,
      );
      final match = base64Pattern.firstMatch(svgString);

      if (match != null && match.groupCount >= 2) {
        final base64Data = match.group(2)!.replaceAll(RegExp(r'\s'), '');
        final imageBytes = base64Decode(base64Data);
        return imageBytes;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  Widget _buildImageWidget(
    BuildContext context,
    Uint8List imageBytes,
    bool isSvg,
    String imageFile,
  ) {
    if (isSvg) {
      final svgString = String.fromCharCodes(imageBytes);
      final cleanedSvg = _cleanSvgString(svgString);
      final cleanedBytes = Uint8List.fromList(cleanedSvg.codeUnits);

      final base64Image = _extractBase64Image(cleanedSvg);
      if (base64Image != null) {
        return GestureDetector(
          onTap: () =>
              _showImageDialog(context, imageFile, cleanedBytes, isSvg),
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                base64Image,
                height: _thumbnailSize,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.broken_image,
                    color: Theme.of(context).colorScheme.outline,
                    size: 24,
                  );
                },
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: () => _showImageDialog(context, imageFile, cleanedBytes, isSvg),
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SizedBox(
            height: _thumbnailSize,
            child: SvgPicture.string(
              cleanedSvg,
              fit: BoxFit.contain,
              allowDrawingOutsideViewBox: true,
              clipBehavior: Clip.none,
              placeholderBuilder: (context) {
                return Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showImageDialog(context, imageFile, imageBytes, isSvg),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.memory(
            imageBytes,
            width: _thumbnailSize,
            height: _thumbnailSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.broken_image,
                color: Theme.of(context).colorScheme.outline,
                size: 24,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showImageDialog(
    BuildContext context,
    String fileName,
    Uint8List? imageBytes,
    bool isSvg,
  ) {
    if (imageBytes == null) {
      showToast(context, '图片加载失败');
      return;
    }

    String? displaySvg;
    Uint8List? displayImageBytes;
    if (isSvg) {
      final svgString = String.fromCharCodes(imageBytes);
      displaySvg = _cleanSvgString(svgString);
      displayImageBytes = _extractBase64Image(displaySvg);
    }

    showDialog(
      context: context,
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        final padding = 16.0;
        final maxWidth = screenSize.width - padding * 2;
        final maxHeight = screenSize.height - padding * 2;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: screenSize.width,
                  height: screenSize.height,
                  color: Colors.transparent,
                ),
              ),
              Center(
                child: Container(
                  padding: EdgeInsets.all(padding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                    ),
                    child: GestureDetector(
                      onTap: () {},
                      child: InteractiveViewer(
                        maxScale: 5.0,
                        minScale: 0.5,
                        constrained: true,
                        child: Builder(
                          builder: (context) {
                            if (isSvg && displaySvg != null) {
                              if (displayImageBytes != null) {
                                return Image.memory(
                                  displayImageBytes,
                                  fit: BoxFit.contain,
                                );
                              }
                              return SvgPicture.string(
                                displaySvg,
                                fit: BoxFit.contain,
                                allowDrawingOutsideViewBox: true,
                                clipBehavior: Clip.none,
                                placeholderBuilder: (context) {
                                  return Center(
                                    child: CircularProgressIndicator(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  );
                                },
                              );
                            } else {
                              return Image.memory(
                                imageBytes,
                                fit: BoxFit.contain,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 懒加载图片组件，等其他元素渲染完后再加载图片
class _LazyImageLoader extends StatefulWidget {
  final String? dictId;
  final String imageFile;
  final bool isSvg;
  final Widget Function(Uint8List bytes) onImageLoaded;

  const _LazyImageLoader({
    super.key,
    required this.dictId,
    required this.imageFile,
    required this.isSvg,
    required this.onImageLoaded,
  });

  @override
  State<_LazyImageLoader> createState() => _LazyImageLoaderState();
}

class _LazyImageLoaderState extends State<_LazyImageLoader>
    with AutomaticKeepAliveClientMixin {
  static final Map<String, Uint8List> _imageCache = {};
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _hasTriedLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  void _loadImageIfNeeded() {
    final cacheKey = '${widget.dictId}_${widget.imageFile}';
    if (_imageCache.containsKey(cacheKey)) {
      if (!mounted) return;
      setState(() {
        _imageBytes = _imageCache[cacheKey];
        _hasTriedLoading = true;
      });
    } else if (!_hasTriedLoading && !_isLoading) {
      _hasTriedLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadImage();
        }
      });
    }
  }

  @override
  void didUpdateWidget(_LazyImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageFile != oldWidget.imageFile ||
        widget.dictId != oldWidget.dictId) {
      _hasTriedLoading = false;
      _loadImageIfNeeded();
    }
  }

  Future<void> _loadImage() async {
    if (_isLoading || _imageBytes != null) return;

    final cacheKey = '${widget.dictId}_${widget.imageFile}';

    setState(() {
      _isLoading = true;
    });

    try {
      Uint8List? bytes;

      if (_imageCache.containsKey(cacheKey)) {
        bytes = _imageCache[cacheKey];
      } else {
        if (widget.dictId != null && widget.dictId!.isNotEmpty) {
          bytes = await DictionaryManager().getImageBytes(
            widget.dictId!,
            widget.imageFile,
          );
          if (bytes != null && bytes.isNotEmpty) {
            _imageCache[cacheKey] = bytes;
          }
        }
      }

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_imageBytes != null) {
      return widget.onImageLoaded(_imageBytes!);
    }

    // 加载中或等待加载，返回透明占位符
    return const SizedBox(width: 48, height: 48);
  }
}

class _DatasTabWidget extends StatefulWidget {
  final List<String> keys;
  final Map<String, dynamic> value;
  final List<String> path;
  final ColorScheme colorScheme;
  final Widget Function(Map<String, dynamic> board, List<String> path)
  contentBuilder;
  final void Function(String path, String label)? onElementTap;
  final String? sourceLanguage;
  final Map<String, Map<String, double>> fontScales;

  const _DatasTabWidget({
    required this.keys,
    required this.value,
    required this.path,
    required this.colorScheme,
    required this.contentBuilder,
    this.onElementTap,
    this.sourceLanguage,
    required this.fontScales,
  });

  @override
  State<_DatasTabWidget> createState() => _DatasTabWidgetState();
}

class _DatasTabWidgetState extends State<_DatasTabWidget> {
  int? _selectedIndex;

  void _selectTab(int? index, String key) {
    setState(() {
      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else {
        _selectedIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.keys.asMap().entries.map((entry) {
            final index = entry.key;
            final key = entry.value;
            final isSelected = _selectedIndex == index;

            return InkWell(
              onTap: () => _selectTab(index, key),
              borderRadius: BorderRadius.circular(4),
              mouseCursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? widget.colorScheme.primaryContainer
                      : widget.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                        ? widget.colorScheme.primary
                        : widget.colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: parseFormattedText(
                          key,
                          TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? widget.colorScheme.onPrimaryContainer
                                : widget.colorScheme.onSurface,
                          ),
                          context: context,
                          sourceLanguage: widget.sourceLanguage,
                          fontScales: widget.fontScales,
                          isSerif: true,
                        ).spans,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 14,
                        color: widget.colorScheme.onPrimaryContainer,
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: widget.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedIndex != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Builder(
              builder: (context) {
                final selectedKey = widget.keys[_selectedIndex!];
                final selectedValue = widget.value[selectedKey];

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: selectedValue is Map<String, dynamic>
                      ? widget.contentBuilder(selectedValue, [
                          ...widget.path,
                          selectedKey,
                        ])
                      : selectedValue is List<dynamic>
                      ? widget.contentBuilder(
                          {selectedKey: selectedValue},
                          [...widget.path, selectedKey],
                        )
                      : Text(
                          selectedValue?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.colorScheme.onSurfaceVariant,
                          ),
                        ),
                );
              },
            ),
          ),
      ],
    );
  }
}
