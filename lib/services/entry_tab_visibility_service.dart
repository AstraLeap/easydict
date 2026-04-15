import 'package:flutter/foundation.dart';

class EntryTabVisibilityService extends ChangeNotifier {
  EntryTabVisibilityService._internal();
  static final EntryTabVisibilityService _instance =
      EntryTabVisibilityService._internal();
  factory EntryTabVisibilityService() => _instance;

  bool _isVisible = false;
  bool _persistentMode = false;

  bool get isVisible => _isVisible;
  bool get persistentMode => _persistentMode;

  void setPersistentMode(bool enabled) {
    if (_persistentMode == enabled) return;
    _persistentMode = enabled;
    notifyListeners();
  }

  void show() {
    if (_isVisible) return;
    _isVisible = true;
    notifyListeners();
  }

  void hide() {
    if (!_isVisible) return;
    _isVisible = false;
    notifyListeners();
  }
}
