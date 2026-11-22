import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../services/arena_service.dart';
import '../widgets/hand_cricket_board.dart';
import '../widgets/snakes_ladders_board.dart';
import '../widgets/ludo_board.dart';
import '../widgets/chess_board.dart';
import '../widgets/carrom_board.dart';

/// Shared match wrapper hosting turn countdown, SC pot badge, Realtime sync,
/// timeout forfeit claim, resign action, and the active game board widget.
class MatchShellScreen extends StatefulWidget {
  const MatchShellScreen({super.key, required this.initialMatch});

  final ArenaMatch initialMatch;

  @override
  State<MatchShellScreen> createState() => _MatchShellScreenState();
}

class _MatchShellScreenState extends State<MatchShellScreen> {
  final _service = ArenaService();
  late ArenaMatch _match;
  RealtimeChannel? _channel;
  Timer? _clock;
  int _secondsLeft = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _match = widget.initialMatch;
    _startClock();
    _channel = _service.subscribeToMatch(
      matchId: _match.id,
      onMatchUpdated: (updated) {
        if (!mounted) return;
        setState(() => _match = updated);
        _startClock();
      },
    );
  }

  void _startClock() {
    _clock?.cancel();
    _updateSecondsLeft();
    if (!_match.isActive) return;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateSecondsLeft();
    });
  }

  void _updateSecondsLeft() {
    final diff = _match.turnExpiresAt.difference(DateTime.now()).inSeconds;
    setState(() => _secondsLeft = diff > 0 ? diff : 0);
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (_channel != null) {
      _service.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _submitHandCricketPick(int pick) async {
    setState(() => _submitting = true);
    try {
      final updated = await _service.submitMove(
        matchId: _match.id,
        movePayload: {'pick': pick},
      );
      if (!mounted) return;
      setState(() {
        _match = updated;
        _submitting = false;
      });
      _startClock();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _claimTimeout() async {
    try {
      final updated = await _service.claimTimeout(_match.id);
      if (mounted) setState(() => _match = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmResign() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resign Match?'),
        content: Text(
          _match.isFree
              ? 'Your opponent will win this free match.'
              : 'You will forfeit your ${_match.stakeSc} SC stake to your opponent.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Stay')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (yes == true) {
      final updated = await _service.resignMatch(_match.id);
      if (mounted) setState(() => _match = updated);
    }
  }


  Future<void> _submitPayload(Map<String, dynamic> payload) async {
    if (_submitting || !_match.isActive) return;
    setState(() => _submitting = true);
    try {
      final updated = await _service.submitMove(matchId: _match.id, movePayload: payload);
      if (!mounted) return;
      setState(() => _match = updated);
      _startClock();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildActiveBoard(String uid) {
    final myMeta = _match.players.firstWhere(
      (p) => p.userId == uid,
      orElse: () => ArenaPlayerMeta(userId: uid, displayName: 'Player'),
    );
    switch (_match.gameType) {
      case ArenaGameType.handCricket:
        return HandCricketBoard(
          match: _match,
          currentUserId: uid,
          submitting: _submitting,
          onPickNumber: _submitHandCricketPick,
        );
      case ArenaGameType.snakesLadders:
        return SnakesLaddersBoard(
          match: _match,
          currentUserId: uid,
          currentDisplayName: myMeta.displayName,
          rolling: _submitting,
          onRollDice: () => _submitPayload({'action': 'roll'}),
        );
      case ArenaGameType.ludo:
        return LudoBoard(
          match: _match,
          currentUserId: uid,
          currentDisplayName: myMeta.displayName,
          busy: _submitting,
          onRollDice: () => _submitPayload({'action': 'roll'}),
          onSelectToken: (idx) => _submitPayload({'action': 'move', 'token_index': idx}),
        );
      case ArenaGameType.chess:
        return ChessBoard(
          match: _match,
          currentUserId: uid,
          currentDisplayName: myMeta.displayName,
          busy: _submitting,
          onMove: (from, to, {String promotion = 'q'}) => _submitPayload({
            'action': 'move',
            'from': from,
            'to': to,
            'promotion': promotion,
          }),
          onOfferDraw: () => _submitPayload({'action': 'offer_draw'}),
          onRespondDraw: (accept) => _submitPayload({
            'action': accept ? 'accept_draw' : 'decline_draw',
          }),
          onResign: _confirmResign,
        );
      case ArenaGameType.carrom:
        return CarromBoard(
          match: _match,
          currentUserId: uid,
          currentDisplayName: myMeta.displayName,
          busy: _submitting,
          onShoot: ({
            required double strikerX,
            required double angleRad,
            required double power,
          }) => _submitPayload({
            'action': 'shoot',
            'striker_x': strikerX,
            'angle_rad': angleRad,
            'power': power,
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _service.currentUserId ?? '';
    final iWon = _match.winnerUserId == uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        title: Row(
          children: [
            Text(
              _match.gameType.title,
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _match.isFree ? const Color(0xFFE2E8F0) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _match.isFree ? 'FREE' : 'POT: ${_match.potSc} SC',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _match.isFree ? const Color(0xFF334155) : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_match.isActive) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${_secondsLeft}s',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _secondsLeft <= 4 ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _confirmResign,
              tooltip: 'Resign',
              icon: const Icon(Icons.flag_outlined, color: Color(0xFFDC2626)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_match.isActive && _secondsLeft == 0)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Turn timer expired.',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(
                    onPressed: _claimTimeout,
                    child: const Text('Claim Timeout Win'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildActiveBoard(uid),
          ),
          if (!_match.isActive)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _match.status == 'draw'
                      ? const Color(0xFFE0F2FE)
                      : (iWon ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _match.status == 'draw'
                          ? '🤝 Match Drawn!'
                          : (iWon ? '🏆 You Won!' : 'Match Over'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _match.winReason ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    if (!_match.isFree) ...[
                      const SizedBox(height: 4),
                      Text(
                        _match.status == 'draw'
                            ? '${_match.stakeSc} SC refunded to both wallets.'
                            : (iWon
                                ? '+${_match.potSc} SC credited to your Spotmate Wallet!'
                                : '${_match.stakeSc} SC stake awarded to winner.'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Back to Games Arena'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
