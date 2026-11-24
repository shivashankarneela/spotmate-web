import '../../../core/widgets/spotmate_avatar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_detail_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<List<Map<String, dynamic>>> _friends;
  Timer? _refresh;

  Future<List<Map<String, dynamic>>> _load() async {
    return _loadFriends();
  }

  @override
  void initState() {
    super.initState();
    _friends = _load();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => _reload());
  }

  Future<void> _reload() async {
    setState(() => _friends = _load());
    try {
      await _friends;
    } catch (_) {
      // FutureBuilder displays the request error.
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _friends,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('Could not load friends. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final friends = snapshot.data!;
          if (friends.isEmpty) {
            return const Center(child: Text('No friends yet'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final friend = friends[index];
                final username = friend['username'] as String?;
                return ListTile(
                  leading: _friendAvatar(friend),
                  title: Text(friend['name'] as String? ?? 'Friend'),
                  subtitle: Text([
                    if (username != null) '@$username',
                    friend['city'] as String? ?? 'Outside city rooms',
                  ].join(' · ')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UserProfileDetailScreen(
                        userId: friend['friend_id'] as String,
                        connectionId: friend['connection_id'] as String,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> _loadFriends() async {
  final client = Supabase.instance.client;
  final result = await client.rpc('spotmate_friends') as List;
  final friends = List<Map<String, dynamic>>.from(result);
  if (friends.isEmpty) return friends;
  final ids = friends.map((row) => row['friend_id'] as String).toList();
  try {
    final profiles = await client.from('user_profiles')
        .select('id,profile_photo,avatar_type,avatar_emoticon')
        .inFilter('id', ids);
    final byId = {for (final profile in profiles) profile['id']: profile};
    return [for (final friend in friends)
      {...?byId[friend['friend_id']], ...friend}];
  } on PostgrestException {
    return friends;
  }
}

Widget _friendAvatar(Map<String, dynamic> friend) => SpotmateAvatar(
  size: 44,
  photoUrl: friend['profile_photo'] as String?,
  avatarType: friend['avatar_type'] as String? ?? 'photo',
  emoticon: friend['avatar_emoticon'] as String? ?? 'boy_01',
);

class FriendsPreview extends StatefulWidget {
  const FriendsPreview({super.key});

  @override
  State<FriendsPreview> createState() => _FriendsPreviewState();
}

class _FriendsPreviewState extends State<FriendsPreview> {
  late Future<List<Map<String, dynamic>>> _friends = _loadFriends();
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 25), (_) {
      setState(() => _friends = _loadFriends());
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() => _friends = _loadFriends());
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero, color: Colors.white, elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Friends', style: Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed: () => _open(const FriendsScreen()), child: const Text('View all')),
        ]),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _friends,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Friends are temporarily unavailable.');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final friends = snapshot.data!;
            if (friends.isEmpty) return const Text('No friends yet');
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (final friend in friends.take(4))
                SizedBox(width: 112, child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(UserProfileDetailScreen(
                    userId: friend['friend_id'] as String,
                    connectionId: friend['connection_id'] as String,
                  )),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(children: [
                      _friendAvatar(friend),
                      const SizedBox(height: 6),
                      Text(friend['name'] as String? ?? 'Friend',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(friend['city'] as String? ?? 'Outside city rooms',
                        maxLines: 2, textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                )),
            ]);
          },
        ),
      ]),
    ),
  );
}
