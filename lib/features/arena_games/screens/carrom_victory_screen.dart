import 'package:flutter/material.dart';
import '../models/arena_models.dart';
import '../models/carrom_models.dart';

/// Screen 3 of the Carrom flow:
/// Board Cleared & SC Settlement with golden trophy, Queen status,
/// player summary with empty circular profile photo slots, and Rematch / Games Arena buttons.
class CarromVictoryScreen extends StatelessWidget {
  const CarromVictoryScreen({
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
    final state = CarromState.fromJson(match.state);
    final iWon = match.winnerUserId == currentUserId;

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
                iWon ? 'You Win!' : 'Match Over',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                match.winReason ?? 'Board Cleared!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: Color(0xFF475569)),
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
                      : (iWon ? '🏆 +${match.potSc} SC Credited' : 'Pot Awarded to Winner'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(height: 26),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Players',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(height: 10),
              ...match.players.map((p) {
                final col = state.teamColor[p.userId] ?? 'white';
                final coins = col == 'white' ? state.whitePocketed : state.blackPocketed;
                final hasQueen = state.queenHolder == col;
                final isWinner = p.userId == match.winnerUserId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isWinner ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                      width: isWinner ? 1.5 : 1,
                    ),
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
                              p.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Text(
                              '$coins/9 ${col == "white" ? "White" : "Black"}${hasQueen ? " + Queen" : ""}',
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                      ),
                      if (!match.isFree)
                        Text(
                          isWinner ? '+${match.potSc} SC' : '-${match.stakeSc} SC',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: isWinner ? const Color(0xFF047857) : const Color(0xFFDC2626),
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
