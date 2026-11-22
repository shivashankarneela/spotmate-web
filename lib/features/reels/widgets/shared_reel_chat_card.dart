import 'package:flutter/material.dart';
import '../models/reel_models.dart';

/// Render this card inside Spotmate's 1-on-1 private chat whenever a message contains a `SharedReelPayload`.
/// Tapping the card calls `onOpenReel(payload.reelId)` to navigate directly to `ReelsFeedScreen(initialReelId: ...)`.
class SharedReelChatCard extends StatelessWidget {
  const SharedReelChatCard({
    super.key,
    required this.payload,
    required this.onOpenReel,
  });

  final SharedReelPayload payload;
  final void Function(String reelId) onOpenReel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpenReel(payload.reelId),
      child: Container(
        width: 224,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 9 / 14,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    payload.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0F172A)),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xAA0F172A)],
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xCC0F172A),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Tap to open in Reels',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payload.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${payload.creatorHandle} • ${payload.cityTag}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  if (payload.note != null && payload.note!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      payload.note!,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
