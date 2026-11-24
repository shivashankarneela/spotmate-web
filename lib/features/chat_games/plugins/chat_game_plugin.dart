import 'package:flutter/material.dart';
import '../models/chat_game_models.dart';

/// Unified plugin contract so every chat game plugs into Spotmate public chat rooms
/// with consistent formatting, input filtering, and badge styling.
abstract class ChatGamePlugin {
  ChatGameType get type;
  IconData get icon;
  Color get accentColor;
  Duration get defaultDuration;

  /// Returns true if a chat message looks like a plausible guess for this game
  /// (avoids firing unnecessary Edge Function calls for unrelated chat chatter).
  bool shouldInspectMessage(String messageText);

  /// Primary prompt headline rendered inside the in-chat bot card.
  String formatHeadline(ChatGameSession session);

  /// Optional secondary hint or progress line.
  String? formatHintLine(ChatGameSession session);
}

class QuizGamePlugin extends ChatGamePlugin {
  @override
  ChatGameType get type => ChatGameType.quiz;
  @override
  IconData get icon => Icons.quiz_rounded;
  @override
  Color get accentColor => const Color(0xFF4F46E5);
  @override
  Duration get defaultDuration => const Duration(seconds: 45);

  @override
  bool shouldInspectMessage(String messageText) {
    final t = messageText.trim();
    return t.isNotEmpty && t.length <= 64;
  }

  @override
  String formatHeadline(ChatGameSession session) {
    return (session.publicState['question'] ?? 'Loading question...').toString();
  }

  @override
  String? formatHintLine(ChatGameSession session) {
    final hint = session.publicState['hint']?.toString();
    return (hint != null && hint.isNotEmpty) ? 'Hint: $hint' : null;
  }
}

class AnagramGamePlugin extends ChatGamePlugin {
  @override
  ChatGameType get type => ChatGameType.anagram;
  @override
  IconData get icon => Icons.shuffle_rounded;
  @override
  Color get accentColor => const Color(0xFFD97706);
  @override
  Duration get defaultDuration => const Duration(seconds: 45);

  @override
  bool shouldInspectMessage(String messageText) {
    final t = messageText.trim();
    return RegExp(r'^[a-zA-Z]{4,14}$').hasMatch(t);
  }

  @override
  String formatHeadline(ChatGameSession session) {
    final scrambled = (session.publicState['scrambled'] ?? '').toString();
    return 'Unscramble: ${scrambled.split('').join(' ')}';
  }

  @override
  String? formatHintLine(ChatGameSession session) {
    final hint = session.publicState['hint']?.toString() ?? '';
    final prefix = session.publicState['revealed_prefix']?.toString() ?? '';
    if (prefix.isNotEmpty) {
      return '$hint • Starts with "$prefix..."';
    }
    return hint.isNotEmpty ? hint : null;
  }
}

class FiveLetterWordGamePlugin extends ChatGamePlugin {
  @override
  ChatGameType get type => ChatGameType.fiveLetter;
  @override
  IconData get icon => Icons.grid_view_rounded;
  @override
  Color get accentColor => const Color(0xFF15803D);
  @override
  Duration get defaultDuration => const Duration(seconds: 120);

  @override
  bool shouldInspectMessage(String messageText) {
    return RegExp(r'^[a-zA-Z]{5}$').hasMatch(messageText.trim());
  }

  @override
  String formatHeadline(ChatGameSession session) {
    final used = session.fiveLetterAttempts.length;
    final max = (session.publicState['max_attempts'] as num?)?.toInt() ?? 6;
    return 'Guess the 5-letter word ($used/$max tries)';
  }

  @override
  String? formatHintLine(ChatGameSession session) {
    return 'Type any 5-letter English word in chat. 🟩 right spot • 🟨 wrong spot • ⬜ miss';
  }
}

class HangmanRevealGamePlugin extends ChatGamePlugin {
  @override
  ChatGameType get type => ChatGameType.hangman;
  @override
  IconData get icon => Icons.visibility_rounded;
  @override
  Color get accentColor => const Color(0xFFBE123C);
  @override
  Duration get defaultDuration => const Duration(seconds: 90);

  @override
  bool shouldInspectMessage(String messageText) {
    final t = messageText.trim();
    return t.isNotEmpty && t.length <= 48;
  }

  @override
  String formatHeadline(ChatGameSession session) {
    return (session.publicState['masked'] ?? '_ _ _ _ _').toString();
  }

  @override
  String? formatHintLine(ChatGameSession session) {
    final wrong = List<String>.from(session.publicState['wrong_letters'] ?? const []);
    final maxWrong = (session.publicState['max_wrong'] as num?)?.toInt() ?? 6;
    final misses = wrong.isEmpty ? 'None' : wrong.join(', ');
    return 'Theme: ${session.category} • Misses (${wrong.length}/$maxWrong): $misses\n'
        'Send a letter or the full phrase in chat.';
  }
}

class ArithmeticBlitzGamePlugin extends ChatGamePlugin {
  @override
  ChatGameType get type => ChatGameType.arithmeticBlitz;
  @override
  IconData get icon => Icons.bolt_rounded;
  @override
  Color get accentColor => const Color(0xFF0284C7);
  @override
  Duration get defaultDuration => const Duration(seconds: 30);

  @override
  bool shouldInspectMessage(String messageText) {
    return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(messageText.trim());
  }

  @override
  String formatHeadline(ChatGameSession session) {
    return (session.publicState['prompt'] ?? 'Loading blitz...').toString();
  }

  @override
  String? formatHintLine(ChatGameSession session) {
    final hint = session.publicState['hint']?.toString();
    return (hint != null && hint.isNotEmpty) ? 'Hint: $hint' : 'First exact number in chat wins!';
  }
}

/// Central registry for all installed chat game plugins.
class ChatGamePluginRegistry {
  ChatGamePluginRegistry._();

  static final Map<ChatGameType, ChatGamePlugin> _plugins = {
    ChatGameType.quiz: QuizGamePlugin(),
    ChatGameType.anagram: AnagramGamePlugin(),
    ChatGameType.fiveLetter: FiveLetterWordGamePlugin(),
    ChatGameType.hangman: HangmanRevealGamePlugin(),
    ChatGameType.arithmeticBlitz: ArithmeticBlitzGamePlugin(),
  };

  static List<ChatGamePlugin> get all => _plugins.values.toList(growable: false);

  static ChatGamePlugin of(ChatGameType type) => _plugins[type]!;
}
