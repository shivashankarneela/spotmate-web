import 'call_media.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/sound_helper.dart';
import 'call_host.dart';

class IncomingCallListener extends StatefulWidget {
  const IncomingCallListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener>
    with WidgetsBindingObserver {
  final _client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _auth;
  RealtimeChannel? _channel;
  Timer? _expires;
  String? _userId;
  Map<String, dynamic>? _call;
  Future<Map<String, dynamic>?>? _profile;
  int _refreshVersion = 0;
  bool _answering = false;
  static const _ringWindow = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = _client.auth.onAuthStateChange.listen((_) => _subscribe());
    _subscribe();
  }

  void _subscribe() {
    final userId = _client.auth.currentUser?.id;
    if (userId == _userId) return;
    _userId = userId;
    _refreshVersion++;
    final previous = _channel;
    _channel = null;
    if (previous != null) unawaited(_client.removeChannel(previous));
    _show(null);
    if (userId == null) return;
    _channel = _client.channel('spotmate-incoming-calls-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (_) => unawaited(_refresh()),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_refresh());
          }
        });
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final userId = _userId;
    if (!mounted || userId == null) return;
    final version = ++_refreshVersion;
    try {
      final call = await _client.from('calls')
          .select('id, caller_id, call_type, created_at')
          .eq('receiver_id', userId)
          .eq('status', 'ringing')
          .gte('created_at', DateTime.now().toUtc()
              .subtract(_ringWindow).toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted && version == _refreshVersion) _show(call);
    } catch (_) {
      // Realtime reconnect and app resume retry the lookup.
    }
  }

  void _show(Map<String, dynamic>? call) {
    if (_call?['id'] == call?['id']) return;
    _expires?.cancel();
    setState(() {
      _call = call;
      _profile = call == null ? null : _loadProfile(call['caller_id'] as String);
    });
    if (call == null) {
      SoundHelper.stopRingtone();
      return;
    }
    SoundHelper.playRingtone();
    final created = DateTime.parse(call['created_at'] as String);
    final remaining = created.add(_ringWindow).difference(DateTime.now());
    _expires = Timer(remaining, () {
      if (!mounted) return;
      _show(null);
      unawaited(_refresh());
    });
  }

  Future<Map<String, dynamic>?> _loadProfile(String callerId) async {
    try {
      return await _client.from('user_profiles')
          .select('name, profile_photo')
          .eq('id', callerId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  Future<void> _respond(
    String id, bool accept, bool isVideo, String name, String? photo,
  ) async {
    final receiver = _userId;
    final navigator = widget.navigatorKey.currentState;
    if (_answering || receiver == null || navigator == null ||
        _call?['id'] != id || (accept && ActiveCallManager.session.value != null)) {
      return;
    }
    setState(() => _answering = true);
    MediaStream? media;
    try {
      if (accept) {
        SoundHelper.stopRingtone();
        media = await openCallMedia(isVideo);
        if (!mounted || _call?['id'] != id || receiver != _userId) return;
      }
      final updated = await _client.from('calls')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', id)
          .eq('receiver_id', receiver)
          .eq('status', 'ringing')
          .gte('created_at', DateTime.now().toUtc()
              .subtract(_ringWindow).toIso8601String())
          .select('id')
          .maybeSingle();
      if (!mounted || receiver != _userId) return;
      if (_call?['id'] == id) _show(null);
      if (accept && updated != null && navigator.mounted) {
        if (ActiveCallManager.start(CallSession(
          id: id, name: name, photo: photo, isVideo: isVideo, isCaller: false,
          media: media!,
        ))) {
          media = null;
        } else {
          await _client.from('calls').update({'status': 'ended'})
              .eq('id', id).eq('status', 'accepted');
        }
      }
      unawaited(_refresh());
    } catch (_) {
      if (mounted && receiver == _userId) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          accept && media == null
              ? callPermissionMessage(isVideo)
              : const SnackBar(content: Text('Could not respond to the call. Try again.')),
        );
        unawaited(_refresh());
      }
    } finally {
      if (mounted) setState(() => _answering = false);
      if (media != null) await releaseCallMedia(media);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expires?.cancel();
    SoundHelper.stopRingtone();
    unawaited(_auth.cancel());
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final id = call?['id'] as String?;
    final isVideo = call?['call_type'] == 'video';
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (id != null) Positioned(
          top: MediaQuery.paddingOf(context).top + 10, left: 12, right: 12,
          child: FutureBuilder<Map<String, dynamic>?>(
            key: ValueKey(id), future: _profile,
            builder: (context, snapshot) {
              final name = snapshot.data?['name'] as String? ?? 'SpotMate caller';
              final photo = snapshot.data?['profile_photo'] as String?;
              return Material(color: Colors.white, elevation: 12,
                borderRadius: BorderRadius.circular(18),
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    CircleAvatar(radius: 24, backgroundColor: const Color(0xFFE1F3EB),
                      backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo == null || photo.isEmpty ? const Icon(Icons.person, color: Color(0xFF075E54)) : null),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(isVideo ? 'Incoming video call' : 'Incoming voice call',
                          style: const TextStyle(color: Color(0xFF667781), fontSize: 12)),
                      ])),
                    IconButton.filled(tooltip: 'Decline',
                      style: IconButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _answering ? null : () => _respond(id, false, isVideo, name, photo),
                      icon: const Icon(Icons.call_end, color: Colors.white)),
                    const SizedBox(width: 6),
                    IconButton.filled(tooltip: 'Answer',
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
                      onPressed: _answering || ActiveCallManager.session.value != null
                        ? null : () => _respond(id, true, isVideo, name, photo),
                      icon: Icon(isVideo ? Icons.videocam : Icons.call, color: Colors.white)),
                  ])));
            },
          ),
        ),
      ],
    );
  }
}
