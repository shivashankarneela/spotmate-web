import 'room_presence.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CityVisitGate extends StatefulWidget {
  const CityVisitGate({super.key, required this.room, required this.child});
  final String room;
  final Widget child;

  static void leaveRoom(BuildContext context) {
    context.findAncestorStateOfType<_CityVisitGateState>()?.leaveRoom();
  }

  @override
  State<CityVisitGate> createState() => _CityVisitGateState();
}

class _CityVisitGateState extends State<CityVisitGate>
    with WidgetsBindingObserver {
  DateTime? joined;
  Timer? _heartbeat;
  bool waiting = true;
  bool foreground = true;
  bool failed = false;
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    request('join', ensureMembership: false);
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
      if (joined != null) request('join', quiet: true);
    });
  }

  void request(
    String action, {
    bool quiet = false,
    bool ensureMembership = true,
  }) {
    if (!quiet && waiting && action == 'leave') return;
    _queue = _queue.then((_) async {
      if (!mounted || (quiet && (!foreground || joined == null))) return;
      await _request(action, quiet: quiet, ensureMembership: ensureMembership);
    });
  }

  Future<void> _request(
    String action, {
    required bool quiet,
    required bool ensureMembership,
  }) async {
    if (!quiet) setState(() => waiting = true);
    try {
      if (action == 'join' && !quiet && ensureMembership) {
        await Supabase.instance.client.rpc(
          'join_hotspot_room',
          params: {'p_hotspot_id': widget.room},
        );
      }
      if (!mounted) return;
      final result = await Supabase.instance.client.rpc(
        'city_visit',
        params: {'p_room': widget.room, 'p_action': action},
      );
      if (action == 'leave') RoomPresence.leave(widget.room);
      if (!mounted) return;
      final visitStart = result == null
          ? null
          : DateTime.parse(result['joined'] as String);
      if (visitStart != joined || failed) {
        setState(() {
          joined = visitStart;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && !quiet) setState(() => failed = true);
    } finally {
      if (mounted && !quiet) setState(() => waiting = false);
    }
  }

  void leaveRoom() => request('leave');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !foreground) {
      foreground = true;
      if (joined != null) request('join', quiet: true);
      _startHeartbeat();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      foreground = false;
      _heartbeat?.cancel();
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (waiting && joined == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (joined == null)
      return Scaffold(
        backgroundColor: const Color(0xFFFAF8F3),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDF3EB),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 38,
                        color: Color(0xFF147D72),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      failed
                          ? 'Unable to open the room'
                          : 'Ready to join the conversation?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF202B30),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      failed
                          ? 'Check your connection and try again.'
                          : 'Rejoin to catch up with everyone.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF147D72),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: () => request('join'),
                        icon: const Icon(Icons.login_rounded),
                        label: Text(failed ? 'Try again' : 'Rejoin room'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: waiting || failed,
          child: ExcludeFocus(
            excluding: waiting || failed,
            child: KeyedSubtree(key: ValueKey(joined), child: widget.child),
          ),
        ),
        if (failed && !waiting)
          Material(
            child: Center(
              child: TextButton(
                onPressed: () => request('join'),
                child: const Text('Retry city room'),
              ),
            ),
          ),
        if (waiting)
          const Material(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}
