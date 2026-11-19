import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-to-one WebRTC audio/video call. Supabase stores signaling only;
/// microphone and camera media is sent peer-to-peer when ICE connects.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.callId,
    required this.otherUserName,
    this.otherUserPhoto,
    required this.isVideo,
    required this.isCaller,
  });

  final String callId;
  final String otherUserName;
  final String? otherUserPhoto;
  final bool isVideo;
  final bool isCaller;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final _supabase = Supabase.instance.client;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  RealtimeChannel? _statusChannel;
  RealtimeChannel? _signalsChannel;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Timer? _durationTimer;
  Timer? _ringTimeout;
  Timer? _connectTimeout;
  Timer? _recoveryTimer;
  bool _restartTried = false;
  int _iceGeneration = 0;
  int _remoteGeneration = -1;
  bool _switchingCamera = false;
  bool _mirrorPreview = true;
  String? _cameraDeviceId;
  MediaStream? _alternateCameraStream;
  int _elapsed = 0;
  int _lastSignalId = 0;
  bool _signalingBusy = false;
  bool _signalSyncAgain = false;
  bool _mediaReady = false;
  bool _accepted = false;
  bool _offerSent = false;
  bool _remoteDescriptionReady = false;
  bool _connected = false;
  bool _closing = false;
  bool _isMuted = false;
  bool _cameraOn = true;
  bool _speakerOn = true;
  String _status = 'Preparing call...';

  @override
  void initState() {
    super.initState();
    _setup();
    if (widget.isCaller) {
      _ringTimeout = Timer(const Duration(seconds: 30), () {
        if (!_accepted && !_closing) _endCall(label: 'No answer', reason: 'missed');
      });
    }
  }

  Future<void> _setup() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    } catch (error) {
      if (mounted && !_closing) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to start camera/audio hardware: $error')));
        await _endCall(label: 'Call unavailable', reason: 'failed');
      }
      return;
    }
    if (!mounted || _closing) return;

    // Subscribe before negotiating so an answer cannot be missed.
    _statusChannel = _supabase
        .channel('spotmate-call-status-${widget.callId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.callId,
          ),
          callback: (payload) =>
              _handleCallStatus(payload.newRecord['status']?.toString()),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _refreshCallStatus();
          }
        });

    _signalsChannel = _supabase
        .channel('spotmate-call-signals-${widget.callId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: widget.callId,
          ),
          callback: (_) => _syncSignals(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _syncSignals();
          }
        });
    await _prepareMedia();
    await _refreshCallStatus();
  }

  Future<void> _prepareMedia() async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': widget.isVideo ? {'facingMode': 'user'} : false,
      });
      if (!mounted || _closing) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
        return;
      }
      _localStream = stream;
      _localRenderer.srcObject = stream;
      _peer = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      });

      _peer!.onIceCandidate = (candidate) {
        if (candidate.candidate == null || _closing) return;
        _sendSignal('candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'generation': _iceGeneration,
        });
      };
      _peer!.onTrack = (event) {
        if (_closing || !mounted || event.streams.isEmpty) return;
        _remoteRenderer.srcObject = event.streams.first;
        setState(() {});
      };
      _peer!.onIceConnectionState = (state) {
        if (!mounted || _closing) return;
        final text = state.toString().toLowerCase();
        if (text.contains('failed') || text.contains('disconnected')) {
          setState(() => _status = 'Reconnecting...');
          _scheduleRecovery();
        } else if (text.contains('connected') || text.contains('completed')) {
          _recoveryTimer?.cancel();
          _recoveryTimer = null;
          if (_connected) {
            setState(() => _status = 'Connected');
          } else {
            _markConnected();
          }
        }
      };
      for (final track in stream.getTracks()) {
        await _peer!.addTrack(track, stream);
      }
      _mediaReady = true;
      if (mounted) {
        setState(() => _status = widget.isCaller ? 'Ringing...' : 'Connecting...');
      }
      await _syncSignals();
      await _beginOfferIfReady();
    } catch (error) {
      if (mounted && !_closing) {
        setState(() => _status = 'Microphone/camera unavailable');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call permissions or media setup failed: $error')),
        );
        await _endCall(label: 'Call unavailable', reason: 'failed');
      }
    }
  }

  Future<void> _refreshCallStatus() async {
    if (_closing) return;
    try {
      final row = await _supabase.from('calls')
          .select('status')
          .eq('id', widget.callId)
          .maybeSingle();
      _handleCallStatus(row?['status']?.toString());
    } catch (_) {}
  }

  void _handleCallStatus(String? status) {
    if (!mounted || _closing) return;
    if (status == 'accepted') {
      if (!_accepted) {
        _connectTimeout = Timer(const Duration(seconds: 45), () {
          if (!_closing && !_connected) {
            _endCall(label: _remoteDescriptionReady
                ? 'Media connection timed out. Try another network.'
                : 'Could not complete call signaling. Please try again.',
                reason: 'failed');
          }
        });
      }
      _accepted = true;
      _ringTimeout?.cancel();
      if (!_connected) setState(() => _status = 'Connecting...');
      _beginOfferIfReady();
    } else if (status == 'ended' || status == 'declined') {
      _closeScreen(status == 'declined' ? 'Call declined' : 'Call ended');
    }
  }

  Future<void> _beginOfferIfReady() async {
    if (!_accepted || !_mediaReady || !widget.isCaller ||
        _offerSent || _closing || _peer == null) return;
    _offerSent = true;
    try {
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await _sendSignal('offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      if (mounted && !_closing) {
        setState(() => _status = 'Could not establish call');
      }
    }
  }

  void _scheduleRecovery() {
    if (_recoveryTimer != null) return;
    _recoveryTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || _closing) return;
      _recoveryTimer = Timer(const Duration(seconds: 18), () {
        if (!_closing) _endCall(label: 'Connection lost', reason: 'failed');
      });
      final peer = _peer;
      if (!widget.isCaller || _restartTried || !_remoteDescriptionReady || peer == null) return;
      _restartTried = true;
      _iceGeneration++;
      _remoteDescriptionReady = false;
      _pendingCandidates.clear();
      try {
        final offer = await peer.createOffer({'iceRestart': true});
        if (_closing) return;
        await peer.setLocalDescription(offer);
        await _sendSignal('offer', {
          'sdp': offer.sdp, 'type': offer.type, 'generation': _iceGeneration,
        });
      } catch (_) {
        // The timeout closes the call if the recovery offer fails.
      }
    });
  }

  Future<void> _sendSignal(String kind, Map<String, dynamic> payload) async {
    if (_closing) return;
    try {
      await _supabase.from('call_signals').insert({
        'call_id': widget.callId,
        'sender_id': _supabase.auth.currentUser!.id,
        'kind': kind,
        'payload': payload,
      });
    } catch (error) {
      if (mounted && !_closing) {
        setState(() => _status = 'Signaling interrupted');
      }
    }
  }

  // Fetch persisted signals on every subscription/reconnect; this also
  // covers the race between accepting a call and subscribing to its channel.
  Future<void> _syncSignals() async {
    if (_closing || !_mediaReady) return;
    if (_signalingBusy) {
      _signalSyncAgain = true;
      return;
    }
    _signalingBusy = true;
    try {
      do {
        _signalSyncAgain = false;
        final rows = await _supabase.from('call_signals')
            .select('id,sender_id,kind,payload')
            .eq('call_id', widget.callId)
            .gt('id', _lastSignalId)
            // Process oldest first: the offer must not be skipped when
            // candidates arrive in the same database result page.
            .order('id', ascending: true)
            .limit(200);
        for (final signal in rows) {
          if (_closing) return;
          final id = (signal['id'] as num).toInt();
          if (id <= _lastSignalId) continue;
          // Failed processing must be retried rather than skipped.
          await _processSignal(signal);
          _lastSignalId = id;
        }
        if (rows.length == 200) _signalSyncAgain = true;
      } while (_signalSyncAgain && !_closing);
    } catch (error) {
      if (mounted && !_closing) {
        setState(() => _status = 'Signaling interrupted');
      }
    } finally {
      _signalingBusy = false;
    }
  }

  Future<void> _processSignal(Map<String, dynamic> signal) async {
    if (signal['sender_id'] == _supabase.auth.currentUser?.id) return;
    final kind = signal['kind']?.toString();
    final payload = Map<String, dynamic>.from(signal['payload'] as Map);
    final peer = _peer;
    if (peer == null) return;

    final generation = (payload['generation'] as num?)?.toInt() ?? 0;
    if (kind == 'offer' && !widget.isCaller && generation > _remoteGeneration) {
      if (generation > _iceGeneration) {
        _iceGeneration = generation;
        _pendingCandidates.clear();
      }
      _remoteDescriptionReady = false;
      await peer.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, 'offer'));
      _remoteGeneration = generation;
      _remoteDescriptionReady = true;
      await _flushCandidates();
      final answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      await _sendSignal('answer', {
        'sdp': answer.sdp, 'type': answer.type, 'generation': generation,
      });
    } else if (kind == 'answer' && widget.isCaller &&
        !_remoteDescriptionReady && generation == _iceGeneration) {
      await peer.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, 'answer'));
      _remoteDescriptionReady = true;
      await _flushCandidates();
    } else if (kind == 'candidate') {
      if (generation < _iceGeneration) return;
      if (!widget.isCaller && generation > _iceGeneration) {
        _iceGeneration = generation;
        _remoteDescriptionReady = false;
        _pendingCandidates.clear();
      }
      if (generation != _iceGeneration) return;
      final candidate = RTCIceCandidate(
        payload['candidate']?.toString(),
        payload['sdpMid']?.toString(),
        (payload['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_remoteDescriptionReady) {
        await peer.addCandidate(candidate);
      } else {
        _pendingCandidates.add(candidate);
      }
    }
  }

  Future<void> _flushCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    for (final candidate in _pendingCandidates) {
      await peer.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  void _markConnected() {
    if (_connected || _closing || !mounted) return;
    _connected = true;
    _ringTimeout?.cancel();
    _connectTimeout?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _closing) return;
      setState(() => _elapsed++);
    });
    setState(() => _status = 'Connected');
  }

  void _toggleMute() {
    final muted = !_isMuted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    setState(() => _isMuted = muted);
  }

  void _toggleCamera() {
    final enabled = !_cameraOn;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
    setState(() => _cameraOn = enabled);
  }

  Future<void> _switchCamera() async {
    final peer = _peer;
    final stream = _localStream;
    final tracks = stream?.getVideoTracks();
    if (_switchingCamera || !_cameraOn || peer == null ||
        stream == null || tracks == null || tracks.isEmpty) return;
    setState(() => _switchingCamera = true);
    MediaStream? replacement;
    try {
      final oldTrack = tracks.first;
      final sender = (await peer.getSenders()).firstWhere(
        (item) => item.track?.id == oldTrack.id,
      );
      final cameras = (await navigator.mediaDevices.enumerateDevices())
          .where((device) => device.kind == 'videoinput' && device.deviceId.isNotEmpty)
          .toList();
      if (cameras.length < 2) throw StateError('No second camera');
      final activeId = _cameraDeviceId ?? oldTrack.getSettings()['deviceId'];
      final current = cameras.indexWhere((device) => device.deviceId == activeId);
      final next = cameras[(current < 0 ? 1 : current + 1) % cameras.length];
      replacement = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'deviceId': {'exact': next.deviceId}},
      });
      if (_closing || !mounted) return;
      final nextTrack = replacement.getVideoTracks().first;
      nextTrack.enabled = _cameraOn;
      await sender.replaceTrack(nextTrack);
      if (_closing || !mounted) return;
      await stream.removeTrack(oldTrack);
      await stream.addTrack(nextTrack);
      await oldTrack.stop();
      final oldCameraStream = _alternateCameraStream;
      _alternateCameraStream = replacement;
      replacement = null;
      await oldCameraStream?.dispose();
      _localRenderer.srcObject = null;
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {
        _cameraDeviceId = next.deviceId;
        _mirrorPreview = current >= 0 ? !_mirrorPreview : false;
      });
    } catch (_) {
      if (mounted && !_closing) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch cameras on this device.')),
      );
    } finally {
      if (replacement != null) {
        for (final track in replacement.getTracks()) {
          await track.stop();
        }
        await replacement.dispose();
      }
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _toggleSpeaker() async {
    final enabled = !_speakerOn;
    // Browser audio output routing is controlled by the browser/OS.
    try {
      await Helper.setSpeakerphoneOn(enabled);
      if (mounted) setState(() => _speakerOn = enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use your device audio output controls.')),
        );
      }
    }
  }

  Future<void> _endCall({String label = 'Call ended', String? reason}) async {
    if (_closing) return;
    _closing = true;
    _ringTimeout?.cancel();
    _connectTimeout?.cancel();
    final callId = widget.callId;
    final outcome = reason ?? (_connected ? 'completed' : 'cancelled');
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      unawaited(track.stop());
    }
    _closeScreen(label);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _supabase.from('calls')
            .update({'status': 'ended', 'end_reason': outcome})
            .eq('id', callId)
            .inFilter('status', ['ringing', 'accepted'])
            .timeout(const Duration(seconds: 6));
        return;
      } catch (_) {
        // Retry once without keeping the microphone, camera, or route open.
      }
    }
  }

  void _closeScreen(String label) {
    if (!mounted) return;
    _closing = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 2)));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closing = true;
    _durationTimer?.cancel();
    _recoveryTimer?.cancel();
    _ringTimeout?.cancel();
    _connectTimeout?.cancel();
    _statusChannel?.unsubscribe();
    _signalsChannel?.unsubscribe();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _peer?.close();
    _peer?.dispose();
    _localStream?.dispose();
    _alternateCameraStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration =
        '${(_elapsed ~/ 60).toString().padLeft(2, '0')}:${(_elapsed % 60).toString().padLeft(2, '0')}';
    final remoteVideo = widget.isVideo && _remoteRenderer.srcObject != null;
    final photo = widget.otherUserPhoto;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF13131F),
        body: SafeArea(
          child: Stack(children: [
            if (remoteVideo)
              Positioned.fill(
                child: RTCVideoView(_remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            // Keep the remote audio stream attached even on audio-only calls.
            if (!widget.isVideo && _remoteRenderer.srcObject != null)
              Positioned(
                left: 0, top: 0,
                child: SizedBox(width: 1, height: 1,
                  child: RTCVideoView(_remoteRenderer)),
              ),
            if (widget.isVideo && _localRenderer.srcObject != null)
              Positioned(
                right: 16, top: 95,
                child: SizedBox(width: 105, height: 155,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cameraOn
                        ? RTCVideoView(_localRenderer, mirror: _mirrorPreview)
                        : const ColoredBox(color: Colors.black),
                  )),
              ),
            Column(children: [
              const SizedBox(height: 24),
              Text(widget.isVideo ? 'Video call' : 'Audio call',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Text(widget.otherUserName,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(_connected && _status == 'Connected' ? duration : _status,
                  style: const TextStyle(color: Color(0xFFA9A3FF), fontSize: 16)),
              const Spacer(),
              if (!remoteVideo)
                CircleAvatar(
                  radius: 76,
                  backgroundColor: const Color(0xFF2B2B42),
                  backgroundImage: photo != null && photo.isNotEmpty
                      ? NetworkImage(photo) : null,
                  child: photo == null || photo.isEmpty
                      ? const Icon(Icons.person, size: 70, color: Colors.white70)
                      : null,
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28),
                color: const Color(0xFF1E1E2E),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _isMuted ? 'Unmute microphone' : 'Mute microphone',
                      onPressed: _toggleMute,
                      icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                    ),
                    if (widget.isVideo)
                      IconButton.filledTonal(
                        tooltip: 'Switch camera',
                        onPressed: !_cameraOn || !_mediaReady || _switchingCamera
                            ? null : _switchCamera,
                        icon: const Icon(Icons.cameraswitch),
                      ),
                    IconButton.filled(
                      tooltip: 'End call',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: _endCall,
                      icon: const Icon(Icons.call_end, size: 29),
                    ),
                    IconButton.filledTonal(
                      tooltip: widget.isVideo ? 'Toggle camera' : 'Toggle speaker',
                      onPressed: widget.isVideo
                          ? (_switchingCamera ? null : _toggleCamera) : _toggleSpeaker,
                      icon: Icon(widget.isVideo
                          ? (_cameraOn ? Icons.videocam : Icons.videocam_off)
                          : (_speakerOn ? Icons.volume_up : Icons.volume_off)),
                    ),
                  ],
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
