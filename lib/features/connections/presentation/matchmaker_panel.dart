import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/spotmate_avatar.dart';

class MatchmakerPanel extends StatefulWidget {
  const MatchmakerPanel({super.key});

  @override
  State<MatchmakerPanel> createState() => _MatchmakerPanelState();
}

class _MatchmakerPanelState extends State<MatchmakerPanel> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _session;
  Timer? _refreshTimer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run('view');
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
      final result = await _client.rpc('spotmate_matchmaker',
        params: {'p_action': action, 'p_target': target});
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
      if (session['active'] == true) {
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
    final hotspot = session?['hotspot_name']?.toString();
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
                  Text('Hotspot matchmaker', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(active && end != null
                      ? 'Discovering at ${hotspot ?? 'your hotspot'} until ${DateFormat.jm().format(end.toLocal())}.'
                      : 'Opt in for one hour. Only people who also opt in at your hotspot can see your suggestion.'),
                  if (eligible && !active && hotspot != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(hotspot, style: theme.textTheme.titleMedium),
                    ),
                  if (session != null && !eligible)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Join a hotspot in Explore. Matchmaker is available to adults with a completed birthday on their profile.'),
                    ),
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
                  child: Text('No new suggestions at this hotspot yet. You can stay in discovery or join another hotspot in Explore.'),
                ),
              for (final raw in suggestions)
                if (raw is Map) Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SpotmateAvatar(
                          size: 52,
                          photoUrl: raw['profile_photo'] as String?,
                          avatarType: raw['avatar_type']?.toString() ?? 'photo',
                          emoticon: raw['avatar_emoticon']?.toString() ?? 'boy_01',
                        ),
                        title: Text(raw['name']?.toString() ?? 'SpotMate member'),
                        subtitle: const Text('Exploring the same hotspot'),
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
