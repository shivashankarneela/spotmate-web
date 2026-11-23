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
    if (initialReelId == null) {
      final response = await _client.functions.invoke('youtube-reels', body: {
        'tab': tab,
        if (cityTag != null) 'city_tag': cityTag,
      });
      final result = response.data;
      if (result is! Map<String, dynamic>) throw Exception('Could not load YouTube videos.');
      if (result['error'] != null) throw Exception(result['error']);
      final reels = (result['reels'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SpotmateReel.fromJson)
          .toList();
      try {
        final rows = await _client.rpc('youtube_reel_like_states', params: {
          'p_video_ids': reels.map((reel) => reel.youtubeVideoId).toList(),
        }) as List;
        final states = {for (final row in rows) row['video_id'].toString(): row};
        return [for (final reel in reels) reel.copyWith(
          likedByMe: states[reel.youtubeVideoId]?['liked'] == true,
          likesCount: (states[reel.youtubeVideoId]?['likes_count'] as num?)?.toInt() ?? 0,
        )];
      } catch (_) {
        return reels;
      }
    }
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

  Future<void> recordView(String videoId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) return;
    await _client.from('youtube_reel_views').upsert({
      'user_id': userId,
      'video_id': videoId,
      'viewed_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,video_id');
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

  Future<({bool liked, int likesCount})> toggleYouTubeLike(SpotmateReel reel) async {
    final result = await _client.rpc('toggle_youtube_reel_like', params: {
      'p_video_id': reel.youtubeVideoId,
      'p_title': reel.title,
      'p_creator': reel.creatorHandle,
    });
    final data = Map<String, dynamic>.from(result as Map);
    return (liked: data['liked'] == true,
      likesCount: (data['likes_count'] as num?)?.toInt() ?? 0);
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
