import 'package:flutter/material.dart';
import 'halo_illustrated_avatar.dart';

/// A deliberately simple, accessible control: the selected pose stays still
/// until the user picks a different one or explicitly enables rotation.
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
    final names = character.poses
        .map((pose) => pose.substring(3).replaceAll('_', ' '))
        .map((text) => text.split(' ').map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '))
        .toList();
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your signature posture',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Choose a pose for ${character.name}. It stays still unless you turn on automatic changes.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Center(child: HaloIllustratedAvatar(
          avatarId: avatarId, size: 216, fullPortrait: true,
          postureIndex: postureIndex, autoChangePosture: autoChange,
          fallback: const Icon(Icons.person_outline, size: 80),
        )),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < names.length; i++)
            ChoiceChip(
              selected: postureIndex == i,
              label: Text(names[i]),
              onSelected: (_) => onPoseChanged(i),
            ),
        ]),
        const Divider(height: 26),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Change postures automatically'),
          subtitle: const Text('Switch to the next posture every 30 seconds'),
          value: autoChange,
          onChanged: onAutoChange,
          secondary: const Icon(Icons.autorenew_rounded),
        ),
      ]),
    );
  }
}
