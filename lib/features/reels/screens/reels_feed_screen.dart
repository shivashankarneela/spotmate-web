import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/connected_user_picker.dart';
import '../models/reel_models.dart';
import '../services/reels_service.dart';
import '../widgets/share_reel_sheet.dart';
import '../widgets/youtube_shorts_player.dart';

/// Full-screen scroll-only YouTube Shorts Reels screen (no user upload button).
/// Pass `initialReelId` when opening from a `SharedReelChatCard` inside private chat
/// so the user lands directly on that exact Reel and can swipe up/down or tap Back to return to chat.
class ReelsFeedScreen extends StatefulWidget {
  const ReelsFeedScreen({
    super.key,
    required this.activeCity,
    required this.loadConnectedUsers,
    this.onOpenPrivateChat,
    this.initialReelId,
  });

  final String activeCity;
  final Future<List<ConnectedSpotmateUser>> Function() loadConnectedUsers;
  final OnOpenPrivateChat? onOpenPrivateChat;
  final String? initialReelId;

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen> {
  final _service = ReelsService();
  final _pageController = PageController();

  String _tab = 'for_you';
  bool _loading = true;
  bool _isMuted = true;
  int _activeIndex = 0;
  List<SpotmateReel> _reels = [];
  bool _catalogueFeed = false;
  String? _feedError;
  final Set<String> _liking = {};
  Timer? _viewTimer;

  @override
  void initState() {
    super.initState();
    _loadFeed(initialReelId: widget.initialReelId);
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({String? initialReelId}) async {
    _viewTimer?.cancel();
    setState(() { _loading = true; _feedError = null; });
    try {
      final items = await _service.fetchFeed(
        tab: _tab,
        cityTag: _tab == 'city' ? widget.activeCity : null,
        initialReelId: initialReelId,
      );
      if (!mounted) return;
      setState(() {
        _reels = items;
        _catalogueFeed = initialReelId != null;
        _activeIndex = 0;
        _loading = false;
      });
      if (items.isNotEmpty) _recordViewAfterDelay(items.first);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _feedError = 'Could not load YouTube videos. Check the connection and try again.'; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load Reels: $e')));
    }
  }

  void _recordViewAfterDelay(SpotmateReel reel) {
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(seconds: 2), () {
      _service.recordView(reel.youtubeVideoId).catchError((_) {});
    });
  }

  Future<void> _toggleLike(int index) async {
    final reel = _reels[index];
    if (!_liking.add(reel.youtubeVideoId)) return;
    try {
      final res = _catalogueFeed
          ? await _service.toggleLike(reel.id)
          : await _service.toggleYouTubeLike(reel);
      if (!mounted) return;
      final current = _reels.indexWhere((item) => item.youtubeVideoId == reel.youtubeVideoId);
      if (current >= 0) setState(() {
        _reels[current] = _reels[current].copyWith(likedByMe: res.liked, likesCount: res.likesCount);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update your like. Please try again.')));
      }
    } finally {
      _liking.remove(reel.youtubeVideoId);
    }
  }

  Future<void> _shareYouTubeReel(SpotmateReel reel) async {
    final person = await pickConnectedUser(context);
    if (person == null || !mounted) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw StateError('Sign in required.');
      final payload = jsonEncode({
        'video_id': reel.youtubeVideoId,
        'title': reel.title,
        'thumbnail': reel.thumbnailUrl,
      });
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': person.conversationId,
        'sender_id': user.id,
        'message': 'YouTube reel · ' + payload,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shared with ${person.name}.')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this video.')),
      );
    }
  }

  Future<void> _openShareSheet(SpotmateReel reel) async {
    final users = await widget.loadConnectedUsers();
    if (!mounted) return;
    await ShareReelSheet.show(
      context,
      reel: reel,
      connectedUsers: users,
      onOpenPrivateChat: widget.onOpenPrivateChat,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          else if (_feedError != null)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_feedError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              TextButton(onPressed: () => _loadFeed(), child: const Text('Retry')),
            ]))
          else if (_reels.isEmpty)
            const Center(
              child: Text(
                'No reels available here yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
              ),
              itemCount: _reels.length,
              onPageChanged: (i) {
                setState(() => _activeIndex = i);
                _recordViewAfterDelay(_reels[i]);
              },
              itemBuilder: (context, index) {
                final reel = _reels[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: YouTubeShortsPlayer(
                          youtubeVideoId: reel.youtubeVideoId,
                          thumbnailUrl: reel.thumbnailUrl,
                          isActive: index == _activeIndex,
                          isMuted: _isMuted,
                        ),
                      ),
                    ),
                    // Right-side action rail (Like, Share to Private Chat, Mute)
                    Positioned(
                      right: 16,
                      bottom: 108,
                      child: Column(
                        children: [
                          _RailButton(
                            icon: reel.likedByMe ? Icons.favorite : Icons.favorite_border,
                            iconColor: reel.likedByMe ? const Color(0xFFEF4444) : Colors.white,
                            label: '${reel.likesCount}',
                            onTap: () => _toggleLike(index),
                          ),
                          const SizedBox(height: 18),
                          _RailButton(
                            icon: Icons.send_rounded,
                            iconColor: const Color(0xFF0F172A),
                            backgroundColor: const Color(0xFFF59E0B),
                            label: 'Share',
                            onTap: () => _catalogueFeed ? _openShareSheet(reel) : _shareYouTubeReel(reel),
                          ),
                          const SizedBox(height: 18),
                          _RailButton(
                            icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            iconColor: Colors.white,
                            label: _isMuted ? 'Muted' : 'Sound',
                            onTap: () => setState(() => _isMuted = !_isMuted),
                          ),
                        ],
                      ),
                    ),
                    // Bottom creator bar with empty circular dashed placeholder
                    Positioned(
                      left: 16,
                      right: 88,
                      bottom: 28,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white12,
                              border: Border.all(color: Colors.white70, width: 1.4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  reel.cityTag.isEmpty ? reel.creatorHandle : '${reel.creatorHandle} • ${reel.cityTag}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  reel.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

          // Top bar: Back button + Scroll-Only Feed Tabs (no upload button)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const Text('YouTube', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _TabPill(
                    label: 'For You',
                    selected: _tab == 'for_you',
                    onTap: () {
                      _tab = 'for_you';
                      _loadFeed();
                    },
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: widget.activeCity,
                    selected: _tab == 'city',
                    onTap: () {
                      _tab = 'city';
                      _loadFeed();
                    },
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'Trending',
                    selected: _tab == 'trending',
                    onTap: () {
                      _tab = 'trending';
                      _loadFeed();
                    },
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF59E0B) : Colors.black45,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF0F172A) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.backgroundColor = const Color(0x880F172A),
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: backgroundColor),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
