import 'package:flutter/foundation.dart';

@immutable
class SpotmateReel {
  const SpotmateReel({
    required this.id,
    required this.youtubeVideoId,
    required this.title,
    required this.creatorHandle,
    required this.cityTag,
    required this.thumbnailUrl,
    required this.likesCount,
    required this.sharesCount,
    this.likedByMe = false,
  });

  final String id;
  final String youtubeVideoId;
  final String title;
  final String creatorHandle;
  final String cityTag;
  final String thumbnailUrl;
  final int likesCount;
  final int sharesCount;
  final bool likedByMe;

  SpotmateReel copyWith({
    int? likesCount,
    int? sharesCount,
    bool? likedByMe,
  }) {
    return SpotmateReel(
      id: id,
      youtubeVideoId: youtubeVideoId,
      title: title,
      creatorHandle: creatorHandle,
      cityTag: cityTag,
      thumbnailUrl: thumbnailUrl,
      likesCount: likesCount ?? this.likesCount,
      sharesCount: sharesCount ?? this.sharesCount,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }

  factory SpotmateReel.fromJson(Map<String, dynamic> json) {
    final vid = (json['youtube_video_id'] ?? '').toString();
    return SpotmateReel(
      id: (json['id'] ?? '').toString(),
      youtubeVideoId: vid,
      title: (json['title'] ?? 'Spotmate Reel').toString(),
      creatorHandle: (json['creator_handle'] ?? '@spotmate').toString(),
      cityTag: (json['city_tag'] ?? 'Hyderabad').toString(),
      thumbnailUrl: (json['thumbnail_url'] ?? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg').toString(),
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      sharesCount: (json['shares_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] == true,
    );
  }
}

@immutable
class ConnectedSpotmateUser {
  const ConnectedSpotmateUser({
    required this.userId,
    required this.spotmateHandle,
    required this.displayName,
    this.avatarUrl,
    this.chatThreadId,
  });

  final String userId;
  final String spotmateHandle;
  final String displayName;
  final String? avatarUrl;
  final String? chatThreadId;
}

/// Canonical private-chat message payload for a shared Reel.
/// Store this JSON inside your private chat message metadata (or JSON body)
/// so `SharedReelChatCard` can render it and deep-link straight back to `ReelsFeedScreen`.
@immutable
class SharedReelPayload {
  const SharedReelPayload({
    required this.reelId,
    required this.youtubeVideoId,
    required this.title,
    required this.creatorHandle,
    required this.cityTag,
    required this.thumbnailUrl,
    this.note,
  });

  final String reelId;
  final String youtubeVideoId;
  final String title;
  final String creatorHandle;
  final String cityTag;
  final String thumbnailUrl;
  final String? note;

  Map<String, dynamic> toJson() => {
        'type': 'shared_reel',
        'reel_id': reelId,
        'youtube_video_id': youtubeVideoId,
        'title': title,
        'creator_handle': creatorHandle,
        'city_tag': cityTag,
        'thumbnail_url': thumbnailUrl,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  static SharedReelPayload? tryParse(Map<String, dynamic>? json) {
    if (json == null || json['type'] != 'shared_reel') return null;
    final reelId = (json['reel_id'] ?? '').toString();
    final vid = (json['youtube_video_id'] ?? '').toString();
    if (reelId.isEmpty || vid.isEmpty) return null;
    return SharedReelPayload(
      reelId: reelId,
      youtubeVideoId: vid,
      title: (json['title'] ?? 'Spotmate Reel').toString(),
      creatorHandle: (json['creator_handle'] ?? '@spotmate').toString(),
      cityTag: (json['city_tag'] ?? 'Hyderabad').toString(),
      thumbnailUrl: (json['thumbnail_url'] ?? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg').toString(),
      note: json['note']?.toString(),
    );
  }
}
