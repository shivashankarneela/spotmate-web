import 'package:flutter/foundation.dart';

@immutable
class MusicRoomMember {
  const MusicRoomMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;

  factory MusicRoomMember.fromJson(Map<String, dynamic> json) {
    return MusicRoomMember(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Listener').toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}

@immutable
class MusicRoom {
  const MusicRoom({
    required this.id,
    required this.roomCode,
    required this.title,
    required this.mode,
    required this.durationMinutes,
    required this.costSc,
    required this.maxMembers,
    required this.hostUserId,
    required this.status,
    required this.seekOffsetMs,
    required this.isPlaying,
    required this.expiresAt,
    this.currentSourceType,
    this.currentSourceRef,
    this.currentTitle,
    this.startedAt,
    this.memberCount = 0,
  });

  final String id;
  final String roomCode;
  final String title;
  final String mode; // free | custom
  final int durationMinutes;
  final int costSc;
  final int maxMembers;
  final String hostUserId;
  final String status; // active | closed
  final String? currentSourceType; // youtube | hls_audio
  final String? currentSourceRef;
  final String? currentTitle;
  final DateTime? startedAt;
  final int seekOffsetMs;
  final bool isPlaying;
  final DateTime expiresAt;
  final int memberCount;

  bool get isActive => status == 'active' && DateTime.now().isBefore(expiresAt);
  bool get isFull => memberCount >= maxMembers;

  /// Computes expected live playback position in seconds using server clock skew.
  double expectedPlaybackSeconds(int clockSkewMs) {
    if (currentSourceRef == null) return 0;
    if (!isPlaying || startedAt == null) return seekOffsetMs / 1000.0;
    final serverNowMs = DateTime.now().millisecondsSinceEpoch + clockSkewMs;
    final elapsedMs = serverNowMs - startedAt!.millisecondsSinceEpoch;
    return ((elapsedMs + seekOffsetMs).clamp(0, 86400000)) / 1000.0;
  }

  factory MusicRoom.fromJson(Map<String, dynamic> json) {
    return MusicRoom(
      id: (json['id'] ?? '').toString(),
      roomCode: (json['room_code'] ?? '').toString(),
      title: (json['title'] ?? 'Music Room').toString(),
      mode: (json['mode'] ?? 'free').toString(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
      costSc: (json['cost_sc'] as num?)?.toInt() ?? 0,
      maxMembers: (json['max_members'] as num?)?.toInt() ?? 5,
      hostUserId: (json['host_user_id'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      currentSourceType: json['current_source_type']?.toString(),
      currentSourceRef: json['current_source_ref']?.toString(),
      currentTitle: json['current_title']?.toString(),
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at'].toString()) : null,
      seekOffsetMs: (json['seek_offset_ms'] as num?)?.toInt() ?? 0,
      isPlaying: json['is_playing'] == true,
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()) ?? DateTime.now(),
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class MusicRoomMessage {
  const MusicRoomMessage({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.content,
    required this.createdAt,
    this.userId,
  });

  final String id;
  final String? userId;
  final String displayName;
  final String kind; // chat | command | bot
  final String content;
  final DateTime createdAt;

  factory MusicRoomMessage.fromJson(Map<String, dynamic> json) {
    return MusicRoomMessage(
      id: (json['id'] ?? '').toString(),
      userId: json['user_id']?.toString(),
      displayName: (json['display_name'] ?? 'MusicBot').toString(),
      kind: (json['kind'] ?? 'chat').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

@immutable
class MusicEmojiBurst {
  const MusicEmojiBurst({
    required this.id,
    required this.senderName,
    required this.emoji,
  });

  final String id;
  final String senderName;
  final String emoji;
}
