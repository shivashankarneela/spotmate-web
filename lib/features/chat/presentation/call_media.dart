import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<MediaStream> openCallMedia(bool isVideo) =>
    navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': isVideo ? {'facingMode': 'user'} : false,
    });

Future<void> releaseCallMedia(MediaStream stream) async {
  for (final track in stream.getTracks()) {
    await track.stop();
  }
  await stream.dispose();
}

SnackBar callPermissionMessage(bool isVideo) {
  final mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);
  return SnackBar(
    content: Text(isVideo
        ? 'Allow microphone and camera access in settings, then try again.'
        : 'Allow microphone access in settings, then try again.'),
    action: mobile ? SnackBarAction(
      label: 'Settings',
      onPressed: () async {
        try {
          await const MethodChannel('spotmate/device_alerts').invokeMethod<void>('appSettings');
        } on PlatformException {
          // The user can open system settings directly.
        } on MissingPluginException {
          // This platform does not expose an app settings shortcut.
        }
      },
    ) : null,
  );
}
