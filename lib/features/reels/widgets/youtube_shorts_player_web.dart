// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Vertical 9:16 YouTube Shorts player for Flutter Web.
/// Mounts an IFrame only when `isActive == true` so swiping in PageView never leaks audio.
class YouTubeShortsPlayer extends StatefulWidget {
  const YouTubeShortsPlayer({
    super.key,
    required this.youtubeVideoId,
    required this.thumbnailUrl,
    required this.isActive,
    required this.isMuted,
  });

  final String youtubeVideoId;
  final String thumbnailUrl;
  final bool isActive;
  final bool isMuted;

  @override
  State<YouTubeShortsPlayer> createState() => _YouTubeShortsPlayerState();
}

class _YouTubeShortsPlayerState extends State<YouTubeShortsPlayer> {
  late String _viewType;
  html.IFrameElement? _frame;

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  @override
  void didUpdateWidget(covariant YouTubeShortsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.isActive != widget.isActive) {
      _frame = null;
      _registerView();
    } else if (oldWidget.isMuted != widget.isMuted) {
      _applyMute();
    }
  }

  void _applyMute() {
    _frame?.contentWindow?.postMessage(jsonEncode({
      'event': 'command',
      'func': widget.isMuted ? 'mute' : 'unMute',
      'args': [],
    }), 'https://www.youtube.com');
  }

  void _registerView() {
    if (!widget.isActive) return;
    final muteFlag = widget.isMuted ? 1 : 0;
    _viewType = 'spotmate-yt-short-${widget.youtubeVideoId}-$muteFlag-${DateTime.now().microsecondsSinceEpoch}';
    final embedUrl =
        'https://www.youtube.com/embed/${widget.youtubeVideoId}'
        '?autoplay=1&mute=$muteFlag&loop=1&playlist=${widget.youtubeVideoId}'
        '&controls=0&playsinline=1&rel=0&modestbranding=1&enablejsapi=1';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none';
      iframe.setAttribute('allow', 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture');
      iframe.setAttribute('allowfullscreen', '');
      iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      _frame = iframe;
      iframe.onLoad.listen((_) {
        if (mounted && identical(_frame, iframe)) _applyMute();
      });
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            widget.thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0F172A)),
          ),
          const Center(
            child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 56),
          ),
        ],
      );
    }

    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: HtmlElementView(
        key: ValueKey(_viewType),
        viewType: _viewType,
      ),
    );
  }
}
