import 'staunton_piece_painter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/arena_models.dart';
import '../models/chess_models.dart';
import '../models/snakes_models.dart';
import '../services/snakes_chat_service.dart';

/// Screen 2 of the Chess flow:
/// - Opponent & Player strips with empty circular profile slots + live chess clocks
/// - Interactive 8x8 Warm Cream & Emerald chessboard (auto-oriented for White or Black)
/// - Tap-to-move with pawn promotion dialog, Draw Offer banner, and live in-game chat + emojis
class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.match,
    required this.currentUserId,
    required this.currentDisplayName,
    required this.busy,
    required this.onMove,
    required this.onOfferDraw,
    required this.onRespondDraw,
    required this.onResign,
  });

  final ArenaMatch match;
  final String currentUserId;
  final String currentDisplayName;
  final bool busy;
  final void Function(String from, String to, {String promotion}) onMove;
  final VoidCallback onOfferDraw;
  final void Function(bool accept) onRespondDraw;
  final VoidCallback onResign;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  final _chatService = MatchChatService();
  final _msgController = TextEditingController();
  RealtimeChannel? _chatChannel;

  final List<MatchChatMessage> _messages = [];
  final List<FloatingEmojiEvent> _floatingEmojis = [];
  String? _selectedSquare;

  static const List<String> _quickEmojis = ['🤔', '🔥', '👏', '😅', '👑'];
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

  String _formatClock(int ms) {
    final totalSecs = (ms / 1000).ceil().clamp(0, 3600);
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _handleSquareTap(
    String square,
    String? piece,
    bool iAmWhite,
    bool isMyTurn,
  ) async {
    if (!isMyTurn || widget.busy) return;

    final isMyPiece = piece != null && (iAmWhite ? piece == piece.toUpperCase() : piece == piece.toLowerCase());

    if (_selectedSquare == null) {
      if (isMyPiece) setState(() => _selectedSquare = square);
      return;
    }

    if (_selectedSquare == square) {
      setState(() => _selectedSquare = null);
      return;
    }

    if (isMyPiece) {
      setState(() => _selectedSquare = square);
      return;
    }

    final from = _selectedSquare!;
    setState(() => _selectedSquare = null);

    // Check pawn promotion on rank 8 (White) or rank 1 (Black)
    final isPromotion = (iAmWhite && square.endsWith('8')) || (!iAmWhite && square.endsWith('1'));
    String promo = 'q';
    if (isPromotion) {
      promo = await _pickPromotionPiece() ?? 'q';
    }
    widget.onMove(from, square, promotion: promo);
  }

  Future<String?> _pickPromotionPiece() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promote Pawn'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final p in const [('q', '♕'), ('r', '♖'), ('b', '♗'), ('n', '♘')])
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(p.$1),
                icon: Text(p.$2, style: const TextStyle(fontSize: 32)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ChessState.fromJson(widget.match.state);
    final board = state.parseBoard();
    final iAmWhite = widget.currentUserId == state.whiteId;
    final isMyTurn = widget.match.isActive && widget.match.turnUserId == widget.currentUserId;

    final me = widget.match.players.firstWhere(
      (p) => p.userId == widget.currentUserId,
      orElse: () => widget.match.players.first,
    );
    final opponent = widget.match.players.firstWhere(
      (p) => p.userId != widget.currentUserId,
      orElse: () => widget.match.players.last,
    );

    final opponentOfferedDraw =
        state.drawOfferBy != null && state.drawOfferBy != widget.currentUserId;
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      child: Column(
        children: [
          // Incoming Draw Offer Banner
          if (opponentOfferedDraw && widget.match.isActive)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Opponent offered a draw (SC refunded).',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onRespondDraw(false),
                    child: const Text('Decline'),
                  ),
                  ElevatedButton(
                    onPressed: () => widget.onRespondDraw(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ),

          // Top Opponent Strip
          _ChessPlayerBar(
            name: opponent.displayName,
            avatarUrl: opponent.avatarUrl,
            clockText: _formatClock(state.clocksMs[opponent.userId] ?? 300000),
            isActive: widget.match.turnUserId == opponent.userId && widget.match.isActive,
          ),
          const SizedBox(height: 8),

          // Interactive 8x8 Board + Floating Emojis
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                    itemCount: 64,
                    itemBuilder: (_, idx) {
                      final displayRow = idx ~/ 8;
                      final displayCol = idx % 8;
                      final r = iAmWhite ? displayRow : 7 - displayRow;
                      final c = iAmWhite ? displayCol : 7 - displayCol;
                      final square = '${String.fromCharCode(97 + c)}${8 - r}';
                      final piece = board[r][c];
                      final isLight = (r + c).isEven;
                      final isSelected = _selectedSquare == square;
                      final isLast = state.lastMoveFrom == square || state.lastMoveTo == square;

                      Color bg = isLight ? const Color(0xFFFAF8F3) : const Color(0xFF15803D);
                      if (isLast) bg = const Color(0xFFFDE047);
                      if (isSelected) bg = const Color(0xFF60A5FA);

                      return GestureDetector(
                        onTap: () => _handleSquareTap(square, piece, iAmWhite, isMyTurn),
                        child: Container(
                          color: bg,
                          alignment: Alignment.center,
                          child: piece == null
                              ? null
                              : FractionallySizedBox(
                                  widthFactor: .9,
                                  heightFactor: .9,
                                  child: StauntonPieceWidget(
                                    pieceCode: '${piece == piece.toUpperCase() ? 'w' : 'b'}${piece.toUpperCase()}',
                                  ),
                                ),
                        ),
                      );
                    },
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
            ),
          ),
          const SizedBox(height: 8),

          // Bottom Player Strip
          _ChessPlayerBar(
            name: me.displayName,
            avatarUrl: me.avatarUrl,
            clockText: _formatClock(state.clocksMs[me.userId] ?? 300000),
            isActive: isMyTurn,
          ),
          const SizedBox(height: 8),

          // Draw & Resign Pills
          if (widget.match.isActive)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onOfferDraw,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('Draw', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onResign,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('Resign', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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

class _ChessPlayerBar extends StatelessWidget {
  const _ChessPlayerBar({
    required this.name,
    required this.clockText,
    required this.isActive,
    this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;
  final String clockText;
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
            border: Border.all(color: const Color(0xFFCBD5E1)),
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
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? const Color(0xFF059669) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            clockText,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
