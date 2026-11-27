import 'package:flutter/material.dart';
import 'halo_illustrated_avatar.dart';

/// Name-only, minimal long-press posture picker.
/// Selection stays fixed until the user explicitly enables 30-second rotation.
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
      return pose.substring(3).split('_').map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 7),
            child: Text('Posture',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          // All five posture names, no avatar image, no large preview.
          Wrap(
            spacing: 5,
            runSpacing: 3,
            children: [
              for (var i = 0; i < names.length; i++)
                ChoiceChip(
                  label: Text(names[i], style: const TextStyle(fontSize: 11)),
                  selected: postureIndex == i,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  onSelected: (_) => onPoseChanged(i),
                ),
            ],
          ),
          SizedBox(
            height: 42,
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
              title: const Text('Auto-change every 30s',
                  style: TextStyle(fontSize: 12)),
              value: autoChange,
              onChanged: onAutoChange,
            ),
          ),
        ],
      ),
    );
  }
}
