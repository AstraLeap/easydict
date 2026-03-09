# Android Audio Playback Fix Plan

## Problem Description

On Android, audio pronunciation has two issues:
1. **Opening Stuttering**: At the beginning of playback, there's a brief stutter (sound starts, then briefly mutes, then resumes)
2. **Ending Truncation**: The end of the audio is cut off prematurely

Windows does not have these issues.

## Root Cause Analysis

### Issue 1: Opening Stuttering

Current code in [`_playTtsAudio()`](lib/components/component_renderer.dart:2139) and [`_playAudioInternal()`](lib/components/component_renderer.dart:5656):

```dart
await player.open(Media(audioFile.path), play: false);
await player.play();
```

**Problem**: `player.open()` returns immediately after initiating the open operation, but on Android, the media pipeline may not be fully ready. When `play()` is called immediately after, the audio starts but the buffer may not have enough data cached, causing a brief stutter at the beginning.

### Issue 2: Ending Truncation

Current code uses `player.stream.completed`:

```dart
_playbackCompletionSub = player.stream.completed.listen((completed) async {
  if (!completed) return;
  await Future.delayed(const Duration(milliseconds: 250));
  if (_currentPlayer == player) {
    await _cleanupPlayer();
  }
});
```

**Problem**: The `completed` event fires when the player considers playback "done", but on Android, this may happen slightly before the actual audio finishes playing due to audio pipeline latency. The 250ms delay may not be sufficient on all Android devices.

## Solution

### Fix 1: Wait for Buffer Ready Before Playing

Use `player.stream.buffer` to wait for the buffer to have some data before starting playback:

```dart
// Open media without playing
await player.open(Media(audioFile.path), play: false);

// Wait for buffer to have some data (indicates player is ready)
await for (final buffer in player.stream.buffer) {
  if (buffer.inMilliseconds > 0) {
    break;
  }
}

// Small additional delay for Android audio pipeline to stabilize
await Future.delayed(const Duration(milliseconds: 50));

// Now start playback
await player.play();
```

### Fix 2: Use Duration + Position for Completion Detection

Instead of relying solely on `completed` stream, monitor position relative to duration:

```dart
// Get duration when available
Duration? totalDuration;
player.stream.duration.listen((d) {
  if (d.inMilliseconds > 0) {
    totalDuration = d;
  }
});

// Monitor position for more accurate completion detection
_playbackCompletionSub = player.stream.position.listen((position) async {
  if (totalDuration != null && position >= totalDuration!) {
    // Playback truly finished
    await Future.delayed(const Duration(milliseconds: 300));
    if (_currentPlayer == player) {
      await _cleanupPlayer();
    }
  }
});

// Also keep completed listener as backup
```

### Alternative Simpler Fix

If the above is too complex, a simpler approach:

1. **For opening stuttering**: Add a small delay after `open()` before `play()`
2. **For ending truncation**: Increase the delay from 250ms to 500ms

```dart
await player.open(Media(audioFile.path), play: false);
// Wait for buffer to stabilize on Android
await Future.delayed(const Duration(milliseconds: 100));
await player.play();

// In completion listener
await Future.delayed(const Duration(milliseconds: 500));
```

## Implementation Plan

### Files to Modify

1. [`lib/components/component_renderer.dart`](lib/components/component_renderer.dart)
   - Modify `_playTtsAudio()` method (line 2139)
   - Modify `_playAudioInternal()` method (line 5656)

### Code Changes

#### Change 1: `_playTtsAudio()` method

Replace:
```dart
// 先缓冲到首帧，再显式播放，减少 Android 开头抖动
await player.open(Media(audioFile.path), play: false);
await player.play();
```

With:
```dart
// 先打开媒体，等待缓冲区就绪后再播放，解决 Android 开头抖动
await player.open(Media(audioFile.path), play: false);

// 等待缓冲区有数据，表示播放器已准备好
await for (final buffer in player.stream.buffer) {
  if (buffer.inMilliseconds > 0) {
    break;
  }
}

// 额外短暂延迟确保 Android 音频管道稳定
await Future.delayed(const Duration(milliseconds: 50));
await player.play();
```

#### Change 2: `_playTtsAudio()` completion handling

Replace:
```dart
await Future.delayed(const Duration(milliseconds: 250));
```

With:
```dart
await Future.delayed(const Duration(milliseconds: 500));
```

#### Change 3: `_playAudioInternal()` method

Apply the same changes as above.

## Testing

After implementing the fix:
1. Test on Android device with various audio files
2. Verify no stuttering at the beginning
3. Verify no truncation at the end
4. Test on Windows to ensure no regression
