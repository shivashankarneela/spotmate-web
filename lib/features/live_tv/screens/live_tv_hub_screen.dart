import 'package:flutter/material.dart';
import '../models/live_tv_models.dart';
import '../services/live_tv_service.dart';
import 'live_tv_player_screen.dart';

/// Opened when tapping "Live" in Spotmate Web's Explore Long-Press Hub.
class LiveTvHubScreen extends StatefulWidget {
  const LiveTvHubScreen({
    super.key,
    required this.currentDisplayName,
    this.currentAvatarUrl,
    this.onShareChannel,
  });

  final String currentDisplayName;
  final String? currentAvatarUrl;
  final void Function(SharedLiveTvPayload payload)? onShareChannel;

  @override
  State<LiveTvHubScreen> createState() => _LiveTvHubScreenState();
}

class _LiveTvHubScreenState extends State<LiveTvHubScreen> {
  final _service = LiveTvService();
  final _searchController = TextEditingController();

  String _category = 'All';
  String _language = 'All';
  bool _loading = true;
  List<LiveTvChannel> _channels = [];

  static const _categories = ['All', 'News', 'Sports', 'Music', 'Movies', 'Devotional', 'City Live'];
  static const _languages = ['All', 'Telugu', 'Hindi', 'English', 'Tamil', 'Kannada'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.fetchChannels(
        category: _category,
        language: _language,
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _channels = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load Live TV: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Spotmate Live TV', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search channels...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
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
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final selected = cat == _category;
                return ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFFF59E0B),
                  onSelected: (_) {
                    setState(() => _category = cat);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _languages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final lang = _languages[i];
                final selected = lang == _language;
                return FilterChip(
                  label: Text(lang, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor: const Color(0xFFFEF3C7),
                  onSelected: (_) {
                    setState(() => _language = lang);
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                : _channels.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No live channels match this filter yet. Add YouTube Live or HLS channels in spotmate_live_channels.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: _channels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final ch = _channels[i];
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            tileColor: Colors.white,
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.live_tv_rounded, color: Color(0xFFD97706)),
                            ),
                            title: Text(ch.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${ch.category} • ${ch.language} • ${ch.viewerCount} watching'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LiveTvPlayerScreen(
                                  channel: ch,
                                  currentDisplayName: widget.currentDisplayName,
                                  currentAvatarUrl: widget.currentAvatarUrl,
                                  onShareChannel: widget.onShareChannel,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
