import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _subscribeToNewMessages();
  }

  Future<void> _loadChats() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final connectionsRes = await _supabase
          .from('connections')
          .select('id, user1_id, user2_id, user_profiles!fk_conn_user1(id, name, profile_photo), user_profiles_user2:user_profiles!fk_conn_user2(id, name, profile_photo)')
          .or('user1_id.eq.${user.id},user2_id.eq.${user.id}');

      final List<Map<String, dynamic>> chatItems = [];

      for (final conn in connectionsRes) {
        final isUser1Me = conn['user1_id'] == user.id;
        final otherProfile = isUser1Me
            ? (conn['user_profiles_user2'] as Map<String, dynamic>? ?? {})
            : (conn['user_profiles'] as Map<String, dynamic>? ?? {});

        final conv = await _supabase
            .from('conversations')
            .select('id')
            .eq('connection_id', conn['id'])
            .maybeSingle();

        if (conv != null) {
          final lastMsgRes = await _supabase
              .from('messages')
              .select('message, created_at, sender_id')
              .eq('conversation_id', conv['id'])
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          chatItems.add({
            'conversation_id': conv['id'],
            'connection_id': conn['id'],
            'other_name': otherProfile['name'] ?? 'Connection',
            'other_photo': otherProfile['profile_photo'],
            'last_message': lastMsgRes?['message'] ?? 'No messages yet',
            'last_time': lastMsgRes?['created_at'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _chats = chatItems;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToNewMessages() {
    _messagesChannel = _supabase
        .channel('public:chats_list_feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _loadChats(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadChats),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No active conversations yet', style: TextStyle(color: Colors.grey[700], fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Connect with people at hotspots to unlock chats!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _chats.length,
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      final otherName = chat['other_name'] as String;
                      final otherPhoto = chat['other_photo'] as String?;
                      final lastMsg = chat['last_message'] as String;
                      final lastTime = chat['last_time'] != null ? DateTime.tryParse(chat['last_time'])?.toLocal() : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: otherPhoto != null && otherPhoto.isNotEmpty ? NetworkImage(otherPhoto) : null,
                            child: otherPhoto == null ? const Icon(Icons.person, color: Colors.grey) : null,
                          ),
                          title: Text(otherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text(
                            lastMsg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[700], fontSize: 13),
                          ),
                          trailing: lastTime != null
                              ? Text(DateFormat('hh:mm a').format(lastTime), style: const TextStyle(fontSize: 11, color: Colors.grey))
                              : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: chat['conversation_id'],
                                  otherUserName: otherName,
                                  otherUserPhoto: otherPhoto,
                                  connectionId: chat['connection_id'],
                                ),
                              ),
                            ).then((_) => _loadChats());
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

