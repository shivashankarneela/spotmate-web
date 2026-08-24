import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActiveCallScreen extends StatefulWidget {
  final String callId;
  final String otherUserName;
  final String? otherUserPhoto;
  final bool isVideo;
  final bool isCaller;

  const ActiveCallScreen({
    super.key,
    required this.callId,
    required this.otherUserName,
    this.otherUserPhoto,
    required this.isVideo,
    required this.isCaller,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  int _seconds = 0;
  Timer? _timer;
  Timer? _ringingTimeoutTimer;
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _isCameraOn = true;
  RealtimeChannel? _callChannel;
  String _status = 'Connecting...';
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _status = widget.isCaller ? 'Ringing...' : 'Connected (Live Stream)';
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    if (widget.isCaller) {
      // Auto cancel after 30s if no answer
      _ringingTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_timer == null) {
          _endCall(statusMessage: 'No Answer');
        }
      });
    } else {
      _startTimer();
    }

    _subscribeToCallStatus();
  }

  void _startTimer() {
    _ringingTimeoutTimer?.cancel();
    setState(() => _status = '00:00');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _seconds++;
          final m = (_seconds ~/ 60).toString().padLeft(2, '0');
          final s = (_seconds % 60).toString().padLeft(2, '0');
          _status = '$m:$s';
        });
      }
    });
  }

  void _subscribeToCallStatus() {
    _callChannel = _supabase
        .channel('public:calls:${widget.callId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.callId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'];
            if (newStatus == 'accepted' && _timer == null) {
              _startTimer();
            } else if (newStatus == 'ended' || newStatus == 'declined') {
              _closeCallScreen(newStatus == 'declined' ? 'Call Declined' : 'Call Ended');
            }
          },
        )
        .subscribe();
  }

  Future<void> _endCall({String statusMessage = 'Call Ended'}) async {
    _ringingTimeoutTimer?.cancel();
    try {
      await _supabase.from('calls').update({'status': 'ended'}).eq('id', widget.callId);
    } catch (_) {}
    _closeCallScreen(statusMessage);
  }

  void _closeCallScreen(String message) {
    _timer?.cancel();
    _ringingTimeoutTimer?.cancel();
    _waveController.dispose();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringingTimeoutTimer?.cancel();
    _waveController.dispose();
    _callChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.otherUserPhoto;

    return Scaffold(
      backgroundColor: const Color(0xFF13131F),
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.isVideo && _isCameraOn)
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade900, const Color(0xFF1E1E30)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_rounded, size: 80, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      const Text(
                        'Live Video Stream Connected',
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            Column(
              children: [
                const SizedBox(height: 24),
                Text(
                  widget.isVideo ? '📹 SPOTMATE Video Call' : '📞 SPOTMATE Audio Call',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.otherUserName,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _status,
                    style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),

                Center(
                  child: AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 150 + (_waveController.value * 35),
                            height: 150 + (_waveController.value * 35),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6C63FF).withOpacity(0.25 - (_waveController.value * 0.2)),
                            ),
                          ),
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF6C63FF), width: 3),
                            ),
                          ),
                          CircleAvatar(
                            radius: 64,
                            backgroundColor: Colors.grey[800],
                            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo == null ? const Icon(Icons.person, size: 64, color: Colors.white70) : null,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isMuted ? Icons.mic_off : Icons.graphic_eq, color: _isMuted ? Colors.red : Colors.greenAccent, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      _isMuted ? 'Muted' : 'Audio Stream Active (Voice Connected)',
                      style: TextStyle(color: _isMuted ? Colors.red : Colors.greenAccent, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _isMuted ? Colors.white : Colors.grey[800],
                        child: IconButton(
                          icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.black : Colors.white),
                          onPressed: () => setState(() => _isMuted = !_isMuted),
                        ),
                      ),
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.red,
                        child: IconButton(
                          icon: const Icon(Icons.call_end, color: Colors.white, size: 30),
                          onPressed: () => _endCall(),
                        ),
                      ),
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _isSpeaker ? const Color(0xFF6C63FF) : Colors.grey[800],
                        child: IconButton(
                          icon: Icon(
                            widget.isVideo ? (_isCameraOn ? Icons.videocam : Icons.videocam_off) : (_isSpeaker ? Icons.volume_up : Icons.volume_down),
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              if (widget.isVideo) {
                                _isCameraOn = !_isCameraOn;
                              } else {
                                _isSpeaker = !_isSpeaker;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

