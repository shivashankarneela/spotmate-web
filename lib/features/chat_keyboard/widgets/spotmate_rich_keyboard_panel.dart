import 'package:flutter/material.dart';
import '../data/regional_meme_stickers.dart';
import '../models/chat_keyboard_models.dart';
import '../services/gif_search_service.dart';

/// Spotmate Rich Chat Keyboard for Public City Chats & 1-on-1 Private Chats:
/// - Emoji Tab
/// - Live Animated GIFs Tab (with Brahmanandam, Hera Pheri, Vadivelu, Telugu, Hindi, Tamil quick pills)
/// - Memes Tab (20 Telugu + 20 Bollywood/Hindi + 20 Kollywood/Tamil = 60 comic-pop stickers)
/// - Quick Desi Replies Tab
class SpotmateRichKeyboardPanel extends StatefulWidget {
  const SpotmateRichKeyboardPanel({
    super.key,
    required this.onInsertText,
    required this.onSendSticker,
    required this.onSendGif,
    this.tenorApiKey = '',
    this.giphyApiKey = '',
    this.customAvatarStickers = const [],
    this.height = 328,
  });

  final void Function(String text) onInsertText;
  final void Function(SpotmateSticker sticker) onSendSticker;
  final void Function(SpotmateGifItem gif) onSendGif;
  final String tenorApiKey;
  final String giphyApiKey;
  final List<SpotmateSticker> customAvatarStickers;
  final double height;

  @override
  State<SpotmateRichKeyboardPanel> createState() => _SpotmateRichKeyboardPanelState();
}

class _SpotmateRichKeyboardPanelState extends State<SpotmateRichKeyboardPanel> {
  SpotmateKeyboardTab _tab = SpotmateKeyboardTab.stickers;
  late final GifSearchService _gifService;
  final _gifSearchController = TextEditingController();
  List<SpotmateGifItem> _gifs = [];
  bool _loadingGifs = false;
  int _gifSearchVersion = 0;
  String _selectedGifTag = 'Trending';
  String _selectedStickerPack = 'telugu_memes';

  static const _gifQuickTags = [
    'Trending',
    'Brahmanandam',
    'Hera Pheri',
    'Vadivelu',
    'Telugu Meme',
    'Bollywood',
    'Tamil Comedy',
    'LOL',
  ];

  static const _emojis = [
    '😂', '🔥', '❤️', '👏', '🙌', '😍', '😎', '🤝',
    '🤩', '🥳', '😭', '🤯', '👀', '💯', '✨', '🎉',
    '☕', '🍛', '👍', '👎', '🙏', '💪', '🫶', '🫡',
    '😏', '🤭', '💀', '🤦', '⚡', '🛑', '💸', '👋',
  ];

  static const _regionalPhrases = [
    'Ela unnav? 👋',
    'Biryani ekkada? 🍛',
    'Kya haal hai? 🔥',
    'Chai peete hain ☕',
    'Eppadi irukka machi? 😎',
    'Weekend plan enti? 🌆',
  ];

  @override
  void initState() {
    super.initState();
    _gifService = GifSearchService(
      tenorApiKey: widget.tenorApiKey,
      giphyApiKey: widget.giphyApiKey,
    );
    if (_gifService.hasLiveKey) _searchGifs('');
  }

  @override
  void dispose() {
    _gifSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchGifs(String q) async {
    if (!_gifService.hasLiveKey) return;
    final version = ++_gifSearchVersion;
    setState(() => _loadingGifs = true);
    try {
      final res = await _gifService.search(q);
      if (mounted && version == _gifSearchVersion) setState(() => _gifs = res);
    } catch (_) {
      if (mounted && version == _gifSearchVersion) setState(() => _gifs = []);
    } finally {
      if (mounted && version == _gifSearchVersion) setState(() => _loadingGifs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: Color(0xFFFAF8F3),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                _tabBtn(SpotmateKeyboardTab.emoji, Icons.emoji_emotions_outlined, 'Emoji'),
                _tabBtn(SpotmateKeyboardTab.gifs, Icons.gif_box_outlined, 'GIFs'),
                _tabBtn(SpotmateKeyboardTab.stickers, Icons.auto_awesome_outlined, 'Memes'),
                _tabBtn(SpotmateKeyboardTab.quick, Icons.bolt_rounded, 'Quick'),
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              SpotmateKeyboardTab.emoji => _buildEmojiGrid(),
              SpotmateKeyboardTab.gifs => _buildGifPicker(),
              SpotmateKeyboardTab.stickers => _buildStickerPicker(),
              SpotmateKeyboardTab.quick => _buildQuickReplies(),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(SpotmateKeyboardTab tab, IconData icon, String label) {
    final active = _tab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = tab),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFEF3C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: active ? const Color(0xFF92400E) : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? const Color(0xFF92400E) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _emojis.length,
      itemBuilder: (_, i) => InkWell(
        onTap: () => widget.onInsertText(_emojis[i]),
        borderRadius: BorderRadius.circular(10),
        child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 24))),
      ),
    );
  }

  Widget _buildGifPicker() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            controller: _gifSearchController,
            onSubmitted: (v) {
              setState(() => _selectedGifTag = v.trim().isEmpty ? 'Trending' : v.trim());
              _searchGifs(v);
            },
            decoration: InputDecoration(
              hintText: 'Search Brahmanandam, Hera Pheri, Vadivelu...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _gifQuickTags.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final tag = _gifQuickTags[i];
              return ChoiceChip(
                label: Text(tag, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                selected: _selectedGifTag == tag,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) {
                  setState(() => _selectedGifTag = tag);
                  _searchGifs(tag == 'Trending' ? '' : tag);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: !_gifService.hasLiveKey
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Pass your free Tenor or GIPHY API key to SpotmateChatComposer (tenorApiKey / giphyApiKey) to stream live animated GIFs here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                  ),
                )
              : _loadingGifs
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.25,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (_, i) {
                        final g = _gifs[i];
                        return GestureDetector(
                          onTap: () => widget.onSendGif(g),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  g.previewUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0F172A)),
                                ),
                                Positioned(
                                  left: 5,
                                  bottom: 5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('GIF',
                                        style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStickerPicker() {
    final hasAvatars = widget.customAvatarStickers.isNotEmpty;
    final packs = [
      ('telugu_memes', 'Telugu (20)'),
      ('hindi_memes', 'Bollywood (20)'),
      ('tamil_memes', 'Kollywood (20)'),
      if (hasAvatars) ('avatars', 'My Avatars'),
    ];
    final items = _selectedStickerPack == 'avatars'
        ? widget.customAvatarStickers
        : RegionalMemeStickers.byPack(_selectedStickerPack);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            itemCount: packs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final (id, title) = packs[i];
              return ChoiceChip(
                label: Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                selected: _selectedStickerPack == id,
                selectedColor: const Color(0xFFF59E0B),
                onSelected: (_) => setState(() => _selectedStickerPack = id),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.06,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final st = items[i];
              final accent = Color(st.accentHex);
              return InkWell(
                onTap: () => widget.onSendSticker(st),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent, width: 1.8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (st.assetPath != null)
                        Expanded(child: Image.asset(st.assetPath!, fit: BoxFit.contain))
                      else if (st.imageUrl != null)
                        Expanded(child: Image.network(st.imageUrl!, fit: BoxFit.contain))
                      else
                        Text(st.badgeEmoji, style: const TextStyle(fontSize: 25)),
                      const SizedBox(height: 3),
                      Text(
                        st.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickReplies() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Quick Chat Replies (Telugu • Hindi • Tamil)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final phrase in _regionalPhrases)
              ActionChip(
                label: Text(phrase, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                backgroundColor: const Color(0xFFFEF3C7),
                onPressed: () => widget.onInsertText(phrase),
              ),
          ],
        ),
      ],
    );
  }
}
