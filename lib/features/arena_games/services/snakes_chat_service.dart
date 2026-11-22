import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/snakes_models.dart';

/// Handles in-game text chat (persisted in `arena_match_messages`) and
/// instant floating emoji reactions (Supabase Realtime broadcast) for any Arena match.
class MatchChatService {
  MatchChatService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<MatchChatMessage>> fetchRecentMessages(String matchId, {int limit = 25}) async {
    final rows = await _client
        .from('arena_match_messages')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => MatchChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> sendTextMessage({
    required String matchId,
    required String displayName,
    required String text,
  }) async {
    final trimmed = text.trim();
    final uid = _client.auth.currentUser?.id;
    if (trimmed.isEmpty || uid == null) return;

    await _client.from('arena_match_messages').insert({
      'match_id': matchId,
      'user_id': uid,
      'display_name': displayName,
      'kind': 'text',
      'content': trimmed.length > 180 ? trimmed.substring(0, 180) : trimmed,
    });
  }

  Future<void> sendEmojiReaction({
    required RealtimeChannel channel,
    required String matchId,
    required String displayName,
    required String emoji,
  }) async {
    await channel.sendBroadcastMessage(
      event: 'emoji_burst',
      payload: {
        'id': '${DateTime.now().microsecondsSinceEpoch}',
        'sender_name': displayName,
        'emoji': emoji,
      },
    );
  }

  RealtimeChannel subscribeToMatchChat({
    required String matchId,
    required void Function(MatchChatMessage message) onMessage,
    required void Function(FloatingEmojiEvent emoji) onEmoji,
  }) {
    final channel = _client.channel('arena_chat_$matchId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'arena_match_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: matchId,
          ),
          callback: (payload) {
            onMessage(
              MatchChatMessage.fromJson(Map<String, dynamic>.from(payload.newRecord)),
            );
          },
        )
        .onBroadcast(
          event: 'emoji_burst',
          callback: (payload) {
            onEmoji(
              FloatingEmojiEvent(
                id: (payload['id'] ?? '').toString(),
                senderName: (payload['sender_name'] ?? 'Player').toString(),
                emoji: (payload['emoji'] ?? '😂').toString(),
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
