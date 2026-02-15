import 'dart:async';
import 'package:media_kit/media_kit.dart';
import '../logger.dart';

class MediaKitManager {
  static final MediaKitManager _instance = MediaKitManager._internal();
  factory MediaKitManager() => _instance;
  MediaKitManager._internal();

  final Set<Player> _activePlayers = {};
  bool _isCleaningUp = false;

  void registerPlayer(Player player) {
    if (_isCleaningUp) return;
    _activePlayers.add(player);
    Logger.d(
      'Player 已注册，当前活动数量: ${_activePlayers.length}',
      tag: 'MediaKitManager',
    );
  }

  void unregisterPlayer(Player player) {
    _activePlayers.remove(player);
    Logger.d(
      'Player 已注销，当前活动数量: ${_activePlayers.length}',
      tag: 'MediaKitManager',
    );
  }

  Future<void> disposeAllPlayers() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    Logger.i('开始清理所有 MediaKit Player 实例...', tag: 'MediaKitManager');

    final playersToDispose = _activePlayers.toList();
    _activePlayers.clear();

    final futures = <Future>[];
    for (final player in playersToDispose) {
      futures.add(_safeDisposePlayer(player));
    }

    await Future.wait(futures)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            Logger.w('清理 Player 超时', tag: 'MediaKitManager');
            return [];
          },
        )
        .catchError((e) {
          Logger.w('清理 Player 时出错: $e', tag: 'MediaKitManager');
          return [];
        });

    Logger.i('所有 MediaKit Player 实例已清理', tag: 'MediaKitManager');
    _isCleaningUp = false;
  }

  Future<void> _safeDisposePlayer(Player player) async {
    try {
      await player.stop().timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
    } catch (e) {
      // 忽略
    }

    try {
      await player.dispose().timeout(
        const Duration(milliseconds: 200),
        onTimeout: () {},
      );
    } catch (e) {
      // 忽略
    }
  }

  int get activePlayerCount => _activePlayers.length;
  bool get hasActivePlayers => _activePlayers.isNotEmpty;
}
