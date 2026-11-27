import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/spotmate_avatar.dart';
import '../../profile/presentation/my_photos_screen.dart';
import '../../profile/presentation/user_profile_detail_screen.dart';

class MatchmakerPanel extends StatefulWidget {
  const MatchmakerPanel({super.key, required this.isVisible});

  final bool isVisible;

  @override
  State<MatchmakerPanel> createState() => _MatchmakerPanelState();
}

class _MatchmakerPanelState extends State<MatchmakerPanel> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _session;
  Timer? _refreshTimer;
  bool _busy = false;
  bool _prompted = false;
  bool _legacy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _enter();
  }

  @override
  void didUpdateWidget(covariant MatchmakerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _enter();
    if (!widget.isVisible) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _prompted = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _enter() async {
    await _run('view');
    if (!mounted || !widget.isVisible || _prompted ||
        _session?['eligible'] != true || _session?['active'] == true) return;
    await _prompt();
  }

  Future<void> _prompt() async {
    _prompted = true;
    final enabled = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.style_outlined),
        title: const Text('Discover me'),
        content: Text(_legacy
            ? 'Join Matchmaker for one hour. Members can see your selected photo and city and connect with you.'
            : 'Join Matchmaker so members can see your avatar and profile city and connect with you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Discover me')),
        ],
      ),
    );
    if (enabled == true && mounted && widget.isVisible) await _run('start');
  }

  Future<void> _settings() async {
    final hide = await showModalBottomSheet<bool>(
      context: context, showDragHandle: true, useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Discovery settings', style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Hide your profile from Matchmaker anytime.'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Undiscover me')),
        ]),
      ),
    );
    if (hide == true && mounted) await _run('stop');
  }

  Future<dynamic> _request(String action, String? target) async {
    final params = {'p_action': action, 'p_target': target, 'p_scope': action == 'start' ? 'any' : null};
    if (!_legacy) {
      try {
        return await _client.rpc('haloberry_matchmaker', params: params);
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202' || !error.message.contains('haloberry_matchmaker')) rethrow;
        _legacy = true;
      }
    }
    return _client.rpc('spotmate_regional_matchmaker', params: params);
  }

  Future<void> _run(String action, {String? target, bool quiet = false}) async {
    if (_busy) return;
    _busy = true;
    if (!quiet) setState(() => _error = null);
    try {
      final result = await _request(action, target);
      if (!mounted) return;
      final session = Map<String, dynamic>.from(result as Map);
      setState(() {
        _session = session;
        _error = null;
      });
      if (action == 'connect') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(session['matched'] == true
              ? 'It’s a match. Find your conversation in Chats.'
              : 'Connect saved. A chat opens if they connect too.'),
        ));
      }
      if (widget.isVisible && session['active'] == true) {
        _refreshTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => _run('view', quiet: true));
      } else {
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    } catch (error) {
      if (mounted && !quiet) {
        final detail = error is PostgrestException ? error.message : '';
        setState(() => _error = detail == 'This suggestion is no longer available'
            ? 'This suggestion is no longer available. Pull down to refresh.'
            : 'Could not update Matchmaker. Try again.');
      }
    } finally {
      _busy = false;
      if (mounted && !quiet) setState(() {});
    }
  }

  Widget _card(Map member) {
    final id = member['id'].toString();
    final city = member['city_name']?.toString();
    final photo = member['matchmaker_photo'];
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 215,
          decoration: BoxDecoration(gradient: LinearGradient(
            colors: [colors.primaryContainer, colors.tertiaryContainer],
          )),
          child: photo is String
              ? _MatchmakerPhoto(key: ValueKey(photo), path: photo)
              : Center(child: SpotmateAvatar(
                  size: 180, avatarType: 'emoticon',
                  emoticon: member['avatar_emoticon']?.toString() ?? 'boy_01')),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member['name']?.toString() ?? 'HaloBerry member',
              style: Theme.of(context).textTheme.headlineSmall),
            if (city != null && city.isNotEmpty) Text(city),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => UserProfileDetailScreen(userId: id)),
              ), child: const Text('View profile')),
              FilledButton(onPressed: _busy ? null : () => _run('connect', target: id), child: const Text('Connect')),
              TextButton(onPressed: _busy ? null : () => _run('pass', target: id), child: const Text('Pass')),
            ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final active = session?['active'] == true;
    final eligible = session?['eligible'] == true;
    final needsPhoto = session?['has_photo'] == false;
    final city = session?['city_name'];
    final suggestions = ((session?['suggestions'] as List?) ?? const []).whereType<Map>().toList();
    bool isLocal(Map person) => person['local'] == true ||
        (_legacy && city != null && person['city_name'] == city);
    final local = suggestions.where(isLocal);
    final elsewhere = suggestions.where((member) => !isLocal(member));
    final theme = Theme.of(context);
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: RefreshIndicator(
        onRefresh: _enter,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Matchmaker', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_busy && session == null) const LinearProgressIndicator(),
            if (_error != null) ListTile(
              title: Text(_error!), trailing: TextButton(onPressed: _enter, child: const Text('Retry'))),
            if (active)
              Card(child: ListTile(
                leading: const Icon(Icons.circle, size: 14, color: Colors.green),
                title: const Text('Discoverable'),
                trailing: IconButton(tooltip: 'Discovery settings', onPressed: _busy ? null : _settings,
                  icon: const Icon(Icons.settings_outlined)),
              ))
            else if (eligible)
              FilledButton(onPressed: _busy ? null : _prompt, child: const Text('Discover me'))
            else if (needsPhoto)
              TextButton.icon(
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Choose a matchmaking photo'),
                onPressed: () async {
                  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const MyPhotosScreen()));
                  if (mounted) await _enter();
                },
              )
            else if (session != null)
              const Text('Matchmaker is for adults. Check your city and birthday in Account.'),
            if (active && suggestions.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No profiles available yet.')),
            if (active && local.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(city == null ? 'People nearby' : 'People in $city', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              ...local.map(_card),
            ],
            if (active && elsewhere.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('People from other cities', style: theme.textTheme.titleLarge),
              if (local.isEmpty) const Text('No one nearby yet.'),
              const SizedBox(height: 8),
              ...elsewhere.map(_card),
            ],
          ],
        ),
      ),
    ));
  }
}

class _MatchmakerPhoto extends StatefulWidget {
  const _MatchmakerPhoto({super.key, required this.path});
  final String path;

  @override
  State<_MatchmakerPhoto> createState() => _MatchmakerPhotoState();
}

class _MatchmakerPhotoState extends State<_MatchmakerPhoto> {
  late final _bytes = Supabase.instance.client.storage.from('my-photos').download(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snapshot) {
      final bytes = snapshot.data;
      return bytes == null
          ? const Center(child: Icon(Icons.person_outline, size: 48))
          : Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => const Icon(Icons.person_outline));
    },
  );
}
