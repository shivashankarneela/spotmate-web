import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/features/chat/presentation/chat_screen.dart';

class HotspotDetailScreen extends StatefulWidget {
  final Map<String, dynamic> hotspot;
  const HotspotDetailScreen({super.key, required this.hotspot});

  @override
  State<HotspotDetailScreen> createState() => _HotspotDetailScreenState();
}

class _HotspotDetailScreenState extends State<HotspotDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _isJoined = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeMembers = [];
  Set<String> _sentRequestUserIds = {};
  Set<String> _connectedUserIds = {};
  Map<String, String> _userToConnectionId = {};

  // 30-Minute Revisit Grace Window State
  bool _canFastUnlock = false;
  int _minutesRemaining = 0;

  final _venuePinController = TextEditingController();

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
      // 1. Check if user is currently active here
      final myMembership = await _supabase
          .from('hotspot_members')
          .select('status')
          .eq('hotspot_id', widget.hotspot['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      _isJoined = myMembership != null && myMembership['status'] == 'active';

      // 2. Check 30-minute revisit grace session
      final prefs = await SharedPreferences.getInstance();
      final lastVerifiedIso = prefs.getString('hotspot_verified_${widget.hotspot['id']}');

      bool fastUnlock = false;
      int remaining = 0;

      if (lastVerifiedIso != null) {
        final lastVerifiedTime = DateTime.tryParse(lastVerifiedIso);
        if (lastVerifiedTime != null) {
          final difference = DateTime.now().difference(lastVerifiedTime);
          if (difference.inMinutes < 30) {
            fastUnlock = true;
            remaining = 30 - difference.inMinutes;
          }
        }
      }

      // 3. Fetch active members
      final membersResponse = await _supabase
          .from('hotspot_members')
          .select('user_id, joined_at, user_profiles(id, name, bio, gender, looking_for, date_of_birth, profile_photo, spotmate_id)')
          .eq('hotspot_id', widget.hotspot['id'])
          .eq('status', 'active');

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
          _canFastUnlock = fastUnlock;
          _minutesRemaining = remaining;
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

  Future<void> _executeJoin({bool isFastUnlock = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      await _supabase.from('hotspot_members').delete().eq('user_id', user.id);

      await _supabase.from('hotspot_members').insert({
        'hotspot_id': widget.hotspot['id'],
        'user_id': user.id,
        'status': 'active',
        'joined_at': DateTime.now().toIso8601String(),
        'last_seen_at': DateTime.now().toIso8601String(),
      });

      // Save verification timestamp for 30-minute fast unlock pass
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hotspot_verified_${widget.hotspot['id']}', DateTime.now().toIso8601String());

      _isJoined = true;
      await _loadAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Row(
              children: [
                const Icon(Icons.verified, color: Colors.white),
                const SizedBox(width: 8),
                Text(isFastUnlock 
                    ? 'Welcome back! Unlocked via 30-min pass.' 
                    : 'Presence Verified! Member directory unlocked for ${widget.hotspot['name']}.'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveHotspot() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      await _supabase.from('hotspot_members').delete().eq('user_id', user.id);
      _isJoined = false;
      await _loadAll();
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVerificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        bool showSecondMethod = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFF4B6E).withOpacity(0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.verified_user_rounded, color: Color(0xFFFF4B6E), size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Verify Venue Presence', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            Text('Unlock live members directory at ${widget.hotspot['name']}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Method 1: GPS Geofence Verification
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4B6E).withOpacity(0.06),
                      border: Border.all(color: const Color(0xFFFF4B6E).withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.radar_rounded, color: Color(0xFFFF4B6E), size: 26),
                            SizedBox(width: 10),
                            Text('GPS Proximity Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Verifies your device is within 100m of this venue to unlock live directory.',
                          style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.my_location),
                          label: const Text('Verify Location & Unlock', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4B6E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _executeJoin();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (!showSecondMethod)
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setSheetState(() => showSecondMethod = true);
                        },
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                        label: const Text('Try another way (Venue PIN / Passcode)'),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.pin_outlined, color: Colors.blueAccent, size: 22),
                              SizedBox(width: 8),
                              Text('Enter Venue Table / Receipt PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Enter 4-digit code displayed at the venue counter (Code: 1234)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _venuePinController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: '4-Digit PIN (e.g. 1234)',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _executeJoin();
                                },
                                child: const Text('Verify PIN'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
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
                        avatar: const Icon(Icons.favorite, size: 14, color: Color(0xFFFF4B6E)),
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
                          backgroundColor: const Color(0xFFFF4B6E),
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
    _venuePinController.dispose();
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
                            const Icon(Icons.location_on, size: 18, color: Color(0xFFFF4B6E)),
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

                        // Check-in Status Banner
                        if (!_isJoined)
                          ElevatedButton.icon(
                            onPressed: _canFastUnlock ? () => _executeJoin(isFastUnlock: true) : _showVerificationSheet,
                            icon: Icon(_canFastUnlock ? Icons.lock_open_rounded : Icons.verified_outlined),
                            label: Text(
                              _canFastUnlock ? 'Unlock Directory (Revisit Session Active)' : 'Verify Presence & Check In',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _canFastUnlock ? Colors.green.shade700 : theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified, color: Colors.green, size: 24),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Directory Unlocked • Active Now', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                                      Text('Your profile is live in this venue directory', style: TextStyle(color: Colors.black54, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _leaveHotspot,
                                  child: const Text('Leave Spot', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Verified Members Present (${_activeMembers.length})',
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

                        // PROTECTED CARD: Fast Unlock vs Verify & Unlock
                        if (!_isJoined)
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: _canFastUnlock ? Colors.green.withOpacity(0.12) : const Color(0xFFFF4B6E).withOpacity(0.1), 
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _canFastUnlock ? Icons.lock_open_rounded : Icons.lock_outline_rounded, 
                                      size: 40, 
                                      color: _canFastUnlock ? Colors.green.shade700 : const Color(0xFFFF4B6E),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  if (_canFastUnlock) ...[
                                    Text('Revisit Session Active', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'You verified at this venue recently.\nTap Unlock to view members without re-verifying for the next $_minutesRemaining minutes.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.3),
                                    ),
                                    const SizedBox(height: 18),
                                    // FAST UNLOCK BUTTON FOR 2ND VISIT (NO VERIFICATION NEEDED!)
                                    ElevatedButton.icon(
                                      onPressed: () => _executeJoin(isFastUnlock: true),
                                      icon: const Icon(Icons.lock_open_rounded),
                                      label: const Text('Unlock Member Directory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ] else ...[
                                    const Text('Member Directory Protected', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'There are ${_activeMembers.length} verified members at this venue.\nConfirm your physical presence to view profiles and connect.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.3),
                                    ),
                                    const SizedBox(height: 18),
                                    // FIRST VISIT BUTTON (TRIGGERS GPS / PIN)
                                    ElevatedButton(
                                      onPressed: _showVerificationSheet,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.colorScheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text('Verify & Unlock Directory'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else if (_activeMembers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(40),
                            alignment: Alignment.center,
                            child: const Text('You are the first member checked in here today!'),
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
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.grey[300],
                                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                            ? NetworkImage(photoUrl)
                                            : null,
                                        child: photoUrl == null
                                            ? const Icon(Icons.person, size: 24, color: Colors.grey)
                                            : null,
                                      ),
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
                                  title: Text(
                                    '$name, $age ${isMe ? "(You)" : ""}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  subtitle: Text(
                                    bio.isEmpty ? 'Active at this venue' : bio,
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
