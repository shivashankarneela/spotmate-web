import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';

/// A public, per-venue conversation. Members can read and post with a
/// Spotmate account; one-to-one chats still require an accepted request.
class HotspotPublicChatScreen extends StatefulWidget {
  const HotspotPublicChatScreen({
    super.key,
    required this.hotspotId,
    required this.hotspotName,
  });

  final String hotspotId;
  final String hotspotName;

  @override
  State<HotspotPublicChatScreen> createState() => _HotspotPublicChatScreenState();
}

class _HotspotPublicChatScreenState extends State<HotspotPublicChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _messages = [];
  final Set<String> _pendingRequests = {};
  final Set<String> _connectedUsers = {};
  bool _loading = true;
  bool _sending = false;
  String? _loadError;

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _supabase
        .channel('hotspot-chat-${widget.hotspotId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'hotspot_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'hotspot_id',
            value: widget.hotspotId,
          ),
          callback: (_) => _load(quiet: true),
        )
        .subscribe();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('hotspot_messages')
          .select('id, sender_id, body, created_at, user_profiles!hotspot_messages_sender_id_fkey(name, profile_photo, avatar_type, avatar_emoticon)')
          .eq('hotspot_id', widget.hotspotId)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows.reversed);
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load the hotspot conversation. Try again.';
        });
      }
    }
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    final uid = _userId;
    if (uid == null || body.isEmpty || _sending || body.length > 500) return;

    setState(() => _sending = true);
    try {
      await _supabase.from('hotspot_messages').insert({
        'hotspot_id': widget.hotspotId,
        'sender_id': uid,
        'body': body,
      });
      _messageController.clear();
      await _load(quiet: true);
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be sent. Please try again shortly.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMember(String targetId, String name) async {
    if (targetId.isEmpty || targetId == _userId) return;
    bool requested = _pendingRequests.contains(targetId);
    bool connected = _connectedUsers.contains(targetId);
    if (!requested && !connected) {
      try {
        final requests = await _supabase.from('connection_requests')
            .select('id')
            .eq('sender_id', _userId!)
            .eq('receiver_id', targetId)
            .eq('status', 'pending')
            .limit(1);
        final relationships = await _supabase.from('connections')
            .select('id')
            .or('and(user1_id.eq.${_userId!},user2_id.eq.$targetId),and(user1_id.eq.$targetId,user2_id.eq.${_userId!})')
            .limit(1);
        requested = requests.isNotEmpty;
        connected = relationships.isNotEmpty;
        if (requested) _pendingRequests.add(targetId);
        if (connected) _connectedUsers.add(targetId);
      } catch (_) {}
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFE0F7F0),
              child: Icon(Icons.person_outline_rounded,
                  color: Color(0xFF162544), size: 30),
            ),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Private messages are available only after a connection request is accepted.',
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (requested || connected) ? null : () async {
                  Navigator.pop(ctx);
                  await _requestConnection(targetId, name);
                },
                icon: Icon(connected
                    ? Icons.check_circle_outline
                    : requested ? Icons.hourglass_bottom : Icons.person_add_alt_1),
                label: Text(connected
                    ? 'Already connected'
                    : requested ? 'Request pending' : 'Send private chat request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestConnection(String targetId, String name) async {
    final uid = _userId;
    if (uid == null || uid == targetId || _pendingRequests.contains(targetId)) return;
    try {
      await _supabase.from('connection_requests').insert({
        'sender_id': uid,
        'receiver_id': targetId,
        'hotspot_id': widget.hotspotId,
        'status': 'pending',
      });
      _pendingRequests.add(targetId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection request sent to $name.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send request. You may already have a request with this person.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF162544);
    const mint = Color(0xFF35D6B4);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F9),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.hotspotName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const Text('Public hotspot chat',
              style: TextStyle(fontSize: 12, color: Color(0xFF657087))),
        ]),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            color: const Color(0xFFEAF8F4),
            child: const Row(children: [
              Icon(Icons.forum_outlined, color: ink, size: 18),
              SizedBox(width: 9),
              Expanded(child: Text(
                'Everyone here can read this chat. Tap a name to request a private connection.',
                style: TextStyle(color: ink, fontSize: 12),
              )),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min, children: [
                          Text(_loadError!, textAlign: TextAlign.center),
                          TextButton(onPressed: () => _load(), child: const Text('Retry')),
                        ],
                      ))
                    : _messages.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(25),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      color: ink, size: 46),
                                  SizedBox(height: 12),
                                  Text('Start the conversation',
                                      style: TextStyle(fontSize: 18,
                                          fontWeight: FontWeight.w700, color: ink)),
                                  SizedBox(height: 6),
                                  Text('Say hello, ask what is happening, or share a friendly recommendation.',
                                      textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final senderId = message['sender_id']?.toString() ?? '';
                              final mine = senderId == _userId;
                              final profile = message['user_profiles'] as Map<String, dynamic>?;
                              final name = profile?['name']?.toString() ?? 'Spotmate member';
                              final body = message['body']?.toString() ?? '';
                              final created = DateTime.tryParse(
                                  message['created_at']?.toString() ?? '')?.toLocal();
                              final time = created == null ? '' :
                                  '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  if (!mine) ...[
                                    GestureDetector(
                                      onTap:()=>_showMember(senderId,name),
                                      child:SpotmateAvatar(
                                        size:32,
                                        photoUrl:profile?['profile_photo']?.toString(),
                                        avatarType:profile?['avatar_type']?.toString() ?? 'photo',
                                        emoticon:profile?['avatar_emoticon']?.toString() ?? 'smile',
                                      ),
                                    ),
                                    const SizedBox(width:8),
                                  ],
                                  Flexible(child: Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * .82),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: mine ? const Color(0xFFDCF8F0) : Colors.white,
                                      border: Border.all(color: const Color(0xFFE4ECEF)),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: mine ? null : () => _showMember(senderId, name),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            Text(mine ? 'You' : name,
                                              style: const TextStyle(color: ink,
                                                fontWeight: FontWeight.w800, fontSize: 12)),
                                            if (!mine) ...[
                                              const SizedBox(width: 5),
                                              const Icon(Icons.person_add_alt_1,
                                                  size: 14, color: ink),
                                            ],
                                          ]),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(body, style: const TextStyle(fontSize: 14, color: ink)),
                                        if (time.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(time, style: const TextStyle(
                                              fontSize: 10, color: Color(0xFF657087))),
                                        ],
                                      ],
                                    ),
                                  ),
                                ))),
                                ],
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Say something to the hotspot...',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: ink,
                      foregroundColor: mint,
                    ),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
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
