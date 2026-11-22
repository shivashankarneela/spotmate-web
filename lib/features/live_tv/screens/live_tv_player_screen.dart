import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/live_tv_models.dart';
import '../services/live_tv_service.dart';
import '../widgets/live_tv_player.dart';

/// Live TV Watch-Together Screen:
/// 16:9 Live TV player on top + viewer badge + quick emoji bursts + live chat below.
class LiveTvPlayerScreen extends StatefulWidget {
  const LiveTvPlayerScreen({
    super.key,
    required this.channel,
    required this.currentDisplayName,
    this.currentAvatarUrl,
    this.onShareChannel,
  });

  final LiveTvChannel channel;
  final String currentDisplayName;
  final String? currentAvatarUrl;
  final void Function(SharedLiveTvPayload payload)? onShareChannel;

  @override
  State<LiveTvPlayerScreen> createState() => _LiveTvPlayerScreenState();
}

class _LiveTvPlayerScreenState extends State<LiveTvPlayerScreen> {
  final _service = LiveTvService();
  final _chatController = TextEditingController();
  final List<LiveTvChatMessage> _messages = [];
  RealtimeChannel? _rtChannel;
  Timer? _heartbeatTimer;
  int _viewerCount = 1;

  static const _quickEmojis = ['🔥', '👏', '😂', '❤️', '🏏'];

  @override
  void initState() {
    super.initState();
    _viewerCount = widget.channel.viewerCount > 0 ? widget.channel.viewerCount : 1;
    _initRoom();
  }

  Future<void> _initRoom() async {
    try {
      final msgs = await _service.fetchRecentMessages(widget.channel.id);
      if (mounted) setState(() => _messages.addAll(msgs));
      final vc = await _service.pingViewer(widget.channel.id);
      if (mounted) setState(() => _viewerCount = vc);
    } catch (_) {}

    _rtChannel = _service.subscribeToChat(
      channelId: widget.channel.id,
      onMessage: (msg) {
        if (!mounted) return;
        setState(() => _messages.add(msg));
      },
    );

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      try {
        final vc = await _service.pingViewer(widget.channel.id);
        if (mounted) setState(() => _viewerCount = vc);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    if (_rtChannel != null) _service.removeChannel(_rtChannel!);
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? emoji}) async {
    final text = emoji == null ? _chatController.text.trim() : null;
    if (emoji == null && (text == null || text.isEmpty)) return;
    if (emoji == null) _chatController.clear();
    try {
      await _service.sendChat(
        channelId: widget.channel.id,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
        body: text,
        reactionEmoji: emoji,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              '${c.category} • ${c.language} • $_viewerCount watching',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          if (widget.onShareChannel != null)
            IconButton(
              tooltip: 'Share to Private Chat',
              icon: const Icon(Icons.send_rounded, color: Color(0xFFD97706)),
              onPressed: () => widget.onShareChannel!(
                SharedLiveTvPayload(
                  channelId: c.id,
                  name: c.name,
                  category: c.category,
                  language: c.language,
                  streamType: c.streamType,
                  streamSource: c.streamSource,
                  logoUrl: c.logoUrl,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          LiveTvPlayer(channel: c),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Text(
                  'Live Reactions',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
                const Spacer(),
                for (final e in _quickEmojis)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () => _sendMessage(emoji: e),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF8F3),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 15)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start chatting with viewers watching this channel.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            m.avatarUrl != null && m.avatarUrl!.isNotEmpty
                                ? CircleAvatar(radius: 15, backgroundImage: NetworkImage(m.avatarUrl!))
                                : Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(color: const Color(0xFF94A3B8), width: 1.2),
                                    ),
                                  ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.displayName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    m.reactionEmoji ?? m.body ?? '',
                                    style: TextStyle(
                                      fontSize: m.reactionEmoji != null ? 20 : 13.5,
                                      color: const Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Say something in Live TV chat...',
                        filled: true,
                        fillColor: const Color(0xFFFAF8F3),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _sendMessage(),
                    icon: const Icon(Icons.send_rounded, color: Color(0xFFD97706)),
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
