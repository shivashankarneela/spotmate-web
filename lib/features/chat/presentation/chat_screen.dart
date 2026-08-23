import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:spotmate/features/chat/presentation/active_call_screen.dart';
import 'package:spotmate/features/profile/presentation/user_profile_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserPhoto;
  final String? otherUserId;
  final String? connectionId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserPhoto,
    this.otherUserId,
    this.connectionId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMessagesAndMarkRead();
    _subscribeToRealtime();
  }

  Future<void> _fetchMessagesAndMarkRead() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final response = await _supabase
          .from('messages')
          .select('id, sender_id, message, created_at, read_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(List<Map<String, dynamic>>.from(response));
          _isLoading = false;
        });
      }

      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', myId)
          .isFilter('read_at', null);

    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToRealtime() {
    final myId = _supabase.auth.currentUser?.id;

    _subscription = _supabase
        .channel('public:messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) async {
            if (!mounted) return;

            if (payload.eventType == PostgresChangeEvent.insert) {
              final newMsg = payload.newRecord;
              setState(() {
                _messages.add(newMsg);
              });

              if (newMsg['sender_id'] != myId && newMsg['read_at'] == null) {
                await _supabase
                    .from('messages')
                    .update({'read_at': DateTime.now().toIso8601String()})
                    .eq('id', newMsg['id']);
              }
            } else if (payload.eventType == PostgresChangeEvent.update) {
              final updated = payload.newRecord;
              setState(() {
                final idx = _messages.indexWhere((m) => m['id'] == updated['id']);
                if (idx != -1) {
                  _messages[idx] = updated;
                }
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final user = _supabase.auth.currentUser;
    if (text.isEmpty || user == null) return;

    _messageController.clear();

    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message': text,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _initiateCall(bool isVideo) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || widget.otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start call at this moment.')),
      );
      return;
    }

    try {
      final callRes = await _supabase.from('calls').insert({
        'caller_id': myId,
        'receiver_id': widget.otherUserId,
        'conversation_id': widget.conversationId,
        'call_type': isVideo ? 'video' : 'audio',
        'status': 'ringing',
      }).select('id').single();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              callId: callRes['id'],
              otherUserName: widget.otherUserName,
              otherUserPhoto: widget.otherUserPhoto,
              isVideo: isVideo,
              isCaller: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call failed to start: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myId = _supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            if (widget.otherUserId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileDetailScreen(
                    userId: widget.otherUserId!,
                    connectionId: widget.connectionId,
                  ),
                ),
              );
            }
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey[300],
                backgroundImage: widget.otherUserPhoto != null && widget.otherUserPhoto!.isNotEmpty
                    ? NetworkImage(widget.otherUserPhoto!)
                    : null,
                child: widget.otherUserPhoto == null || widget.otherUserPhoto!.isEmpty
                    ? const Icon(Icons.person, size: 18, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherUserName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Text('Tap to view profile', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined, color: Color(0xFFFF4B6E)),
            tooltip: 'Audio Call',
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: Color(0xFFFF4B6E)),
            tooltip: 'Video Call',
            onPressed: () => _initiateCall(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Say hi to ${widget.otherUserName}! 👋',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_id'] == myId;
                          final isRead = msg['read_at'] != null;
                          final time = DateTime.tryParse(msg['created_at'] ?? '')?.toLocal();
                          final formattedTime = time != null ? DateFormat('hh:mm a').format(time) : '';

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? theme.colorScheme.primary : Colors.grey[200],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
                                  bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg['message'] ?? '',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formattedTime,
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.black45,
                                          fontSize: 10,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        if (isRead) ...[
                                          const Icon(Icons.done_all_rounded, size: 14, color: Colors.lightBlueAccent),
                                          const SizedBox(width: 2),
                                          const Icon(Icons.remove_red_eye_outlined, size: 12, color: Colors.lightBlueAccent),
                                        ] else ...[
                                          const Icon(Icons.done_rounded, size: 14, color: Colors.white70),
                                        ],
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                    onPressed: _sendMessage,
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
