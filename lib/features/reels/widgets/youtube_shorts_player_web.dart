import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  @override
  void didUpdateWidget(covariant YouTubeShortsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.isMuted != widget.isMuted ||
        oldWidget.isActive != widget.isActive) {
      _registerView();
    }
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
      final iframe = web.HTMLIFrameElement()
        ..src = embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture'
        ..allowFullscreen = true;
      iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
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
