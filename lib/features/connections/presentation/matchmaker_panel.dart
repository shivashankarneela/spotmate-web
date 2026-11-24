import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/presentation/my_photos_screen.dart';

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
  String? _error;
  String _scope = 'city';

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _run('view');
  }

  @override
  void didUpdateWidget(covariant MatchmakerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _run('view');
    if (!widget.isVisible) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(String action, {String? target, bool quiet = false}) async {
    if (_busy) return;
    _busy = true;
    if (!quiet) setState(() => _error = null);
    try {
      final result = await _client.rpc('spotmate_regional_matchmaker',
        params: {'p_action': action, 'p_target': target, 'p_scope': action == 'start' ? _scope : null});
      if (!mounted) return;
      final session = Map<String, dynamic>.from(result as Map);
      setState(() {
        _session = session;
        _error = null;
      });
      if (!quiet && (action == 'connect' || session['matched'] == true)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(session['matched'] == true
              ? 'It’s a match. Find your conversation in Chats.'
              : 'Connect saved. A chat opens if they connect too.'),
        ));
      }
      if (widget.isVisible && session['active'] == true) {
        _refreshTimer ??= Timer.periodic(const Duration(seconds: 15),
          (_) => _run('view', quiet: true));
      } else {
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    } catch (error) {
      if (mounted && !quiet) {
        final detail = error is PostgrestException ? error.message : '';
        setState(() => _error = detail == 'This suggestion is no longer available'
            ? 'This suggestion is no longer available. Refresh to see who is still here.'
            : 'Could not update Matchmaker. Try again.');
      }
    } finally {
      _busy = false;
      if (mounted && !quiet) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final active = session?['active'] == true;
    final eligible = session?['eligible'] == true;
    final needsPhoto = session?['has_photo'] == false;
    final city = session?['city_name']?.toString();
    final state = session?['state_name']?.toString();
    final region = switch (session?['scope']) {
      'state' => state ?? 'your state',
      'any' => 'any region',
      _ => city ?? 'your city',
    };
    final end = DateTime.tryParse(session?['expires_at']?.toString() ?? '');
    final suggestions = (session?['suggestions'] as List?) ?? const [];
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: RefreshIndicator(
          onRefresh: () => _run('view'),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Regional Matchmaker', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(active && end != null
                      ? 'Discovering in $region until ${DateFormat.jm().format(end.toLocal())}.'
                      : 'Opt in for one hour to meet people whose region and preferences match yours.'),
                  if (eligible && !active)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final option in const {'city':'My city','state':'My state','any':'Any region'}.entries)
                          ChoiceChip(label: Text(option.value), selected: _scope == option.key,
                            onSelected: _busy ? null : (_) => setState(() => _scope = option.key)),
                      ]),
                    ),
                  if (session != null && !eligible && !needsPhoto)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Matchmaker is for adults. Check your city and birthday in Account.'),
                    ),
                  if (needsPhoto)
                    TextButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Add a photo to join matchmaking'),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const MyPhotosScreen()),
                        );
                        if (mounted) await _run('view');
                      },
                    ),
                  if (eligible && !active)
                    const Text('While discovery is active, suggested members can see your selected matchmaking photo. Your gallery keeps its own visibility settings.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    if (active)
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run('stop'),
                        child: const Text('End discovery'),
                      )
                    else if (eligible)
                      FilledButton(
                        onPressed: _busy ? null : () => _run('start'),
                        child: const Text('Find a match'),
                      ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _run('view'),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ]),
                ]),
              )),
              if (_busy && session == null) const LinearProgressIndicator(),
              if (_error != null) Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
              if (active && suggestions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No new suggestions for this region yet. You can stay in discovery or end it and choose a wider region.'),
                ),
              for (final raw in suggestions)
                if (raw is Map) Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: raw['matchmaker_photo'] is String
                            ? _MatchmakerPhoto(
                                key: ValueKey(raw['matchmaker_photo']),
                                path: raw['matchmaker_photo'] as String,
                              )
                            : const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(raw['name']?.toString() ?? 'SpotMate member'),
                        subtitle: Text([raw['city_name'], raw['state_name']].whereType<String>().join(', ')),
                      ),
                      if (raw['bio']?.toString().trim().isNotEmpty == true)
                        Text(raw['bio'].toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(spacing: 8, children: [
                          TextButton(
                            onPressed: _busy ? null : () => _run('pass', target: raw['id'].toString()),
                            child: const Text('Pass'),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _run('connect', target: raw['id'].toString()),
                            child: const Text('Connect'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchmakerPhoto extends StatefulWidget {
  const _MatchmakerPhoto({super.key, required this.path});
  final String path;

  @override
  State<_MatchmakerPhoto> createState() => _MatchmakerPhotoState();
}

class _MatchmakerPhotoState extends State<_MatchmakerPhoto> {
  late final _bytes = Supabase.instance.client.storage
      .from('my-photos').download(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snapshot) {
      final bytes = snapshot.data;
      return CircleAvatar(
        radius: 26,
        foregroundImage: bytes == null ? null : MemoryImage(bytes),
        child: const Icon(Icons.person_outline),
      );
    },
  );
}
