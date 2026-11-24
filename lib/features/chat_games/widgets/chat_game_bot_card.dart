import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_game_models.dart';
import '../plugins/chat_game_plugin.dart';

/// Compact in-chat bot card designed for Spotmate's Warm Paper (#FAF8F3) public chat rooms.
class ChatGameBotCard extends StatefulWidget {
  const ChatGameBotCard({
    super.key,
    required this.session,
    this.onRequestHint,
    this.onExpired,
  });

  final ChatGameSession session;
  final VoidCallback? onRequestHint;
  final VoidCallback? onExpired;

  @override
  State<ChatGameBotCard> createState() => _ChatGameBotCardState();
}

class _ChatGameBotCardState extends State<ChatGameBotCard> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _expiredFired = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ChatGameBotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.status != widget.session.status) {
      _expiredFired = false;
      _syncTimer();
    }
  }

  void _syncTimer() {
    _ticker?.cancel();
    _remaining = widget.session.remainingTime;
    if (widget.session.status != ChatGameStatus.active) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = widget.session.remainingTime;
      setState(() => _remaining = next);
      if (next == Duration.zero && !_expiredFired) {
        _expiredFired = true;
        _ticker?.cancel();
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plugin = ChatGamePluginRegistry.of(widget.session.gameType);
    final totalSecs = widget.session.expiresAt
        .difference(widget.session.startedAt)
        .inSeconds
        .clamp(1, 600);
    final progress = (_remaining.inSeconds / totalSecs).clamp(0.0, 1.0);
    final hintLine = plugin.formatHintLine(widget.session);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: plugin.accentColor.withOpacity(0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Game badge + Category + Reward + Timer
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: plugin.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(plugin.icon, size: 15, color: plugin.accentColor),
                    const SizedBox(width: 5),
                    Text(
                      widget.session.gameType.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: plugin.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.session.category,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              if (widget.session.status == ChatGameStatus.active) ...[
                const SizedBox(width: 8),
                Text(
                  '${_remaining.inSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _remaining.inSeconds <= 10 ? const Color(0xFFDC2626) : const Color(0xFF334155),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Main Prompt
          Text(
            plugin.formatHeadline(widget.session),
            style: TextStyle(
              fontSize: widget.session.gameType == ChatGameType.hangman ? 18 : 15,
              fontWeight: FontWeight.w700,
              letterSpacing: widget.session.gameType == ChatGameType.hangman ? 1.5 : 0.0,
              color: const Color(0xFF0F172A),
            ),
          ),

          // 5-Letter Word Attempts Grid
          if (widget.session.gameType == ChatGameType.fiveLetter &&
              widget.session.fiveLetterAttempts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...widget.session.fiveLetterAttempts.map(_buildFiveLetterRow),
          ],

          // Hint line
          if (hintLine != null) ...[
            const SizedBox(height: 8),
            Text(
              hintLine,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
          ],

          // Active countdown progress bar + Hint trigger
          if (widget.session.status == ChatGameStatus.active) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(plugin.accentColor),
                    ),
                  ),
                ),
                if (widget.onRequestHint != null &&
                    widget.session.gameType != ChatGameType.fiveLetter) ...[
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: widget.onRequestHint,
                    icon: const Icon(Icons.lightbulb_outline, size: 15),
                    label: const Text('Hint', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Solved or Expired Footer Banner
          if (widget.session.status == ChatGameStatus.solved) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🎉 ${widget.session.winnerDisplayName ?? "Winner"} solved it! '
                'Answer: ${widget.session.revealedAnswer ?? ""}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF166534),
                ),
              ),
            ),
          ] else if (widget.session.status == ChatGameStatus.expired) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '⏱ Time up! Answer: ${widget.session.revealedAnswer ?? ""}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiveLetterRow(FiveLetterAttempt attempt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          for (var i = 0; i < attempt.guess.length; i++)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tileColor(i < attempt.statuses.length ? attempt.statuses[i] : 'absent'),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                attempt.guess[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              attempt.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Color _tileColor(String status) {
    switch (status) {
      case 'correct':
        return const Color(0xFF16A34A);
      case 'present':
        return const Color(0xFFCA8A04);
      default:
        return const Color(0xFF64748B);
    }
  }
}
