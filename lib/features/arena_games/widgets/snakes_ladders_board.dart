import 'dart:math' as math;
import 'dice_3d_widget.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../models/snakes_models.dart';
import '../services/snakes_chat_service.dart';

/// Screen 2 of the Snakes & Ladders flow:
/// - 4 compact player cards with empty circular profile photo placeholders (auto-fills if avatarUrl exists)
/// - Programmatic 10x10 zig-zag 1..100 board with 10 snakes and 6 ladders (ZERO ladder to 100)
/// - Floating emoji reaction bursts + live in-game text chat bar
/// - Server-rolled dice + ROLL DICE button
class SnakesLaddersBoard extends StatefulWidget {
  const SnakesLaddersBoard({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.rolling,
    required this.onRollDice,
  });

  final ArenaMatch match;
  final String currentUserId;
  final String currentDisplayName;
  final bool rolling;
  final VoidCallback onRollDice;

  @override
  State<SnakesLaddersBoard> createState() => _SnakesLaddersBoardState();
}

class _SnakesLaddersBoardState extends State<SnakesLaddersBoard> {
  final _chatService = MatchChatService();
  final _msgController = TextEditingController();
  RealtimeChannel? _chatChannel;

  final List<MatchChatMessage> _messages = [];
  final List<FloatingEmojiEvent> _floatingEmojis = [];

  static const List<Color> _pawnColors = [
    Color(0xFF2563EB), // P1 Blue
    Color(0xFFDC2626), // P2 Red
    Color(0xFF16A34A), // P3 Green
    Color(0xFFD97706), // P4 Amber
  ];

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
      onMessage: (msg) {
        if (!mounted) return;
        setState(() => _messages.add(msg));
      },
      onEmoji: (ev) {
        if (!mounted) return;
        setState(() => _floatingEmojis.add(ev));
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _floatingEmojis.removeWhere((e) => e.id == ev.id));
        });
      },
    );
  }

  @override
  void dispose() {
    _msgController.dispose();
    if (_chatChannel != null) {
      _chatService.removeChannel(_chatChannel!);
    }
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
    final state = SnakesLaddersState.fromJson(widget.match.state);
    final isMyTurn = widget.match.isActive && widget.match.turnUserId == widget.currentUserId;
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      child: Column(
        children: [
          // 4-Player Compact Header Row (Empty circular profile photo slots)
          Row(
            children: List.generate(widget.match.players.length, (idx) {
              final player = widget.match.players[idx];
              final tile = state.positions[player.userId] ?? 0;
              final activeTurn = widget.match.turnUserId == player.userId && widget.match.isActive;
              final color = _pawnColors[idx % _pawnColors.length];

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
                          Flexible(
                            child: Text(
                              'P${idx + 1} • $tile',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                            ),
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
                      // Empty circular profile photo slot (auto-renders photo if avatarUrl is provided)
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

          // 10x10 Board + Floating Emoji Bursts
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SnakesBoardPainter(
                      snakes: state.snakes,
                      ladders: state.ladders,
                      players: widget.match.players,
                      positions: state.positions,
                      pawnColors: _pawnColors,
                    ),
                  ),
                ),
                // Floating Emoji Reaction Bubbles
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
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 8,
                              ),
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
            ),
          ),
          const SizedBox(height: 8),

          // Last move / event banner
          if (state.lastMove != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _formatMoveBanner(state.lastMove!),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),

          // Compact In-Game Text Chat + Quick Emojis
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

          // Bottom Dice + ROLL DICE CTA
          Row(
            children: [
              Dice3DWidget(
                value: state.lastMove?.dice ?? 1,
                rolling: widget.rolling,
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (isMyTurn && !widget.rolling) ? widget.onRollDice : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: Text(
                    isMyTurn
                        ? (widget.rolling ? 'ROLLING...' : 'ROLL DICE')
                        : 'WAITING FOR TURN...',
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

  String _formatMoveBanner(SnakesMoveLog m) {
    if (m.event == 'snake') {
      return '🐍 ${m.displayName} rolled ${m.dice}, hit a snake at ${m.landed} → ${m.finalTile}!';
    }
    if (m.event == 'ladder') {
      return '🪜 ${m.displayName} rolled ${m.dice}, climbed ${m.landed} → ${m.finalTile}!';
    }
    if (m.event == 'overshoot') {
      return '${m.displayName} rolled ${m.dice} (needs exact 100 to win).';
    }
    return '${m.displayName} rolled ${m.dice} → tile ${m.finalTile}${m.extraTurn ? " (Bonus roll!)" : ""}';
  }
}

/// Programmatic 10x10 boustrophedon (1..100) Snakes & Ladders painter.
class _SnakesBoardPainter extends CustomPainter {
  _SnakesBoardPainter({
    required this.snakes,
    required this.ladders,
    required this.players,
    required this.positions,
    required this.pawnColors,
  });

  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final List<ArenaPlayerMeta> players;
  final Map<String, int> positions;
  final List<Color> pawnColors;

  Offset _tileCenter(int tile, double cell) {
    final zero = tile - 1;
    final rowFromBottom = zero ~/ 10;
    final colInRow = zero % 10;
    final col = rowFromBottom.isEven ? colInRow : (9 - colInRow);
    final rowFromTop = 9 - rowFromBottom;
    return Offset((col + 0.5) * cell, (rowFromTop + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 10;
    const palette = [Color(0xFFFEF3C7), Color(0xFFFFFFFF), Color(0xFFD1FAE5)];

    // 1. Draw 100 numbered tiles
    for (var tile = 1; tile <= 100; tile++) {
      final center = _tileCenter(tile, cell);
      final rect = Rect.fromCenter(center: center, width: cell, height: cell);
      final paint = Paint()..color = palette[tile % palette.length];
      canvas.drawRect(rect, paint);

      final tp = TextPainter(
        text: TextSpan(
          text: '$tile',
          style: TextStyle(
            fontSize: cell * 0.30,
            fontWeight: tile == 100 ? FontWeight.w900 : FontWeight.w600,
            color: tile == 100 ? const Color(0xFFB45309) : const Color(0xFF334155),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 3, rect.top + 2));
    }

    // 2. Draw Ladders (none reach tile 100)
    final ladderPaint = Paint()
      ..color = const Color(0xFF92400E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    for (final entry in ladders.entries) {
      final start = _tileCenter(entry.key, cell);
      final end = _tileCenter(entry.value, cell);
      final dir = end - start;
      final perp = Offset(-dir.dy, dir.dx) / (dir.distance == 0 ? 1 : dir.distance) * (cell * 0.16);
      canvas.drawLine(start + perp, end + perp, ladderPaint);
      canvas.drawLine(start - perp, end - perp, ladderPaint);
      const rungs = 5;
      for (var i = 1; i < rungs; i++) {
        final t = i / rungs;
        final mid = Offset.lerp(start, end, t)!;
        canvas.drawLine(mid + perp, mid - perp, ladderPaint);
      }
    }

    const snakeColors = [Color(0xFF557246), Color(0xFF9B5C30), Color(0xFF27665B), Color(0xFF68517A)];
    var index = 0;
    for (final entry in snakes.entries) {
      final head = _tileCenter(entry.key, cell);
      final tail = _tileCenter(entry.value, cell);
      final axis = tail - head;
      if (axis.distance == 0) continue;
      final normal = Offset(-axis.dy, axis.dx) / axis.distance;
      final bend = normal * cell * (index.isEven ? 1.25 : -1.25);
      final path = Path()..moveTo(head.dx, head.dy);
      final controlA = head + axis * .25 + bend;
      final controlB = head + axis * .75 - bend;
      path.cubicTo(controlA.dx, controlA.dy, controlB.dx, controlB.dy, tail.dx, tail.dy);
      final metric = path.computeMetrics().first;
      final color = snakeColors[index++ % snakeColors.length];
      final body = <Offset>[];
      final opposite = <Offset>[];
      for (var i = 0; i <= 48; i++) {
        final t = i / 48;
        final sample = metric.getTangentForOffset(metric.length * t)!;
        final v = sample.vector;
        final width = cell * (.01 + .092 * math.pow(1 - t, .55));
        final side = Offset(-v.dy, v.dx) * width;
        body.add(sample.position + side);
        opposite.add(sample.position - side);
      }
      final silhouette = Path()..addPolygon([...body, ...opposite.reversed], true);
      canvas.drawShadow(silhouette, Colors.black54, 2, false);
      canvas.drawPath(silhouette, Paint()..color = color);
      for (var d = cell * .19; d < metric.length - cell * .20; d += cell * .14) {
        final sample = metric.getTangentForOffset(d)!;
        final radius = cell * .045 * (1 - d / metric.length);
        canvas.drawCircle(sample.position, radius, Paint()..color = Colors.black38);
      }
      final heading = metric.getTangentForOffset(0)!.vector;
      canvas.save();
      canvas.translate(head.dx, head.dy);
      canvas.rotate(math.atan2(heading.dy, heading.dx));
      final oval = Rect.fromCenter(center: Offset.zero, width: cell * .38, height: cell * .24);
      canvas.drawOval(oval, Paint()..shader = RadialGradient(
        colors: [Color.lerp(color, Colors.white, .35)!, color, Colors.black87],
        stops: const [0, .75, 1],
      ).createShader(oval));
      for (final sign in [-1, 1]) {
        final eye = Offset(-cell * .075, sign * cell * .066);
        canvas.drawCircle(eye, cell * .033, Paint()..color = const Color(0xFFFFD47C));
        canvas.drawOval(Rect.fromCenter(center: eye, width: cell * .019, height: cell * .05),
          Paint()..color = Colors.black);
      }
      canvas.restore();
    }

    // 4. Draw up to 4 Player Pawns (offset neatly if sharing a tile)
    final offsets = [
      Offset(-cell * 0.18, -cell * 0.15),
      Offset(cell * 0.18, -cell * 0.15),
      Offset(-cell * 0.18, cell * 0.18),
      Offset(cell * 0.18, cell * 0.18),
    ];
    for (var i = 0; i < players.length; i++) {
      final tile = positions[players[i].userId] ?? 0;
      if (tile <= 0) continue;
      final center = _tileCenter(tile, cell) + offsets[i % 4];
      final color = pawnColors[i % pawnColors.length];
      final base = Rect.fromCenter(center: center + Offset(0, cell * .07),
        width: cell * .37, height: cell * .19);
      canvas.drawOval(base.shift(Offset(0, cell * .045)), Paint()..color = Colors.black54);
      canvas.drawOval(base, Paint()..color = Color.lerp(color, Colors.black, .35)!);
      final cap = Rect.fromCircle(center: center - Offset(0, cell * .02), radius: cell * .15);
      canvas.drawOval(cap, Paint()..shader = RadialGradient(
        center: const Alignment(-.45, -.55),
        colors: [Color.lerp(color, Colors.white, .68)!, color, Colors.black87],
        stops: const [0, .63, 1],
      ).createShader(cap));
      canvas.drawOval(cap, Paint()..color = Colors.white70..style = PaintingStyle.stroke
        ..strokeWidth = cell * .022);
    }
  }

  @override
  bool shouldRepaint(covariant _SnakesBoardPainter oldDelegate) => true;
}
