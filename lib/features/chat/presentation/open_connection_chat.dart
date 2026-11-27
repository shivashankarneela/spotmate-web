import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_screen.dart';

Future<void> openConnectionChat(
  BuildContext context, {
  required String connectionId,
  required String userId,
  required String name,
  String? photo,
}) async {
  final client = Supabase.instance.client;
  final viewer = client.auth.currentUser?.id;
  if (viewer == null) return;
  try {
    final conversation = await client.from('conversations').select('id')
        .eq('connection_id', connectionId).maybeSingle();
    final id = conversation?['id'] as String? ??
        (await client.from('conversations').insert({
          'connection_id': connectionId,
        }).select('id').single())['id'] as String;
    if (conversation == null) {
      await client.from('conversation_members').insert([
        {'conversation_id': id, 'user_id': userId},
        {'conversation_id': id, 'user_id': viewer},
      ]);
    }
    if (!context.mounted || client.auth.currentUser?.id != viewer) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: id,
        otherUserName: name,
        otherUserPhoto: photo,
        otherUserId: userId,
        connectionId: connectionId,
      ),
    ));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Please try again.')),
      );
    }
  }
}
