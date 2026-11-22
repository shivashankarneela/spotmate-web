import 'package:flutter/foundation.dart';

@immutable
class SnakesMoveLog {
  const SnakesMoveLog({
    required this.userId,
    required this.displayName,
    required this.dice,
    required this.from,
    required this.landed,
    required this.finalTile,
    required this.event,
    required this.extraTurn,
  });

  final String userId;
  final String displayName;
  final int dice;
  final int from;
  final int landed;
  final int finalTile;
  final String event; // normal | ladder | snake | overshoot | win
  final bool extraTurn;

  factory SnakesMoveLog.fromJson(Map<String, dynamic> json) {
    return SnakesMoveLog(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      dice: (json['dice'] as num?)?.toInt() ?? 1,
      from: (json['from'] as num?)?.toInt() ?? 0,
      landed: (json['landed'] as num?)?.toInt() ?? 0,
      finalTile: (json['final_tile'] as num?)?.toInt() ?? 0,
      event: (json['event'] ?? 'normal').toString(),
      extraTurn: json['extra_turn'] == true,
    );
  }
}

@immutable
class SnakesLaddersState {
  const SnakesLaddersState({
    required this.positions,
    required this.turnIndex,
    required this.snakes,
    required this.ladders,
    required this.standings,
    this.lastDice,
    this.lastMove,
  });

  final Map<String, int> positions;
  final int turnIndex;
  final int? lastDice;
  final SnakesMoveLog? lastMove;
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final List<String> standings;

  factory SnakesLaddersState.fromJson(Map<String, dynamic> json) {
    final rawPos = Map<String, dynamic>.from(json['positions'] ?? const {});
    final rawSnakes = Map<String, dynamic>.from(json['snakes'] ?? const {});
    final rawLadders = Map<String, dynamic>.from(json['ladders'] ?? const {});

    return SnakesLaddersState(
      positions: rawPos.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      turnIndex: (json['turn_index'] as num?)?.toInt() ?? 0,
      lastDice: (json['last_dice'] as num?)?.toInt(),
      lastMove: json['last_move'] is Map
          ? SnakesMoveLog.fromJson(Map<String, dynamic>.from(json['last_move'] as Map))
          : null,
      snakes: rawSnakes.map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
      ladders: rawLadders.map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
      standings: List<String>.from(json['standings'] ?? const []),
    );
  }
}

@immutable
class MatchChatMessage {
  const MatchChatMessage({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.kind,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String kind; // text | emoji
  final String content;
  final DateTime createdAt;

  factory MatchChatMessage.fromJson(Map<String, dynamic> json) {
    return MatchChatMessage(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      kind: (json['kind'] ?? 'text').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

@immutable
class FloatingEmojiEvent {
  const FloatingEmojiEvent({
    required this.id,
    required this.senderName,
    required this.emoji,
  });

  final String id;
  final String senderName;
  final String emoji;
}
