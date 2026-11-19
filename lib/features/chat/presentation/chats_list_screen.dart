import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/spotmate_avatar.dart';
import 'chat_screen.dart';
import 'hotspot_public_chat_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _direct = [];
  List<Map<String, dynamic>> _rooms = [];
  Set<String> _pinned = {};
  Set<String> _muted = {};
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _showRooms = false;
  bool _unreadOnly = false;
  bool _loading = true;
  bool _failed = false;
  String _search = '';
  int _generation = 0;

  String get _preferenceKey => 'spotmate.inbox.${_client.auth.currentUser?.id}';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _load();
    var channel = _client.channel('spotmate-inbox-${_client.auth.currentUser?.id}');
    for (final table in ['messages', 'calls', 'connections', 'hotspot_messages', 'hotspot_members']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _load);
        },
      );
    }
    _channel = channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) _load();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinned = (prefs.getStringList('$_preferenceKey.pin') ?? []).toSet();
      _muted = (prefs.getStringList('$_preferenceKey.mute') ?? []).toSet();
    });
  }

  Future<void> _load() async {
    if (!mounted || _client.auth.currentUser == null) return;
    final request = ++_generation;
    try {
      final results = await Future.wait([
        _client.rpc('spotmate_direct_inbox'),
        _client.rpc('spotmate_room_inbox'),
      ]);
      if (mounted && request == _generation) setState(() {
        _direct = List<Map<String, dynamic>>.from(results[0] as List);
        _rooms = List<Map<String, dynamic>>.from(results[1] as List);
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _generation) setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _togglePreference(String id, String action) async {
    final values = action == 'pin' ? _pinned : _muted;
    setState(() {
      if (!values.remove(id)) values.add(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_preferenceKey.$action', values.toList());
  }

  Future<void> _open(Map<String, dynamic> entry, bool room) async {
    if (room) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        HotspotPublicChatScreen(hotspotId: entry['hotspot_id'] as String,
          hotspotName: entry['name']?.toString() ?? 'Room')));
      if (!mounted) return;
      try {
        // Only mark messages already represented by the row the user opened.
        final lastTime = entry['last_time'] as String?;
        final userId = _client.auth.currentUser?.id;
        if (lastTime != null && userId != null) {
          await _client.rpc('spotmate_mark_room_read', params: {
            'p_hotspot': entry['hotspot_id'], 'p_read_at': lastTime,
          });
        }
      } catch (_) {
        // The inbox will retain the unread count if the update fails.
      }
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
        conversationId: entry['conversation_id'] as String,
        connectionId: entry['connection_id'] as String,
        otherUserId: entry['other_id'] as String,
        otherUserName: entry['other_name']?.toString() ?? 'Connection',
        otherUserPhoto: entry['other_photo'] as String?,
        otherUserAvatarType: entry['other_avatar_type'] as String?,
        otherUserAvatarEmoticon: entry['other_avatar_emoticon'] as String?,
      )));
    }
    if (mounted) await _load();
  }

  String _id(Map<String, dynamic> item, bool room) =>
      room ? 'room:${item['hotspot_id']}' : 'direct:${item['conversation_id']}';

  int _unread(Map<String, dynamic> item) => (item['unread'] as num?)?.toInt() ?? 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _showRooms;
    final all = room ? _rooms : _direct;
    final query = _search.trim().toLowerCase();
    final items = all.where((item) {
      final name = item[room ? 'name' : 'other_name']?.toString() ?? '';
      final preview = item['last_message']?.toString() ?? '';
      return (!_unreadOnly || _unread(item) > 0) &&
          (name.toLowerCase().contains(query) || preview.toLowerCase().contains(query));
    }).toList();
    items.sort((a,b) {
      final pinOrder = (_pinned.contains(_id(b, room)) ? 1 : 0) -
          (_pinned.contains(_id(a, room)) ? 1 : 0);
      if (pinOrder != 0) return pinOrder;
      return (b['last_time']?.toString() ?? '').compareTo(a['last_time']?.toString() ?? '');
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                hintText: 'Search chats', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              ChoiceChip(label: const Text('Direct'), selected: !room,
                onSelected: (_) => setState(() => _showRooms = false)),
              ChoiceChip(label: const Text('Rooms'), selected: room,
                onSelected: (_) => setState(() => _showRooms = true)),
              FilterChip(label: const Text('Unread'), selected: _unreadOnly,
                onSelected: (value) => setState(() => _unreadOnly = value)),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (_failed) TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Could not refresh chats. Retry'),
                ),
                if (!_loading && !_failed && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _unreadOnly || query.isNotEmpty ? 'No matching chats.' :
                      room ? 'Join a hotspot in Explore to see its room chat here.' :
                        'Connect with someone to start a conversation.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final entry in items) _row(entry, room),
              ],
            ),
          )),
        ]),
      )),
    );
  }

  Widget _row(Map<String, dynamic> entry, bool room) {
    final id = _id(entry, room);
    final name = entry[room ? 'name' : 'other_name']?.toString() ?? 'Chat';
    final time = DateTime.tryParse(entry['last_time']?.toString() ?? '')?.toLocal();
    final unread = _unread(entry);
    final pinned = _pinned.contains(id);
    final muted = _muted.contains(id);
    return Card(
      child: ListTile(
        onTap: () => _open(entry, room),
        leading: room
            ? const CircleAvatar(child: Icon(Icons.forum_outlined))
            : SpotmateAvatar(size: 44, photoUrl: entry['other_photo'] as String?,
                avatarType: entry['other_avatar_type']?.toString() ?? 'photo',
                emoticon: entry['other_avatar_emoticon']?.toString() ?? 'boy_01'),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500)),
        subtitle: Text(entry['last_message']?.toString() ?? 'No messages yet',
          maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (time != null) Text(DateFormat.Md().add_jm().format(time),
              style: Theme.of(context).textTheme.labelSmall),
            if (unread > 0)
              Badge(label: Text(unread > 99 ? '99+' : '$unread'), isLabelVisible: true),
          ]),
          PopupMenuButton<String>(
            tooltip: 'Chat options',
            icon: Icon(pinned ? Icons.push_pin_outlined :
                muted ? Icons.notifications_off_outlined : Icons.more_vert),
            onSelected: (action) => _togglePreference(id, action),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
              if (!room)
                PopupMenuItem(value: 'mute', child: Text(muted ? 'Unmute alerts' : 'Mute alerts')),
            ],
          ),
        ]),
      ),
    );
  }
}
