import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../models/carrom_models.dart';
import '../models/snakes_models.dart';
import '../services/snakes_chat_service.dart';

/// Screen 2 of the Carrom flow:
/// - Opponent & Player strips with empty circular profile photo slots & coin scores (X/9)
/// - Classic walnut & birch Carrom board painter (4 corner pockets, baselines, compass rose, 19 coins)
/// - Interactive drag-to-aim dotted trajectory line + power ring & horizontal striker slider
/// - Live in-game text chat + floating emoji bursts
class CarromBoard extends StatefulWidget {
  const CarromBoard({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.busy,
    required this.onShoot,
  });

  final ArenaMatch match;
  final String currentUserId;
  final String currentDisplayName;
  final bool busy;
  final void Function({
    required double strikerX,
    required double angleRad,
    required double power,
  }) onShoot;

  @override
  State<CarromBoard> createState() => _CarromBoardState();
}

class _CarromBoardState extends State<CarromBoard> {
  final _chatService = MatchChatService();
  final _msgController = TextEditingController();
  RealtimeChannel? _chatChannel;

  final List<MatchChatMessage> _messages = [];
  final List<FloatingEmojiEvent> _floatingEmojis = [];

  double _strikerX = 0.5; // 0.18..0.82
  Offset? _dragStart;
  Offset? _dragCurrent;

  Timer? _replayTimer;
  List<dynamic>? _frame;

  @override
  void didUpdateWidget(covariant CarromBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shot = widget.match.state['last_shot'];
    final previous = oldWidget.match.state['last_shot'];
    if (shot is! Map || shot['number'] == null ||
        (previous is Map && shot['number'] == previous['number'])) return;
    final frames = shot['replay'];
    if (frames is! List || frames.length < 2) return;
    _replayTimer?.cancel();
    _dragStart = null;
    _dragCurrent = null;
    _frame = frames.first as List;
    final clock = Stopwatch()..start();
    final duration = (frames.length * 34).clamp(300, 2400);
    _replayTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      final progress = clock.elapsedMilliseconds / duration;
      setState(() {
        if (progress >= 1) {
          timer.cancel();
          _frame = null;
        } else {
          _frame = frames[(progress * frames.length).floor()] as List;
        }
      });
    });
  }

  static const List<String> _quickEmojis = ['🔥', '🎯', '😱', '👏', '😂'];

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
    _replayTimer?.cancel();
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
    final state = CarromState.fromJson(widget.match.state);
    final myColor = state.teamColor[widget.currentUserId] ?? 'white';
    final isMyTurn = widget.match.isActive && widget.match.turnUserId == widget.currentUserId;
    final canShoot = isMyTurn && !widget.busy && _frame == null;

    final me = widget.match.players.firstWhere(
      (p) => p.userId == widget.currentUserId,
      orElse: () => widget.match.players.first,
    );
    final opponent = widget.match.players.firstWhere(
      (p) => p.userId != widget.currentUserId,
      orElse: () => widget.match.players.last,
    );

    final myCount = myColor == 'white' ? state.whitePocketed : state.blackPocketed;
    final oppCount = myColor == 'white' ? state.blackPocketed : state.whitePocketed;
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      child: Column(
        children: [
          // Top Opponent Strip
          _CarromPlayerStrip(
            name: opponent.displayName,
            avatarUrl: opponent.avatarUrl,
            scoreText: '$oppCount/9',
            isWhiteCoins: myColor != 'white',
            isActive: widget.match.turnUserId == opponent.userId && widget.match.isActive,
          ),
          const SizedBox(height: 8),

          // Interactive Carrom Board Canvas + Floating Emojis
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardPx = constraints.maxWidth;
                final flipY = myColor == 'black';
                final baseline = Offset(_strikerX * boardPx, .835 * boardPx);
                final blocked = state.coins.any((coin) => !coin.pocketed &&
                    (Offset(coin.x, flipY ? 1000 - coin.y : coin.y) -
                        Offset(_strikerX * 1000, 835)).distance < 54);

                return Stack(
                  children: [
                    GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: canShoot
                          ? (d) {
                              if (blocked || (d.localPosition - baseline).distance > boardPx * .12) return;
                              setState(() {
                                _dragStart = baseline;
                                _dragCurrent = d.localPosition;
                              });
                            }
                          : null,
                      onPanUpdate: canShoot
                          ? (d) {
                              if (_dragStart != null) setState(() => _dragCurrent = d.localPosition);
                            }
                          : null,
                      onPanCancel: () => setState(() {
                        _dragStart = null;
                        _dragCurrent = null;
                      }),
                      onPanEnd: canShoot
                          ? (_) {
                              if (_dragStart != null && _dragCurrent != null) {
                                // Pull-back slingshot aim vector
                                final pull = _dragStart! - _dragCurrent!;
                                final dist = pull.distance;
                                if (dist > 14 && pull.dy < -dist * .05) {
                                  final power = (dist / (boardPx * 0.15)).clamp(0.18, 1.0);
                                  var angle = math.atan2(pull.dy, pull.dx);
                                  if (flipY) angle = -angle;
                                  widget.onShoot(
                                    strikerX: _strikerX,
                                    angleRad: angle,
                                    power: power,
                                  );
                                }
                              }
                              setState(() {
                                _dragStart = null;
                                _dragCurrent = null;
                              });
                            }
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CustomPaint(
                          size: Size.square(boardPx),
                          painter: _CarromBoardPainter(
                            coins: state.coins,
                            strikerNormX: _strikerX,
                            showStriker: isMyTurn,
                            frame: _frame,
                            strikerBlocked: blocked,
                            flipBoard: flipY,
                            dragStart: _dragStart,
                            dragCurrent: _dragCurrent,
                          ),
                        ),
                      ),
                    ),
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

          // Bottom Player Strip
          _CarromPlayerStrip(
            name: me.displayName,
            avatarUrl: me.avatarUrl,
            scoreText: '$myCount/9',
            isWhiteCoins: myColor == 'white',
            isActive: isMyTurn,
          ),

          // Striker Horizontal Position Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF92400E),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFFB45309),
            ),
            child: Slider(
              value: _strikerX,
              min: 0.18,
              max: 0.82,
              onChanged: canShoot ? (v) => setState(() => _strikerX = v) : null,
            ),
          ),

          Text(
            _frame != null ? 'Shot in motion…' : isMyTurn
                ? (state.queenPendingCoverBy == myColor
                    ? 'Queen pocketed! Pocket one of your coins now to cover it.'
                    : 'Slide to position striker, then pull back & release to shoot!')
                : 'Waiting for opponent\'s shot...',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),

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
        ],
      ),
    );
  }
}

class _CarromPlayerStrip extends StatelessWidget {
  const _CarromPlayerStrip({
    required this.name,
    required this.scoreText,
    required this.isWhiteCoins,
    required this.isActive,
    this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;
  final String scoreText;
  final bool isWhiteCoins;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF1F5F9),
            border: Border.all(
              color: isActive ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
              width: isActive ? 2 : 1.2,
            ),
            image: (avatarUrl != null && avatarUrl!.isNotEmpty)
                ? DecorationImage(image: NetworkImage(avatarUrl!), fit: BoxFit.cover)
                : null,
          ),
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? const Icon(Icons.person_outline_rounded, size: 20, color: Color(0xFF94A3B8))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$name • $scoreText',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isWhiteCoins ? const Color(0xFFFEF3C7) : const Color(0xFF1E293B),
            border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
          ),
        ),
      ],
    );
  }
}

class _CarromBoardPainter extends CustomPainter {
  _CarromBoardPainter({
    required this.coins,
    required this.strikerNormX,
    required this.showStriker,
    required this.flipBoard,
    this.frame,
    required this.strikerBlocked,
    this.dragStart,
    this.dragCurrent,
  });

  final List<CarromCoin> coins;
  final List<dynamic>? frame;
  final double strikerNormX;
  final bool showStriker;
  final bool strikerBlocked;
  final bool flipBoard;
  final Offset? dragStart;
  final Offset? dragCurrent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final scale = s / 1000.0;

    // 1. Rich Walnut Wooden Frame
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(
      colors: [Color(0xFF69391E), Color(0xFF32180C), Color(0xFF795032)],
    ).createShader(Offset.zero & size));

    // 2. Pale Birch Playing Surface
    final margin = 46 * scale;
    final playRect = Rect.fromLTWH(margin, margin, s - margin * 2, s - margin * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(playRect, const Radius.circular(12)),
      Paint()..shader = const RadialGradient(
        colors: [Color(0xFFFFE9BD), Color(0xFFD9A871)],
      ).createShader(playRect),
    );

    // 3. 4 Dark Corner Pockets
    final pocketOffset = 54 * scale;
    final pocketR = 36 * scale;
    final pocketPaint = Paint()..color = const Color(0xFF1C1917);
    for (final p in [
      Offset(pocketOffset, pocketOffset),
      Offset(s - pocketOffset, pocketOffset),
      Offset(pocketOffset, s - pocketOffset),
      Offset(s - pocketOffset, s - pocketOffset),
    ]) {
      canvas.drawCircle(p, pocketR, pocketPaint);
    }

    // 4. Center Compass Circle
    final center = Offset(s / 2, s / 2);
    canvas.drawCircle(
      center,
      115 * scale,
      Paint()
        ..color = const Color(0xFF991B1B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      center,
      28 * scale,
      Paint()..color = const Color(0xFFDC2626).withOpacity(0.25),
    );

    // 5. Top & Bottom Baselines
    final linePaint = Paint()
      ..color = const Color(0xFF78350F)
      ..strokeWidth = 1.6;
    for (final yNorm in [165.0, 835.0]) {
      final y = yNorm * scale;
      canvas.drawLine(Offset(180 * scale, y), Offset(820 * scale, y), linePaint);
      canvas.drawCircle(Offset(180 * scale, y), 18 * scale, Paint()..color = const Color(0xFFDC2626));
      canvas.drawCircle(Offset(820 * scale, y), 18 * scale, Paint()..color = const Color(0xFFDC2626));
    }

    // 6. Coins (9 White, 9 Black, 1 Pink Queen)
    final replay = frame;
    final playing = replay != null && replay.length == coins.length + 1;
    for (var i = 0; i < coins.length; i++) {
      final c = coins[i];
      final point = playing ? replay![i] as List? : null;
      if (playing ? point == null : c.pocketed) continue;
      final x = point == null ? c.x : (point[0] as num).toDouble();
      final y = point == null ? c.y : (point[1] as num).toDouble();
      final cx = x * scale;
      final cy = (flipBoard ? (1000.0 - y) : y) * scale;
      final pos = Offset(cx, cy);
      final r = 24 * scale;

      Color fill;
      Color ring;
      if (c.color == 'queen') {
        fill = const Color(0xFFEC4899);
        ring = const Color(0xFF9D174D);
      } else if (c.color == 'white') {
        fill = const Color(0xFFFFFBEB);
        ring = const Color(0xFFD97706);
      } else {
        fill = const Color(0xFF1E293B);
        ring = const Color(0xFF64748B);
      }

      canvas.drawCircle(pos + Offset(0, r * .18), r, Paint()..color = Colors.black38);
      canvas.drawCircle(pos, r, Paint()..shader = RadialGradient(
        center: const Alignment(-.4, -.5),
        colors: [Color.lerp(fill, Colors.white, .45)!, fill, ring],
        stops: const [0, .7, 1],
      ).createShader(Rect.fromCircle(center: pos, radius: r)));
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // 7. Ivory Striker + Pull-Back Dotted Aim Line
    final movingStriker = playing ? replay!.last as List? : null;
    if (playing ? movingStriker != null : showStriker) {
      final strikerPos = movingStriker == null
          ? Offset(strikerNormX * s, 835 * scale)
          : Offset(
              (movingStriker[0] as num).toDouble() * scale,
              (flipBoard ? 1000.0 - (movingStriker[1] as num).toDouble()
                  : (movingStriker[1] as num).toDouble()) * scale,
            );
      canvas.drawCircle(strikerPos, 30 * scale, Paint()..color = const Color(0xFFFEF9C3));
      canvas.drawCircle(
        strikerPos,
        30 * scale,
        Paint()
          ..color = strikerBlocked && !playing ? Colors.red : const Color(0xFFB45309)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      if (dragStart != null && dragCurrent != null) {
        final pull = dragStart! - dragCurrent!;
        if (pull.distance > 14 && pull.dy < -pull.distance * .05) {
          final power = (pull.distance / (s * .15)).clamp(.18, 1.0);
          canvas.drawArc(
            Rect.fromCircle(center: strikerPos, radius: 40 * scale),
            -math.pi / 2, power * math.pi * 2, false,
            Paint()..color = const Color(0xFFB45309)
              ..style = PaintingStyle.stroke..strokeWidth = 2.5,
          );
          final dir = pull / pull.distance;
          final aimLen = (pull.distance * 1.8).clamp(40.0, s * 0.45);
          final dotPaint = Paint()..color = const Color(0xFF0F172A);
          for (double d = 24; d < aimLen; d += 14) {
            canvas.drawCircle(strikerPos + dir * d, 3.0, dotPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CarromBoardPainter oldDelegate) => true;
}
