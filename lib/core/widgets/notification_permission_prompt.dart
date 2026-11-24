import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/notification_permission.dart';

class NotificationPermissionPrompt extends StatefulWidget {
  const NotificationPermissionPrompt({super.key, required this.child});
  final Widget child;

  @override
  State<NotificationPermissionPrompt> createState() =>
      _NotificationPermissionPromptState();
}

class _NotificationPermissionPromptState extends State<NotificationPermissionPrompt>
    with WidgetsBindingObserver {
  String? _state;
  bool _busy = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final state = await notificationPermission();
    if (mounted && !_busy) setState(() => _state = state);
  }

  Future<void> _request() async {
    if (_busy) return;
    _busy = true;
    try {
      if (_state == 'denied' && !kIsWeb) {
        await openNotificationSettings();
      } else {
        final state = await requestNotifications();
        if (mounted) setState(() => _state = state);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _dismissed = false;
    } else if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = !_dismissed && (_state == 'default' || _state == 'denied');
    final webDenied = kIsWeb && _state == 'denied';
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (show)
          Positioned(
            left: 12, right: 12, top: MediaQuery.paddingOf(context).top + 6,
            child: Material(
              elevation: 5,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                title: const Text('Enable notifications'),
                subtitle: Text(webDenied
                    ? 'Allow notifications in your browser’s site settings.'
                    : 'Get alerts for messages and calls.'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!webDenied)
                    TextButton(
                      onPressed: _request,
                      child: Text(_state == 'denied' ? 'Settings' : 'Allow'),
                    ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => setState(() => _dismissed = true),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
