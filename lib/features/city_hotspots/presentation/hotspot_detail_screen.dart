import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';
import 'package:spotmate/features/chat/presentation/hotspot_public_chat_screen.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';

class HotspotDetailScreen extends StatefulWidget {
  final Map<String, dynamic> hotspot;
  const HotspotDetailScreen({super.key, required this.hotspot});

  @override
  State<HotspotDetailScreen> createState() => _HotspotDetailScreenState();
}

class _HotspotDetailScreenState extends State<HotspotDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _isJoined = false;
  bool _isLocked=false;
  String? _roomOwnerId;
  String _roomOwnerName='Room owner';
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeMembers = [];
  Set<String> _sentRequestUserIds = {};
  Set<String> _connectedUserIds = {};
  Map<String, String> _userToConnectionId = {};

  DateTime? _sessionExpiry;


  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // Room availability and owner are always read fresh, not from a stale listing.
      final room=await _supabase.from('hotspots')
        .select('is_locked,owner_id,hotspot_type')
        .eq('id',widget.hotspot['id']).single();
      _isLocked=room['is_locked']==true;
      _roomOwnerId=room['owner_id']?.toString();
      if(_roomOwnerId!=null){
        final owner=await _supabase.from('user_profiles')
          .select('name').eq('id',_roomOwnerId!).maybeSingle();
        _roomOwnerName=owner?['name']?.toString()??'Room owner';
      }

      // Check if the account is currently a room member
      final myMembership = await _supabase
          .from('hotspot_members')
          .select('status, expires_at')
          .eq('hotspot_id', widget.hotspot['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      _sessionExpiry = DateTime.tryParse(myMembership?['expires_at']?.toString() ?? '');
      _isJoined = myMembership != null && myMembership['status'] == 'active' &&
          _sessionExpiry != null && _sessionExpiry!.isAfter(DateTime.now().toUtc());

      // 3. Fetch active members
      final membersResponse = await _supabase
          .from('hotspot_members')
          .select('user_id, joined_at, user_profiles(id, name, bio, gender, looking_for, date_of_birth, profile_photo, avatar_type, avatar_emoticon, spotmate_id)')
          .eq('hotspot_id', widget.hotspot['id'])
          .eq('status', 'active')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());

      // 4. Fetch sent requests
      final sentReqs = await _supabase
          .from('connection_requests')
          .select('receiver_id, status')
          .eq('sender_id', user.id)
          .eq('status', 'pending');

      // 5. Fetch existing connections
      final conns = await _supabase
          .from('connections')
          .select('id, user1_id, user2_id')
          .or('user1_id.eq.${user.id},user2_id.eq.${user.id}');

      final sentSet = <String>{};
      for (final r in sentReqs) {
        sentSet.add(r['receiver_id']);
      }

      final connSet = <String>{};
      final connMap = <String, String>{};
      for (final c in conns) {
        final otherId = c['user1_id'] == user.id ? c['user2_id'] : c['user1_id'];
        connSet.add(otherId);
        connMap[otherId] = c['id'];
      }

      if (mounted) {
        setState(() {
          _activeMembers = List<Map<String, dynamic>>.from(membersResponse);
          _sentRequestUserIds = sentSet;
          _connectedUserIds = connSet;
          _userToConnectionId = connMap;
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

  Future<void> _joinRoom() async {
    setState(()=>_isLoading=true);
    try{
      await _supabase.rpc('join_hotspot_room',params:{
        'p_hotspot_id':widget.hotspot['id'],
      });
      await _loadAll();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('You have joined the room. Welcome!')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not join: $e')));
    }finally{if(mounted)setState(()=>_isLoading=false);}
  }

  Future<void> _leaveHotspot() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      await _supabase.rpc('leave_hotspot');
      _isJoined = false;
      await _loadAll();
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendConnectionRequest(String targetUserId, String targetName) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('connection_requests').insert({
        'sender_id': user.id,
        'receiver_id': targetUserId,
        'hotspot_id': widget.hotspot['id'],
        'status': 'pending',
      });

      setState(() {
        _sentRequestUserIds.add(targetUserId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection request sent to $targetName!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send request: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showUserPhotoPopup(Map<String, dynamic> profile) {
    final name = profile['name'] ?? 'Spotmate Member';
    final age = _calculateAge(profile['date_of_birth']);
    final photo = profile['profile_photo'] as String?;
    final bio = profile['bio'] ?? 'No bio provided.';
    final gender = profile['gender'] ?? 'Not specified';
    final lookingFor = profile['looking_for'] ?? 'Everyone';
    final targetId = profile['id'] as String? ?? '';
    final isMe = targetId == _supabase.auth.currentUser?.id;

    final isConnected = _connectedUserIds.contains(targetId);
    final isRequested = _sentRequestUserIds.contains(targetId);

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
              height: 300,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                image: photo != null && photo.isNotEmpty
                    ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover)
                    : null,
              ),
              child: photo == null
                  ? const Icon(Icons.person, size: 90, color: Colors.white70)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$name, $age', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Chip(
                        avatar: const Icon(Icons.favorite, size: 14, color: Color(0xFF6C63FF)),
                        label: Text('Seeking $lookingFor', style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Gender: $gender', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 10),
                  Text(bio, style: TextStyle(color: Colors.grey[800], fontSize: 14, height: 1.3)),
                  const SizedBox(height: 22),

                  if (!isMe) ...[
                    if (isConnected)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final connectionId = _userToConnectionId[targetId];
                          if (connectionId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: connectionId,
                                  otherUserName: name,
                                  otherUserPhoto: photo,
                                  otherUserId: targetId,
                                  connectionId: connectionId,
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('Open Chat'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else if (isRequested)
                      OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Connection Request Pending'),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendConnectionRequest(targetId, name);
                        },
                        icon: const Icon(Icons.favorite_rounded),
                        label: const Text('Send Connection Request', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = _supabase.auth.currentUser?.id;
    final imageUrl = widget.hotspot['image_url'] as String? ?? 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800';

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 16, bottom: 16, right: 16),
                    title: Text(
                      widget.hotspot['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(imageUrl, fit: BoxFit.cover),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.85)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 18, color: Color(0xFF6C63FF)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.hotspot['address'] ?? '',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // A shared conversation for everyone signed in to Spotmate.
                        Container(
                          padding: const EdgeInsets.all(17),
                          decoration: BoxDecoration(
                            color: const Color(0xFF162544),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Icon(Icons.forum_rounded, color: Color(0xFF35D6B4), size: 24),
                                SizedBox(width: 10),
                                Expanded(child: Text('Hotspot public chat',
                                  style: TextStyle(color: Colors.white, fontSize: 18,
                                    fontWeight: FontWeight.w800))),
                              ]),
                              const SizedBox(height: 9),
                              const Text(
                                'Say hello to people interested in this place. Public messages are visible to other Spotmate members. Request a connection for private chat.',
                                style: TextStyle(color: Color(0xFFE2E9F2),
                                  fontSize: 13, height: 1.45),
                              ),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isJoined ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HotspotPublicChatScreen(
                                        hotspotId: widget.hotspot['id'].toString(),
                                        hotspotName: widget.hotspot['name'].toString(),
                                      ),
                                    ),
                                  ) : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF35D6B4),
                                    foregroundColor: const Color(0xFF162544),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                                  label: Text(_isJoined ? 'Open public chat' : 'Join to enter chat',
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        if(_roomOwnerId!=null)
                          Container(
                            margin:const EdgeInsets.only(bottom:14),
                            padding:const EdgeInsets.all(12),
                            decoration:BoxDecoration(color:const Color(0xFFFFF5DC),
                              borderRadius:BorderRadius.circular(12)),
                            child:Row(children:[
                              const Icon(Icons.workspace_premium_rounded,color:Color(0xFFB9821C)),
                              const SizedBox(width:8),
                              Expanded(child:Text(_roomOwnerId==currentUserId
                                ? 'You own this community room'
                                : 'Room owner: $_roomOwnerName',
                                style:const TextStyle(fontWeight:FontWeight.w700))),
                              if(_isLocked)const Icon(Icons.lock,color:Color(0xFFB9821C)),
                            ]),
                          ),
                        if(!_isJoined)
                          ElevatedButton.icon(
                            onPressed:_isLocked && _roomOwnerId!=currentUserId
                              ? null : _joinRoom,
                            icon:Icon(_isLocked ? Icons.lock_rounded : Icons.login_rounded),
                            label:Text(_isLocked && _roomOwnerId!=currentUserId
                              ? 'Room locked · New members cannot join'
                              : 'Join room · No verification required'),
                            style:ElevatedButton.styleFrom(
                              padding:const EdgeInsets.symmetric(vertical:16),
                              backgroundColor:const Color(0xFF162544),
                              foregroundColor:Colors.white,
                            ),
                          )
                        else Card(
                          color:const Color(0xFFEAF8F4),
                          child:ListTile(
                            leading:const Icon(Icons.check_circle_rounded,color:Color(0xFF188F76)),
                            title:const Text('You are a room member'),
                            subtitle:Text(_isLocked
                              ? 'Room locked to new visitors; current members can chat'
                              : 'Public chat and member directory are available'),
                            trailing:TextButton(
                              onPressed:_leaveHotspot,child:const Text('Leave')),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Room members (${_activeMembers.length})',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            if (_isJoined)
                              const Row(
                                children: [
                                  Icon(Icons.circle, color: Colors.green, size: 8),
                                  SizedBox(width: 4),
                                  Text('LIVE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if(!_isJoined)
                          const Padding(
                            padding:EdgeInsets.symmetric(vertical:25),
                            child:Center(child:Text('Join the room to see other members.')),
                          )
                                                else if (_activeMembers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(40),
                            alignment: Alignment.center,
                            child: const Text('You are the first member here. Say hello!'),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _activeMembers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final member = _activeMembers[index];
                              final profile = member['user_profiles'] as Map<String, dynamic>? ?? {};
                              final targetId = profile['id'] as String? ?? '';
                              final isMe = targetId == currentUserId;
                              final photoUrl = profile['profile_photo'] as String?;
                              final name = profile['name'] ?? 'Spotmate Member';
                              final age = _calculateAge(profile['date_of_birth']);
                              final bio = profile['bio'] ?? '';

                              return Card(
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 2,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  leading: Stack(
                                    children: [
                                      SpotmateAvatar(size:48, photoUrl:photoUrl,
                                        avatarType:profile['avatar_type']?.toString() ?? 'photo',
                                        emoticon:profile['avatar_emoticon']?.toString() ?? 'smile'),
                                      const Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: CircleAvatar(
                                          radius: 6,
                                          backgroundColor: Colors.white,
                                          child: CircleAvatar(radius: 4, backgroundColor: Colors.green),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Row(children:[
                                    Flexible(child:Text('$name, $age ${isMe ? "(You)" : ""}',
                                      overflow:TextOverflow.ellipsis,
                                      style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15))),
                                    if(targetId==_roomOwnerId) ...[
                                      const SizedBox(width:6),
                                      const Chip(
                                        visualDensity:VisualDensity.compact,
                                        avatar:Icon(Icons.workspace_premium_rounded,
                                          color:Color(0xFFB9821C),size:15),
                                        label:Text('OWNER',style:TextStyle(fontSize:10)),
                                      ),
                                    ],
                                  ]),
                                  subtitle: Text(
                                    bio.isEmpty ? 'Room member' : bio,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                                  onTap: () => _showUserPhotoPopup(profile),
                                ),
                              );
                            },
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

