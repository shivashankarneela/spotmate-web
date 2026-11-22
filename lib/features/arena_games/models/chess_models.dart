import 'package:flutter/foundation.dart';

@immutable
class ChessEloSummary {
  const ChessEloSummary({
    required this.whiteOld,
    required this.whiteNew,
    required this.whiteDelta,
    required this.blackOld,
    required this.blackNew,
    required this.blackDelta,
  });

  final int whiteOld;
  final int whiteNew;
  final int whiteDelta;
  final int blackOld;
  final int blackNew;
  final int blackDelta;

  factory ChessEloSummary.fromJson(Map<String, dynamic> json) {
    return ChessEloSummary(
      whiteOld: (json['white_old'] as num?)?.toInt() ?? 1200,
      whiteNew: (json['white_new'] as num?)?.toInt() ?? 1200,
      whiteDelta: (json['white_delta'] as num?)?.toInt() ?? 0,
      blackOld: (json['black_old'] as num?)?.toInt() ?? 1200,
      blackNew: (json['black_new'] as num?)?.toInt() ?? 1200,
      blackDelta: (json['black_delta'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ChessState {
  const ChessState({
    required this.whiteId,
    required this.blackId,
    required this.fen,
    required this.timeControl,
    required this.clocksMs,
    required this.movesSan,
    required this.inCheck,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.drawOfferBy,
    this.eloSummary,
  });

  final String whiteId;
  final String blackId;
  final String fen;
  final String timeControl;
  final Map<String, int> clocksMs;
  final List<String> movesSan;
  final bool inCheck;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? drawOfferBy;
  final ChessEloSummary? eloSummary;

  /// Parses the piece-placement field of FEN into an 8x8 matrix (rank 8 at row 0 .. rank 1 at row 7).
  List<List<String?>> parseBoard() {
    final placement = fen.split(' ').first;
    final ranks = placement.split('/');
    final grid = List.generate(8, (_) => List<String?>.filled(8, null));
    for (var r = 0; r < 8 && r < ranks.length; r++) {
      var col = 0;
      for (final ch in ranks[r].split('')) {
        final empty = int.tryParse(ch);
        if (empty != null) {
          col += empty;
        } else if (col < 8) {
          grid[r][col] = ch;
          col++;
        }
      }
    }
    return grid;
  }

  factory ChessState.fromJson(Map<String, dynamic> json) {
    final rawClocks = Map<String, dynamic>.from(json['clocks_ms'] ?? const {});
    final lastMove = json['last_move'] is Map
        ? Map<String, dynamic>.from(json['last_move'] as Map)
        : null;

    return ChessState(
      whiteId: (json['white_id'] ?? '').toString(),
      blackId: (json['black_id'] ?? '').toString(),
      fen: (json['fen'] ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1').toString(),
      timeControl: (json['time_control'] ?? '5+3').toString(),
      clocksMs: rawClocks.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 300000)),
      movesSan: List<String>.from(json['moves_san'] ?? const []),
      inCheck: json['in_check'] == true,
      lastMoveFrom: lastMove?['from']?.toString(),
      lastMoveTo: lastMove?['to']?.toString(),
      drawOfferBy: json['draw_offer_by']?.toString(),
      eloSummary: json['elo_summary'] is Map
          ? ChessEloSummary.fromJson(Map<String, dynamic>.from(json['elo_summary'] as Map))
          : null,
    );
  }
}
