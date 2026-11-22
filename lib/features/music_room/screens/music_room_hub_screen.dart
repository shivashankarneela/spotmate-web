import 'package:flutter/material.dart';
import '../models/music_room_models.dart';
import '../services/music_room_service.dart';
import 'create_custom_music_room_screen.dart';
import 'music_room_live_screen.dart';

/// Screen 1 of the Music Room flow:
/// Segmented Free (30m) | Custom tabs, live Available Free Rooms list (5-seat cap + countdown),
/// Next-Batch waitlist when full, Join by Room Code, and + CREATE CUSTOM ROOM CTA.
class MusicRoomHubScreen extends StatefulWidget {
  const MusicRoomHubScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<MusicRoomHubScreen> createState() => _MusicRoomHubScreenState();
}

class _MusicRoomHubScreenState extends State<MusicRoomHubScreen> {
  final _service = MusicRoomService();
  final _codeController = TextEditingController();

  bool _showCustomTab = false;
  bool _loading = true;
  List<MusicRoom> _freeRooms = [];

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rooms = await _service.listFreeRooms();
      if (mounted) {
        setState(() {
          _freeRooms = rooms;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _toast(e.toString());
      }
    }
  }

  Future<void> _joinRoom(MusicRoom room) async {
    try {
      final joined = await _service.joinRoom(
        roomId: room.id,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );
      if (!mounted) return;
      _openLiveRoom(joined);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _joinByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    try {
      final room = await _service.joinByCode(
        roomCode: code,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );
      if (!mounted) return;
      _openLiveRoom(room);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _startNewFreeRoom() async {
    try {
      final room = await _service.createFreeRoom(
        title: '${widget.currentDisplayName}\'s Free Lounge',
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );
      if (!mounted) return;
      _openLiveRoom(room);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _joinNextBatch() async {
    try {
      await _service.joinNextBatchWaitlist(
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );
      _toast('Added to Next Batch! You will auto-join when the next 5-seat Free room opens.');
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _openLiveRoom(MusicRoom room) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => MusicRoomLiveScreen(
              initialRoom: room,
              currentDisplayName: widget.currentDisplayName,
              currentAvatarUrl: widget.currentAvatarUrl,
            ),
          ),
        )
        .then((_) => _loadRooms());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        title: const Text(
          'Music Room',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _loadRooms,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => CreateCustomMusicRoomScreen(
                          currentDisplayName: widget.currentDisplayName,
                          currentAvatarUrl: widget.currentAvatarUrl,
                        ),
                      ),
                    )
                    .then((_) => _loadRooms());
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Create room', style: TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
          const SizedBox(height:12),
          // Free (30m) | Custom Segmented Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabPill(
                    label: 'Free (30m)',
                    selected: !_showCustomTab,
                    onTap: () => setState(() => _showCustomTab = false),
                  ),
                ),
                Expanded(
                  child: _TabPill(
                    label: 'Custom',
                    selected: _showCustomTab,
                    onTap: () => setState(() => _showCustomTab = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (!_showCustomTab) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Free rooms',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                ),
                TextButton.icon(
                  onPressed: _startNewFreeRoom,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Start Free'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF0D9488))),
              )
            else if (_freeRooms.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'No active Free rooms right now.',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Start a fresh 30-minute Free room for up to 5 random listeners.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _startNewFreeRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start 30m Free Room'),
                    ),
                  ],
                ),
              )
            else
              ..._freeRooms.map((room) {
                final minsLeft = room.expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 30);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.headphones)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.title,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${room.memberCount}/5 Seats • ${minsLeft}m left',
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      if (room.isFull)
                        OutlinedButton(
                          onPressed: _joinNextBatch,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: const Text('Next Batch'),
                        )
                      else
                        ElevatedButton(
                          onPressed: () => _joinRoom(room),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                );
              }),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private Custom Rooms (Max 5 Members)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• 30 mins — 5 SC\n• 1 hour — 10 SC\n• Share the room code to invite friends\n• Everyone can use !play and playback controls',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.5),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Text(
            'Join by Room Code',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Enter Code (e.g. SPOT-84K2)',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _joinByCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),


        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: selected ? const Color(0xFF0F172A) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
