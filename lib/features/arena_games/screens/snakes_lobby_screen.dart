import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../services/arena_service.dart';
import 'match_shell_screen.dart';

/// Screen 1 of the Snakes & Ladders flow:
/// Register & Join a 2P / 3P / 4P table in Free (0 SC) or Bet SC mode,
/// with empty circular profile photo slots and Challenge by Spotmate ID.
class SnakesLobbyScreen extends StatefulWidget {
  const SnakesLobbyScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<SnakesLobbyScreen> createState() => _SnakesLobbyScreenState();
}

class _SnakesLobbyScreenState extends State<SnakesLobbyScreen> {
  final _service = ArenaService();

  bool _isBetMode = false;
  int _seatCount = 4; // 2, 3, or 4
  int _stakeSc = 25;
  bool _registered = false;
  int _joinedCount = 0;
  RealtimeChannel? _queueChannel;

  static const List<int> _stakes = [10, 25, 50];

  int get _effectiveStake => _isBetMode ? _stakeSc : 0;
  int get _totalPot => _effectiveStake * _seatCount;

  @override
  void dispose() {
    _cancelRegistration(silent: true);
    super.dispose();
  }

  Future<void> _registerAndPlay() async {
    setState(() {
      _registered = true;
      _joinedCount = 1;
    });

    try {
      final uid = _service.currentUserId;
      if (uid != null) {
        _queueChannel = _service.subscribeToQueueMatch(
          userId: uid,
          onMatched: (matchId) async {
            final match = await _service.fetchMatchState(matchId);
            if (!mounted) return;
            _stopQueueListener();
            setState(() => _registered = false);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: match)),
            );
          },
        );
      }

      final instant = await _service.joinRandomQueue(
        gameType: ArenaGameType.snakesLadders,
        playerCount: _seatCount,
        stakeSc: _effectiveStake,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );

      if (instant != null && mounted) {
        _stopQueueListener();
        setState(() => _registered = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: instant)),
        );
      }
    } catch (e) {
      _stopQueueListener();
      if (mounted) {
        setState(() {
          _registered = false;
          _joinedCount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _cancelRegistration({bool silent = false}) async {
    _stopQueueListener();
    if (_registered) {
      try {
        await _service.leaveRandomQueue();
      } catch (_) {}
      if (!silent && mounted) {
        setState(() {
          _registered = false;
          _joinedCount = 0;
        });
      }
    }
  }

  void _stopQueueListener() {
    if (_queueChannel != null) {
      _service.removeChannel(_queueChannel!);
      _queueChannel = null;
    }
  }

  Future<void> _openChallengeById() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF8F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Challenge by Spotmate ID', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Spotmate ID or Username',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final id = controller.text.trim();
              if (id.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await _service.createSpotmateIdChallenge(
                  toSpotmateId: id,
                  gameType: ArenaGameType.snakesLadders,
                  stakeSc: _effectiveStake,
                  displayName: widget.currentDisplayName,
                  avatarUrl: widget.currentAvatarUrl,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Snakes & Ladders invite sent to $id!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        title: const Text(
          'Snakes & Ladders',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          // POT Pill
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _isBetMode ? const Color(0xFFFEF3C7) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _isBetMode ? 'POT: $_totalPot SC' : 'FREE PLAY • 0 SC',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _isBetMode ? const Color(0xFFB45309) : const Color(0xFF334155),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Free (0 SC) | Bet SC Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegButton(
                    label: 'Free (0 SC)',
                    selected: !_isBetMode,
                    onTap: _registered ? null : () => setState(() => _isBetMode = false),
                  ),
                ),
                Expanded(
                  child: _SegButton(
                    label: 'Bet SC',
                    selected: _isBetMode,
                    onTap: _registered ? null : () => setState(() => _isBetMode = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Seat Selection (2P, 3P, 4P)
          const Text(
            'Seat selection (max 4 players)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [2, 3, 4].map((n) {
              final active = _seatCount == n;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: n < 4 ? 8 : 0),
                  child: ChoiceChip(
                    label: Center(child: Text('${n}P')),
                    selected: active,
                    selectedColor: const Color(0xFF059669),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : const Color(0xFF334155),
                    ),
                    onSelected: _registered ? null : (_) => setState(() => _seatCount = n),
                  ),
                ),
              );
            }).toList(),
          ),

          if (_isBetMode) ...[
            const SizedBox(height: 20),
            const Text(
              'Stake per player',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Row(
              children: _stakes.map((s) {
                final active = _stakeSc == s;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: s != _stakes.last ? 8 : 0),
                    child: ChoiceChip(
                      label: Center(child: Text('$s SC')),
                      selected: active,
                      selectedColor: const Color(0xFFFEF3C7),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: active ? const Color(0xFFB45309) : const Color(0xFF334155),
                      ),
                      onSelected: _registered ? null : (_) => setState(() => _stakeSc = s),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Lobby Status + Empty Circular Profile Slots
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lobby status',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
              ),
              Text(
                _registered ? 'Joined $_joinedCount/$_seatCount' : 'Ready to register',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_seatCount, (i) {
              final filled = i < _joinedCount;
              return Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
                  border: Border.all(
                    color: filled ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
                    width: filled ? 2 : 1.2,
                  ),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 28,
                  color: filled ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                ),
              );
            }),
          ),

          const SizedBox(height: 28),

          // Register & Play / Cancel
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _registered ? _cancelRegistration : _registerAndPlay,
              style: ElevatedButton.styleFrom(
                backgroundColor: _registered ? const Color(0xFFDC2626) : const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(
                _registered ? 'CANCEL REGISTRATION' : 'REGISTER & PLAY',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _registered ? null : _openChallengeById,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFF059669), width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text(
                'Challenge by ID',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: selected ? const Color(0xFF0F172A) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
