import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/utils/sound_helper.dart';
import 'package:spotmate/core/widgets/heart_pin_logo.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/features/city_hotspots/presentation/hotspot_detail_screen.dart';
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
    const screens = [
      HotspotsFeedView(),
      ConnectionsScreen(),
      ChatsListScreen(),
      MyProfileScreen(),
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
class HotspotsFeedView extends StatefulWidget {
  const HotspotsFeedView({super.key});

  @override
  State<HotspotsFeedView> createState() => _HotspotsFeedViewState();
}

class _HotspotsFeedViewState extends State<HotspotsFeedView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _cities = [];
  String? _selectedCityId;
  String? _selectedCategory;
  String _hotspotSearch = '';
  List<Map<String, dynamic>> _hotspots = [];
  bool _isLoading = true;
  RealtimeChannel? _presenceSyncChannel;

  final List<Map<String, dynamic>> _categoriesList = [
    {'title':'Community Rooms','icon':Icons.groups_rounded,'color':Colors.teal,'tagline':'Create your own spaces and chat with your community'},
    {
      'title': 'Malls & Shopping',
      'icon': Icons.shopping_bag_rounded,
      'color': Colors.indigo,
      'tagline': 'Shopping destinations, flagship retail & social food courts',
    },
    {
      'title': 'Parks & Lakes',
      'icon': Icons.park_rounded,
      'color': Colors.green,
      'tagline': 'Scenic lakefronts, national parks & outdoor walking trails',
    },
    {
      'title': 'Theatres & Cinemas',
      'icon': Icons.movie_filter_rounded,
      'color': Colors.deepOrange,
      'tagline': 'IMAX screens, luxury multiplexes & movie destinations',
    },
    {
      'title': 'Cafes & Roasteries',
      'icon': Icons.coffee_rounded,
      'color': Colors.brown,
      'tagline': 'Artisanal roasteries, garden courtyards & relaxed cafes',
    },
    {
      'title': 'Rooftops & Pubs',
      'icon': Icons.nightlife_rounded,
      'color': Colors.purple,
      'tagline': 'Open-air skyline lounges, craft breweries & restobars',
    },
    {
      'title': 'Food Streets & Events',
      'icon': Icons.fastfood_rounded,
      'color': Colors.amber.shade900,
      'tagline': 'Evening culinary streets, cultural venues & exhibition hubs',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCitiesAndHotspots();
    _subscribeToLivePresence();
  }

  void _subscribeToLivePresence() {
    _presenceSyncChannel = _supabase
        .channel('public:hotspot_live_feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspot_members',
          callback: (_) {
            if (_selectedCityId != null) {
              _fetchHotspotsForCity(_selectedCityId!);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspots',
          callback: (_) {
            if (_selectedCityId != null) {
              _fetchHotspotsForCity(_selectedCityId!);
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              _selectedCityId != null) {
            // Re-sync after the subscription reconnects.
            _fetchHotspotsForCity(_selectedCityId!);
          }
        });
  }

  @override
  void dispose() {
    _presenceSyncChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCitiesAndHotspots() async {
    setState(() => _isLoading = true);
    try {
      final citiesResponse = await _supabase.from('cities').select('id, name, state').eq('is_active', true).order('name', ascending: true);
      _cities = List<Map<String, dynamic>>.from(citiesResponse);

      if (_cities.isNotEmpty) {
        final hyd = _cities.firstWhere((c) => c['name'] == 'Hyderabad', orElse: () => _cities.first);
        _selectedCityId = hyd['id'];
        await _fetchHotspotsForCity(_selectedCityId!);
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

  Future<void> _fetchHotspotsForCity(String cityId) async {
    final response = await _supabase
        .from('hotspots')
        .select('id, name, description, address, status, checkin_enabled, hotspot_type, expires_at, promoted_until, room_theme, is_locked, owner_id, image_url, category, latitude, longitude, hotspot_members(user_id, status, user_profiles(id, name, profile_photo))')
        .eq('city_id', cityId)
        .eq('status', 'approved');

    if (mounted && _selectedCityId == cityId) {
      final list = List<Map<String, dynamic>>.from(response);

      list.sort((a, b) {
        final aFeatured=DateTime.tryParse(a['promoted_until']?.toString()??'')
            ?.isAfter(DateTime.now().toUtc())??false;
        final bFeatured=DateTime.tryParse(b['promoted_until']?.toString()??'')
            ?.isAfter(DateTime.now().toUtc())??false;
        if(aFeatured!=bFeatured)return aFeatured?-1:1;
        final aCount = (a['hotspot_members'] as List?)?.where((m) => m['status'] == 'active').length ?? 0;
        final bCount = (b['hotspot_members'] as List?)?.where((m) => m['status'] == 'active').length ?? 0;
        return bCount.compareTo(aCount);
      });

      setState(() {
        _hotspots = list;
      });
    }
  }

  int _getActiveCountForCategory(String categoryName) {
    int count = 0;
    for (final spot in _hotspots) {
      if ((spot['category'] ?? '') == categoryName) {
        final members = spot['hotspot_members'] as List?;
        count += members?.where((m) => m['status'] == 'active').length ?? 0;
      }
    }
    return count;
  }

  void _showPlacePopupModal(Map<String, dynamic> spot) {
    final members = (spot['hotspot_members'] as List?)?.where((m) => m['status'] == 'active').toList() ?? [];
    final activeCount = members.length;
    final imageUrl = spot['image_url'] as String? ?? 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.75)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                          const SizedBox(width: 4),
                          Text('$activeCount Active Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 16,
                    child: Text(
                      spot['name'],
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF6C63FF), size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(spot['address'] ?? '', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    spot['description'] ?? '',
                    style: TextStyle(color: Colors.grey[800], fontSize: 14, height: 1.3),
                  ),
                  if(spot['hotspot_type']=='community')...[
                    Row(children:[
                      Icon(spot['is_locked']==true?Icons.lock_rounded:Icons.lock_open_rounded,
                        color:const Color(0xFF162544),size:17),
                      const SizedBox(width:7),
                      Text(spot['is_locked']==true?'Room locked to new members':'Open community room',
                        style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12)),
                    ]),
                    const SizedBox(height:10),
                  ],
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => HotspotDetailScreen(hotspot: spot)),
                      ).then((_) {
                        final city = _selectedCityId;
                        if (mounted && city != null) _fetchHotspotsForCity(city);
                      });
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('View and join this room', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hotspotCard(Map<String, dynamic> spot) {
    final activeCount = (spot['hotspot_members'] as List?)
        ?.where((member) => member['status'] == 'active').length ?? 0;
    final address = spot['address']?.toString().trim() ?? '';
    final imageUrl = spot['image_url']?.toString() ?? '';
    const placeholder = ColoredBox(
      color: Color(0xFFE8EEF4),
      child: Center(child: Icon(Icons.place_outlined, color: Color(0xFF315477))),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPlacePopupModal(spot),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: imageUrl.isEmpty ? placeholder : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spot['name']?.toString() ?? 'Hotspot',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('$activeCount active', style: Theme.of(context).textTheme.bodyMedium),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View hotspot', style: TextStyle(
                            color: Color(0xFF315477), fontWeight: FontWeight.w600)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward, size: 16, color: Color(0xFF315477)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hotspotRows(List<Map<String, dynamic>> spots, double width) {
    final columns = width >= 680 ? 3 : width >= 480 ? 2 : 1;
    const gap = 12.0;
    final cardWidth = (width - (columns - 1) * gap) / columns;
    return [
      Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final spot in spots)
            SizedBox(width: cardWidth, child: _hotspotCard(spot)),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _hotspotSearch.trim().toLowerCase();
    final active = _hotspots.where((spot) {
      final members = spot['hotspot_members'] as List?;
      return members?.any((member) => member['status'] == 'active') ?? false;
    }).take(3).toList();
    final filtered = _hotspots.where((spot) {
      if (_selectedCategory != null && spot['category'] != _selectedCategory) return false;
      return query.isEmpty || ['name', 'address', 'category', 'description'].any(
        (key) => (spot[key]?.toString().toLowerCase() ?? '').contains(query),
      );
    }).toList();
    final browsing = query.isEmpty && _selectedCategory == null;

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          HeartPinLogo(size: 28),
          SizedBox(width: 8),
          Text('Explore'),
        ]),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: RefreshIndicator(
                  onRefresh: () async {
                    final city = _selectedCityId;
                    if (city != null) await _fetchHotspotsForCity(city);
                  },
                  child: LayoutBuilder(builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth - 32;
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCityId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
                          items: [
                            for (final city in _cities)
                              DropdownMenuItem(value: city['id'] as String, child: Text(
                                '${city['name']}, ${city['state']}',
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (city) {
                            if (city == null || city == _selectedCityId) return;
                            setState(() {
                              _selectedCityId = city;
                              _selectedCategory = null;
                              _hotspots = [];
                            });
                            _fetchHotspotsForCity(city);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          onChanged: (value) => setState(() => _hotspotSearch = value),
                          decoration: const InputDecoration(
                            hintText: 'Search hotspots and neighborhoods',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (browsing) ...[
                          Text('Happening now', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          if (active.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text('No active hotspots in this city right now.'),
                            )
                          else
                            ..._hotspotRows(active, contentWidth),
                          const SizedBox(height: 22),
                          Text('Browse categories', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final category in _categoriesList)
                                ActionChip(
                                  avatar: Icon(category['icon'] as IconData, size: 17),
                                  label: Text('${category['title']} · ${_getActiveCountForCategory(category['title'] as String)}'),
                                  onPressed: () => setState(() => _selectedCategory = category['title'] as String),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: _selectedCityId == null ? null : () async {
                              final city = _selectedCityId!;
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => CreateCommunityHotspotScreen(cityId: city)));
                              if (mounted && _selectedCityId == city) await _fetchHotspotsForCity(city);
                            },
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('Create community room'),
                          ),
                        ] else ...[
                          Row(children: [
                            Expanded(child: Text(_selectedCategory ?? 'Search results',
                              style: theme.textTheme.titleLarge)),
                            if (_selectedCategory != null)
                              TextButton(
                                onPressed: () => setState(() => _selectedCategory = null),
                                child: const Text('All categories'),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No matching hotspots.'),
                            )
                          else
                            ..._hotspotRows(filtered, contentWidth),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
    );
  }
}
