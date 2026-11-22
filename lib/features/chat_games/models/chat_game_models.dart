import 'package:flutter/foundation.dart';

enum ChatGameType {
  quiz('quiz', 'Quiz', 'Current affairs & 8+ subjects'),
  anagram('anagram', 'Anagram', 'Unscramble the hidden word'),
  fiveLetter('five_letter', '5-Letter Word', 'Wordle-style room challenge'),
  hangman('hangman', 'Hangman / Reveal', 'Guess letters or solve the phrase'),
  arithmeticBlitz('arithmetic_blitz', 'Arithmetic & Sequence Blitz', 'Fast mental math & patterns');

  const ChatGameType(this.id, this.title, this.subtitle);

  final String id;
  final String title;
  final String subtitle;

  static ChatGameType fromId(String id) {
    return ChatGameType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ChatGameType.quiz,
    );
  }
}

enum ChatGameStatus { active, solved, expired, cancelled }

@immutable
class FiveLetterAttempt {
  const FiveLetterAttempt({
    required this.userId,
    required this.displayName,
    required this.guess,
    required this.statuses,
    required this.emoji,
  });

  final String userId;
  final String displayName;
  final String guess;
  final List<String> statuses; // 'correct' | 'present' | 'absent'
  final String emoji;

  factory FiveLetterAttempt.fromJson(Map<String, dynamic> json) {
    return FiveLetterAttempt(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      guess: (json['guess'] ?? '').toString(),
      statuses: List<String>.from(json['statuses'] ?? const <String>[]),
      emoji: (json['emoji'] ?? '').toString(),
    );
  }
}

@immutable
class ChatGameSession {
  const ChatGameSession({
    required this.id,
    required this.roomId,
    required this.gameType,
    required this.category,
    required this.difficulty,
    required this.publicState,
    required this.hintStep,
    required this.status,
    required this.scReward,
    required this.startedAt,
    required this.expiresAt,
    this.winnerUserId,
    this.winnerDisplayName,
    this.revealedAnswer,
    this.solvedAt,
  });

  final String id;
  final String roomId;
  final ChatGameType gameType;
  final String category;
  final String difficulty;
  final Map<String, dynamic> publicState;
  final int hintStep;
  final ChatGameStatus status;
  final int scReward;
  final DateTime startedAt;
  final DateTime expiresAt;
  final String? winnerUserId;
  final String? winnerDisplayName;
  final String? revealedAnswer;
  final DateTime? solvedAt;

  bool get isActive => status == ChatGameStatus.active && DateTime.now().isBefore(expiresAt);

  Duration get remainingTime {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  List<FiveLetterAttempt> get fiveLetterAttempts {
    final raw = publicState['attempts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => FiveLetterAttempt.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  factory ChatGameSession.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'active').toString();
    final parsedStatus = ChatGameStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => ChatGameStatus.active,
    );

    return ChatGameSession(
      id: (json['id'] ?? '').toString(),
      roomId: (json['room_id'] ?? '').toString(),
      gameType: ChatGameType.fromId((json['game_type'] ?? 'quiz').toString()),
      category: (json['category'] ?? '').toString(),
      difficulty: (json['difficulty'] ?? 'medium').toString(),
      publicState: Map<String, dynamic>.from(json['public_state'] ?? const {}),
      hintStep: (json['hint_step'] as num?)?.toInt() ?? 0,
      status: parsedStatus,
      scReward: (json['sc_reward'] as num?)?.toInt() ?? 10,
      startedAt: DateTime.tryParse((json['started_at'] ?? '').toString()) ?? DateTime.now(),
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()) ?? DateTime.now(),
      winnerUserId: json['winner_user_id']?.toString(),
      winnerDisplayName: json['winner_display_name']?.toString(),
      revealedAnswer: json['revealed_answer']?.toString(),
      solvedAt: json['solved_at'] != null ? DateTime.tryParse(json['solved_at'].toString()) : null,
    );
  }
}

@immutable
class ChatGameLeaderboardEntry {
  const ChatGameLeaderboardEntry({
    required this.roomId,
    required this.userId,
    required this.displayName,
    required this.wins,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalScEarned,
  });

  final String roomId;
  final String userId;
  final String displayName;
  final int wins;
  final int currentStreak;
  final int bestStreak;
  final int totalScEarned;

  factory ChatGameLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return ChatGameLeaderboardEntry(
      roomId: (json['room_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? 'Player').toString(),
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      totalScEarned: (json['total_sc_earned'] as num?)?.toInt() ?? 0,
    );
  }
}
