import 'package:flutter/material.dart';
import '../models/music_room_models.dart';

/// Visible 16:9 Video + Audio Player Card for Spotmate Music Room.
/// - Compliant with YouTube's visible-viewport requirement (>= 200x200 px, 16:9).
/// - Displays a one-tap "Tap to Tune In" overlay to unlock browser autoplay cleanly.
/// - Supports Compact vs Expanded video height toggle, plus Audio Equalizer view for HLS streams.
///
/// NOTE: On Flutter Web, pair this widget with `youtube_player_iframe` (or `HtmlElementView`
/// embedding `https://www.youtube.com/embed/<videoId>?autoplay=1&start=<sec>&enablejsapi=1`
/// with `referrerpolicy="strict-origin-when-cross-origin"`).
class SyncedMediaPlayerCard extends StatefulWidget {
  const SyncedMediaPlayerCard({
    super.key,
    required this.room,
    required this.clockSkewMs,
    this.youtubeWidgetBuilder,
  });

  final MusicRoom room;
  final int clockSkewMs;

  /// Optional builder to mount `YoutubePlayer` from `youtube_player_iframe` directly inside
  /// the 16:9 viewport once the listener taps "Tune In".
  final Widget Function(String videoId, int startSeconds, bool isPlaying)? youtubeWidgetBuilder;

  @override
  State<SyncedMediaPlayerCard> createState() => _SyncedMediaPlayerCardState();
}

class _SyncedMediaPlayerCardState extends State<SyncedMediaPlayerCard> {
  bool _tunedIn = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasTrack = widget.room.currentSourceRef != null && widget.room.currentSourceRef!.isNotEmpty;
    final isYouTube = widget.room.currentSourceType == 'youtube';
    final startSec = widget.room.expectedPlaybackSeconds(widget.clockSkewMs).floor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _expanded ? 16 / 10 : 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!hasTrack)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.headphones_rounded, size: 42, color: Color(0xFF2DD4BF)),
                        SizedBox(height: 8),
                        Text(
                          'Waiting for Host to type !play <song>',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isYouTube && _tunedIn && widget.youtubeWidgetBuilder != null)
                  widget.youtubeWidgetBuilder!(
                    widget.room.currentSourceRef!,
                    startSec,
                    widget.room.isPlaying,
                  )
                else
                  // Visual fallback / Audio Equalizer / YouTube Thumbnail preview
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F172A), Color(0xFF134E4A)],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isYouTube ? Icons.ondemand_video_rounded : Icons.graphic_eq_rounded,
                          size: 46,
                          color: const Color(0xFF2DD4BF),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.room.currentTitle ?? 'Now Playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isYouTube ? "YouTube Video" : "Audio Stream"} • '
                          '${widget.room.isPlaying ? "Synced @ ${_fmtSec(startSec)}" : "Paused"}',
                          style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                // One-tap Autoplay Unlock Overlay (required by Chrome/Safari on Flutter Web)
                if (hasTrack && !_tunedIn)
                  Container(
                    color: Colors.black.withOpacity(0.46),
                    alignment: Alignment.center,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _tunedIn = true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        'Tap to Tune In (Synced)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  ),

                // Top-Right Expand / Compact Video Toggle
                if (hasTrack && isYouTube)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _expanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _expanded ? 'Compact' : 'Expand',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtSec(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }
}
