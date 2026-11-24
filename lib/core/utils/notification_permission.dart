import 'package:flutter/services.dart';

import 'notification_permission_stub.dart'
    if (dart.library.js_interop) 'notification_permission_web.dart' as web;

const _platform = MethodChannel('spotmate/device_alerts');

Future<String> notificationPermission() async {
  final state = await web.notificationPermission();
  if (state != 'native') return state;
  try {
    return await _platform.invokeMethod<String>('notificationStatus') ?? 'unsupported';
  } on PlatformException {
    return 'unsupported';
  } on MissingPluginException {
    return 'unsupported';
  }
}

Future<String> requestNotifications() async {
  final state = await web.requestNotifications();
  if (state != 'native') return state;
  try {
    return await _platform.invokeMethod<String>('requestNotifications') ?? 'unsupported';
  } on PlatformException {
    return 'unsupported';
  } on MissingPluginException {
    return 'unsupported';
  }
}

Future<void> openNotificationSettings() async {
  try {
    await _platform.invokeMethod<void>('notificationSettings');
  } on MissingPluginException {
    // Web permissions are managed in the browser's site settings.
  } on PlatformException {
    // Some devices do not expose app-specific settings.
  }
}
