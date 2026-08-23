import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/utils/sound_helper.dart';
import 'package:spotmate/core/widgets/heart_pin_logo.dart';
import 'package:spotmate/features/chat/presentation/active_call_screen.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/features/city_hotspots/presentation/hotspot_detail_screen.dart';
import 'package:spotmate/features/connections/presentation/connections_screen.dart';
import 'package:spotmate/features/chat/presentation/chats_list_screen.dart';
import 'package:spotmate/features/profile/presentation/my_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _incomingRequestsChannel;
  RealtimeChannel? _acceptedRequestsChannel;
  RealtimeChannel? _incomingCallsChannel;

  @override
  void initState() {
    super.initState();
    _subscribeToIncomingRequests();
    _subscribeToAcceptedRequests();
    _subscribeToIncomingCalls();
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
          callback: (payload) {
            SoundHelper.playNotificationBeep();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFFFF4B6E),
                  duration: const Duration(seconds: 6),
                  content: const Row(
                    children: [
                      Icon(Icons.favorite, color: Colors.white),
                      SizedBox(width: 8),
                      Text('🔔 New Connection Request Received!'),
                    ],
                  ),
                  action: SnackBarAction(
                    label: 'View',
                    textColor: Colors.white,
                    onPressed: () {
                      setState(() => _currentIndex = 1);
                    },
                  ),
                ),
              );
            }
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
            if (payload.newRecord['status'] == 'accepted') {
              SoundHelper.playMatchChime();

              final receiverId = payload.newRecord['receiver_id'];
              final profileRes = await _supabase.from('user_profiles').select('name, profile_photo').eq('id', receiverId).maybeSingle();
              final name = profileRes?['name'] ?? 'Your match';
              final photo = profileRes?['profile_photo'] as String?;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 8),
                    content: Row(
                      children: [
                        const Icon(Icons.celebration, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(child: Text('🎉 $name approved your request! You can chat now.')),
                      ],
                    ),
                    action: SnackBarAction(
                      label: 'Chat Now',
                      textColor: Colors.white,
                      onPressed: () async {
                        final conv = await _supabase.from('conversations').select('id, connection_id').maybeSingle();
                        if (conv != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                conversationId: conv['id'],
                                otherUserName: name,
                                otherUserPhoto: photo,
                                otherUserId: receiverId,
                                connectionId: conv['connection_id'],
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _subscribeToIncomingCalls() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _incomingCallsChannel = _supabase
        .channel('public:calls:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: user.id,
          ),
          callback: (payload) async {
            final call = payload.newRecord;
            if (call['status'] != 'ringing') return;

            SoundHelper.playRingtone();

            final callerId = call['caller_id'];
            final isVideo = call['call_type'] == 'video';

            final callerProfile = await _supabase
                .from('user_profiles')
                .select('name, profile_photo')
                .eq('id', callerId)
                .maybeSingle();

            final callerName = callerProfile?['name'] ?? 'Spotmate Caller';
            final callerPhoto = callerProfile?['profile_photo'] as String?;

            if (!mounted) return;

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.all(24),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: callerPhoto != null && callerPhoto.isNotEmpty ? NetworkImage(callerPhoto) : null,
                      child: callerPhoto == null ? const Icon(Icons.person, size: 48) : null,
                    ),
                    const SizedBox(height: 16),
                    Text(callerName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      isVideo ? '📹 Incoming Video Call...' : '📞 Incoming Audio Call...',
                      style: const TextStyle(color: Color(0xFFFF4B6E), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.red,
                          child: IconButton(
                            icon: const Icon(Icons.call_end, color: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _supabase.from('calls').update({'status': 'declined'}).eq('id', call['id']);
                            },
                          ),
                        ),
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.green,
                          child: IconButton(
                            icon: const Icon(Icons.call, color: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _supabase.from('calls').update({'status': 'accepted'}).eq('id', call['id']);

                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ActiveCallScreen(
                                      callId: call['id'],
                                      otherUserName: callerName,
                                      otherUserPhoto: callerPhoto,
                                      isVideo: isVideo,
                                      isCaller: false,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _incomingRequestsChannel?.unsubscribe();
    _acceptedRequestsChannel?.unsubscribe();
    _incomingCallsChannel?.unsubscribe();
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
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF4B6E),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Hotspots'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_rounded), label: 'Connections'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
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
  List<Map<String, dynamic>> _hotspots = [];
  bool _isLoading = true;
  RealtimeChannel? _presenceSyncChannel;

  final List<Map<String, dynamic>> _categoriesList = [
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
        .subscribe();
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
        .select('id, name, description, address, status, image_url, category, latitude, longitude, hotspot_members(user_id, status, user_profiles(id, name, profile_photo))')
        .eq('city_id', cityId)
        .eq('status', 'approved');

    if (mounted) {
      final list = List<Map<String, dynamic>>.from(response);

      list.sort((a, b) {
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

  int get _totalActiveInCity {
    int total = 0;
    for (final spot in _hotspots) {
      final members = spot['hotspot_members'] as List?;
      total += members?.where((m) => m['status'] == 'active').length ?? 0;
    }
    return total;
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
                      const Icon(Icons.location_on, color: Color(0xFFFF4B6E), size: 16),
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
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => HotspotDetailScreen(hotspot: spot)),
                      ).then((_) => _fetchHotspotsForCity(_selectedCityId!));
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Enter & Check-in to this Spot', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4B6E),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cityName = _cities.firstWhere(
      (c) => c['id'] == _selectedCityId,
      orElse: () => {'name': 'Hyderabad'},
    )['name'];

    final placesInCategory = _selectedCategory == null
        ? <Map<String, dynamic>>[]
        : _hotspots.where((h) => (h['category'] ?? '') == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            const HeartPinLogo(size: 32),
            const SizedBox(width: 8),
            Text(
              'SPOTMATE',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCityId,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFFF4B6E)),
                selectedItemBuilder: (ctx) => _cities.map((city) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4B6E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on, size: 15, color: Color(0xFFFF4B6E)),
                          const SizedBox(width: 4),
                          Text(city['name'], style: const TextStyle(color: Color(0xFFFF4B6E), fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                items: _cities.map((city) {
                  return DropdownMenuItem<String>(
                    value: city['id'] as String,
                    child: Text('${city['name']}, ${city['state']}'),
                  );
                }).toList(),
                onChanged: (newCityId) {
                  if (newCityId != null) {
                    setState(() {
                      _selectedCityId = newCityId;
                      _selectedCategory = null;
                    });
                    _fetchHotspotsForCity(newCityId);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchHotspotsForCity(_selectedCityId!),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4B6E), Color(0xFFFF758C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFFF4B6E).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_totalActiveInCity People Spotted Across $cityName',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Explore curated venue destinations & meet people live.',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // PROFESSIONAL SECTION HEADING
                  if (_selectedCategory == null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Discover Social Hotspots',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.green, size: 8),
                            SizedBox(width: 4),
                            Text('LIVE RADAR', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _categoriesList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final cat = _categoriesList[index];
                        final catName = cat['title'] as String;
                        final activeCount = _getActiveCountForCategory(catName);
                        final color = cat['color'] as Color;

                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              setState(() => _selectedCategory = catName);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(cat['icon'] as IconData, color: color, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          catName,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          cat['tagline'] as String,
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: activeCount > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: activeCount > 0 ? Colors.green : Colors.grey.shade300),
                                    ),
                                    child: Text(
                                      '$activeCount live',
                                      style: TextStyle(
                                        color: activeCount > 0 ? Colors.green.shade800 : Colors.grey[600],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => setState(() => _selectedCategory = null),
                        ),
                        Expanded(
                          child: Text(
                            '$_selectedCategory in $cityName',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _selectedCategory = null),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ranked by highest live crowd right now • Tap a place to view & enter',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    if (placesInCategory.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(40),
                        alignment: Alignment.center,
                        child: const Text('No places added in this category yet.'),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: placesInCategory.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final spot = placesInCategory[index];
                          final members = (spot['hotspot_members'] as List?)?.where((m) => m['status'] == 'active').toList() ?? [];
                          final activeCount = members.length;
                          final isTop1 = index == 0 && activeCount > 0;
                          final imageUrl = spot['image_url'] as String? ?? 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800';

                          return Card(
                            elevation: isTop1 ? 4 : 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: isTop1 ? const BorderSide(color: Color(0xFFFF4B6E), width: 1.5) : BorderSide.none,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  imageUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(width: 60, height: 60, color: Colors.grey),
                                ),
                              ),
                              title: Row(
                                children: [
                                  if (isTop1) ...[
                                    const Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      spot['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    spot['address'] ?? '',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: activeCount > 0 ? const Color(0xFFFF4B6E).withOpacity(0.12) : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.people, size: 14, color: activeCount > 0 ? const Color(0xFFFF4B6E) : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$activeCount',
                                          style: TextStyle(
                                            color: activeCount > 0 ? const Color(0xFFFF4B6E) : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showPlacePopupModal(spot),
                            ),
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
