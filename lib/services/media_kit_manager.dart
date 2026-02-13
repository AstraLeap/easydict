import 'dart:async';
import 'package:media_kit/media_kit.dart';
import '../logger.dart';

/// MediaKit 全局管理器
/// 
/// 用于管理所有 Player 实例，确保在热重启时正确释放资源
/// 避免 "Callback invoked after it has been deleted" 错误
class MediaKitManager {
  static final MediaKitManager _instance = MediaKitManager._internal();
  factory MediaKitManager() => _instance;
  MediaKitManager._internal();

  /// 所有活动的 Player 实例
  final Set<Player> _activePlayers = {};

  /// 是否正在执行全局清理
  bool _isCleaningUp = false;

  /// 注册一个 Player 实例
  void registerPlayer(Player player) {
    if (_isCleaningUp) return;
    _activePlayers.add(player);
    Logger.d('Player 已注册，当前活动数量: ${_activePlayers.length}', tag: 'MediaKitManager');
  }

  /// 注销一个 Player 实例
  void unregisterPlayer(Player player) {
    _activePlayers.remove(player);
    Logger.d('Player 已注销，当前活动数量: ${_activePlayers.length}', tag: 'MediaKitManager');
  }

  /// 安全地释放所有 Player 实例
  /// 
  /// 在热重启或应用退出时调用，确保所有原生资源被正确释放
  Future<void> disposeAllPlayers() async {
    if (_isCleaningUp) return;
    _isCleaningUp = true;

    Logger.i('开始清理所有 MediaKit Player 实例...', tag: 'MediaKitManager');

    final playersToDispose = _activePlayers.toList();
    _activePlayers.clear();

    for (final player in playersToDispose) {
      try {
        // 先停止播放
        await player.stop().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {
            Logger.w('Player 停止超时', tag: 'MediaKitManager');
          },
        );
      } catch (e) {
        // 忽略停止时的错误
      }

      try {
        // 释放资源
        await player.dispose().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {
            Logger.w('Player 释放超时', tag: 'MediaKitManager');
          },
        );
      } catch (e) {
        // 忽略释放时的错误
      }
    }

    Logger.i('所有 MediaKit Player 实例已清理', tag: 'MediaKitManager');
    _isCleaningUp = false;
  }

  /// 获取当前活动的 Player 数量
  int get activePlayerCount => _activePlayers.length;

  /// 检查是否有活动的 Player
  bool get hasActivePlayers => _activePlayers.isNotEmpty;
}

/// 包装 Player 类，自动注册到管理器
class ManagedPlayer {
  Player? _player;
  bool _isDisposed = false;
  final _completer = Completer<void>();

  Player? get player => _player;
  bool get isDisposed => _isDisposed;
  Future<void> get ready => _completer.future;

  ManagedPlayer() {
    _player = Player();
    MediaKitManager().registerPlayer(_player!);
    _completer.complete();
  }

  Future<void> stop() async {
    if (_isDisposed || _player == null) return;
    try {
      await _player!.stop();
    } catch (e) {
      // 忽略错误
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_player != null) {
      MediaKitManager().unregisterPlayer(_player!);
      try {
        await _player!.stop();
      } catch (e) {
        // 忽略错误
      }
      try {
        await _player!.dispose();
      } catch (e) {
        // 忽略错误
      }
      _player = null;
    }
  }
}
