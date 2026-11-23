// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../models/live_tv_models.dart';

class LiveTvPlayer extends StatefulWidget {
  const LiveTvPlayer({super.key, required this.channel, this.commands});
  final LiveTvChannel channel;
  final ValueNotifier<String?>? commands;
  @override
  State<LiveTvPlayer> createState() => _LiveTvPlayerState();
}

class _LiveTvPlayerState extends State<LiveTvPlayer> {
  late String _viewType;
  html.IFrameElement? _frame;
  html.VideoElement? _video;
  bool _playing = true;
  bool _muted = true;

  @override
  void initState() { super.initState(); widget.commands?.addListener(_externalCommand); _register(); }

  void _externalCommand() {
    final command = widget.commands?.value;
    if (command == 'mute' && !_muted || command == 'unmute' && _muted) _toggleMuted();
    if (command == 'pause' && _playing || command == 'play' && !_playing) _togglePlaying();
  }

  @override
  void dispose() { widget.commands?.removeListener(_externalCommand); super.dispose(); }

  @override
  void didUpdateWidget(covariant LiveTvPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commands != widget.commands) {
      oldWidget.commands?.removeListener(_externalCommand);
      widget.commands?.addListener(_externalCommand);
    }
    if (oldWidget.channel.streamType != widget.channel.streamType ||
        oldWidget.channel.streamSource != widget.channel.streamSource) {
      _frame = null;
      _video = null;
      _playing = true;
      _register();
    }
  }

  void _command(String action) {
    _frame?.contentWindow?.postMessage(jsonEncode({
      'event': 'command', 'func': action, 'args': <dynamic>[],
    }), 'https://www.youtube.com');
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    if (_video != null) {
      if (_playing) { _video!.play(); } else { _video!.pause(); }
    } else {
      _command(_playing ? 'playVideo' : 'pauseVideo');
    }
  }

  void _toggleMuted() {
    setState(() => _muted = !_muted);
    if (_video != null) { _video!.muted = _muted; }
    else { _command(_muted ? 'mute' : 'unMute'); }
  }

  void _register() {
    final channel = widget.channel;
    _viewType = 'spotmate-livetv-${channel.id}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      if (channel.streamType == 'hls') {
        final video = html.VideoElement()
          ..src = channel.streamSource
          ..autoplay = true
          ..muted = _muted
          ..style.width = '100%'
          ..style.height = '100%'
            ..style.backgroundColor = '#0F172A';
        video.setAttribute('playsinline', 'true');
        _video = video;
        return video;
      }
      final path = channel.streamType == 'youtube_channel' ? '/embed/live_stream' : '/embed/${channel.streamSource}';
      final params = <String, String>{
        if (channel.streamType == 'youtube_channel') 'channel': channel.streamSource,
        'autoplay': '1', 'mute': _muted ? '1' : '0', 'playsinline': '1',
        'controls': '1', 'enablejsapi': '1', 'origin': html.window.location.origin,
      };
      final iframe = html.IFrameElement()
        ..src = Uri.https('www.youtube.com', path, params).toString()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      iframe.setAttribute('allow', 'autoplay; encrypted-media; fullscreen');
      iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      _frame = iframe;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    LayoutBuilder(builder: (context, constraints) => SizedBox(
      width: double.infinity,
      height: (constraints.maxWidth * 9 / 16).clamp(200.0, double.infinity),
      child: ColoredBox(color: const Color(0xFF0F172A), child: HtmlElementView(
        key: ValueKey(_viewType), viewType: _viewType)),
    )),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TextButton.icon(onPressed: _togglePlaying,
        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        label: Text(_playing ? 'Pause' : 'Play')),
      TextButton.icon(onPressed: _toggleMuted,
        icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
        label: Text(_muted ? 'Unmute' : 'Mute')),
    ]),
  ]);
}
