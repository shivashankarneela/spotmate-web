import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/arena_service.dart';
import 'match_shell_screen.dart';

/// Screen 1 of the Carrom flow:
/// Free (0 SC) | Bet SC toggle, 1v1 | 2v2 mode pills, stake chips,
/// empty circular profile slots, FIND MATCH & Challenge by Spotmate ID.
class CarromLobbyScreen extends StatefulWidget {
  const CarromLobbyScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<CarromLobbyScreen> createState() => _CarromLobbyScreenState();
}

class _CarromLobbyScreenState extends State<CarromLobbyScreen> {
  final _service = ArenaService();

  bool _isBetMode = false;
  int _playerCount = 2; // 2 (1v1) or 4 (2v2)
  int _stakeSc = 50;
  bool _searching = false;
  RealtimeChannel? _queueChannel;

  static const List<int> _stakes = [25, 50, 100];

  int get _effectiveStake => _isBetMode ? _stakeSc : 0;
  int get _totalPot => _effectiveStake * _playerCount;

  @override
  void dispose() {
    _cancelSearch(silent: true);
    super.dispose();
  }

  Future<void> _findMatch() async {
    setState(() => _searching = true);
    try {
      final uid = _service.currentUserId;
      if (uid != null) {
        _queueChannel = _service.subscribeToQueueMatch(
          userId: uid,
          onMatched: (matchId) async {
            final match = await _service.fetchMatchState(matchId);
            if (!mounted) return;
            _stopQueueListener();
            setState(() => _searching = false);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: match)),
            );
          },
        );
      }

      final res = await Supabase.instance.client.functions.invoke(
        'arena-match-engine',
        body: {
          'action': 'queue.join',
          'game_type': 'carrom',
          'player_count': _playerCount,
          'stake_sc': _effectiveStake,
          'display_name': widget.currentDisplayName,
          if (widget.currentAvatarUrl != null) 'avatar_url': widget.currentAvatarUrl,
        },
      );
      final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
      if (data['error'] != null) throw Exception(data['error'].toString());

      if (data['matched'] == true && data['match_id'] != null && mounted) {
        final match = await _service.fetchMatchState(data['match_id'].toString());
        _stopQueueListener();
        if (!mounted) return;
        setState(() => _searching = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: match)),
        );
      }
    } catch (e) {
      _stopQueueListener();
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _cancelSearch({bool silent = false}) async {
    _stopQueueListener();
    if (_searching) {
      try {
        await _service.leaveRandomQueue();
      } catch (_) {}
      if (!silent && mounted) setState(() => _searching = false);
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
        title: const Text('Challenge to Carrom', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Spotmate ID',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.people_outline),
              label: const Text('Choose a connection'),
              onPressed: () async {
                final person = await pickConnectedUser(ctx);
                if (person == null || !ctx.mounted) return;
                if (person.spotmateId.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('This connection has no SpotMate ID yet.')));
                  return;
                }
                controller.text = person.spotmateId;
              },
            ),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final id = controller.text.trim();
              if (id.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                final res = await Supabase.instance.client.functions.invoke(
                  'arena-match-engine',
                  body: {
                    'action': 'challenge.create',
                    'to_spotmate_id': id,
                    'game_type': 'carrom',
                    'stake_sc': _effectiveStake,
                    'display_name': widget.currentDisplayName,
                    if (widget.currentAvatarUrl != null) 'avatar_url': widget.currentAvatarUrl,
                  },
                );
                final data = Map<String, dynamic>.from((res.data as Map?) ?? const {});
                if (data['error'] != null) throw Exception(data['error'].toString());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Carrom invite sent to $id!')),
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
          'Carrom',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
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
                    onTap: _searching ? null : () => setState(() => _isBetMode = false),
                  ),
                ),
                Expanded(
                  child: _SegButton(
                    label: 'Bet SC',
                    selected: _isBetMode,
                    onTap: _searching ? null : () => setState(() => _isBetMode = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 1v1 | 2v2 Mode Toggle
          const Text(
            'Mode',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('1v1')),
                  selected: _playerCount == 2,
                  selectedColor: const Color(0xFF059669),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _playerCount == 2 ? Colors.white : const Color(0xFF334155),
                  ),
                  onSelected: _searching ? null : (_) => setState(() => _playerCount = 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('2v2')),
                  selected: _playerCount == 4,
                  selectedColor: const Color(0xFF059669),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _playerCount == 4 ? Colors.white : const Color(0xFF334155),
                  ),
                  onSelected: _searching ? null : (_) => setState(() => _playerCount = 4),
                ),
              ),
            ],
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
                      onSelected: _searching ? null : (_) => setState(() => _stakeSc = s),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 26),
          const Text(
            'Match Lobby',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_playerCount, (i) {
              return Column(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF1F5F9),
                      border: Border.all(
                        color: i == 0 ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
                        width: i == 0 ? 2 : 1.2,
                      ),
                    ),
                    child: const Icon(Icons.person_outline_rounded, size: 28, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    i == 0 ? 'You' : (_searching ? 'Searching...' : 'Waiting...'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      color: i == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _searching ? _cancelSearch : _findMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: _searching ? const Color(0xFFDC2626) : const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(
                _searching ? 'CANCEL SEARCH' : 'FIND MATCH',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _searching ? null : _openChallengeById,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFF059669), width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('Challenge by ID', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
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
