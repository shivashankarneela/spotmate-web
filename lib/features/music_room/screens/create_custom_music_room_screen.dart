import 'package:flutter/material.dart';
import '../services/music_room_service.dart';
import 'music_room_live_screen.dart';

/// Screen 2 of the Music Room flow:
/// Create Custom Room — 30 mins (5 SC) or 1 hr (10 SC), optional initial Spotmate ID / User ID
/// invites, 5 empty circular dashed profile slots, and atomic SC debit on creation.
class CreateCustomMusicRoomScreen extends StatefulWidget {
  const CreateCustomMusicRoomScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;

  @override
  State<CreateCustomMusicRoomScreen> createState() => _CreateCustomMusicRoomScreenState();
}

class _CreateCustomMusicRoomScreenState extends State<CreateCustomMusicRoomScreen> {
  final _service = MusicRoomService();
  final _titleController = TextEditingController();

  int _durationMinutes = 60; // 30 (5 SC) or 60 (10 SC)
  bool _creating = false;

  int get _costSc => _durationMinutes == 60 ? 10 : 5;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }


  Future<void> _createRoom() async {
    setState(() => _creating = true);
    try {
      final room = await _service.createCustomRoom(
        title: _titleController.text.trim().isEmpty
            ? '${widget.currentDisplayName}\'s Music Room'
            : _titleController.text.trim(),
        durationMinutes: _durationMinutes,
        displayName: widget.currentDisplayName,
        avatarUrl: widget.currentAvatarUrl,
      );


      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MusicRoomLiveScreen(
            initialRoom: room,
            currentDisplayName: widget.currentDisplayName,
            currentAvatarUrl: widget.currentAvatarUrl,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        title: const Text(
          'Create Custom Room',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          // Duration & SC Pricing Toggle (30 mins • 5 SC | 1 hr • 10 SC)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PriceOption(
                    label: '30 mins • 5 SC',
                    selected: _durationMinutes == 30,
                    onTap: () => setState(() => _durationMinutes = 30),
                  ),
                ),
                Expanded(
                  child: _PriceOption(
                    label: '1 hr • 10 SC',
                    selected: _durationMinutes == 60,
                    onTap: () => setState(() => _durationMinutes = 60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Room Name',
              hintText: 'e.g. Hyderabad Late Night',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),


          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Room Seats',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
              ),
              Text(
                '1/5 Seats',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final isHost = i == 0;
              return Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF1F5F9),
                      border: Border.all(
                        color: isHost
                            ? const Color(0xFF059669)
                            : const Color(0xFFCBD5E1),
                        width: isHost ? 2 : 1.2,
                      ),
                    ),
                    child: Icon(
                      isHost ? Icons.person_outline_rounded : Icons.add_rounded,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isHost ? 'You' : 'Open',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(height: 14),
          const Text(
            'A shareable Room Code (SPOT-XXXX) is generated automatically once created.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creating ? null : _createRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(
                _creating ? 'CREATING...' : 'CREATE ROOM ($_costSc SC)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceOption extends StatelessWidget {
  const _PriceOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF059669) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
