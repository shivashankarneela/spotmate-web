import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_game_models.dart';
import '../plugins/chat_game_plugin.dart';

/// Client service bridging Spotmate chat rooms with the `chat-game-engine` Edge Function
/// and Supabase Realtime updates.
class ChatGameService {
  ChatGameService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String _fnName = 'chat-game-engine';

  Future<ChatGameSession?> fetchActiveSession(String roomId) async {
    final res = await _client.functions.invoke(
      _fnName,
      body: {'action': 'status', 'room_id': roomId},
    );
    final data = res.data as Map<String, dynamic>?;
    final raw = data?['active_session'];
    if (raw is Map<String, dynamic>) {
      return ChatGameSession.fromJson(raw);
    }
    return null;
  }

  Future<ChatGameSession> startGame({
    required String roomId,
    required ChatGameType gameType,
    String? difficulty,
  }) async {
    final user = _client.auth.currentUser;
    final res = await _client.functions.invoke(
      _fnName,
      body: {
        'action': 'start',
        'room_id': roomId,
        'game_type': gameType.id,
        if (difficulty != null) 'difficulty': difficulty,
        if (user != null) 'user_id': user.id,
      },
    );

    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['session'] is Map) {
      return ChatGameSession.fromJson(Map<String, dynamic>.from(data['session'] as Map));
    }
    if (data['active_session'] is Map) {
      return ChatGameSession.fromJson(Map<String, dynamic>.from(data['active_session'] as Map));
    }
    throw Exception(data['error'] ?? 'Failed to start game');
  }

  /// Hook this directly into your chat room's `sendMessage` pipeline.
  /// It filters messages via the active plugin before calling the server.
  Future<Map<String, dynamic>?> submitGuessIfEligible({
    required ChatGameSession activeSession,
    required String messageText,
    required String displayName,
  }) async {
    if (!activeSession.isActive) return null;

    final plugin = ChatGamePluginRegistry.of(activeSession.gameType);
    if (!plugin.shouldInspectMessage(messageText)) return null;

    final user = _client.auth.currentUser;
    if (user == null) return null;

    final res = await _client.functions.invoke(
      _fnName,
      body: {
        'action': 'guess',
        'room_id': activeSession.roomId,
        'guess': messageText.trim(),
        'user_id': user.id,
        'display_name': displayName,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> requestHint(String roomId) async {
    await _client.functions.invoke(
      _fnName,
      body: {'action': 'hint', 'room_id': roomId},
    );
  }

  Future<void> expireSession(String roomId) async {
    await _client.functions.invoke(
      _fnName,
      body: {'action': 'timeout', 'room_id': roomId},
    );
  }

  /// Subscribes to live session updates for a specific city/public chat room.
  RealtimeChannel subscribeToRoomGame({
    required String roomId,
    required void Function(ChatGameSession? session) onUpdate,
  }) {
    final channel = _client.channel('chat_game_$roomId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_game_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) async {
            final latest = await fetchActiveSession(roomId);
            onUpdate(latest);
          },
        )
        .subscribe();
    return channel;
  }

  Future<List<ChatGameLeaderboardEntry>> fetchRoomLeaderboard(
    String roomId, {
    int limit = 10,
  }) async {
    final rows = await _client
        .from('chat_game_leaderboard')
        .select()
        .eq('room_id', roomId)
        .order('wins', ascending: false)
        .order('total_sc_earned', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => ChatGameLeaderboardEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
