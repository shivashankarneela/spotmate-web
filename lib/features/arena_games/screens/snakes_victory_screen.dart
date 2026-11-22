import 'package:flutter/material.dart';
import '../models/arena_models.dart';
import '../models/snakes_models.dart';

/// Screen 3 of the Snakes & Ladders flow:
/// Game End & SC Settlement showing trophy, winner payout, 1st-4th standings
/// with empty circular profile photo slots, and Rematch / Games Arena actions.
class SnakesVictoryScreen extends StatelessWidget {
  const SnakesVictoryScreen({
    super.key,
    required this.match,
    required this.onRematch,
    required this.onBackToArena,
  });

  final ArenaMatch match;
  final VoidCallback onRematch;
  final VoidCallback onBackToArena;

  @override
  Widget build(BuildContext context) {
    final state = SnakesLaddersState.fromJson(match.state);
    final orderedIds = state.standings.isNotEmpty
        ? state.standings
        : match.players.map((p) => p.userId).toList();

    final winner = match.players.firstWhere(
      (p) => p.userId == match.winnerUserId,
      orElse: () => match.players.first,
    );

    const rankLabels = ['1st', '2nd', '3rd', '4th'];

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
                '${winner.displayName} Wins!',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                match.winReason ?? 'Reached 100!',
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
                      : '🏆 +${match.potSc} SC Credited',
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
                  'Final Standings',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                ),
              ),
              const SizedBox(height: 10),

              // 1st - 4th Leaderboard with empty circular profile photo slots
              Expanded(
                child: ListView.separated(
                  itemCount: orderedIds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final uid = orderedIds[idx];
                    final player = match.players.firstWhere(
                      (p) => p.userId == uid,
                      orElse: () => match.players.first,
                    );
                    final tile = state.positions[uid] ?? 0;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: idx == 0 ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                          width: idx == 0 ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              idx < rankLabels.length ? rankLabels[idx] : '${idx + 1}th',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: idx == 0 ? const Color(0xFFB45309) : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFF1F5F9),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              image: (player.avatarUrl != null && player.avatarUrl!.isNotEmpty)
                                  ? DecorationImage(
                                      image: NetworkImage(player.avatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: (player.avatarUrl == null || player.avatarUrl!.isEmpty)
                                ? const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF94A3B8))
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              player.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                          Text(
                            'Tile $tile',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
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
