import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/presentation/hotspot_public_chat_screen.dart';
import '../../hotspots/presentation/create_community_hotspot_screen.dart';
import '../../profile/presentation/user_profile_detail_screen.dart';
import '../../../core/widgets/spotmate_avatar.dart';

class CityChatView extends StatefulWidget {
  const CityChatView({super.key, required this.isVisible});

  final bool isVisible;

  @override
  State<CityChatView> createState() => _CityChatViewState();
}

class _CityChatViewState extends State<CityChatView> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _cities = [];
  Map<String, dynamic>? _city;
  Map<String, dynamic>? _room;
  bool _loading = true;
  bool _searchOpen = false;
  String? _error;
  Future<void> _joinQueue = Future.value();
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void didUpdateWidget(covariant CityChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final city = _city;
    if (widget.isVisible && !oldWidget.isVisible && city != null) {
      _enter(city);
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _request++;
    }
  }

  Future<void> _loadCities() async {
    try {
      final cities = await _client.from('cities')
          .select('id,name,state').eq('is_active', true).order('name');
      final user = _client.auth.currentUser;
      final profile = user == null ? null : await _client.from('user_profiles')
          .select('city_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final preferred = cities.where((city) => city['id'] == profile?['city_id']);
      setState(() {
        _cities = cities;
        _loading = false;
        _error = null;
      });
      if (preferred.isNotEmpty) await _enter(preferred.first);
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load regions. Try again.';
      });
    }
  }

  Future<void> _enter(Map<String, dynamic> city) {
    final request = ++_request;
    setState(() {
      _city = city;
      _room = null;
      _loading = widget.isVisible;
      _error = null;
    });
    if (!widget.isVisible) return Future.value();
    _joinQueue = _joinQueue.then((_) async {
      if (!mounted || request != _request) return;
      try {
        final room = await _client.from('hotspots').select('id,name')
            .eq('city_id', city['id']).eq('is_city_chat', true).maybeSingle();
        if (!mounted || request != _request) return;
        if (room == null) throw StateError('No city chat available');
        await _client.rpc('join_hotspot_room', params: {'p_hotspot_id': room['id']});
        if (mounted && request == _request) setState(() {
          _room = room;
          _loading = false;
        });
      } catch (_) {
        if (mounted && request == _request) setState(() {
          _loading = false;
          _error = 'Could not enter this city chat. Try again.';
        });
      }
    });
    return _joinQueue;
  }

  Future<void> _pickRegion() async {
    final states = _cities.map((city) => city['state']?.toString() ?? '')
        .where((state) => state.isNotEmpty).toSet().toList()..sort();
    String? state = _city?['state'] as String?;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (context, update) => SafeArea(
        child: FractionallySizedBox(heightFactor: .65, child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Choose a region', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: state,
              decoration: const InputDecoration(labelText: 'State'),
              items: [for (final name in states)
                DropdownMenuItem(value: name, child: Text(name))],
              onChanged: (value) => update(() => state = value),
            ),
            if (state != null) ...[
              const SizedBox(height: 8),
              for (final city in _cities.where((city) => city['state'] == state))
                ListTile(title: Text(city['name'].toString()),
                  onTap: () => Navigator.pop(sheet, city)),
            ],
          ],
        )),
      )),
    );
    if (mounted && picked != null) await _enter(picked);
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    final city = _city;
    setState(() => _searchOpen = true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ExploreSearch(city: city)));
    if (!mounted) return;
    setState(() => _searchOpen = false);
    if (city != null && widget.isVisible) await _enter(city);
  }

  @override
  Widget build(BuildContext context) {
    final region = _city == null ? 'Select region' : "${_city!['state']} / ${_city!['name']}";
    final room = _room;
    if (!widget.isVisible || _searchOpen) return const SizedBox.shrink();
    if (room != null) {
      return HotspotPublicChatScreen(
        key: ValueKey(room['id']),
        hotspotId: room['id'] as String,
        hotspotName: room['name'].toString(),
        cityRegion: region,
        onPickRegion: _pickRegion,
        onSearch: _openSearch,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: TextButton.icon(
          onPressed: _cities.isEmpty ? null : _pickRegion,
          icon: const Icon(Icons.location_on_outlined), label: Text(region),
        ),
        actions: [IconButton(tooltip: 'Search', onPressed: _openSearch,
          icon: const Icon(Icons.search))],
      ),
      body: Center(child: _loading ? const CircularProgressIndicator()
          : _error != null ? TextButton(onPressed: () {
              final city = _city;
              if (city == null) {
                _loadCities();
              } else {
                _enter(city);
              }
            }, child: Text(_error!))
          : FilledButton(onPressed: _pickRegion, child: const Text('Choose your city'))),
    );
  }
}

class _ExploreSearch extends StatefulWidget {
  const _ExploreSearch({required this.city});

  final Map<String, dynamic>? city;

  @override
  State<_ExploreSearch> createState() => _ExploreSearchState();
}

class _ExploreSearchState extends State<_ExploreSearch> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _rooms = [];
  bool _showRooms = false;
  bool _joining = false;
  bool _loading = false;
  bool _roomsLoading = true;
  bool _failed = false;
  bool _roomsFailed = false;
  String _query = '';
  Timer? _debounce;
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rows = await _client.rpc('spotmate_room_directory');
      if (mounted) setState(() {
        _rooms = List<Map<String, dynamic>>.from(rows as List)
            .where((row) => row['city_id'] == widget.city?['id']).toList();
        _roomsLoading = false;
        _roomsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _roomsLoading = false;
        _roomsFailed = true;
      });
    }
  }

  void _search(String value) {
    final query = value.trim();
    final version = ++_searchRequest;
    _debounce?.cancel();
    setState(() {
      _query = query;
      _people = [];
      _loading = query.length >= 2;
      _failed = false;
    });
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final rows = await _client.rpc('find_spotmate_people', params: {'p_query': query});
        if (mounted && version == _searchRequest) setState(() {
          _people = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      } catch (_) {
        if (mounted && version == _searchRequest) setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  Future<void> _openRoom(Map<String, dynamic> room) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final id = room['id'] as String;
      await _client.rpc('join_hotspot_room', params: {'p_hotspot_id': id});
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        HotspotPublicChatScreen(hotspotId: id, hotspotName: room['name'].toString())));
      if (mounted) await _loadRooms();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not enter this chat room.')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms.where((room) => (room['name']?.toString().toLowerCase() ?? '')
        .contains(_query.toLowerCase()));
    final city = widget.city;
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: TextField(
            maxLength: 64,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: _showRooms ? 'Search chat rooms' : 'Search by name or user ID',
              prefixIcon: const Icon(Icons.search), counterText: '',
            ),
          )),
          Wrap(spacing: 10, children: [
            ChoiceChip(label: const Text('People'), selected: !_showRooms,
              onSelected: (_) => setState(() => _showRooms = false)),
            ChoiceChip(label: const Text('Chat rooms'), selected: _showRooms,
              onSelected: (_) => setState(() => _showRooms = true)),
          ]),
          if (_showRooms ? _roomsLoading : _loading) const LinearProgressIndicator(),
          Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
            if (_showRooms) ...[
              if (_roomsFailed) TextButton(onPressed: _loadRooms, child: const Text('Could not load rooms. Retry')),
              if (city == null) const ListTile(title: Text('Choose a city in Explore to find chat rooms.')),
              if (city != null) ...[
                ListTile(
                  title: Text(city['name'].toString()),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create chat room'),
                    onPressed: _joining ? null : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                        CreateCommunityHotspotScreen(cityId: city['id'] as String)));
                      if (mounted) await _loadRooms();
                    },
                  ),
                ),
                for (final room in rooms)
                  ListTile(
                    title: Text(room['name'].toString()),
                    subtitle: Text("${room['member_count']} active members"),
                    leading: Icon(room['is_locked'] == true ? Icons.lock_outline : Icons.forum_outlined),
                    onTap: _joining || (room['is_locked'] == true && room['joined'] != true &&
                      room['owner_id'] != _client.auth.currentUser?.id) ? null : () => _openRoom(room),
                  ),
                if (!_roomsLoading && !_roomsFailed && rooms.isEmpty)
                  const ListTile(title: Text('No chat rooms found.')),
              ],
            ] else ...[
              if (_failed) TextButton(onPressed: () => _search(_query),
                child: const Text('Could not search people. Retry')),
              if (!_loading && !_failed && _query.length >= 2 && _people.isEmpty)
                const ListTile(title: Text('No people found.')),
              for (final person in _people)
                ListTile(
                  leading: SpotmateAvatar(photoUrl: person['profile_photo'] as String?,
                    avatarType: person['avatar_type']?.toString() ?? 'photo',
                    emoticon: person['avatar_emoticon']?.toString() ?? 'boy_01'),
                  title: Text(person['name'].toString()),
                  subtitle: person['spotmate_id'] == null ? null : Text(person['spotmate_id'].toString()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                    UserProfileDetailScreen(userId: person['id'] as String))),
                ),
            ],
          ])),
        ]),
      )),
    );
  }
}
