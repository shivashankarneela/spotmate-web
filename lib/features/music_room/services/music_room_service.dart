import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/music_room_models.dart';

class MusicRoomService {
  MusicRoomService({SupabaseClient? client, this.roomKind = 'music'})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final String roomKind;
  static const String _fn = 'music-room-engine';

  int _clockSkewMs = 0;
  int get clockSkewMs => _clockSkewMs;
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await _client.functions.invoke(_fn, body: {...body, 'room_kind': roomKind});
    final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
    if (data['server_now_ms'] is num) {
      _clockSkewMs = (data['server_now_ms'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
    }
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return data;
  }

  Future<List<MusicRoom>> listFreeRooms() async {
    final data = await _invoke({'action': 'rooms.list_free'});
    final list = (data['rooms'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => MusicRoom.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<MusicRoom> createFreeRoom({
    required String title,
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'room.create_free',
      'title': title,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    return MusicRoom.fromJson(Map<String, dynamic>.from(data['room'] as Map));
  }

  Future<MusicRoom> createCustomRoom({
    required String title,
    required int durationMinutes, // 30 (5 SC) or 60 (10 SC)
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'room.create_custom',
      'title': title,
      'duration_minutes': durationMinutes,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    return MusicRoom.fromJson(Map<String, dynamic>.from(data['room'] as Map));
  }

  Future<MusicRoom> joinRoom({
    required String roomId,
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'room.join',
      'room_id': roomId,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    return MusicRoom.fromJson(Map<String, dynamic>.from(data['room'] as Map));
  }

  Future<MusicRoom> joinByCode({
    required String roomCode,
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'room.join_by_code',
      'room_code': roomCode.trim().toUpperCase(),
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    return MusicRoom.fromJson(Map<String, dynamic>.from(data['room'] as Map));
  }

  Future<void> joinNextBatchWaitlist({
    required String displayName,
    String? avatarUrl,
  }) async {
    await _invoke({
      'action': 'room.join_waitlist',
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
  }

  Future<void> transferHost(String roomId,String nextHost) async {
    await _invoke({'action':'room.transfer_host','room_id':roomId,'next_host_id':nextHost});
  }

  Future<void> changeTvChannel(String roomId, String videoId) async {
    await _invoke({'action': 'room.change_tv', 'room_id': roomId, 'video_id': videoId});
  }

  Future<void> leaveRoom(String roomId) async {
    await _invoke({'action': 'room.leave', 'room_id': roomId});
  }

  Future<void> inviteBySpotmateOrUserId({
    required String roomId,
    required String identifier,
    required String displayName,
  }) async {
    await _invoke({
      'action': 'room.invite_by_id',
      'room_id': roomId,
      'to_identifier': identifier.trim(),
      'display_name': displayName,
    });
  }

  Future<({MusicRoom? room, List<MusicRoomMember> members})> syncRoomState(String roomId) async {
    final data = await _invoke({'action': 'room.sync_state', 'room_id': roomId});
    final room = data['room'] is Map
        ? MusicRoom.fromJson(Map<String, dynamic>.from(data['room'] as Map))
        : null;
    final members = ((data['members'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => MusicRoomMember.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return (room: room, members: members);
  }

  Future<List<MusicRoomMessage>> fetchRecentMessages(String roomId, {int limit = 40}) async {
    final rows = await _client
        .from('music_room_messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => MusicRoomMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> sendChatOrCommand({
    required String roomId,
    required String displayName,
    required String text,
  }) async {
    await _invoke({
      'action': 'chat.send',
      'room_id': roomId,
      'display_name': displayName,
      'message': text.trim(),
    });
  }

  Future<void> sendEmojiBurst({
    required RealtimeChannel channel,
    required String displayName,
    required String emoji,
  }) async {
    await channel.sendBroadcastMessage(
      event: 'music_emoji',
      payload: {
        'id': '${DateTime.now().microsecondsSinceEpoch}',
        'sender_name': displayName,
        'emoji': emoji,
      },
    );
  }

  RealtimeChannel subscribeToRoom({
    required String roomId,
    required VoidCallback onRoomOrMembersChanged,
    required void Function(MusicRoomMessage msg) onMessage,
    required void Function(MusicEmojiBurst burst) onEmoji,
  }) {
    final channel = _client.channel('music_room_$roomId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'music_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (_) => onRoomOrMembersChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'music_room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => onRoomOrMembersChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'music_room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            onMessage(MusicRoomMessage.fromJson(Map<String, dynamic>.from(payload.newRecord)));
          },
        )
        .onBroadcast(
          event: 'music_emoji',
          callback: (payload) {
            onEmoji(
              MusicEmojiBurst(
                id: (payload['id'] ?? '').toString(),
                senderName: (payload['sender_name'] ?? 'Listener').toString(),
                emoji: (payload['emoji'] ?? '🎵').toString(),
              ),
            );
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
