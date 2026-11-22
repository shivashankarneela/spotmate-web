import 'package:flutter/foundation.dart';

enum ArenaGameType {
  handCricket('hand_cricket', 'Hand Cricket', '1v1 • Super Over', true),
  snakesLadders('snakes_ladders', 'Snakes & Ladders', '2–4p • Dice Race', true),
  ludo('ludo', 'Ludo', '2–4p • Classic Board', true),
  chess('chess', 'Chess', '1v1 • 5+3 Blitz + ELO', true),
  carrom('carrom', 'Carrom', '1v1 / 2v2 • Striker', true);

  const ArenaGameType(this.id, this.title, this.subtitle, this.enabledInPhase1);

  final String id;
  final String title;
  final String subtitle;
  final bool enabledInPhase1;

  static ArenaGameType fromId(String id) {
    return ArenaGameType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ArenaGameType.handCricket,
    );
  }
}

@immutable
class ArenaPlayerMeta {
  const ArenaPlayerMeta({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;

  factory ArenaPlayerMeta.fromJson(Map<String, dynamic> json) {
    return ArenaPlayerMeta(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}

@immutable
class ArenaChallenge {
  const ArenaChallenge({
    required this.id,
    required this.fromUserId,
    required this.fromName,
    required this.toUserId,
    required this.toSpotmateId,
    required this.gameType,
    required this.stakeSc,
    required this.status,
    required this.expiresAt,
    this.fromAvatarUrl,
    this.matchId,
  });

  final String id;
  final String fromUserId;
  final String fromName;
  final String? fromAvatarUrl;
  final String toUserId;
  final String toSpotmateId;
  final ArenaGameType gameType;
  final int stakeSc;
  final String status;
  final DateTime expiresAt;
  final String? matchId;

  bool get isFree => stakeSc <= 0;

  factory ArenaChallenge.fromJson(Map<String, dynamic> json) {
    return ArenaChallenge(
      id: (json['id'] ?? '').toString(),
      fromUserId: (json['from_user_id'] ?? '').toString(),
      fromName: (json['from_name'] ?? 'Player').toString(),
      fromAvatarUrl: json['from_avatar_url']?.toString(),
      toUserId: (json['to_user_id'] ?? '').toString(),
      toSpotmateId: (json['to_spotmate_id'] ?? '').toString(),
      gameType: ArenaGameType.fromId((json['game_type'] ?? 'hand_cricket').toString()),
      stakeSc: (json['stake_sc'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'pending').toString(),
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()) ?? DateTime.now(),
      matchId: json['match_id']?.toString(),
    );
  }
}

@immutable
class HandCricketBall {
  const HandCricketBall({
    required this.innings,
    required this.ball,
    required this.batterId,
    required this.bowlerId,
    required this.batterPick,
    required this.bowlerPick,
    required this.isOut,
    required this.runs,
  });

  final int innings;
  final int ball;
  final String batterId;
  final String bowlerId;
  final int batterPick;
  final int bowlerPick;
  final bool isOut;
  final int runs;

  factory HandCricketBall.fromJson(Map<String, dynamic> json) {
    return HandCricketBall(
      innings: (json['innings'] as num?)?.toInt() ?? 1,
      ball: (json['ball'] as num?)?.toInt() ?? 1,
      batterId: (json['batter_id'] ?? '').toString(),
      bowlerId: (json['bowler_id'] ?? '').toString(),
      batterPick: (json['batter_pick'] as num?)?.toInt() ?? 0,
      bowlerPick: (json['bowler_pick'] as num?)?.toInt() ?? 0,
      isOut: json['is_out'] == true,
      runs: (json['runs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class HandCricketState {
  const HandCricketState({
    required this.innings,
    required this.ball,
    required this.maxBalls,
    required this.batterId,
    required this.bowlerId,
    required this.scores,
    required this.wickets,
    required this.lockedPlayers,
    required this.history,
    this.target,
    this.myPick,
    this.lastBall,
  });

  final int innings;
  final int ball;
  final int maxBalls;
  final String batterId;
  final String bowlerId;
  final Map<String, int> scores;
  final Map<String, int> wickets;
  final int? target;
  final List<String> lockedPlayers;
  final int? myPick;
  final HandCricketBall? lastBall;
  final List<HandCricketBall> history;

  factory HandCricketState.fromJson(Map<String, dynamic> json) {
    final rawScores = Map<String, dynamic>.from(json['scores'] ?? const {});
    final rawWickets = Map<String, dynamic>.from(json['wickets'] ?? const {});
    final rawHistory = (json['history'] as List?) ?? const [];

    return HandCricketState(
      innings: (json['innings'] as num?)?.toInt() ?? 1,
      ball: (json['ball'] as num?)?.toInt() ?? 1,
      maxBalls: (json['max_balls'] as num?)?.toInt() ?? 6,
      batterId: (json['batter_id'] ?? '').toString(),
      bowlerId: (json['bowler_id'] ?? '').toString(),
      scores: rawScores.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      wickets: rawWickets.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      target: (json['target'] as num?)?.toInt(),
      lockedPlayers: List<String>.from(json['locked_players'] ?? const []),
      myPick: (json['my_pick'] as num?)?.toInt(),
      lastBall: json['last_ball'] is Map
          ? HandCricketBall.fromJson(Map<String, dynamic>.from(json['last_ball'] as Map))
          : null,
      history: rawHistory
          .whereType<Map>()
          .map((m) => HandCricketBall.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

@immutable
class ArenaMatch {
  const ArenaMatch({
    required this.id,
    required this.gameType,
    required this.sourceMode,
    required this.stakeSc,
    required this.potSc,
    required this.players,
    required this.state,
    required this.turnExpiresAt,
    required this.status,
    this.turnUserId,
    this.winnerUserId,
    this.winReason,
  });

  final String id;
  final ArenaGameType gameType;
  final String sourceMode;
  final int stakeSc;
  final int potSc;
  final List<ArenaPlayerMeta> players;
  final Map<String, dynamic> state;
  final String? turnUserId;
  final DateTime turnExpiresAt;
  final String status; // active | completed | draw | forfeit | cancelled
  final String? winnerUserId;
  final String? winReason;

  bool get isActive => status == 'active';
  bool get isFree => stakeSc <= 0;

  HandCricketState get handCricketState => HandCricketState.fromJson(state);

  factory ArenaMatch.fromJson(Map<String, dynamic> json) {
    final rawPlayers = (json['players_meta'] as List?) ?? const [];
    return ArenaMatch(
      id: (json['id'] ?? '').toString(),
      gameType: ArenaGameType.fromId((json['game_type'] ?? 'hand_cricket').toString()),
      sourceMode: (json['source_mode'] ?? 'random_queue').toString(),
      stakeSc: (json['stake_sc'] as num?)?.toInt() ?? 0,
      potSc: (json['pot_sc'] as num?)?.toInt() ?? 0,
      players: rawPlayers
          .whereType<Map>()
          .map((m) => ArenaPlayerMeta.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      state: Map<String, dynamic>.from(json['state'] ?? const {}),
      turnUserId: json['turn_user_id']?.toString(),
      turnExpiresAt:
          DateTime.tryParse((json['turn_expires_at'] ?? '').toString()) ?? DateTime.now(),
      status: (json['status'] ?? 'active').toString(),
      winnerUserId: json['winner_user_id']?.toString(),
      winReason: json['win_reason']?.toString(),
    );
  }
}
