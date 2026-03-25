import 'dart:async';
import 'package:media_kit/media_kit.dart';
import '../core/logger.dart';

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

  /// 安全地释放单个 Player
  Future<void> safeDisposePlayer(Player player) async {
    _activePlayers.remove(player);
    await _safeDisposePlayer(player);
  }

  Future<void> disposeAllPlayers() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    Logger.i('开始清理所有 MediaKit Player 实例...', tag: 'MediaKitManager');

    final playersToDispose = _activePlayers.toList();
    _activePlayers.clear();

    // 先停止所有播放
    final stopFutures = <Future>[];
    for (final player in playersToDispose) {
      stopFutures.add(_safeStopPlayer(player));
    }
    await Future.wait(stopFutures).timeout(
      const Duration(seconds: 1),
      onTimeout: () => [],
    );

    // 短暂延迟，让 native 端完成停止操作
    await Future.delayed(const Duration(milliseconds: 100));

    // 然后释放所有 player
    final disposeFutures = <Future>[];
    for (final player in playersToDispose) {
      disposeFutures.add(_safeDisposePlayer(player));
    }

    await Future.wait(disposeFutures)
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            Logger.w('清理 Player 超时', tag: 'MediaKitManager');
            return [];
          },
        )
        .catchError((e) {
          Logger.w('清理 Player 时出错: $e', tag: 'MediaKitManager');
          return [];
        });

    Logger.i('所有 MediaKit Player 实例已清理 (${playersToDispose.length} 个)', tag: 'MediaKitManager');
    _isCleaningUp = false;
  }

  Future<void> _safeStopPlayer(Player player) async {
    try {
      await player.stop().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    } catch (e) {
      // 忽略
    }
  }

  Future<void> _safeDisposePlayer(Player player) async {
    try {
      await player.dispose().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    } catch (e) {
      // 忽略，native 资源可能已被释放
      Logger.d('释放 Player 时出错: $e', tag: 'MediaKitManager');
    }
  }

  int get activePlayerCount => _activePlayers.length;
  bool get hasActivePlayers => _activePlayers.isNotEmpty;
}
