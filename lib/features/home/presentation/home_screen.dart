import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/utils/sound_helper.dart';
import 'package:spotmate/core/widgets/heart_pin_logo.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/features/chat/presentation/hotspot_public_chat_screen.dart';
import 'package:spotmate/features/connections/presentation/connections_screen.dart';
import 'package:spotmate/features/chat/presentation/chats_list_screen.dart';
import 'package:spotmate/features/profile/presentation/my_profile_screen.dart';
import 'package:spotmate/features/hotspots/presentation/create_community_hotspot_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ActivityNotification {
  final String type;
  final String title;
  final String message;
  final String? image;
  final DateTime time;
  final String? conversationId;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserPhoto;

  _ActivityNotification({
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    this.image,
    this.conversationId,
    this.otherUserId,
    this.otherUserName,
    this.otherUserPhoto,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  int _newMessages = 0;
  int _newConnections = 0;

  final _supabase = Supabase.instance.client;

  final List<_ActivityNotification> _notifications = [];

  bool _showNotifications = false;

  RealtimeChannel? _incomingRequestsChannel;
  RealtimeChannel? _acceptedRequestsChannel;
  RealtimeChannel? _incomingMessagesChannel;

  @override
  void initState() {
    super.initState();
    _loadActivityCounts();
    _subscribeToIncomingRequests();
    _subscribeToAcceptedRequests();
    _subscribeToIncomingMessages();
  }

  Future<void> _loadActivityCounts() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final requests = await _supabase
        .from('connection_requests')
        .select('id')
        .eq('receiver_id', user.id)
        .eq('status', 'pending');

    if (mounted) {
      setState(() {
        _newConnections = requests.length;
      });
    }
  }

  void _addNotification(_ActivityNotification notification) {
    if (!mounted) return;

    setState(() {
      _notifications.insert(0, notification);

      if (_notifications.length > 10) {
        _notifications.removeLast();
      }

      _showNotifications = true;
    });
  }

  void _subscribeToIncomingRequests() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _incomingRequestsChannel = _supabase
        .channel('public:incoming_requests:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'connection_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: user.id,
          ),
          callback: (payload) async {
            SoundHelper.playNotificationBeep();

            final senderId = payload.newRecord['sender_id'];

            final profile = await _supabase
                .from('user_profiles')
                .select('name, profile_photo')
                .eq('id', senderId)
                .maybeSingle();

            final name = profile?['name'] ?? 'Spotmate Member';
            final photo = profile?['profile_photo'] as String?;

            if (!mounted) return;

            setState(() {
              _newConnections++;
            });

            _addNotification(
              _ActivityNotification(
                type: 'request',
                title: '$name sent you a connection request',
                message: 'Wants to connect with you',
                image: photo,
                time: DateTime.now(),
                otherUserId: senderId,
                otherUserName: name,
                otherUserPhoto: photo,
              ),
            );
          },
        )
        .subscribe();
  }

  void _subscribeToAcceptedRequests() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _acceptedRequestsChannel = _supabase
        .channel('public:accepted_requests:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'connection_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'sender_id',
            value: user.id,
          ),
          callback: (payload) async {
            if (payload.newRecord['status'] != 'accepted') return;

            SoundHelper.playMatchChime();

            final receiverId = payload.newRecord['receiver_id'];

            final profile = await _supabase
                .from('user_profiles')
                .select('name, profile_photo')
                .eq('id', receiverId)
                .maybeSingle();

            final name = profile?['name'] ?? 'Your match';
            final photo = profile?['profile_photo'] as String?;

            if (!mounted) return;

            _addNotification(
              _ActivityNotification(
                type: 'match',
                title: '$name accepted your request',
                message: 'You can now chat with this connection',
                image: photo,
                time: DateTime.now(),
                otherUserId: receiverId,
                otherUserName: name,
                otherUserPhoto: photo,
              ),
            );
          },
        )
        .subscribe();
  }

  void _subscribeToIncomingMessages() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _incomingMessagesChannel = _supabase
        .channel('public:incoming_messages:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final message = payload.newRecord;
            final senderId = message['sender_id'];

            if (senderId == user.id) return;

            final conversationId = message['conversation_id'] as String?;

            if (conversationId == null) return;

            final profile = await _supabase
                .from('user_profiles')
                .select('name, profile_photo')
                .eq('id', senderId)
                .maybeSingle();

            final name = profile?['name'] ?? 'New message';
            final photo = profile?['profile_photo'] as String?;
            final text = message['message'] ?? 'Sent you a message';

            if (!mounted) return;

            setState(() {
              _newMessages++;
            });

            final preferences = await SharedPreferences.getInstance();
            if (!mounted || (preferences.getStringList('spotmate.inbox.${user.id}.mute') ?? [])
                .contains('direct:$conversationId')) return;

            _addNotification(
              _ActivityNotification(
                type: 'message',
                title: '$name sent you a message',
                message: text,
                image: photo,
                time: DateTime.now(),
                conversationId: conversationId,
                otherUserId: senderId,
                otherUserName: name,
                otherUserPhoto: photo,
              ),
            );

            SoundHelper.playNotificationBeep();
          },
        )
        .subscribe();
  }

  String _timeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);

    if (difference.inSeconds < 10) return 'Just now';
    if (difference.inMinutes < 1) return '${difference.inSeconds}s ago';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';

    return '${difference.inDays}d ago';
  }

  Future<void> _openNotification(_ActivityNotification notification) async {
    setState(() {
      _notifications.remove(notification);
    });

    if (notification.type == 'message' &&
        notification.conversationId != null) {
      final connection = await _supabase
          .from('conversations')
          .select('connection_id')
          .eq('id', notification.conversationId!)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _currentIndex = 2;
        _newMessages = 0;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: notification.conversationId!,
            otherUserName:
                notification.otherUserName ?? 'Connection',
            otherUserPhoto: notification.otherUserPhoto,
            otherUserId: notification.otherUserId,
            connectionId: connection?['connection_id'],
          ),
        ),
      );

      return;
    }

    if (notification.type == 'request' ||
        notification.type == 'match') {
      setState(() {
        _currentIndex = 1;
        _newConnections = 0;
      });

      return;
    }
  }

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;

      if (index == 1) {
        _newConnections = 0;
      }

      if (index == 2) {
        _newMessages = 0;
      }
    });
  }

  Widget _badgeIcon(IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 19,
                minHeight: 19,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF304F),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _notificationPanel() {
    if (!_showNotifications || _notifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      left: 12,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        child: Container(
          constraints: const BoxConstraints(
            maxHeight: 420,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_notifications.length > 1)
                      Text(
                        '${_notifications.length} new',
                        style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showNotifications = false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];

                    final isMessage =
                        notification.type == 'message';

                    return InkWell(
                      onTap: () =>
                          _openNotification(notification),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage:
                                      notification.image != null &&
                                              notification.image!
                                                  .isNotEmpty
                                          ? NetworkImage(
                                              notification.image!,
                                            )
                                          : null,
                                  child: notification.image == null
                                      ? Icon(
                                          isMessage
                                              ? Icons.chat_bubble
                                              : Icons.favorite,
                                          color: const Color(
                                            0xFFFF4B6E,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: isMessage
                                          ? Colors.green
                                          : const Color(
                                              0xFFFF4B6E,
                                            ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.title,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    notification.message,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _timeAgo(notification.time),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  _openNotification(notification),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF6C63FF),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(52, 32),
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'View',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              TextButton(
                onPressed: () {
                  setState(() {
                    _notifications.clear();
                    _showNotifications = false;
                  });
                },
                child: const Text(
                  'Mark all as read',
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationBell() {
    final total = _newMessages + _newConnections;

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        elevation: 6,
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            setState(() {
              _showNotifications = !_showNotifications;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 25,
                  color: Color(0xFF333333),
                ),
                if (total > 0)
                  Positioned(
                    right: -7,
                    top: -7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF304F),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        total > 99 ? '99+' : '$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _incomingRequestsChannel?.unsubscribe();
    _acceptedRequestsChannel?.unsubscribe();
    _incomingMessagesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const RegionalRoomsView(),
      ConnectionsScreen(isVisible: _currentIndex == 1),
      const ChatsListScreen(),
      const MyProfileScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: screens,
          ),

          _notificationBell(),
          _notificationPanel(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _selectTab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF315477),
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_rounded),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: _badgeIcon(
              Icons.favorite_rounded,
              _newConnections,
            ),
            label: 'Matches',
          ),
          BottomNavigationBarItem(
            icon: _badgeIcon(
              Icons.chat_bubble_rounded,
              _newMessages,
            ),
            label: 'Chats',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
class RegionalRoomsView extends StatefulWidget {
  const RegionalRoomsView({super.key});

  @override
  State<RegionalRoomsView> createState() => _RegionalRoomsViewState();
}

class _RegionalRoomsViewState extends State<RegionalRoomsView> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _rooms = [];
  String? _state;
  String? _city;
  String _search = '';
  String? _joining;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cities = await _client.from('cities').select('id,name,state').order('name');
      final rooms = await _client.rpc('spotmate_room_directory');
      if (mounted) setState(() {
        _cities = List<Map<String, dynamic>>.from(cities);
        _rooms = List<Map<String, dynamic>>.from(rooms as List);
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> room) async {
    if (_joining != null) return;
    final id = room['id'] as String;
    setState(() => _joining = id);
    try {
      if (room['joined'] != true) {
        await _client.rpc('join_hotspot_room', params: {'p_hotspot_id': id});
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        HotspotPublicChatScreen(hotspotId: id, hotspotName: room['name'].toString())));
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not enter the room. It may be locked or unavailable.')),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = _cities.map((city) => city['state'].toString()).toSet().toList()..sort();
    final cities = _cities.where((city) => _state == null || city['state'] == _state);
    final query = _search.trim().toLowerCase();
    final visible = _rooms.where((room) =>
      (_state == null || room['state'] == _state) &&
      (_city == null || room['city_id'] == _city) &&
      ['name','description','city_name'].any((field) =>
        (room[field]?.toString().toLowerCase() ?? '').contains(query))).toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Row(children: [
        HeartPinLogo(size: 28), SizedBox(width: 8), Text('Chat rooms'),
      ])),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: visible.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropdownButtonFormField<String>(
                    initialValue: _state ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All states')),
                      for (final state in states)
                        DropdownMenuItem(value: state, child: Text(state)),
                    ],
                    onChanged: (value) => setState(() {
                      _state = value == '' ? null : value;
                      _city = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_state),
                    initialValue: _city ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'City'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('All cities')),
                      for (final city in cities)
                        DropdownMenuItem(value: city['id'] as String, child: Text(city['name'].toString())),
                    ],
                    onChanged: (value) => setState(() => _city = value == '' ? null : value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: 'Search rooms'),
                  ),
                  const SizedBox(height: 10),
                  if (_city != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final city = _city!;
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                            CreateCommunityHotspotScreen(cityId: city)));
                          if (mounted) await _load();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create room'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  if (_failed) TextButton(onPressed: _load, child: const Text('Could not load rooms. Retry')),
                  if (!_loading && !_failed && visible.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('No rooms match this region or search.')),
                ]);
              }
              final room = visible[index - 1];
              final locked = room['is_locked'] == true;
              final accessible = !locked || room['joined'] == true ||
                  room['owner_id'] == _client.auth.currentUser?.id;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  enabled: accessible && _joining == null,
                  leading: CircleAvatar(child: Icon(locked ? Icons.lock_outline : Icons.forum_outlined)),
                  title: Text(room['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                  subtitle: Text("${room['city_name']}, ${room['state']} · ${room['member_count']} active members"),
                  trailing: _joining == room['id']
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(accessible ? Icons.chevron_right : Icons.lock_outline),
                  onTap: accessible ? () => _open(room) : null,
                ),
              );
            },
          ),
        ),
      )),
    );
  }
}
