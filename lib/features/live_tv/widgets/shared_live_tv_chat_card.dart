import 'package:flutter/material.dart';
import '../models/live_tv_models.dart';

/// Compact Live TV invite card rendered inside 1-on-1 private chat.
/// Tapping opens `LiveTvPlayerScreen` directly on that channel.
class SharedLiveTvChatCard extends StatelessWidget {
  const SharedLiveTvChatCard({
    super.key,
    required this.payload,
    required this.onOpenChannel,
  });

  final SharedLiveTvPayload payload;
  final void Function(LiveTvChannel channel) onOpenChannel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpenChannel(payload.toChannel()),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'LIVE TV',
                    style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${payload.category} • ${payload.language}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              payload.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Watch Together Live',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
