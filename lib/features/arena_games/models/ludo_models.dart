import 'package:flutter/foundation.dart';

@immutable
class LudoMoveLog {
  const LudoMoveLog({
    required this.userId,
    required this.displayName,
    required this.dice,
    required this.event,
    required this.extraTurn,
    this.tokenIndex,
    this.fromStep,
    this.toStep,
    this.capturedUserId,
  });

  final String userId;
  final String displayName;
  final int dice;
  final int? tokenIndex;
  final int? fromStep;
  final int? toStep;
  final String? capturedUserId;
  final String event;
  final bool extraTurn;

  factory LudoMoveLog.fromJson(Map<String, dynamic> json) {
    return LudoMoveLog(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      dice: (json['dice'] as num?)?.toInt() ?? 1,
      tokenIndex: (json['token_index'] as num?)?.toInt(),
      fromStep: (json['from_step'] as num?)?.toInt(),
      toStep: (json['to_step'] as num?)?.toInt(),
      capturedUserId: json['captured_user_id']?.toString(),
      event: (json['event'] ?? 'moved').toString(),
      extraTurn: json['extra_turn'] == true,
    );
  }
}

@immutable
class LudoState {
  const LudoState({
    required this.seatStarts,
    required this.tokens,
    required this.turnIndex,
    required this.phase,
    required this.legalTokens,
    required this.standings,
    this.diceValue,
    this.lastMove,
  });

  final Map<String, int> seatStarts;
  final Map<String, List<int>> tokens;
  final int turnIndex;
  final String phase; // await_roll | await_token
  final int? diceValue;
  final List<int> legalTokens;
  final LudoMoveLog? lastMove;
  final List<String> standings;

  factory LudoState.fromJson(Map<String, dynamic> json) {
    final rawStarts = Map<String, dynamic>.from(json['seat_starts'] ?? const {});
    final rawTokens = Map<String, dynamic>.from(json['tokens'] ?? const {});

    return LudoState(
      seatStarts: rawStarts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      tokens: rawTokens.map(
        (k, v) => MapEntry(
          k,
          (v as List? ?? const [-1, -1, -1, -1]).map((e) => (e as num).toInt()).toList(),
        ),
      ),
      turnIndex: (json['turn_index'] as num?)?.toInt() ?? 0,
      phase: (json['phase'] ?? 'await_roll').toString(),
      diceValue: (json['dice_value'] as num?)?.toInt(),
      legalTokens: (json['legal_tokens'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
      lastMove: json['last_move'] is Map
          ? LudoMoveLog.fromJson(Map<String, dynamic>.from(json['last_move'] as Map))
          : null,
      standings: List<String>.from(json['standings'] ?? const []),
    );
  }
}
