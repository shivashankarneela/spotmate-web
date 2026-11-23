// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as web;
import 'package:flutter/material.dart';

Widget musicVideo(String id, int seconds, bool playing) =>
    _Video(key: ValueKey(id), id: id, seconds: seconds, playing: playing);

class _Video extends StatefulWidget {
  const _Video({super.key, required this.id, required this.seconds, required this.playing});
  final String id;
  final int seconds;
  final bool playing;
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  static const view = 'city-music-youtube';
  static bool registered = false;
  html.IFrameElement? frame;
  StreamSubscription<html.Event>? _loadSubscription;
  Timer? _readyTimer;

  @override
  void initState() {
    super.initState();
    if (!registered) {
      web.platformViewRegistry.registerViewFactory(view, (int id) => html.IFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'autoplay; encrypted-media; fullscreen')
        ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin'));
      registered = true;
    }
  }

  void _command(String function) {
    frame?.contentWindow?.postMessage(jsonEncode({
      'event': 'command', 'func': function, 'args': <dynamic>[],
    }), 'https://www.youtube.com');
  }

  void _applyPlayback() => _command(widget.playing ? 'playVideo' : 'pauseVideo');

  void _loadPlayer() {
    final current = frame;
    if (current == null) return;
    _loadSubscription?.cancel();
    _loadSubscription = current.onLoad.listen((_) {
      _readyTimer?.cancel();
      _readyTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && identical(frame, current)) _applyPlayback();
      });
    });
    current.src = Uri.https('www.youtube.com', '/embed/${widget.id}', {
      'autoplay': widget.playing ? '1' : '0',
      'mute': '1',
      'start': widget.seconds.toString(),
      'playsinline': '1',
      'controls': '1',
      'enablejsapi': '1',
      'origin': html.window.location.origin,
    }).toString();
  }

  @override
  void didUpdateWidget(covariant _Video oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _loadPlayer();
    } else if (oldWidget.playing != widget.playing) {
      _applyPlayback();
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _loadSubscription?.cancel();
    frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
    viewType: view,
    onPlatformViewCreated: (id) {
      frame = web.platformViewRegistry.getViewById(id) as html.IFrameElement;
      _loadPlayer();
    },
  );
}
