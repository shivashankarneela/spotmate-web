import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Updated Explore Long-Press Hub (Shop replaced with Music Room):
/// Shows Games, Live, Reels, and Music Room when the user long-presses Explore.
class ExploreLongPressTrigger extends StatelessWidget {
  const ExploreLongPressTrigger({
    super.key,
    required this.child,
    required this.onGamesSelected,
    required this.onMusicRoomSelected,
    this.onLiveSelected,
    this.onReelsSelected,
  });

  final Widget child;
  final VoidCallback onGamesSelected;
  final VoidCallback onMusicRoomSelected;
  final VoidCallback? onLiveSelected;
  final VoidCallback? onReelsSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ExploreHubTopDrawer.show(
          context,
          onGames: onGamesSelected,
          onMusicRoom: onMusicRoomSelected,
          onLive: onLiveSelected,
          onReels: onReelsSelected,
        );
      },
      child: child,
    );
  }
}

class ExploreHubTopDrawer extends StatelessWidget {
  const ExploreHubTopDrawer({
    super.key,
    required this.onGames,
    required this.onMusicRoom,
    this.onLive,
    this.onReels,
  });

  final VoidCallback onGames;
  final VoidCallback onMusicRoom;
  final VoidCallback? onLive;
  final VoidCallback? onReels;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGames,
    required VoidCallback onMusicRoom,
    VoidCallback? onLive,
    VoidCallback? onReels,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Explore Hub',
      barrierColor: Colors.black.withOpacity(0.38),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogCtx, _, __) {
        return Align(
          alignment: Alignment.topCenter,
          child: ExploreHubTopDrawer(
            onGames: () {
              Navigator.of(dialogCtx).pop();
              onGames();
            },
            onMusicRoom: () {
              Navigator.of(dialogCtx).pop();
              onMusicRoom();
            },
            onLive: () {
              Navigator.of(dialogCtx).pop();
              if (onLive != null) {
                onLive();
              } else {
                _comingSoon(context, 'Live');
              }
            },
            onReels: () {
              Navigator.of(dialogCtx).pop();
              if (onReels != null) {
                onReels();
              } else {
                _comingSoon(context, 'Reels');
              }
            },
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(curved),
          child: child,
        );
      },
    );
  }

  static void _comingSoon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name is coming soon to Spotmate!'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.08,
                  children: [
                    _HubTile(
                      label: 'Games Arena',
                      icon: Icons.sports_esports_rounded,
                      colors: const [Color(0xFF10B981), Color(0xFF047857)],
                      onTap: onGames,
                    ),
                    _HubTile(
                      label: 'Music Room',
                      icon: Icons.headphones_rounded,
                      colors: const [Color(0xFF0D9488), Color(0xFF1D4ED8)],
                      onTap: onMusicRoom,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
