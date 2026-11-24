import 'package:flutter/foundation.dart';

enum SpotmateKeyboardTab { emoji, gifs, stickers, quick }

@immutable
class SpotmateSticker {
  const SpotmateSticker({
    required this.id,
    required this.packId,
    required this.label,
    required this.badgeEmoji,
    required this.accentHex,
    required this.subTag,
    this.isMemeDialogue = true,
    this.assetPath,
    this.imageUrl,
  });

  final String id;
  final String packId; // 'telugu_memes' | 'hindi_memes' | 'tamil_memes' | 'avatars'
  final String label;
  final String badgeEmoji;
  final int accentHex;
  final String subTag;
  final bool isMemeDialogue;
  final String? assetPath;
  final String? imageUrl;

  Map<String, dynamic> toPayload() => {
        'type': 'spotmate_sticker',
        'sticker_id': id,
        'pack_id': packId,
        'label': label,
        'emoji': badgeEmoji,
        'accent_hex': accentHex,
        'sub_tag': subTag,
        'is_meme_dialogue': isMemeDialogue,
        if (assetPath != null) 'asset_path': assetPath,
        if (imageUrl != null) 'image_url': imageUrl,
      };

  static SpotmateSticker? tryParse(Map<String, dynamic>? json) {
    if (json == null || json['type'] != 'spotmate_sticker') return null;
    return SpotmateSticker(
      id: (json['sticker_id'] ?? '').toString(),
      packId: (json['pack_id'] ?? 'telugu_memes').toString(),
      label: (json['label'] ?? 'Sticker').toString(),
      badgeEmoji: (json['emoji'] ?? '🔥').toString(),
      accentHex: (json['accent_hex'] as num?)?.toInt() ?? 0xFFF59E0B,
      subTag: (json['sub_tag'] ?? 'MEME').toString(),
      isMemeDialogue: json['is_meme_dialogue'] != false,
      assetPath: json['asset_path']?.toString(),
      imageUrl: json['image_url']?.toString(),
    );
  }
}

@immutable
class SpotmateGifItem {
  const SpotmateGifItem({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.gifUrl,
    this.width = 240,
    this.height = 180,
  });

  final String id;
  final String title;
  final String previewUrl;
  final String gifUrl;
  final int width;
  final int height;

  Map<String, dynamic> toPayload() => {
        'type': 'spotmate_gif',
        'gif_id': id,
        'title': title,
        'preview_url': previewUrl,
        'gif_url': gifUrl,
        'width': width,
        'height': height,
      };

  static SpotmateGifItem? tryParse(Map<String, dynamic>? json) {
    if (json == null || json['type'] != 'spotmate_gif') return null;
    final url = (json['gif_url'] ?? '').toString();
    if (url.isEmpty) return null;
    return SpotmateGifItem(
      id: (json['gif_id'] ?? '').toString(),
      title: (json['title'] ?? 'GIF').toString(),
      previewUrl: (json['preview_url'] ?? url).toString(),
      gifUrl: url,
      width: (json['width'] as num?)?.toInt() ?? 240,
      height: (json['height'] as num?)?.toInt() ?? 180,
    );
  }
}
