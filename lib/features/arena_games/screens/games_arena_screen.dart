import '../space_shooter/space_shooter_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../../shared/connected_user_picker.dart';
import '../services/arena_service.dart';
import 'match_shell_screen.dart';
import 'snakes_lobby_screen.dart';
import 'ludo_lobby_screen.dart';
import 'chess_lobby_screen.dart';

/// Main "Games Arena" screen opened when the user taps "Games" in the long-press Explore hub.
/// Supports Free (0 SC) & SC Wager modes, Random Matchmaking, and Direct Spotmate ID Challenges.
class GamesArenaScreen extends StatefulWidget {
  const GamesArenaScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<GamesArenaScreen> createState() => _GamesArenaScreenState();
}

class _GamesArenaScreenState extends State<GamesArenaScreen> {
  final _service = ArenaService();

  bool _isWagerMode = false;
  int _selectedStakeSc = 25;
  bool _searchingQueue = false;
  ArenaGameType? _queuedGame;
  RealtimeChannel? _queueChannel;

  static const List<int> _stakeOptions = [10, 25, 50, 100];

  int get _effectiveStake => _isWagerMode ? _selectedStakeSc : 0;

  @override
  void dispose() {
    _cancelQueue(silent: true);
    super.dispose();
  }

  Future<void> _startRandomMatch(ArenaGameType game) async {
    if (_searchingQueue || game == ArenaGameType.carrom) return;
    if (game == ArenaGameType.snakesLadders) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SnakesLobbyScreen(
          currentDisplayName: widget.currentDisplayName,
          currentAvatarUrl: widget.currentAvatarUrl,
        ),
      ));
      return;
    }
    if (game == ArenaGameType.ludo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LudoLobbyScreen(
          currentDisplayName: widget.currentDisplayName,
          currentAvatarUrl: widget.currentAvatarUrl,
        ),
      ));
      return;
    }
    if (game == ArenaGameType.chess) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChessLobbyScreen(
          currentDisplayName: widget.currentDisplayName,
          currentAvatarUrl: widget.currentAvatarUrl,
        ),
      ));
      return;
    }
    setState(() {
      _searchingQueue = true;
      _queuedGame = game;
    });

    try {
      final uid = _service.currentUserId;
      if (uid != null) {
        _queueChannel = _service.subscribeToQueueMatch(
          userId: uid,
          onMatched: (matchId) async {
            final match = await _service.fetchMatchState(matchId);
            if (!mounted || !_searchingQueue) return;
            _stopQueueListener();
            setState(() => _searchingQueue = false);
            _openMatch(match);
          },
        );
      }

      final instantMatch = await _service.joinRandomQueue(
        gameType: game,
        stakeSc: _effectiveStake,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );

      if (instantMatch != null && mounted && _searchingQueue) {
        _stopQueueListener();
        setState(() => _searchingQueue = false);
        _openMatch(instantMatch);
      }
    } catch (e) {
      _stopQueueListener();
      if (mounted) {
        setState(() => _searchingQueue = false);
        _toast(e.toString());
      }
    }
  }

  Future<void> _cancelQueue({bool silent = false}) async {
    _stopQueueListener();
    if (_searchingQueue) {
      try {
        await _service.leaveRandomQueue();
      } catch (_) {}
      if (!silent && mounted) {
        setState(() {
          _searchingQueue = false;
          _queuedGame = null;
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

  void _openMatch(ArenaMatch match) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MatchShellScreen(initialMatch: match)),
    );
  }

  Future<void> _showChallengeByIdDialog() async {
    final idController = TextEditingController();
    ArenaGameType chosenGame = ArenaGameType.handCricket;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFFFF7FB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Challenge a player',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: idController,
                    decoration: InputDecoration(
                      labelText: 'HaloBerry ID',
                      hintText: 'e.g. spot_rohan99',
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
                          const SnackBar(content: Text('This connection has no HaloBerry ID yet.')));
                        return;
                      }
                      idController.text = person.spotmateId;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ArenaGameType>(
                    value: chosenGame,
                    decoration: InputDecoration(
                      labelText: 'Game',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: ArenaGameType.values.where((game) => game != ArenaGameType.carrom)
                        .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text(g.enabledInPhase1 ? g.title : '${g.title} (Coming Soon)'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => chosenGame = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isWagerMode
                        ? 'Wager: $_selectedStakeSc SC each (Pot: ${_selectedStakeSc * 2} SC)'
                        : 'Mode: Free Play (0 SC)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final target = idController.text.trim();
                    if (target.isEmpty) return;
                    Navigator.of(ctx).pop();
                    try {
                      await _service.createSpotmateIdChallenge(
                        toSpotmateId: target,
                        gameType: chosenGame,
                        stakeSc: _effectiveStake,
                        displayName: widget.currentDisplayName,
                        avatarUrl: widget.currentAvatarUrl,
                      );
                      _toast('Challenge sent to $target (valid for 60s)!');
                    } catch (e) {
                      _toast(e.toString());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Send Invite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7FB),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFFFFF7FB),
        elevation: 0,
        title: const Text(
          'Games Arena',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _showChallengeByIdDialog,
              icon: const Icon(Icons.person_search_rounded, size: 18),
              label: const Text('Challenge by ID'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // Free | SC Wager Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeTab(
                        label: 'Free (0 SC)',
                        selected: !_isWagerMode,
                        onTap: () => setState(() => _isWagerMode = false),
                      ),
                    ),
                    Expanded(
                      child: _ModeTab(
                        label: 'SC Wager',
                        selected: _isWagerMode,
                        onTap: () => setState(() => _isWagerMode = true),
                      ),
                    ),
                  ],
                ),
              ),

              // Stake Chips when SC Wager is active
              if (_isWagerMode) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _stakeOptions.map((sc) {
                    final active = _selectedStakeSc == sc;
                    return ChoiceChip(
                      label: Text('$sc SC'),
                      selected: active,
                      selectedColor: const Color(0xFFFEF3C7),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: active ? const Color(0xFFB45309) : const Color(0xFF334155),
                      ),
                      onSelected: (_) => setState(() => _selectedStakeSc = sc),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 18),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: SizedBox(width: 78, child: Image.asset(spaceShooterArtwork, fit: BoxFit.cover)),
                  title: const Text('Space Shooter'),
                  subtitle: const Text('Solo · Free to play'),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () => openSpaceShooter(context),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pick a game to match with a random player:',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 12),

              for (final game in ArenaGameType.values.where((game) => game != ArenaGameType.carrom))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: ClipRRect(borderRadius: BorderRadius.circular(6),
                      child: Image.asset('assets/arena/${game.id}.webp',width:88,height:56,fit:BoxFit.cover)),
                    title: Text(game.title), subtitle: Text(game.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _startRandomMatch(game),
                  ),
                ),
            ],
          ),

          // Random Queue Searching Overlay
          if (_searchingQueue)
            Container(
              color: Colors.black.withOpacity(0.45),
              alignment: Alignment.center,
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    Text(
                      'Finding ${_queuedGame?.title ?? "match"} opponent...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isWagerMode ? 'Stake: $_selectedStakeSc SC' : 'Free Play (0 SC)',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _cancelQueue,
                      child: const Text('Cancel Search'),
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

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
