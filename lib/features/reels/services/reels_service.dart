import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reel_models.dart';

class ReelsService {
  ReelsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await _client.functions.invoke('reels-engine', body: body);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) throw Exception(data['error'].toString());
      return data;
    }
    throw Exception('Unexpected response from reels-engine');
  }

  Future<List<SpotmateReel>> fetchFeed({
    String tab = 'for_you',
    String? cityTag,
    String? initialReelId,
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _invoke({
      'action': 'feed.list',
      'tab': tab,
      if (cityTag != null) 'city_tag': cityTag,
      if (initialReelId != null) 'initial_reel_id': initialReelId,
      'limit': limit,
      'offset': offset,
    });
    final list = (data['reels'] as List<dynamic>? ?? []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(SpotmateReel.fromJson)
        .toList();
  }

  Future<({bool liked, int likesCount})> toggleLike(String reelId) async {
    final data = await _invoke({
      'action': 'reel.toggle_like',
      'reel_id': reelId,
    });
    return (
      liked: data['liked'] == true,
      likesCount: (data['likes_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SharedReelPayload> recordShare({
    required String reelId,
    required String recipientId,
    String? chatThreadId,
    String? note,
  }) async {
    final data = await _invoke({
      'action': 'reel.share',
      'reel_id': reelId,
      'recipient_id': recipientId,
      if (chatThreadId != null) 'chat_thread_id': chatThreadId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    final parsed = SharedReelPayload.tryParse(data['payload'] as Map<String, dynamic>?);
    if (parsed == null) throw Exception('Invalid shared reel payload returned');
    return parsed;
  }
}
