import 'package:flutter/material.dart';

class SpotmateAvatar extends StatelessWidget {
  const SpotmateAvatar({
    super.key, this.size = 48, this.photoUrl, this.avatarType = 'photo',
    this.emoticon = 'smile',
  });
  final double size;
  final String? photoUrl;
  final String avatarType;
  final String emoticon;
  static const symbols = <String,String>{
    'smile':'🙂', 'cool':'😎', 'star':'🤩', 'heart':'🥰',
    'laugh':'😄', 'wave':'👋', 'spark':'✨', 'flower':'🌸',
  };
  @override
  Widget build(BuildContext context) {
    final showPhoto = avatarType == 'photo' && photoUrl != null && photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFE0F7F0),
      backgroundImage: showPhoto ? NetworkImage(photoUrl!) : null,
      child: showPhoto ? null : Text(
        symbols[emoticon] ?? symbols['smile']!,
        style: TextStyle(fontSize: size * .52),
      ),
    );
  }
}

class SpotmateAvatarPicker extends StatelessWidget {
  const SpotmateAvatarPicker({super.key, required this.avatarType,
    required this.emoticon, required this.onChoice, required this.onPickPhoto});
  final String avatarType;
  final String emoticon;
  final void Function(String type,String emoticon) onChoice;
  final VoidCallback onPickPhoto;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      const Text('Choose how you appear', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children:[
        ChoiceChip(
          label: const Text('Profile photo'),
          selected: avatarType == 'photo',
          onSelected: (_) => onChoice('photo', emoticon),
        ),
        ChoiceChip(
          label: const Text('Emoticon'),
          selected: avatarType == 'emoticon',
          onSelected: (_) => onChoice('emoticon', emoticon),
        ),
      ]),
      if (avatarType == 'photo') TextButton.icon(
        onPressed: onPickPhoto, icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Choose photo'),
      ) else
        Wrap(spacing: 8, runSpacing: 8, children:
          SpotmateAvatar.symbols.entries.map((entry) =>
            InkWell(
              onTap: () => onChoice('emoticon',entry.key),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 48,height:48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: emoticon == entry.key ? const Color(0xFFDCF8F0) : Colors.white,
                  border: Border.all(color: emoticon == entry.key
                      ? const Color(0xFF162544) : const Color(0xFFE1E5EA)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(entry.value, style: const TextStyle(fontSize: 26)),
              ),
            )).toList(),
        ),
    ]);
  }
}
