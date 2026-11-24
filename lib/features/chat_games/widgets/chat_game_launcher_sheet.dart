import 'package:flutter/material.dart';
import '../models/chat_game_models.dart';
import '../plugins/chat_game_plugin.dart';

/// Bottom sheet / modal launcher for starting any of the 5 chat game plugins inside a room.
class ChatGameLauncherSheet extends StatelessWidget {
  const ChatGameLauncherSheet({
    super.key,
    required this.onSelectGame,
  });

  final void Function(ChatGameType gameType) onSelectGame;

  static Future<void> show(
    BuildContext context, {
    required void Function(ChatGameType gameType) onSelectGame,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFAF8F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChatGameLauncherSheet(
        onSelectGame: (type) {
          Navigator.of(context).pop();
          onSelectGame(type);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugins = ChatGamePluginRegistry.all;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start a Room Game',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Win rounds to build your room streak.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            ...plugins.map((plugin) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: plugin.accentColor.withOpacity(0.12),
                    child: Icon(plugin.icon, color: plugin.accentColor, size: 20),
                  ),
                  title: Text(
                    plugin.type.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    plugin.type.subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.play_arrow_rounded, color: Color(0xFF475569)),
                  onTap: () => onSelectGame(plugin.type),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
