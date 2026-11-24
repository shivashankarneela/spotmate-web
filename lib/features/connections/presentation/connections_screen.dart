import '../../../core/optional_column.dart';
import 'package:flutter/material.dart';
import 'matchmaker_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';
import 'package:spotmate/features/profile/presentation/user_profile_detail_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, this.isVisible = true});

  final bool isVisible;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  List<Map<String, dynamic>> _receivedRequests = [];
  List<Map<String, dynamic>> _connections = [];
  bool _isLoading = true;
  RealtimeChannel? _profileChannel;
  RealtimeChannel? _matchesChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _matchesChannel = _supabase.channel('match-list-connections')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
        table: 'connections', callback: (_) => _loadData())
      .subscribe();
    _profileChannel = _supabase.channel('connections-profiles')
      .onPostgresChanges(event:PostgresChangeEvent.update,schema:'public',
        table:'user_profiles',callback:(_)=>_loadData())
      .subscribe();
  }

  @override
  void dispose() {
    _profileChannel?.unsubscribe();
    _matchesChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final requestsRes = await selectOptionalColumn('profile_look',
          'id, sender_id, created_at, hotspots(name), user_profiles!fk_conn_req_sender(id, name, bio, gender, looking_for, date_of_birth, profile_photo, profile_look, avatar_type, avatar_emoticon)',
          (fields) => _supabase
          .from('connection_requests')
          .select(fields)
          .eq('receiver_id', user.id)
          .eq('status', 'pending'));

      final connectionsRes = await selectOptionalColumn('profile_look',
          'id, user1_id, user2_id, created_at, user_profiles!fk_conn_user1(id, name, bio, profile_photo, profile_look, avatar_type, avatar_emoticon), user_profiles_user2:user_profiles!fk_conn_user2(id, name, bio, profile_photo, profile_look, avatar_type, avatar_emoticon)',
          (fields) => _supabase
          .from('connections')
          .select(fields)
          .or('user1_id.eq.${user.id},user2_id.eq.${user.id}'));

      // DEDUPLICATE Connections by Partner User ID so each person appears only once!
      final Map<String, Map<String, dynamic>> uniqueConnections = {};
      for (final conn in connectionsRes) {
        final isUser1Me = conn['user1_id'] == user.id;
        final otherId = isUser1Me ? conn['user2_id'] : conn['user1_id'];
        if (!uniqueConnections.containsKey(otherId)) {
          uniqueConnections[otherId] = conn;
        }
      }

      if (mounted) {
        setState(() {
          _receivedRequests = List<Map<String, dynamic>>.from(requestsRes);
          _connections = uniqueConnections.values.toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading requests: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRequest(Map<String, dynamic> request, bool accept) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final senderId = request['sender_id'];

    try {
      if (accept) {
        await _supabase.from('connection_requests').update({'status': 'accepted'}).eq('id', request['id']);

        final connectionRes = await _supabase.from('connections').upsert({
          'user1_id': senderId,
          'user2_id': user.id,
        }).select('id').single();

        final convRes = await _supabase.from('conversations').insert({
          'connection_id': connectionRes['id'],
        }).select('id').single();

        await _supabase.from('conversation_members').insert([
          {'conversation_id': convRes['id'], 'user_id': senderId},
          {'conversation_id': convRes['id'], 'user_id': user.id},
        ]);

        await _loadData();
      } else {
        await _supabase.from('connection_requests').update({'status': 'rejected'}).eq('id', request['id']);
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _disconnectConnection(String connectionId, String otherUserName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect from $otherUserName?'),
        content: const Text('You will no longer be connected and will not be able to message each other.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('connections').delete().eq('id', connectionId);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Disconnected from $otherUserName')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to disconnect: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _openChat(Map<String, dynamic> connection, String otherUserId, String otherUserName, String? otherUserPhoto) async {
    try {
      final conv = await _supabase
          .from('conversations')
          .select('id')
          .eq('connection_id', connection['id'])
          .maybeSingle();

      String conversationId;
      if (conv != null) {
        conversationId = conv['id'];
      } else {
        final newConv = await _supabase.from('conversations').insert({
          'connection_id': connection['id'],
        }).select('id').single();
        conversationId = newConv['id'];

        final user = _supabase.auth.currentUser!;
        await _supabase.from('conversation_members').insert([
          {'conversation_id': conversationId, 'user_id': otherUserId},
          {'conversation_id': conversationId, 'user_id': user.id},
        ]);
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId,
              otherUserName: otherUserName,
              otherUserPhoto: otherUserPhoto,
              otherUserId: otherUserId,
              connectionId: connection['id'],
            ),
          ),
        ).then((_) => _loadData());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chat: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F5F8),
        title: const Text('Matches', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Discover'),
            Tab(child: Badge(
              isLabelVisible: _receivedRequests.isNotEmpty,
              label: Text('${_receivedRequests.length}'),
              child: const Text('Requests'),
            )),
            const Tab(text: 'Connections'),
          ],
        ),
      ),
      body: TabBarView(
              controller: _tabController,
              children: [
                MatchmakerPanel(isVisible: widget.isVisible),
                // 1. Pending Requests Tab
                _isLoading && _receivedRequests.isEmpty && _connections.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _receivedRequests.isEmpty
                    ? const Center(child: Text('No pending connection requests.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _receivedRequests.length,
                        itemBuilder: (context, index) {
                          final req = _receivedRequests[index];
                          final sender = req['user_profiles'] as Map<String, dynamic>? ?? {};
                          final senderId = sender['id'] as String? ?? req['sender_id'];
                          final hotspot = req['hotspots'] as Map<String, dynamic>?;
                          final name = sender['name'] ?? 'Spotmate Member';
                          final photo = sender['profile_photo'] as String?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => UserProfileDetailScreen(userId: senderId)),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Row(
                                  children: [
                                    SpotmateAvatar(size:52,photoUrl:photo,
                                      avatarType:sender['avatar_type']?.toString() ?? 'photo',
                                      storeLook:sender['profile_look'] as String?,
                                      emoticon:sender['avatar_emoticon']?.toString() ?? 'smile'),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          if (hotspot != null)
                                            Text('Spotted at ${hotspot['name']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                          const Text('Tap to view profile 🔍', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red),
                                      tooltip: 'Decline',
                                      onPressed: () => _handleRequest(req, false),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      tooltip: 'Accept',
                                      onPressed: () => _handleRequest(req, true),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                // 2. Connected Tab (Deduplicated Single Instances)
                _connections.isEmpty
                    ? const Center(child: Text('No connections yet. Connect with people at a hotspot!'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _connections.length,
                        itemBuilder: (context, index) {
                          final conn = _connections[index];
                          final isUser1Me = conn['user1_id'] == currentUserId;
                          final otherProfile = isUser1Me
                              ? (conn['user_profiles_user2'] as Map<String, dynamic>? ?? {})
                              : (conn['user_profiles'] as Map<String, dynamic>? ?? {});

                          final otherId = isUser1Me ? conn['user2_id'] : conn['user1_id'];
                          final otherName = otherProfile['name'] ?? 'Connection';
                          final otherPhoto = otherProfile['profile_photo'] as String?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileDetailScreen(
                                      userId: otherId,
                                      connectionId: conn['id'],
                                    ),
                                  ),
                                );
                              },
                              leading: SpotmateAvatar(size:48,photoUrl:otherPhoto,
                                avatarType:otherProfile['avatar_type']?.toString() ?? 'photo',
                                storeLook:otherProfile['profile_look'] as String?,
                                emoticon:otherProfile['avatar_emoticon']?.toString() ?? 'smile'),
                              title: Text(otherName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Matched Connection • Tap to view profile', style: TextStyle(fontSize: 12, color: Colors.green)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                                    label: const Text('Chat'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _openChat(conn, otherId, otherName, otherPhoto),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'disconnect') {
                                        _disconnectConnection(conn['id'], otherName);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'disconnect',
                                        child: Text('Disconnect', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}

