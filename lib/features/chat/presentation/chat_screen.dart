import 'dart:async';
import 'package:spotmate/core/utils/spotmate_image_upload.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _subscription;
  bool _isLoading = true;
  bool _showEmojiTray = false;
  bool _isUploadingImage = false;
  bool _otherUserOnline = false;
  DateTime? _otherUserLastSeen;
  Timer? _presenceRefreshTimer;

  final Map<String, Future<String>> _signedImageLinks = {};

  Future<String> _getChatImageUrl(String imagePath) {
    if (imagePath.startsWith('https://')) return Future.value(imagePath);
    return _signedImageLinks.putIfAbsent(imagePath, () =>
      _supabase.storage.from('chat_media').createSignedUrl(imagePath, 3600));
  }

  final List<String> _quickEmojis = [
    '❤️', '😂', '😍', '🔥', '👋', '☕', '🍕', '🎉', '💯', '😎', '🥂', '✨', '💬', '🙌', '🥰', '👍'
  ];

  @override
  void initState() {
    super.initState();
    _fetchMessagesAndMarkRead();
    _subscribeToRealtime();
    _fetchOtherUserPresence();

    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchOtherUserPresence(),
    );
  }
  Future<void> _fetchOtherUserPresence() async {
    final otherUserId = widget.otherUserId;
    if (otherUserId == null) return;

    try {
      final profile = await _supabase
          .from('user_profiles')
          .select('last_seen_at')
          .eq('id', otherUserId)
          .maybeSingle();

      if (!mounted) return;

      final rawLastSeen = profile?['last_seen_at'];
      final lastSeen = rawLastSeen != null
          ? DateTime.tryParse(rawLastSeen.toString())?.toLocal()
          : null;

      final isOnline = lastSeen != null &&
          DateTime.now().difference(lastSeen).inSeconds < 60;

      setState(() {
        _otherUserLastSeen = lastSeen;
        _otherUserOnline = isOnline;
      });
    } catch (_) {}
  }

  String _presenceText() {
    if (_otherUserOnline) return 'Online';

    final lastSeen = _otherUserLastSeen;
    if (lastSeen == null) return 'Offline';

    final difference = DateTime.now().difference(lastSeen);

    if (difference.inSeconds < 60) {
      return 'Last seen just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return 'Last seen $minutes min ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return 'Last seen $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    if (difference.inDays == 1) {
      return 'Last seen yesterday';
    }

    return 'Last seen ${DateFormat('dd MMM').format(lastSeen)}';
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _fetchMessagesAndMarkRead() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      final response = await _supabase
          .from('messages')
          .select('id, sender_id, message, image_url, created_at, read_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(List<Map<String, dynamic>>.from(response));
          _isLoading = false;
        });
        _scrollToBottom();
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
              
              if (!_messages.any((m) => m['id'] == newMsg['id'])) {
                setState(() {
                  _messages.add(newMsg);
                });
                _scrollToBottom();
              }

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
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final deletedId = payload.oldRecord['id'];
              setState(() {
                _messages.removeWhere((m) => m['id'] == deletedId);
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    final user = _supabase.auth.currentUser;
    if ((text.isEmpty && imageUrl == null) || user == null) return;

    _messageController.clear();

    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'message': text.isNotEmpty ? text : (imageUrl != null ? '📷 Photo' : ''),
        if (imageUrl != null) 'image_url': imageUrl,
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAndSendPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 82);
    if (pickedFile == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final image = await prepareSpotmateImage(
          await pickedFile.readAsBytes(), maxBytes: 10 * 1024 * 1024);
      final fileName = '${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}.${image.extension}';

      await _supabase.storage.from('chat_media').uploadBinary(
        fileName,
        image.bytes,
        fileOptions: FileOptions(upsert: false, contentType: image.mimeType),
      );

      await _sendMessage(imageUrl: fileName);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Chat History?'),
          ],
        ),
        content: const Text('Are you sure you want to clear all messages in this conversation? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('messages').delete().eq('conversation_id', widget.conversationId);
        setState(() => _messages.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat history cleared.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteSingleMessage(String msgId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Do you want to delete this message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('messages').delete().eq('id', msgId);
      } catch (_) {}
    }
  }

  Future<void> _initiateCall(bool isVideo) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || widget.otherUserId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to identify the other user. Reopen this conversation and try again.')));
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
          SnackBar(content: Text('Call failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _presenceRefreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 1,
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
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('User profile unavailable. Reopen the chat and try again.')));
            }
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: Colors.grey[300],
                backgroundImage: widget.otherUserPhoto != null && widget.otherUserPhoto!.isNotEmpty
                    ? NetworkImage(widget.otherUserPhoto!)
                    : null,
                child: widget.otherUserPhoto == null || widget.otherUserPhoto!.isEmpty
                    ? const Icon(Icons.person, size: 19, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherUserName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Text(_presenceText(), style: TextStyle(fontSize: 11, color: _otherUserOnline ? const Color(0xFF22A06B) : const Color(0xFF737887), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Color(0xFF6C63FF)),
            tooltip: 'Audio Call',
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Color(0xFF6C63FF)),
            tooltip: 'Video Call',
            onPressed: () => _initiateCall(true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.black87),
            onSelected: (val) {
              if (val == 'clear') _clearChat();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Clear Chat History', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isUploadingImage)
            const LinearProgressIndicator(color: Color(0xFF6C63FF), minHeight: 3),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.favorite_rounded, size: 40, color: Color(0xFF6C63FF)),
                            ),
                            const SizedBox(height: 12),
                            Text('You matched with ${widget.otherUserName}!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Say hi or share a photo to start talking.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_id'] == myId;
                          final isRead = msg['read_at'] != null;
                          final imageUrl = msg['image_url'] as String?;
                          final text = msg['message'] ?? '';
                          final time = DateTime.tryParse(msg['created_at'] ?? '')?.toLocal();
                          final formattedTime = time != null ? DateFormat('hh:mm a').format(time) : '';

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _deleteSingleMessage(msg['id']),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                                decoration: BoxDecoration(
                                  color: isMe ? const Color(0xFF6C63FF) : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                                    bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                                        FutureBuilder<String>(
                                          future: _getChatImageUrl(imageUrl),
                                          builder: (context, snapshot) {
                                            if (snapshot.hasError) {
                                              return const Text('Image unavailable');
                                            }
                                            if (!snapshot.hasData) {
                                              return const SizedBox(
                                                height: 140,
                                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                              );
                                            }
                                            final signedUrl = snapshot.data!;
                                            return GestureDetector(
                                              onTap: () => _showFullScreenImage(signedUrl),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Image.network(signedUrl, fit: BoxFit.cover),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 6),
                                      ],

                                      if (text.isNotEmpty && text != '📷 Photo')
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              color: isMe ? Colors.white : Colors.black87,
                                              fontSize: 15,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),

                                      const SizedBox(height: 3),
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
                                            Icon(
                                              isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                              size: 14,
                                              color: isRead ? Colors.lightBlueAccent : Colors.white70,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          if (_showEmojiTray)
            Container(
              height: 52,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickEmojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (ctx, idx) {
                  final em = _quickEmojis[idx];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      _messageController.text += em;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text(em, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmojiTray ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                      color: _showEmojiTray ? const Color(0xFF6C63FF) : Colors.grey[700],
                    ),
                    onPressed: () => setState(() => _showEmojiTray = !_showEmojiTray),
                  ),

                  IconButton(
                    icon: const Icon(Icons.photo_camera_rounded, color: Color(0xFF6C63FF)),
                    tooltip: 'Send Photo',
                    onPressed: _pickAndSendPhoto,
                  ),

                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),

                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6C63FF),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(),
                    ),
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






