import '../../../core/widgets/horizontal_swipe_action.dart';
import 'dart:async';
import '../../arena_games/screens/games_arena_screen.dart';
import '../../arena_games/widgets/challenge_toast_overlay.dart';
import '../../music_room/screens/music_room_hub_screen.dart';
import '../../music_room/widgets/explore_hub_top_drawer.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/utils/sound_helper.dart';
import 'city_chat_view.dart';
import '../../media/media_navigation.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/features/connections/presentation/connections_screen.dart';
import 'package:spotmate/features/chat/presentation/chats_list_screen.dart';
import 'package:spotmate/features/profile/presentation/my_profile_screen.dart';

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
  String _mediaCity = "";
  int _currentIndex = 0;
  final _tabHistory = <int>[];
  int _newMessages = 0;
  int _newConnections = 0;

  final _supabase = Supabase.instance.client;

  final List<_ActivityNotification> _notifications = [];

  bool _showNotifications = false;
  Timer? _notificationTimer;

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
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showNotifications = false);
    });

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

      _selectTab(2);

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
      _selectTab(1);

      return;
    }
  }

  void _selectTab(int index, {bool remember = true}) {
    if (_currentIndex != index) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      if (remember && _currentIndex != index) _tabHistory.add(_currentIndex);
      _currentIndex = index;
      if (index == 1) _newConnections = 0;
      if (index == 2) _newMessages = 0;
    });
  }

  void _returnToPreviousTab() {
    if (_tabHistory.isNotEmpty) {
      _selectTab(_tabHistory.removeLast(), remember: false);
    }
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
    if (!_showNotifications || _notifications.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8, left: 12, right: 12,
      child: Material(elevation: 8, color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
              child: Row(children: [
                const Icon(Icons.notifications_outlined, color: Color(0xFF128C7E), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('SpotMate · ${_notifications.length} new',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                IconButton(tooltip: 'Close notifications', visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _showNotifications = false)),
              ])),
            Flexible(child: ListView.builder(shrinkWrap: true, padding: EdgeInsets.zero,
              itemCount: _notifications.length, itemBuilder: (context, index) {
                final n = _notifications[index];
                return ListTile(dense: true,
                  leading: CircleAvatar(backgroundColor: const Color(0xFFE1F3EB),
                    backgroundImage: n.image != null && n.image!.isNotEmpty ? NetworkImage(n.image!) : null,
                    child: n.image == null || n.image!.isEmpty
                      ? const Icon(Icons.person, color: Color(0xFF075E54)) : null),
                  title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: Text(n.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(_timeAgo(n.time), style: const TextStyle(fontSize: 11, color: Color(0xFF667781))),
                  onTap: () => _openNotification(n));
              })),
            TextButton(onPressed: () => setState(() { _notifications.clear(); _showNotifications = false; }),
              child: const Text('Clear notifications')),
          ]))),
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
    _notificationTimer?.cancel();
    _incomingRequestsChannel?.unsubscribe();
    _acceptedRequestsChannel?.unsubscribe();
    _incomingMessagesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = user?.userMetadata?['name']?.toString() ?? 'Player';
    final screens = [
      ExcludeFocus(
        excluding: _currentIndex != 0,
        child: CityChatView(onCityChanged: (city) => _mediaCity = city),
      ),
      ConnectionsScreen(isVisible: _currentIndex == 1),
      const ChatsListScreen(),
      const MyProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnToPreviousTab();
      },
      child: ChallengeToastOverlay(
        currentDisplayName: displayName,
        child: Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: screens,
              ),

              if (_currentIndex != 0) _notificationBell(),
              _notificationPanel(),
              if (Theme.of(context).platform == TargetPlatform.iOS &&
                  _tabHistory.isNotEmpty)
                Positioned(
                  left: 0, top: 0, bottom: 0, width: 20,
                  child: HorizontalSwipeAction(
                    onSwipe: _returnToPreviousTab,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _selectTab,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF147D72),
            unselectedItemColor: Colors.grey,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.local_fire_department_rounded),
                activeIcon: ExploreLongPressTrigger(
                  onGamesSelected:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>GamesArenaScreen(currentDisplayName:displayName))),
                  onLiveSelected:()=>openLiveTv(context),
                  onReelsSelected:()=>openReels(context,_mediaCity),
                  onMusicRoomSelected:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>MusicRoomHubScreen(currentDisplayName:displayName))),
                  child:const Padding(padding:EdgeInsets.symmetric(horizontal:12),child:Icon(Icons.local_fire_department_rounded))),
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
        ),
      ),
    );
  }
}
