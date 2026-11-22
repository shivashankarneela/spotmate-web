import 'package:flutter/material.dart';
import '../models/reel_models.dart';
import '../services/reels_service.dart';

typedef OnSendReelToPrivateChat = Future<void> Function(
  ConnectedSpotmateUser recipient,
  SharedReelPayload payload,
);

typedef OnOpenPrivateChat = void Function(ConnectedSpotmateUser recipient);

/// Warm Paper bottom sheet for sharing a Reel to connected Spotmate users.
class ShareReelSheet extends StatefulWidget {
  const ShareReelSheet({
    super.key,
    required this.reel,
    required this.connectedUsers,
    this.onOpenPrivateChat,
  });

  final SpotmateReel reel;
  final List<ConnectedSpotmateUser> connectedUsers;
  final OnOpenPrivateChat? onOpenPrivateChat;

  static Future<void> show(
    BuildContext context, {
    required SpotmateReel reel,
    required List<ConnectedSpotmateUser> connectedUsers,
    OnOpenPrivateChat? onOpenPrivateChat,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF8F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ShareReelSheet(
        reel: reel,
        connectedUsers: connectedUsers,
        onOpenPrivateChat: onOpenPrivateChat,
      ),
    );
  }

  @override
  State<ShareReelSheet> createState() => _ShareReelSheetState();
}

class _ShareReelSheetState extends State<ShareReelSheet> {
  final _service = ReelsService();
  final _searchController = TextEditingController();
  final _noteController = TextEditingController();
  final Set<String> _sentUserIds = {};
  final Set<String> _sendingUserIds = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _sendTo(ConnectedSpotmateUser user) async {
    if (_sendingUserIds.contains(user.userId) || _sentUserIds.contains(user.userId)) return;
    setState(() => _sendingUserIds.add(user.userId));
    try {
      await _service.recordShare(
        reelId: widget.reel.id,
        recipientId: user.userId,
        chatThreadId: user.chatThreadId,
        note: _noteController.text,
      );
      if (!mounted) return;
      setState(() {
        _sendingUserIds.remove(user.userId);
        _sentUserIds.add(user.userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared reel with ${user.displayName}'),
          action: widget.onOpenPrivateChat != null
              ? SnackBarAction(
                  label: 'Open Chat',
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenPrivateChat!(user);
                  },
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingUserIds.remove(user.userId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.connectedUsers.where((u) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return u.displayName.toLowerCase().contains(q) ||
          u.spotmateHandle.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Text(
              'Share to Spotmate Chat',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search connected users...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No connected Spotmate users found.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final user = filtered[i];
                        final sent = _sentUserIds.contains(user.userId);
                        final sending = _sendingUserIds.contains(user.userId);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: _EmptySlotAvatar(avatarUrl: user.avatarUrl),
                          title: Text(
                            user.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                          ),
                          subtitle: Text(
                            user.spotmateHandle,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                          ),
                          trailing: ElevatedButton(
                            onPressed: (sent || sending) ? null : () => _sendTo(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: sent ? const Color(0xFF475569) : const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF475569),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            ),
                            child: Text(sending ? '...' : (sent ? 'Sent' : 'Send')),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                hintText: 'Add a note...',
                filled: true,
                fillColor: const Color(0xFFF1EFE9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty circular dashed profile photo placeholder when no real avatarUrl is set.
class _EmptySlotAvatar extends StatelessWidget {
  const _EmptySlotAvatar({this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(radius: 21, backgroundImage: NetworkImage(avatarUrl!));
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.4),
      ),
    );
  }
}
