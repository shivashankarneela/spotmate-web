import '../widgets/music_player_native.dart' if (dart.library.html) '../widgets/music_player_web.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/music_room_models.dart';
import '../services/music_room_service.dart';
import '../widgets/synced_media_player.dart';
import '../../shared/connected_user_picker.dart';
import 'dart:convert';
import '../../live_tv/widgets/tv_room_player.dart';

/// Screen 3 of the Music Room flow:
/// - Live session countdown pill (30m Free / 30m or 60m Custom) + shareable Room Code
/// - Visible 16:9 synced Video + Audio player
/// - 5 empty circular dashed profile photo seats (golden HOST badge on Host)
/// - Live chat with Host-only Groovy-style commands (!play, !pause, !resume, !skip, !queue, !np, !stop)
/// - Floating music emoji reactions (🔥 🎵 💜 🕺)
class MusicRoomLiveScreen extends StatefulWidget {
  const MusicRoomLiveScreen({
    super.key,
    required this.initialRoom,
    required this.currentDisplayName,
    this.currentAvatarUrl,
    this.isTv = false,
  });

  final bool isTv;
  final MusicRoom initialRoom;
  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<MusicRoomLiveScreen> createState() => _MusicRoomLiveScreenState();
}

class _MusicRoomLiveScreenState extends State<MusicRoomLiveScreen> {
  late final _service = MusicRoomService(roomKind: widget.isTv ? 'tv' : 'music');
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  late MusicRoom _room;
  List<MusicRoomMember> _members = [];
  final List<MusicRoomMessage> _messages = [];
  final List<MusicEmojiBurst> _floatingEmojis = [];

  RealtimeChannel? _channel;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  static const List<String> _emojis = ['🔥', '🎵', '💜', '🕺'];

  bool get _isHost => _room.hostUserId == _service.currentUserId;

  @override
  void initState() {
    super.initState();
    _room = widget.initialRoom;
    _refreshState();
    _loadMessages();
    _startCountdown();

    _channel = _service.subscribeToRoom(
      roomId: _room.id,
      onRoomOrMembersChanged: _refreshState,
      onMessage: (msg) {
        if (!mounted) return;
        setState(() {
          if (!_messages.any((existing) => existing.id == msg.id)) _messages.add(msg);
        });
        _scrollToBottom();
      },
      onEmoji: (burst) {
        if (!mounted) return;
        setState(() => _floatingEmojis.add(burst));
        Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _floatingEmojis.removeWhere((e) => e.id == burst.id));
        });
      },
    );
  }

  void _startCountdown() {
    _updateRemaining();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final serverNow = DateTime.now().add(Duration(milliseconds: _service.clockSkewMs));
    final diff = _room.expiresAt.difference(serverNow);
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    if(diff.inMilliseconds<=0){
      _countdownTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted && ModalRoute.of(context)?.isCurrent==true)Navigator.of(context).pop();});
    }
  }

  Future<void> _refreshState() async {
    try {
      final res = await _service.syncRoomState(_room.id);
      if (!mounted) return;
      setState(() {
        if (res.room != null) _room = res.room!;
        _members = res.members;
      });
      if ((_room.status != 'active' || _room.expiresAt.isBefore(
          DateTime.now().add(Duration(milliseconds: _service.clockSkewMs)))) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Music Room session ended.')),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      final recent = await _service.fetchRecentMessages(_room.id);
      if (mounted) {
        setState(() {
          final knownIds = _messages.map((message) => message.id).toSet();
          _messages.insertAll(0, recent.where((message) => !knownIds.contains(message.id)));
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _inviteConnection() async {
    final person = await pickConnectedUser(context,
      excludedUserIds: _members.map((member) => member.userId).toSet());
    if (person == null || !mounted) return;
    try {
      final state = await _service.syncRoomState(_room.id);
      final room = state.room;
      if (room == null || !room.isActive || state.members.length >= room.maxMembers) {
        throw StateError('Room is full or has ended.');
      }
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw StateError('Sign in required.');
      final payload = jsonEncode({
        'code': room.roomCode,
        'title': room.title,
        'kind': widget.isTv ? 'tv' : 'music',
      });
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': person.conversationId,
        'sender_id': user.id,
        'message': 'Room invite · ' + payload,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${person.name}.')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send invite. The room may be full or closed.')),
      );
    }
  }

  Future<void> _controlPlayback(String command) async {
    try {
      await _service.sendChatOrCommand(
        roomId: _room.id,
        displayName: widget.currentDisplayName,
        text: command,
      );
      await _refreshState();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update playback. Try again.')),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    try {
      await _service.sendChatOrCommand(
        roomId: _room.id,
        displayName: widget.currentDisplayName,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        if (_msgController.text.isEmpty) _msgController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Try again.')),
        );
      }
    }
  }



  @override
  void dispose() {
    _countdownTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    if (_channel != null) _service.removeChannel(_channel!);
    _service.leaveRoom(_room.id);
    super.dispose();
  }

  String _fmtTimer(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs left';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _room.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 16),
            ),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _room.roomCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied room code ${_room.roomCode}')),
                );
              },
              child: Text(
                'Code: ${_room.roomCode} (tap to copy)',
                style: const TextStyle(color: Color(0xFF0D9488), fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Invite a connection',
            onPressed: _inviteConnection,
            icon: const Icon(Icons.person_add_alt_1),
          ),
          if (_isHost && _room.mode == 'free' && _members.any((m)=>m.userId!=_room.hostUserId))
            PopupMenuButton<String>(
              tooltip:'Make another listener host',icon:const Icon(Icons.manage_accounts_outlined),
              itemBuilder:(_)=>[for(final m in _members.where((m)=>m.userId!=_room.hostUserId))
                PopupMenuItem(value:m.userId,child:Text('Make ${m.displayName} host'))],
              onSelected:(id)async{
                try{await _service.transferHost(_room.id,id);await _refreshState();}
                catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
              },
            ),

          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '⏱ ${_fmtTimer(_remaining)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Visible 16:9 Synced Video + Audio Player + Floating Emojis
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Stack(
              children: [
                if (widget.isTv) TvRoomPlayer(room: _room, service: _service) else SyncedMediaPlayerCard(
                  youtubeWidgetBuilder: musicVideo,
                  room: _room,
                  clockSkewMs: _service.clockSkewMs,
                ),
                if (_floatingEmojis.isNotEmpty)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _floatingEmojis.map((ev) {
                        return Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${ev.senderName}: ${ev.emoji}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.isTv) Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _room.currentSourceRef == null ? null : () =>
                    _controlPlayback(_room.isPlaying ? '!pause' : '!resume'),
                icon: Icon(_room.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(_room.isPlaying ? 'Pause' : 'Resume'),
              ),
              TextButton.icon(
                onPressed: _room.currentSourceRef == null ? null : () => _controlPlayback('!skip'),
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip'),
              ),
            ],
          ),

          // 5 Empty Circular Profile Photo Seats (Host Crown on Host)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (idx) {
                final member = idx < _members.length ? _members[idx] : null;
                final isHostSeat = member != null && member.userId == _room.hostUserId;

                return Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF1F5F9),
                            border: Border.all(
                              color: isHostSeat
                                  ? const Color(0xFFF59E0B)
                                  : (member != null ? const Color(0xFF0D9488) : const Color(0xFFCBD5E1)),
                              width: isHostSeat ? 2.2 : 1.2,
                            ),
                            image: (member?.avatarUrl != null && member!.avatarUrl!.isNotEmpty)
                                ? DecorationImage(
                                    image: NetworkImage(member.avatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (member?.avatarUrl == null || member!.avatarUrl!.isEmpty)
                              ? Icon(
                                  Icons.person_outline_rounded,
                                  size: 22,
                                  color: member != null ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                )
                              : null,
                        ),
                        if (isHostSeat)
                          Positioned(
                            top: -7,
                            left: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF08A),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFFD97706)),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'HOST',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 56,
                      child: Text(
                        member?.displayName ?? 'Open',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 10),

          // Live Chat & MusicBot Command Feed
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              itemCount: _messages.length,
              itemBuilder: (_, idx) {
                final m = _messages[idx];
                final isBot = m.kind == 'bot';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: isBot ? const Color(0xFFDCFCE7) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isBot ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                      children: [
                        TextSpan(
                          text: '${m.displayName}: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isBot ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                          ),
                        ),
                        TextSpan(text: m.content),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Chat / !play Input + Quick Emojis
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgController,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: widget.isTv ? 'Send a message...' : 'Message or !play <song>...',
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
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
                        onPressed: _send,
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF059669)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _emojis.map((em) {
                      return InkWell(
                        onTap: () {
                          if (_channel != null) {
                            _service.sendEmojiBurst(
                              channel: _channel!,
                              displayName: widget.currentDisplayName,
                              emoji: em,
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          child: Text(em, style: const TextStyle(fontSize: 22)),
                        ),
                      );
                    }).toList(),
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
