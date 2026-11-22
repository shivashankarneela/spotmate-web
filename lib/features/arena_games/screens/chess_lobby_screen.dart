import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../../shared/connected_user_picker.dart';
import '../services/arena_service.dart';
import 'match_shell_screen.dart';

/// Screen 1 of the Chess flow:
/// Free (0 SC) | Bet SC toggle, time control (3+2, 5+3, 10+0), stake chips,
/// 2 empty circular profile slots with player ELO, FIND MATCH & Challenge by ID.
class ChessLobbyScreen extends StatefulWidget {
  const ChessLobbyScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
    this.currentElo = 1200,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;
  final int currentElo;

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  final _service = ArenaService();

  bool _isBetMode = false;
  String _timeControl = '5+3';
  int _stakeSc = 50;
  bool _searching = false;
  RealtimeChannel? _queueChannel;

  static const List<String> _timeControls = ['3+2', '5+3', '10+0'];
  static const List<int> _stakes = [25, 50, 100];

  int get _effectiveStake => _isBetMode ? _stakeSc : 0;

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

      final instant = await _service.joinRandomQueue(
        gameType: ArenaGameType.chess,
        playerCount: 2,
        stakeSc: _effectiveStake,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );

      if (instant != null && mounted) {
        _stopQueueListener();
        setState(() => _searching = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: instant)),
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
        title: const Text('Challenge to Chess', style: TextStyle(fontWeight: FontWeight.w800)),
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
                await _service.createSpotmateIdChallenge(
                  toSpotmateId: id,
                  gameType: ArenaGameType.chess,
                  stakeSc: _effectiveStake,
                  displayName: widget.currentDisplayName,
                  avatarUrl: widget.currentAvatarUrl,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Chess invite sent to $id!')),
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
          'Chess',
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
                _isBetMode ? 'POT: ${_effectiveStake * 2} SC' : 'FREE PLAY • 0 SC',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _isBetMode ? const Color(0xFFB45309) : const Color(0xFF334155),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

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

          const Text(
            'Time control',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: _timeControls.map((tc) {
              final active = _timeControl == tc;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: tc != _timeControls.last ? 8 : 0),
                  child: ChoiceChip(
                    label: Center(child: Text(tc)),
                    selected: active,
                    selectedColor: const Color(0xFF059669),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : const Color(0xFF334155),
                    ),
                    onSelected: _searching ? null : (_) => setState(() => _timeControl = tc),
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
            children: [
              Column(
                children: [
                  _EmptyAvatarSlot(highlighted: true, avatarUrl: widget.currentAvatarUrl),
                  const SizedBox(height: 6),
                  Text(
                    'You • ${widget.currentElo} ELO',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ),
              const Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
              Column(
                children: [
                  const _EmptyAvatarSlot(highlighted: false),
                  const SizedBox(height: 6),
                  Text(
                    _searching ? 'Searching...' : 'Waiting...',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
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

class _EmptyAvatarSlot extends StatelessWidget {
  const _EmptyAvatarSlot({required this.highlighted, this.avatarUrl});

  final bool highlighted;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF1F5F9),
        border: Border.all(
          color: highlighted ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
          width: highlighted ? 2 : 1.2,
        ),
        image: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? DecorationImage(image: NetworkImage(avatarUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? const Icon(Icons.person_outline_rounded, size: 30, color: Color(0xFF94A3B8))
          : null,
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
