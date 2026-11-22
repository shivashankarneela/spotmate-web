import 'package:flutter/foundation.dart';

@immutable
class CarromCoin {
  const CarromCoin({
    required this.id,
    required this.color,
    required this.x,
    required this.y,
    required this.pocketed,
  });

  final String id;
  final String color; // white | black | queen
  final double x; // 0..1000
  final double y; // 0..1000
  final bool pocketed;

  factory CarromCoin.fromJson(Map<String, dynamic> json) {
    return CarromCoin(
      id: (json['id'] ?? '').toString(),
      color: (json['color'] ?? 'white').toString(),
      x: (json['x'] as num?)?.toDouble() ?? 500.0,
      y: (json['y'] as num?)?.toDouble() ?? 500.0,
      pocketed: json['pocketed'] == true,
    );
  }
}

@immutable
class CarromShotLog {
  const CarromShotLog({
    required this.userId,
    required this.displayName,
    required this.pocketedColors,
    required this.foul,
    required this.queenCovered,
    required this.extraTurn,
  });

  final String userId;
  final String displayName;
  final List<String> pocketedColors;
  final bool foul;
  final bool queenCovered;
  final bool extraTurn;

  factory CarromShotLog.fromJson(Map<String, dynamic> json) {
    return CarromShotLog(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      pocketedColors: List<String>.from(json['pocketed_colors'] ?? const []),
      foul: json['foul'] == true,
      queenCovered: json['queen_covered'] == true,
      extraTurn: json['extra_turn'] == true,
    );
  }
}

@immutable
class CarromState {
  const CarromState({
    required this.teamColor,
    required this.coins,
    required this.turnIndex,
    required this.whitePocketed,
    required this.blackPocketed,
    this.queenHolder,
    this.queenPendingCoverBy,
    this.lastShot,
  });

  final Map<String, String> teamColor;
  final List<CarromCoin> coins;
  final int turnIndex;
  final String? queenHolder;
  final String? queenPendingCoverBy;
  final int whitePocketed;
  final int blackPocketed;
  final CarromShotLog? lastShot;

  factory CarromState.fromJson(Map<String, dynamic> json) {
    final rawTeam = Map<String, dynamic>.from(json['team_color'] ?? const {});
    final rawCoins = (json['coins'] as List?) ?? const [];
    final rawCounts = Map<String, dynamic>.from(json['pocketed_counts'] ?? const {});

    return CarromState(
      teamColor: rawTeam.map((k, v) => MapEntry(k, v.toString())),
      coins: rawCoins
          .whereType<Map>()
          .map((m) => CarromCoin.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      turnIndex: (json['turn_index'] as num?)?.toInt() ?? 0,
      queenHolder: json['queen_holder']?.toString(),
      queenPendingCoverBy: json['queen_pending_cover_by']?.toString(),
      whitePocketed: (rawCounts['white'] as num?)?.toInt() ?? 0,
      blackPocketed: (rawCounts['black'] as num?)?.toInt() ?? 0,
      lastShot: json['last_shot'] is Map
          ? CarromShotLog.fromJson(Map<String, dynamic>.from(json['last_shot'] as Map))
          : null,
    );
  }
}
