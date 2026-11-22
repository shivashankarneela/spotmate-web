import 'package:flutter/foundation.dart';

@immutable
class LiveTvChannel {
  const LiveTvChannel({
    required this.id,
    required this.name,
    required this.category,
    required this.language,
    required this.streamType,
    required this.streamSource,
    this.logoUrl,
    this.viewerCount = 0,
  });

  final String id;
  final String name;
  final String category;
  final String language;
  final String streamType; // youtube_live | youtube_channel | hls
  final String streamSource;
  final String? logoUrl;
  final int viewerCount;

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) {
    return LiveTvChannel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Live Channel').toString(),
      category: (json['category'] ?? 'News').toString(),
      language: (json['language'] ?? 'Telugu').toString(),
      streamType: (json['stream_type'] ?? 'youtube_live').toString(),
      streamSource: (json['stream_source'] ?? '').toString(),
      logoUrl: json['logo_url']?.toString(),
      viewerCount: (json['viewer_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class LiveTvChatMessage {
  const LiveTvChatMessage({
    required this.id,
    required this.channelId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.body,
    this.reactionEmoji,
    required this.createdAt,
  });

  final String id;
  final String channelId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? body;
  final String? reactionEmoji;
  final DateTime createdAt;

  factory LiveTvChatMessage.fromJson(Map<String, dynamic> json) {
    return LiveTvChatMessage(
      id: (json['id'] ?? '').toString(),
      channelId: (json['channel_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'User').toString(),
      avatarUrl: json['avatar_url']?.toString(),
      body: json['body']?.toString(),
      reactionEmoji: json['reaction_emoji']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

/// Canonical private-chat payload for sharing a Live TV channel to a connected user.
@immutable
class SharedLiveTvPayload {
  const SharedLiveTvPayload({
    required this.channelId,
    required this.name,
    required this.category,
    required this.language,
    required this.streamType,
    required this.streamSource,
    this.logoUrl,
  });

  final String channelId;
  final String name;
  final String category;
  final String language;
  final String streamType;
  final String streamSource;
  final String? logoUrl;

  Map<String, dynamic> toJson() => {
        'type': 'shared_live_tv',
        'channel_id': channelId,
        'name': name,
        'category': category,
        'language': language,
        'stream_type': streamType,
        'stream_source': streamSource,
        if (logoUrl != null) 'logo_url': logoUrl,
      };

  static SharedLiveTvPayload? tryParse(Map<String, dynamic>? json) {
    if (json == null || json['type'] != 'shared_live_tv') return null;
    final id = (json['channel_id'] ?? '').toString();
    if (id.isEmpty) return null;
    return SharedLiveTvPayload(
      channelId: id,
      name: (json['name'] ?? 'Live TV').toString(),
      category: (json['category'] ?? 'News').toString(),
      language: (json['language'] ?? 'Telugu').toString(),
      streamType: (json['stream_type'] ?? 'youtube_live').toString(),
      streamSource: (json['stream_source'] ?? '').toString(),
      logoUrl: json['logo_url']?.toString(),
    );
  }

  LiveTvChannel toChannel() => LiveTvChannel(
        id: channelId,
        name: name,
        category: category,
        language: language,
        streamType: streamType,
        streamSource: streamSource,
        logoUrl: logoUrl,
      );
}
