import 'package:flutter/services.dart';

class SoundHelper {
  static void playNotificationBeep() {
    SystemSound.play(SystemSoundType.click);
  }

  static void playMatchChime() {
    SystemSound.play(SystemSoundType.alert);
  }

  static void playRingtone() {
    SystemSound.play(SystemSoundType.alert);
  }
}
