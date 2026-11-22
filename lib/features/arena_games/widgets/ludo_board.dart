import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../models/ludo_models.dart';
import '../models/snakes_models.dart';
import '../services/snakes_chat_service.dart';

/// Screen 2 of the Ludo flow:
/// - 4 compact player cards with empty circular profile photo placeholders
/// - Programmatic 15x15 4-color Ludo board with star safe squares & tappable legal tokens
/// - Live in-game text chat + floating emoji bursts
/// - Bottom 3D-style die + ROLL DICE button
class LudoBoard extends StatefulWidget {
  const LudoBoard({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.busy,
    required this.onRollDice,
    required this.onSelectToken,
  });

  final ArenaMatch match;
  final String currentUserId;
  final String currentDisplayName;
  final bool busy;
  final VoidCallback onRollDice;
  final void Function(int tokenIndex) onSelectToken;

  @override
  State<LudoBoard> createState() => _LudoBoardState();
}

class _LudoBoardState extends State<LudoBoard> {
  final _chatService = MatchChatService();
  final _msgController = TextEditingController();
  RealtimeChannel? _chatChannel;

  final List<MatchChatMessage> _messages = [];
  final List<FloatingEmojiEvent> _floatingEmojis = [];

  static const Map<int, Color> _seatColors = {
    0: Color(0xFF2563EB),  // Blue (bottom-left)
    13: Color(0xFFDC2626), // Red (top-left)
    26: Color(0xFF16A34A), // Green (top-right)
    39: Color(0xFFEAB308), // Yellow (bottom-right)
  };

  static const List<String> _quickEmojis = ['😂', '🔥', '😱', '👏', '😍'];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final recent = await _chatService.fetchRecentMessages(widget.match.id);
      if (mounted) setState(() => _messages.addAll(recent));
    } catch (_) {}

    _chatChannel = _chatService.subscribeToMatchChat(
      matchId: widget.match.id,
      onMessage: (m) {
        if (mounted) setState(() => _messages.add(m));
      },
      onEmoji: (ev) {
        if (!mounted) return;
        setState(() => _floatingEmojis.add(ev));
        Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _floatingEmojis.removeWhere((e) => e.id == ev.id));
        });
      },
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    if (_chatChannel != null) _chatService.removeChannel(_chatChannel!);
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final txt = _msgController.text.trim();
    if (txt.isEmpty) return;
    _msgController.clear();
    await _chatService.sendTextMessage(
      matchId: widget.match.id,
      displayName: widget.currentDisplayName,
      text: txt,
    );
  }

  Future<void> _sendEmoji(String emoji) async {
    if (_chatChannel == null) return;
    await _chatService.sendEmojiReaction(
      channel: _chatChannel!,
      matchId: widget.match.id,
      displayName: widget.currentDisplayName,
      emoji: emoji,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = LudoState.fromJson(widget.match.state);
    final isMyTurn = widget.match.isActive && widget.match.turnUserId == widget.currentUserId;
    final canRoll = isMyTurn && state.phase == 'await_roll' && !widget.busy;
    final awaitingToken = isMyTurn && state.phase == 'await_token';
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      child: Column(
        children: [
          // 4-Player Compact Header Row (Empty circular profile photo slots)
          Row(
            children: List.generate(widget.match.players.length, (idx) {
              final player = widget.match.players[idx];
              final seatStart = state.seatStarts[player.userId] ?? 0;
              final color = _seatColors[seatStart] ?? const Color(0xFF2563EB);
              final homeCount =
                  (state.tokens[player.userId] ?? const []).where((t) => t == 56).length;
              final activeTurn = widget.match.turnUserId == player.userId && widget.match.isActive;

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: idx < widget.match.players.length - 1 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: activeTurn ? color : const Color(0xFFE2E8F0),
                      width: activeTurn ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'P${idx + 1} • $homeCount/4',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF1F5F9),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                          image: (player.avatarUrl != null && player.avatarUrl!.isNotEmpty)
                              ? DecorationImage(
                                  image: NetworkImage(player.avatarUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: (player.avatarUrl == null || player.avatarUrl!.isEmpty)
                            ? const Icon(Icons.person_outline_rounded, size: 20, color: Color(0xFF94A3B8))
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Interactive 15x15 Ludo Board + Floating Emojis
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = constraints.maxWidth;
                final cell = boardSize / 15.0;

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CustomPaint(
                        size: Size.square(boardSize),
                        painter: _LudoBoardPainter(),
                      ),
                    ),

                    // Interactive Tokens Layer
                    ..._buildTokens(state, cell, awaitingToken),

                    // Floating Emoji Bursts
                    if (_floatingEmojis.isNotEmpty)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: _floatingEmojis.map((ev) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 8),
                                ],
                              ),
                              child: Text(
                                '${ev.senderName}: ${ev.emoji}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Status / Token Prompt
          Text(
            awaitingToken
                ? 'Rolled ${state.diceValue}! Tap a highlighted token to move.'
                : _formatMoveBanner(state.lastMove),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),

          // Compact In-Game Chat + Quick Emojis
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (latestMsg != null) ...[
                  Text(
                    '${latestMsg.displayName}: ${latestMsg.content}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Message...',
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    ..._quickEmojis.map((em) {
                      return InkWell(
                        onTap: () => _sendEmoji(em),
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(em, style: const TextStyle(fontSize: 18)),
                        ),
                      );
                    }),
                    IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send_rounded, size: 18, color: Color(0xFF2563EB)),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.only(left: 6),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Bottom Dice + ROLL DICE Button
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                ),
                child: Text(
                  '${state.diceValue ?? "🎲"}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: canRoll ? widget.onRollDice : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: Text(
                    awaitingToken
                        ? 'TAP A TOKEN TO MOVE'
                        : (canRoll ? 'ROLL DICE' : 'WAITING FOR TURN...'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTokens(LudoState state, double cell, bool awaitingToken) {
    final widgets = <Widget>[];
    for (final player in widget.match.players) {
      final seatStart = state.seatStarts[player.userId] ?? 0;
      final color = _seatColors[seatStart] ?? const Color(0xFF2563EB);
      final tokens = state.tokens[player.userId] ?? const [-1, -1, -1, -1];
      final isOwner = player.userId == widget.currentUserId;

      for (var tIdx = 0; tIdx < 4; tIdx++) {
        final step = tokens[tIdx];
        final coord = _tokenGridCoord(seatStart, step, tIdx);
        final selectable = isOwner && awaitingToken && state.legalTokens.contains(tIdx);
        final size = cell * (selectable ? 0.92 : 0.78);

        widgets.add(
          Positioned(
            left: (coord.dx + 0.5) * cell - size / 2,
            top: (coord.dy + 0.5) * cell - size / 2,
            child: GestureDetector(
              onTap: selectable ? () => widget.onSelectToken(tIdx) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: selectable ? const Color(0xFFFEF08A) : Colors.white,
                    width: selectable ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selectable ? color.withOpacity(0.65) : Colors.black26,
                      blurRadius: selectable ? 10 : 3,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '${tIdx + 1}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: cell * 0.34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// Maps (seatStart, relativeStep -1..56, tokenIndex) -> 15x15 grid (col, row).
  Offset _tokenGridCoord(int seatStart, int step, int tokenIdx) {
    // Home yards (-1)
    if (step == -1) {
      final yardOrigins = {
        0: const Offset(1.5, 10.5),  // Blue bottom-left
        13: const Offset(1.5, 1.5),  // Red top-left
        26: const Offset(10.5, 1.5), // Green top-right
        39: const Offset(10.5, 10.5),// Yellow bottom-right
      };
      final origin = yardOrigins[seatStart] ?? const Offset(1.5, 10.5);
      final dx = (tokenIdx % 2) * 2.0;
      final dy = (tokenIdx ~/ 2) * 2.0;
      return Offset(origin.dx + dx, origin.dy + dy);
    }

    // Center home finish (56)
    if (step == 56) {
      final homeCenters = {
        0: const Offset(7, 8),
        13: const Offset(6, 7),
        26: const Offset(7, 6),
        39: const Offset(8, 7),
      };
      return homeCenters[seatStart] ?? const Offset(7, 7);
    }

    // Private 5-step colored home columns (51..55)
    if (step >= 51) {
      final k = step - 50; // 1..5
      if (seatStart == 0) return Offset(7, 14 - k.toDouble());
      if (seatStart == 13) return Offset(k.toDouble(), 7);
      if (seatStart == 26) return Offset(7, k.toDouble());
      return Offset(14 - k.toDouble(), 7);
    }

    // 52-square clockwise outer track (global 0..51 starting at Blue entry (6,13))
    const outerTrack = <Offset>[
      Offset(6, 13), Offset(6, 12), Offset(6, 11), Offset(6, 10), Offset(6, 9),
      Offset(5, 8), Offset(4, 8), Offset(3, 8), Offset(2, 8), Offset(1, 8), Offset(0, 8),
      Offset(0, 7), Offset(0, 6),
      Offset(1, 6), Offset(2, 6), Offset(3, 6), Offset(4, 6), Offset(5, 6),
      Offset(6, 5), Offset(6, 4), Offset(6, 3), Offset(6, 2), Offset(6, 1), Offset(6, 0),
      Offset(7, 0), Offset(8, 0),
      Offset(8, 1), Offset(8, 2), Offset(8, 3), Offset(8, 4), Offset(8, 5),
      Offset(9, 6), Offset(10, 6), Offset(11, 6), Offset(12, 6), Offset(13, 6), Offset(14, 6),
      Offset(14, 7), Offset(14, 8),
      Offset(13, 8), Offset(12, 8), Offset(11, 8), Offset(10, 8), Offset(9, 8),
      Offset(8, 9), Offset(8, 10), Offset(8, 11), Offset(8, 12), Offset(8, 13), Offset(8, 14),
      Offset(7, 14), Offset(6, 14),
    ];
    final g = (seatStart + step) % 52;
    return outerTrack[g];
  }

  String _formatMoveBanner(LudoMoveLog? m) {
    if (m == null) return 'Roll a 6 to bring a token out of your yard!';
    if (m.event == 'captured') return '💥 ${m.displayName} captured an opponent! Bonus roll!';
    if (m.event == 'home') return '🏠 ${m.displayName} brought a token home! Bonus roll!';
    if (m.event == 'triple_six') return '😅 ${m.displayName} rolled three 6s — turn passed!';
    if (m.event == 'no_moves') return '${m.displayName} rolled ${m.dice} (no legal moves).';
    return '${m.displayName} rolled ${m.dice}${m.extraTurn ? " — Bonus roll!" : ""}';
  }
}

class _LudoBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 15.0;

    // White base
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // 4 Corner Yards
    _drawYard(canvas, Rect.fromLTWH(0, 0, 6 * c, 6 * c), const Color(0xFFDC2626), c);
    _drawYard(canvas, Rect.fromLTWH(9 * c, 0, 6 * c, 6 * c), const Color(0xFF16A34A), c);
    _drawYard(canvas, Rect.fromLTWH(0, 9 * c, 6 * c, 6 * c), const Color(0xFF2563EB), c);
    _drawYard(canvas, Rect.fromLTWH(9 * c, 9 * c, 6 * c, 6 * c), const Color(0xFFEAB308), c);

    // Colored Home Columns
    for (var i = 1; i <= 5; i++) {
      canvas.drawRect(Rect.fromLTWH(i * c, 7 * c, c, c), Paint()..color = const Color(0xFFFCA5A5));
      canvas.drawRect(Rect.fromLTWH(7 * c, i * c, c, c), Paint()..color = const Color(0xFF86EFAC));
      canvas.drawRect(Rect.fromLTWH((14 - i) * c, 7 * c, c, c), Paint()..color = const Color(0xFFFDE047));
      canvas.drawRect(Rect.fromLTWH(7 * c, (14 - i) * c, c, c), Paint()..color = const Color(0xFF93C5FD));
    }

    // Center 4-Triangle Finish Home
    final center = Offset(7.5 * c, 7.5 * c);
    _drawTri(canvas, Offset(6 * c, 6 * c), Offset(6 * c, 9 * c), center, const Color(0xFFDC2626));
    _drawTri(canvas, Offset(6 * c, 6 * c), Offset(9 * c, 6 * c), center, const Color(0xFF16A34A));
    _drawTri(canvas, Offset(9 * c, 6 * c), Offset(9 * c, 9 * c), center, const Color(0xFFEAB308));
    _drawTri(canvas, Offset(6 * c, 9 * c), Offset(9 * c, 9 * c), center, const Color(0xFF2563EB));

    // Grid lines on track
    final gridPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var r = 0; r < 15; r++) {
      for (var col = 0; col < 15; col++) {
        final inTrack = (col >= 6 && col <= 8) || (r >= 6 && r <= 8);
        final inCenter = col >= 6 && col <= 8 && r >= 6 && r <= 8;
        if (inTrack && !inCenter) {
          canvas.drawRect(Rect.fromLTWH(col * c, r * c, c, c), gridPaint);
        }
      }
    }

    // Star Safe Squares
    const safeCoords = [
      Offset(6, 13), Offset(2, 8), Offset(1, 6), Offset(6, 2),
      Offset(8, 1), Offset(12, 6), Offset(13, 8), Offset(8, 12),
    ];
    for (final pt in safeCoords) {
      _drawStar(canvas, Offset((pt.dx + 0.5) * c, (pt.dy + 0.5) * c), c * 0.30);
    }
  }

  void _drawYard(Canvas canvas, Rect rect, Color color, double c) {
    canvas.drawRect(rect, Paint()..color = color);
    final inner = rect.deflate(c * 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(10)),
      Paint()..color = Colors.white,
    );
  }

  void _drawTri(Canvas canvas, Offset a, Offset b, Offset c, Color color) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawStar(Canvas canvas, Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final x = center.dx + rad * math.cos(angle);
      final y = center.dy + rad * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) => false;
}
