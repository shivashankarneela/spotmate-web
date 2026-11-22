import 'package:flutter/material.dart';
import '../models/arena_models.dart';
import '../models/chess_models.dart';

/// Screen 3 of the Chess flow:
/// Checkmate / Draw / Timeout settlement showing SC payout, ELO rating delta,
/// 2-player summary with empty circular profile slots, and Rematch / Games Arena buttons.
class ChessVictoryScreen extends StatelessWidget {
  const ChessVictoryScreen({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.onRematch,
    required this.onBackToArena,
  });

  final ArenaMatch match;
  final String currentUserId;
  final VoidCallback onRematch;
  final VoidCallback onBackToArena;

  @override
  Widget build(BuildContext context) {
    final state = ChessState.fromJson(match.state);
    final elo = state.eloSummary;
    final iAmWhite = currentUserId == state.whiteId;
    final isDraw = match.status == 'draw';
    final iWon = match.winnerUserId == currentUserId;

    final myOld = iAmWhite ? (elo?.whiteOld ?? 1200) : (elo?.blackOld ?? 1200);
    final myNew = iAmWhite ? (elo?.whiteNew ?? 1200) : (elo?.blackNew ?? 1200);
    final myDelta = iAmWhite ? (elo?.whiteDelta ?? 0) : (elo?.blackDelta ?? 0);
    final deltaSign = myDelta >= 0 ? '+$myDelta' : '$myDelta';

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 76, color: Color(0xFFF59E0B)),
              const SizedBox(height: 12),
              Text(
                isDraw ? 'Draw!' : (iWon ? 'Checkmate!' : 'Match Over'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                match.winReason ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  match.isFree
                      ? 'Free Match Complete'
                      : (isDraw
                          ? '${match.stakeSc} SC Refunded'
                          : (iWon ? '🏆 +${match.potSc} SC Credited' : 'Pot Awarded to Winner')),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ELO $myOld → $myNew ($deltaSign)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Players',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(height: 10),
              ...match.players.map((p) {
                final isW = p.userId == state.whiteId;
                final oldElo = isW ? (elo?.whiteOld ?? 1200) : (elo?.blackOld ?? 1200);
                final newElo = isW ? (elo?.whiteNew ?? 1200) : (elo?.blackNew ?? 1200);
                final d = isW ? (elo?.whiteDelta ?? 0) : (elo?.blackDelta ?? 0);
                final dStr = d >= 0 ? '+$d' : '$d';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF1F5F9),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          image: (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
                              ? DecorationImage(image: NetworkImage(p.avatarUrl!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: (p.avatarUrl == null || p.avatarUrl!.isEmpty)
                            ? const Icon(Icons.person_outline_rounded, size: 22, color: Color(0xFF94A3B8))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p.displayName} (${isW ? "White" : "Black"})',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Text(
                              'ELO $oldElo → $newElo ($dStr)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: d >= 0 ? const Color(0xFF047857) : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRematch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('REMATCH', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onBackToArena,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFF059669), width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('GAMES ARENA', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
