import 'package:flutter/material.dart';
import 'halo_illustrated_avatar.dart';

/// Compact avatar long-press panel. Poses remain stationary unless the user
/// explicitly enables the optional 30-second cycle.
class HaloPostureSelector extends StatelessWidget {
  const HaloPostureSelector({
    super.key, required this.avatarId, required this.postureIndex,
    required this.autoChange, required this.onPoseChanged,
    required this.onAutoChange,
  });

  final String avatarId;
  final int postureIndex;
  final bool autoChange;
  final ValueChanged<int> onPoseChanged;
  final ValueChanged<bool> onAutoChange;

  @override
  Widget build(BuildContext context) {
    final character = HaloAvatarCatalog.characters[avatarId] ??
        HaloAvatarCatalog.characters['boy_01']!;
    final names = character.poses.map((pose) {
      final words = pose.substring(3).split('_');
      return words.map((word) => word.isEmpty
          ? word : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
    }).toList();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            HaloIllustratedAvatar(
              avatarId: avatarId, size: 90, fullPortrait: true,
              postureIndex: postureIndex, autoChangePosture: false,
              fallback: const Icon(Icons.person_outline, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Posture', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(names[postureIndex.clamp(0, names.length - 1)],
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
          ]),
          const SizedBox(height: 8),
          // All five poses must be visible without sideways scrolling.
          // Keep each choice compact so the long-press sheet stays short.
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              for (var index = 0; index < names.length; index++)
                ChoiceChip(
                  label: Text('${index + 1}. ${names[index]}',
                      style: const TextStyle(fontSize: 11)),
                  selected: postureIndex == index,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  onSelected: (_) => onPoseChanged(index),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: const Text('Auto-change · 30s'),
            subtitle: const Text('Off = stay in selected pose'),
            value: autoChange,
            onChanged: onAutoChange,
          ),
        ]),
    );
  }
}
