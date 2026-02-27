import 'package:flutter/foundation.dart';
import '../data/models/dictionary_metadata.dart';
import '../data/models/user_dictionary.dart' as user_dict;
import '../services/dictionary_manager.dart';
import '../services/user_dicts_service.dart';
import '../services/preferences_service.dart';
import '../core/logger.dart';

class DictUpdateCheckService extends ChangeNotifier {
  static final DictUpdateCheckService _instance =
      DictUpdateCheckService._internal();
  factory DictUpdateCheckService() => _instance;
  DictUpdateCheckService._internal();

  final DictionaryManager _dictManager = DictionaryManager();
  final UserDictsService _userDictsService = UserDictsService();
  final PreferencesService _preferencesService = PreferencesService();

  Map<String, user_dict.DictUpdateInfo> _updatableDicts = {};
  bool _isChecking = false;
  DateTime? _lastCheckTime;

  Map<String, user_dict.DictUpdateInfo> get updatableDicts => _updatableDicts;
  int get updatableCount => _updatableDicts.length;
  bool get isChecking => _isChecking;
  DateTime? get lastCheckTime => _lastCheckTime;

  void setBaseUrl(String? url) {
    _userDictsService.setBaseUrl(url);
  }

  /// 启动时检查：如果上次检查距今已超过24小时，则在后台触发一次更新检查。
  /// 此方法本身是非阻塞的，不需要 await。
  Future<void> startDailyCheck() async {
    final enabled = await _preferencesService.getAutoCheckDictUpdate();
    if (!enabled) return;

    final lastCheck = await _preferencesService.getLastDictUpdateCheckTime();
    if (lastCheck != null) {
      _lastCheckTime = lastCheck;
    }

    final now = DateTime.now();
    if (lastCheck == null || now.difference(lastCheck).inHours >= 24) {
      // 不提前 await，让检查在后台运行不阻塞 UI
      checkForUpdates();
    }
  }

  void stopDailyCheck() {
    // 已移除定期检查机制，此方法保留以兼容设置开关逻辑
  }

  Future<void> checkForUpdates() async {
    if (_isChecking) return;

    final enabled = await _preferencesService.getAutoCheckDictUpdate();
    if (!enabled) {
      Logger.i('自动检查词典更新已禁用', tag: 'DictUpdateCheckService');
      return;
    }

    final baseUrl = await _dictManager.onlineSubscriptionUrl;
    if (baseUrl.isEmpty) {
      Logger.i('未设置在线订阅URL，跳过检查', tag: 'DictUpdateCheckService');
      return;
    }

    _isChecking = true;
    notifyListeners();

    try {
      final allDicts = await _dictManager.getAllDictionariesMetadata();
      if (allDicts.isEmpty) {
        Logger.i('没有本地词典，跳过检查', tag: 'DictUpdateCheckService');
        _updatableDicts = {};
        _isChecking = false;
        _lastCheckTime = DateTime.now();
        await _preferencesService.setLastDictUpdateCheckTime(_lastCheckTime!);
        notifyListeners();
        return;
      }

      final dictVersions = <String, (int, int?)>{};
      for (final dict in allDicts) {
        dictVersions[dict.id] = (dict.version, null);
      }

      Logger.i(
        '检查 ${dictVersions.length} 个词典的更新...',
        tag: 'DictUpdateCheckService',
      );
      final updateInfos = await _userDictsService.getDictsUpdateInfo(
        dictVersions,
      );

      final updatable = <String, user_dict.DictUpdateInfo>{};
      updateInfos.forEach((dictId, info) {
        if (info.from < info.to) {
          updatable[dictId] = info;
          Logger.i(
            '词典 $dictId 有更新: v${info.from} -> v${info.to}',
            tag: 'DictUpdateCheckService',
          );
        }
      });

      _updatableDicts = updatable;
      _lastCheckTime = DateTime.now();
      await _preferencesService.setLastDictUpdateCheckTime(_lastCheckTime!);

      Logger.i(
        '检查完成，发现 ${updatable.length} 个可更新词典',
        tag: 'DictUpdateCheckService',
      );
    } catch (e) {
      Logger.e('检查词典更新失败: $e', tag: 'DictUpdateCheckService');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  void clearUpdate(String dictId) {
    if (_updatableDicts.containsKey(dictId)) {
      _updatableDicts.remove(dictId);
      notifyListeners();
    }
  }

  void clearAllUpdates() {
    _updatableDicts.clear();
    notifyListeners();
  }

  bool hasUpdate(String dictId) {
    return _updatableDicts.containsKey(dictId);
  }

  user_dict.DictUpdateInfo? getUpdateInfo(String dictId) {
    return _updatableDicts[dictId];
  }

  @override
  void dispose() {
    super.dispose();
  }
}
