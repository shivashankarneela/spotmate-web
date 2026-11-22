import 'package:flutter/material.dart';
import '../models/arena_models.dart';

/// Full playable 1v1 Hand Cricket (Super Over) board styled for Spotmate's Warm Paper theme.
/// Uses classic Indian Hand Cricket gestures (1-5 fingers, 👍 thumbs-up for 6).
class HandCricketBoard extends StatelessWidget {
  const HandCricketBoard({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.submitting,
    required this.onPickNumber,
  });

  final ArenaMatch match;
  final String currentUserId;
  final bool submitting;
  final void Function(int number) onPickNumber;

  static const Map<int, String> _handCue = {
    1: '☝️',
    2: '✌️',
    3: '🤟',
    4: '🖖',
    5: '🖐️',
    6: '👍', // Classic Indian Hand Cricket gesture for 6
  };

  @override
  Widget build(BuildContext context) {
    final hc = match.handCricketState;
    final batter = match.players.firstWhere(
      (p) => p.userId == hc.batterId,
      orElse: () => match.players.first,
    );
    final bowler = match.players.firstWhere(
      (p) => p.userId == hc.bowlerId,
      orElse: () => match.players.last,
    );

    final iAmBatting = currentUserId == hc.batterId;
    final iLocked = hc.myPick != null;
    final opponentId = match.players
        .firstWhere((p) => p.userId != currentUserId, orElse: () => bowler)
        .userId;
    final opponentLocked = hc.lockedPlayers.contains(opponentId);
    final batterScore = hc.scores[hc.batterId] ?? 0;
    final batterWickets = hc.wickets[hc.batterId] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          // Scoreboard Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF047857),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'INNINGS ${hc.innings} • BALL ${hc.ball}/${hc.maxBalls}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  hc.target != null
                      ? 'SCORE $batterScore/$batterWickets • TARGET ${hc.target}'
                      : 'SCORE $batterScore/$batterWickets',
                  style: const TextStyle(
                    color: Color(0xFFFEF08A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Players Versus Row
          Row(
            children: [
              Expanded(
                child: _PlayerPill(
                  name: batter.displayName,
                  role: 'Batting',
                  score: hc.scores[batter.userId] ?? 0,
                  isLocked: hc.lockedPlayers.contains(batter.userId),
                  accent: const Color(0xFF059669),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF475569),
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: _PlayerPill(
                  name: bowler.displayName,
                  role: 'Bowling',
                  score: hc.scores[bowler.userId] ?? 0,
                  isLocked: hc.lockedPlayers.contains(bowler.userId),
                  accent: const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Center Clash Arena
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: hc.lastBall == null
                ? Column(
                    children: [
                      const Text('🏏', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(
                        iAmBatting
                            ? 'You are BATTING! Pick 1–6 to score runs.'
                            : 'You are BOWLING! Match the batter to get them OUT.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: hc.lastBall!.isOut
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          hc.lastBall!.isOut
                              ? 'OUT! WICKET!'
                              : '+${hc.lastBall!.runs} RUN${hc.lastBall!.runs == 1 ? "" : "S"}!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ClashHand(
                            label: 'Batter',
                            number: hc.lastBall!.batterPick,
                            emoji: _handCue[hc.lastBall!.batterPick] ?? '🖐️',
                          ),
                          const Text(
                            '⚡',
                            style: TextStyle(fontSize: 26),
                          ),
                          _ClashHand(
                            label: 'Bowler',
                            number: hc.lastBall!.bowlerPick,
                            emoji: _handCue[hc.lastBall!.bowlerPick] ?? '🖐️',
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Status Prompt + 1-6 Number Buttons
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !match.isActive
                      ? (match.winReason ?? 'Match finished')
                      : iLocked
                          ? 'Locked ${_handCue[hc.myPick]} (${hc.myPick}) — waiting for opponent...'
                          : opponentLocked
                              ? 'Opponent locked! ${iAmBatting ? "Pick your shot!" : "Pick your delivery!"}'
                              : (iAmBatting ? 'Pick your shot (1–6)' : 'Pick your delivery (1–6)'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var n = 1; n <= 6; n++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: n < 6 ? 6 : 0),
                          child: ElevatedButton(
                            onPressed: (!match.isActive || iLocked || submitting)
                                ? null
                                : () => onPickNumber(n),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hc.myPick == n
                                  ? const Color(0xFF047857)
                                  : (n == 6 ? const Color(0xFFD97706) : const Color(0xFF0F172A)),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_handCue[n]!, style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  '$n',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({
    required this.name,
    required this.role,
    required this.score,
    required this.isLocked,
    required this.accent,
  });

  final String name;
  final String role;
  final int score;
  final bool isLocked;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isLocked ? accent : const Color(0xFFE2E8F0), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              if (isLocked)
                Icon(Icons.check_circle_rounded, size: 16, color: accent),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '$role • $score runs',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
          ),
        ],
      ),
    );
  }
}

class _ClashHand extends StatelessWidget {
  const _ClashHand({
    required this.label,
    required this.number,
    required this.emoji,
  });

  final String label;
  final int number;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 42)),
        const SizedBox(height: 4),
        Text(
          '$label: $number',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}
