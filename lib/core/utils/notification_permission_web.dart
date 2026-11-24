import 'dart:js_interop';

@JS('spotmateNotificationStatus')
external JSString _status();

@JS('spotmateRequestNotifications')
external JSPromise<JSString> _request();

Future<String> notificationPermission() async => _status().toDart;

Future<String> requestNotifications() async => (await _request().toDart).toDart;
