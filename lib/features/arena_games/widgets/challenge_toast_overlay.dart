import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../screens/match_shell_screen.dart';
import '../services/arena_service.dart';

/// Wrap your root app scaffold with this widget so incoming Spotmate ID game challenges
/// pop in smoothly at the top of any screen with Accept / Decline actions.
class ChallengeToastOverlay extends StatefulWidget {
  const ChallengeToastOverlay({
    super.key,
    required this.child,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final Widget child;
  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<ChallengeToastOverlay> createState() => _ChallengeToastOverlayState();
}

class _ChallengeToastOverlayState extends State<ChallengeToastOverlay> {
  final _service = ArenaService();
  RealtimeChannel? _channel;
  ArenaChallenge? _pending;
  bool _busy = false;
  final Set<String> _openedMatches = {};

  @override
  void initState() {
    super.initState();
    final uid = _service.currentUserId;
    if (uid != null) {
      _channel = _service.subscribeToIncomingChallenges(
        userId: uid,
        onChallengeReceived: (ch) {
          if (!mounted) return;
          setState(() => _pending = ch);
        },
        onChallengeAccepted: (matchId) async {
          if (!_openedMatches.add(matchId)) return;
          try {
            final match = await _service.fetchMatchState(matchId);
            if (!mounted) return;
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MatchShellScreen(initialMatch: match),
            ));
          } catch (_) {
            _openedMatches.remove(matchId);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open the accepted game.')),
            );
          }
        },
      );
      _loadPending(uid);
    }
  }

  Future<void> _loadPending(String userId) async {
    try {
      final rows = await Supabase.instance.client.from('arena_game_challenges')
          .select().eq('to_user_id', userId).eq('status', 'pending')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false).limit(1);
      if (mounted && _pending == null && rows.isNotEmpty) {
        setState(() => _pending = ArenaChallenge.fromJson(Map<String, dynamic>.from(rows.first)));
      }
    } catch (_) {
      // Realtime will continue delivering challenges after the subscription connects.
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      _service.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    final ch = _pending;
    if (ch == null || _busy) return;
    setState(() => _busy = true);
    try {
      final match = await _service.respondToChallenge(
        challengeId: ch.id,
        accept: accept,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );
      if (!mounted) return;
      setState(() {
        _pending = null;
        _busy = false;
      });
      if (accept && match != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchShellScreen(initialMatch: match),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = _pending;
    return Stack(
      children: [
        widget.child,
        if (ch != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFF2563EB),
                          child: Icon(Icons.sports_esports_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${ch.fromName} challenged you!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ch.gameType.title} • ${ch.isFree ? "Free (0 SC)" : "${ch.stakeSc} SC stake"}',
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _respond(false),
                          child: const Text('Decline', style: TextStyle(color: Color(0xFF94A3B8))),
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: _busy ? null : () => _respond(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
