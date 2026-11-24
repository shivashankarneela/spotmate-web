import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps presence on the room's existing realtime topic while its screens change.
class RoomPresence with WidgetsBindingObserver {
  RoomPresence._(this._client, this.roomId, this.isCity, this._userId) {
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    _auth = _client.auth.onAuthStateChange.listen((_) {
      if (_client.auth.currentUser?.id != _userId) close();
    });
    channel = _client
        .channel('hotspot-chat-$roomId')
        .onPresenceSync((_) {
          for (final listener in _listeners.toList()) {
            listener.onRosterChanged();
          }
        })
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            for (final listener in _listeners.toList()) {
              listener.onTyping(payload);
            }
          },
        )
        .subscribe((status, _) {
          _subscribed = status == RealtimeSubscribeStatus.subscribed;
          if (_subscribed && !_closed) {
            _schedulePublish();
            _syncCityPresence(_foreground);
          }
        });
  }

  static final _rooms = <String, RoomPresence>{};

  static RoomPresence attach({
    required SupabaseClient client,
    required String roomId,
    required bool isCity,
    required RoomPresenceListener listener,
  }) {
    // The server admits only one community room membership at a time.
    for (final room in _rooms.values.toList()) {
      if (room._userId != client.auth.currentUser?.id ||
          (!isCity && !room.isCity && room.roomId != roomId)) {
        room.close();
      }
    }
    final room = _rooms.putIfAbsent(
      roomId,
      () => RoomPresence._(client, roomId, isCity, client.auth.currentUser?.id),
    );
    room._listeners.add(listener);
    return room;
  }

  static void leave(String roomId) => _rooms[roomId]?.close();

  static void leaveCommunityRooms() {
    for (final room in _rooms.values.where((room) => !room.isCity).toList()) {
      room.close();
    }
  }

  final SupabaseClient _client;
  final String roomId;
  final bool isCity;
  final String? _userId;
  final _listeners = <RoomPresenceListener>{};
  late final StreamSubscription<AuthState> _auth;
  late final RealtimeChannel channel;
  Map<String, dynamic>? _payload;
  Future<void> _publishQueue = Future.value();
  bool _subscribed = false;
  bool _foreground = true;
  bool _closed = false;

  Timer? _cityHeartbeat;
  Future<void> _cityQueue = Future.value();

  void _syncCityPresence(bool present) {
    if (!isCity) return;
    _cityHeartbeat?.cancel();
    _writeCityPresence(present);
    if (present) {
      _cityHeartbeat = Timer.periodic(
        const Duration(seconds: 30), (_) => _writeCityPresence(true),
      );
    }
  }

  void _writeCityPresence(bool present) {
    _cityQueue = _cityQueue.then((_) async {
      if (_client.auth.currentUser?.id != _userId) return;
      try {
        await _client.rpc('set_city_presence', params: {
          'p_room': roomId,
          'p_present': present,
        });
      } catch (_) {
        // The lease expires if the server cannot be reached.
      }
    });
  }

  void detach(RoomPresenceListener listener) {
    _listeners.remove(listener);
    if (!_foreground && _listeners.isEmpty) close();
  }

  Future<ChannelResponse> publish(Map<String, dynamic> payload) {
    _payload = payload;
    return _schedulePublish();
  }

  Future<ChannelResponse> _schedulePublish() {
    final operation = _publishQueue.then((_) async {
      if (_closed || !_subscribed) return ChannelResponse.ok;
      final payload = _payload;
      if (!_foreground) return channel.untrack();
      if (payload == null) return ChannelResponse.ok;
      return channel.track(payload);
    });
    _publishQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground && _listeners.isEmpty) {
      close();
    } else {
      _schedulePublish();
      _syncCityPresence(foreground);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _syncCityPresence(false);
    _rooms.remove(roomId);
    _listeners.clear();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth.cancel());
    unawaited(_client.removeChannel(channel));
  }
}

class RoomPresenceListener {
  const RoomPresenceListener({
    required this.onRosterChanged,
    required this.onTyping,
  });

  final VoidCallback onRosterChanged;
  final ValueChanged<Map<String, dynamic>> onTyping;
}
