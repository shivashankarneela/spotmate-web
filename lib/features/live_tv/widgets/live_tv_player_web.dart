import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../models/live_tv_models.dart';

/// 16:9 Live TV Player for Flutter Web supporting:
/// - `youtube_live` (YouTube Live video ID)
/// - `youtube_channel` (YouTube live_stream?channel=UC...)
/// - `hls` (native Safari HLS or browser <video> stream URL)
class LiveTvPlayer extends StatefulWidget {
  const LiveTvPlayer({super.key, required this.channel});

  final LiveTvChannel channel;

  @override
  State<LiveTvPlayer> createState() => _LiveTvPlayerState();
}

class _LiveTvPlayerState extends State<LiveTvPlayer> {
  late String _viewType;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant LiveTvPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id ||
        oldWidget.channel.streamSource != widget.channel.streamSource) {
      _register();
    }
  }

  void _register() {
    final c = widget.channel;
    _viewType = 'spotmate-livetv-${c.id}-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      if (c.streamType == 'hls') {
        final video = web.HTMLVideoElement()
          ..src = c.streamSource
          ..controls = true
          ..autoplay = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = '#0F172A';
        video.setAttribute('playsinline', 'true');
        return video;
      }

      final embedUrl = c.streamType == 'youtube_channel'
          ? 'https://www.youtube.com/embed/live_stream?channel=${c.streamSource}&autoplay=1&rel=0&modestbranding=1'
          : 'https://www.youtube.com/embed/${c.streamSource}?autoplay=1&rel=0&modestbranding=1';

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
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: const Color(0xFF0F172A),
        child: HtmlElementView(
          key: ValueKey(_viewType),
          viewType: _viewType,
        ),
      ),
    );
  }
}
