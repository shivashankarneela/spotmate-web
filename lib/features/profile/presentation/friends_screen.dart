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
    final rows = await Supabase.instance.client.rpc('spotmate_friends');
    return List<Map<String, dynamic>>.from(rows as List);
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
                  leading: const Icon(Icons.person_outline),
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
