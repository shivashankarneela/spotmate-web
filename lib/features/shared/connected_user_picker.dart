import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectedUser {
  const ConnectedUser({
    required this.userId,
    required this.name,
    required this.spotmateId,
    required this.conversationId,
    required this.online,
  });

  final String userId;
  final String name;
  final String spotmateId;
  final String conversationId;
  final bool online;
}

Future<ConnectedUser?> pickConnectedUser(BuildContext context, {
  Set<String> excludedUserIds = const {},
}) {
  return showModalBottomSheet<ConnectedUser>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ConnectedUserPicker(excludedUserIds: excludedUserIds),
  );
}

class _ConnectedUserPicker extends StatefulWidget {
  const _ConnectedUserPicker({required this.excludedUserIds});
  final Set<String> excludedUserIds;

  @override
  State<_ConnectedUserPicker> createState() => _ConnectedUserPickerState();
}

class _ConnectedUserPickerState extends State<_ConnectedUserPicker> {
  List<ConnectedUser> _users = [];
  bool _loading = true;
  bool _failed = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final client = Supabase.instance.client;
      final inbox = (await client.rpc('spotmate_direct_inbox') as List)
          .whereType<Map>()
          .where((row) => !widget.excludedUserIds.contains(row['other_id']?.toString()))
          .toList();
      final ids = inbox.map((row) => row['other_id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet().toList();
      List<dynamic> profiles = [];
      if (ids.isNotEmpty) {
        try {
          profiles = await client.from('user_profiles')
              .select('id,last_seen_at').inFilter('id', ids);
        } catch (_) {
          // Chat sharing still works when profile presence is unavailable.
        }
      }
      final spotmateIds = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final rows = await client.rpc('visible_spotmate_ids', params: {'p_users': ids}) as List;
          for (final row in rows) {
            spotmateIds[row['user_id'] as String] = row['spotmate_id'] as String;
          }
        } on PostgrestException {
          // Sharing still works without displaying identifiers.
        }
      }
      final byId = {for (final row in profiles) row['id'].toString(): row};
      final now = DateTime.now().toUtc();
      final users = <ConnectedUser>[];
      for (final row in inbox) {
        final id = row['other_id']?.toString() ?? '';
        final conversation = row['conversation_id']?.toString() ?? '';
        if (id.isEmpty || conversation.isEmpty) continue;
        final profile = byId[id];
        final seen = DateTime.tryParse(profile?['last_seen_at']?.toString() ?? '')?.toUtc();
        final seconds = seen == null ? null : now.difference(seen).inSeconds;
        users.add(ConnectedUser(
          userId: id,
          name: row['other_name']?.toString() ?? 'Connection',
          spotmateId: spotmateIds[id] ?? '',
          conversationId: conversation,
          online: seconds != null && seconds >= 0 && seconds < 60,
        ));
      }
      users.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (mounted) setState(() { _users = users; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _users.where((user) =>
      user.name.toLowerCase().contains(_search.toLowerCase()) ||
      user.spotmateId.toLowerCase().contains(_search.toLowerCase())).toList();
    return SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(children: [
        const Text('Invite a connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Padding(padding: EdgeInsets.all(8),
          child: Text('Online status is based on recent activity.', style: TextStyle(fontSize: 12))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search connections'))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
          : _failed ? Center(child: TextButton(onPressed: _load, child: const Text('Could not load connections. Retry')))
          : filtered.isEmpty ? const Center(child: Text('No connections found.'))
          : ListView.builder(itemCount: filtered.length, itemBuilder: (context, index) {
              final user = filtered[index];
              return ListTile(
                leading: CircleAvatar(child: Text(user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase())),
                title: Text(user.name),
                subtitle: Text(user.online ? 'Online recently' : 'Not recently active'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, user),
              );
            })),
      ]),
    ));
  }
}
