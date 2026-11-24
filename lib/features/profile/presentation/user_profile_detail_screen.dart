import 'my_photos_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';

class UserProfileDetailScreen extends StatefulWidget {
  final String userId;
  final String? connectionId;

  const UserProfileDetailScreen({
    super.key,
    required this.userId,
    this.connectionId,
  });

  @override
  State<UserProfileDetailScreen> createState() => _UserProfileDetailScreenState();
}

class _UserProfileDetailScreenState extends State<UserProfileDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  String? _visibleSpotmateId;
  String? _cityName;
  bool _isLoading = true;
  String? _activeConnectionId;
  RealtimeChannel? _profileChannel;

  @override
  void initState() {
    super.initState();
    _activeConnectionId = widget.connectionId;
    _fetchFullProfile();
    _profileChannel = _supabase.channel('profile-detail-${widget.userId}')
      .onPostgresChanges(event:PostgresChangeEvent.update,schema:'public',
        table:'user_profiles',
        filter:PostgresChangeFilter(type:PostgresChangeFilterType.eq,
          column:'id',value:widget.userId),
        callback:(_)=>_fetchFullProfile())
      .subscribe();
  }

  @override
  void dispose() {
    _profileChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchFullProfile() async {
    final myId = _supabase.auth.currentUser?.id;

    try {
      final res = await _supabase
          .from('user_profiles')
          .select('name,date_of_birth,profile_photo,avatar_type,avatar_emoticon,bio,gender,looking_for,is_verified,profile_look,cities(name,state)')
          .eq('id', widget.userId)
          .maybeSingle();

      if (myId != null && _activeConnectionId == null) {
        final conn = await _supabase
            .from('connections')
            .select('id')
            .or('and(user1_id.eq.$myId,user2_id.eq.${widget.userId}),and(user1_id.eq.${widget.userId},user2_id.eq.$myId)')
            .maybeSingle();
        if (conn != null) {
          _activeConnectionId = conn['id'];
        }
      }

      String? visibleId;
      try {
        final rows = await _supabase.rpc('visible_spotmate_ids', params: {
          'p_users': [widget.userId],
        }) as List;
        if (rows.isNotEmpty) visibleId = rows.first['spotmate_id'] as String?;
      } on PostgrestException {
        // Older deployments do not have the private ID lookup yet.
      }

      if (mounted) {
        setState(() {
          _profile = res;
          _visibleSpotmateId = visibleId;
          final city = res?['cities'] as Map<String, dynamic>?;
          _cityName = city != null ? '${city['name']}, ${city['state']}' : 'Unknown City';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _calculateAge(String? dobString) {
    if (dobString == null) return 24;
    try {
      final dob = DateTime.parse(dobString);
      final today = DateTime.now();
      int age = today.year - dob.year;
      if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return 24;
    }
  }

  Future<void> _openChat() async {
    if (_activeConnectionId == null || _profile == null) return;

    final name = _profile!['name'] ?? 'Connection';
    final photo = _profile!['profile_photo'] as String?;

    try {
      final conv = await _supabase
          .from('conversations')
          .select('id')
          .eq('connection_id', _activeConnectionId!)
          .maybeSingle();

      String conversationId;
      if (conv != null) {
        conversationId = conv['id'];
      } else {
        final newConv = await _supabase.from('conversations').insert({
          'connection_id': _activeConnectionId!,
        }).select('id').single();
        conversationId = newConv['id'];

        final myId = _supabase.auth.currentUser!.id;
        await _supabase.from('conversation_members').insert([
          {'conversation_id': conversationId, 'user_id': widget.userId},
          {'conversation_id': conversationId, 'user_id': myId},
        ]);
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversationId,
              otherUserName: name,
              otherUserPhoto: photo,
              otherUserId: widget.userId,
              connectionId: _activeConnectionId,
            ),
          ),
        );
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
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('User profile not found.')),
      );
    }

    final name = _profile!['name'] ?? 'Member';
    final age = _calculateAge(_profile!['date_of_birth']);
    final photo = _profile!['profile_photo'] as String?;
    final avatarType = _profile!['avatar_type']?.toString() ?? 'emoticon';
    final avatarEmoticon = _profile!['avatar_emoticon']?.toString() ?? 'boy_01';
    final bio = _profile!['bio'] ?? 'No bio provided yet.';
    final gender = _profile!['gender'] ?? 'Not set';
    final lookingFor = _profile!['looking_for'] ?? 'Everyone';
    final spotmateId = _visibleSpotmateId;
    final isVerified = _profile!['is_verified'] == true;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color:const Color(0xFFE4E8E9),
                child:Center(child:LayoutBuilder(builder:(context,box) {
                  final dimension=box.maxWidth<box.maxHeight
                      ? box.maxWidth*.82 : box.maxHeight*.82;
                  return SpotmateAvatar(
                    size:dimension.clamp(110.0,320.0).toDouble(),
                    storeLook:_profile?['profile_look'] as String?,
                    photoUrl:photo,
                    avatarType:avatarType,
                    emoticon:avatarEmoticon);
                })),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '$name, $age',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified, color: Colors.green, size: 16),
                              SizedBox(width: 4),
                              Text('Verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MyPhotosScreen(ownerId: widget.userId),
                      ),
                    ),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('View photos'),
                  ),
                  if (spotmateId != null) Text(
                    'SpotMate ID: $spotmateId',
                    style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(_cityName ?? '', style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.person_outline, size: 16),
                        label: Text(gender),
                      ),
                      Chip(
                        avatar: const Icon(Icons.favorite_outline, size: 16),
                        label: Text('Looking for $lookingFor'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('About Me', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(bio, style: TextStyle(fontSize: 15, color: Colors.grey[800], height: 1.4)),
                  const SizedBox(height: 36),

                  if (_activeConnectionId != null)
                    ElevatedButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Send Message', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

