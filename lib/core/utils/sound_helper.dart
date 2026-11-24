import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundHelper {
  static const _platform = MethodChannel('spotmate/device_alerts');
  static AudioPlayer? _ringtone;
  static AudioPlayer? _message;
  static Future<void> _ringQueue = Future.value();

  static Future<bool> _playNative(String action) async {
    try {
      return await _platform.invokeMethod<bool>(action) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static void playNotificationBeep() => unawaited(_playMessage());

  static Future<void> _playMessage() async {
    try {
      if (await _playNative('playMessageSound')) return;
      final player = _message ??= AudioPlayer();
      await player.play(AssetSource('sounds/message.wav'));
    } catch (_) {
      // Browsers can require prior interaction before playing audio.
    }
  }

  static void playMatchChime() => unawaited(SystemSound.play(SystemSoundType.alert));

  static void playRingtone() {
    _ringQueue = _ringQueue.then((_) async {
      try {
        if (await _playNative('playRingtone')) return;
        final player = _ringtone ??= AudioPlayer();
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(AssetSource('sounds/ringtone.wav'));
      } catch (_) {
        // The incoming-call controls remain available without audio.
      }
    });
  }

  static void stopRingtone() {
    _ringQueue = _ringQueue.then((_) async {
      try {
        if (_ringtone != null) await _ringtone!.stop();
        await _platform.invokeMethod<void>('stopRingtone');
      } catch (_) {
        // No platform ringtone is active.
      }
    });
  }
}
