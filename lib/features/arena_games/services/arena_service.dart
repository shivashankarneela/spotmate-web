import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';

class ArenaService {
  ArenaService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String _fn = 'arena-match-engine';

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await _client.functions.invoke(_fn, body: body);
    final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return data;
  }

  /// Joins the random matchmaking queue for a game + stake (0 SC for Free).
  /// Returns an `ArenaMatch` immediately if paired, or `null` if waiting in queue.
  Future<ArenaMatch?> joinRandomQueue({
    required ArenaGameType gameType,
    required int stakeSc,
    required String displayName,
    String? avatarUrl,
    int playerCount = 2,
  }) async {
    final data = await _invoke({
      'action': 'queue.join',
      'game_type': gameType.id,
      'player_count': playerCount,
      'stake_sc': stakeSc,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    if (data['matched'] == true && data['match'] is Map) {
      return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
    }
    return null;
  }

  Future<void> leaveRandomQueue() async {
    await _invoke({'action': 'queue.leave'});
  }

  Future<ArenaChallenge> createSpotmateIdChallenge({
    required String toSpotmateId,
    required ArenaGameType gameType,
    required int stakeSc,
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'challenge.create',
      'to_spotmate_id': toSpotmateId.trim(),
      'game_type': gameType.id,
      'stake_sc': stakeSc,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    return ArenaChallenge.fromJson(Map<String, dynamic>.from(data['challenge'] as Map));
  }

  Future<ArenaMatch?> respondToChallenge({
    required String challengeId,
    required bool accept,
    required String displayName,
    String? avatarUrl,
  }) async {
    final data = await _invoke({
      'action': 'challenge.respond',
      'challenge_id': challengeId,
      'accept': accept,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    });
    if (accept && data['match'] is Map) {
      return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
    }
    return null;
  }

  Future<ArenaMatch> fetchMatchState(String matchId) async {
    final data = await _invoke({
      'action': 'match.state',
      'match_id': matchId,
    });
    return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
  }

  Future<ArenaMatch> submitMove({
    required String matchId,
    required Map<String, dynamic> movePayload,
  }) async {
    final data = await _invoke({
      'action': 'match.move',
      'match_id': matchId,
      'move_payload': movePayload,
    });
    return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
  }

  Future<ArenaMatch> claimTimeout(String matchId) async {
    final data = await _invoke({
      'action': 'match.claim_timeout',
      'match_id': matchId,
    });
    return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
  }

  Future<ArenaMatch> resignMatch(String matchId) async {
    final data = await _invoke({
      'action': 'match.resign',
      'match_id': matchId,
    });
    return ArenaMatch.fromJson(Map<String, dynamic>.from(data['match'] as Map));
  }

  /// Subscribes to server broadcast events for a live match and re-fetches sanitized state.
  RealtimeChannel subscribeToMatch({
    required String matchId,
    required void Function(ArenaMatch match) onMatchUpdated,
  }) {
    final channel = _client.channel('arena_match_$matchId');
    channel
        .onBroadcast(
          event: 'match_updated',
          callback: (_) async {
            final latest = await fetchMatchState(matchId);
            onMatchUpdated(latest);
          },
        )
        .subscribe();
    return channel;
  }

  /// Listens for when a waiting queue entry gets paired with an opponent.
  RealtimeChannel subscribeToQueueMatch({
    required String userId,
    required void Function(String matchId) onMatched,
  }) {
    final channel = _client.channel('arena_queue_$userId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'arena_matchmaking_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['status'] == 'matched' && record['matched_id'] != null) {
              onMatched(record['matched_id'].toString());
            }
          },
        )
        .subscribe();
    return channel;
  }

  /// Global listener for incoming Spotmate ID challenges (used by ChallengeToastOverlay).
  RealtimeChannel subscribeToIncomingChallenges({
    required String userId,
    required void Function(ArenaChallenge challenge) onChallengeReceived,
  }) {
    final channel = _client.channel('arena_challenges_$userId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'arena_game_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user_id',
            value: userId,
          ),
          callback: (payload) {
            final ch = ArenaChallenge.fromJson(Map<String, dynamic>.from(payload.newRecord));
            if (ch.status == 'pending') {
              onChallengeReceived(ch);
            }
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
