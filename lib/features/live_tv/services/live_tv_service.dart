import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/live_tv_models.dart';

class LiveTvService {
  LiveTvService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await _client.functions.invoke('live-tv-engine', body: body);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) throw Exception(data['error'].toString());
      return data;
    }
    throw Exception('Unexpected response from live-tv-engine');
  }

  Future<List<LiveTvChannel>> fetchChannels({
    String category = 'All',
    String language = 'All',
    String search = '',
  }) async {
    final data = await _invoke({
      'action': 'channels.list',
      'category': category,
      'language': language,
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    return (data['channels'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(LiveTvChannel.fromJson)
        .toList();
  }

  Future<int> pingViewer(String channelId) async {
    final data = await _invoke({
      'action': 'channel.ping',
      'channel_id': channelId,
    });
    return (data['viewer_count'] as num?)?.toInt() ?? 1;
  }

  Future<List<LiveTvChatMessage>> fetchRecentMessages(String channelId) async {
    final rows = await _client
        .from('spotmate_live_tv_messages')
        .select('*')
        .eq('channel_id', channelId)
        .order('created_at', ascending: false)
        .limit(40);
    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(LiveTvChatMessage.fromJson)
        .toList()
        .reversed
        .toList();
  }

  Future<void> sendChat({
    required String channelId,
    required String displayName,
    String? avatarUrl,
    String? body,
    String? reactionEmoji,
  }) async {
    await _invoke({
      'action': 'chat.send',
      'channel_id': channelId,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (body != null) 'body': body,
      if (reactionEmoji != null) 'reaction_emoji': reactionEmoji,
    });
  }

  RealtimeChannel subscribeToChat({
    required String channelId,
    required void Function(LiveTvChatMessage msg) onMessage,
  }) {
    return _client
        .channel('live-tv-chat-$channelId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'spotmate_live_tv_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'channel_id',
            value: channelId,
          ),
          callback: (payload) {
            onMessage(LiveTvChatMessage.fromJson(payload.newRecord));
          },
        )
        .subscribe();
  }

  Future<void> removeChannel(RealtimeChannel channel) async { await _client.removeChannel(channel); }
}
