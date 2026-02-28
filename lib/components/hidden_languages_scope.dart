import 'package:flutter/material.dart';

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
