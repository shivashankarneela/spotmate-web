import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/live_tv_models.dart';
import '../widgets/live_tv_player.dart';

class YouTubeLiveScreen extends StatefulWidget {
  const YouTubeLiveScreen({super.key});

  @override
  State<YouTubeLiveScreen> createState() => _YouTubeLiveScreenState();
}

class _YouTubeLiveScreenState extends State<YouTubeLiveScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _streams = [];
  Map<String, dynamic>? _selected;
  String _category = 'All';
  String _language = 'All';
  String? _error;
  bool _loading = true;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client.functions.invoke('youtube-live-tv', body: {
        'category': _category, 'language': _language, 'search': _search.text.trim(),
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw StateError(data['error'].toString());
      final streams = (data['reels'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted || loadId != _loadId) return;
      setState(() { _streams = streams; _selected = streams.isEmpty ? null : streams.first; _loading = false; });
    } catch (_) {
      if (!mounted || loadId != _loadId) return;
      setState(() { _loading = false; _error = 'Could not load YouTube Live. Check the connection and try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _selected;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      appBar: AppBar(title: const Text('Live TV · YouTube')),
      body: Column(children: [
        if (current != null)
          LiveTvPlayer(channel: LiveTvChannel(
            id: current['id'] as String, name: current['name'] as String,
            category: 'Live', language: '', streamType: 'youtube_live',
            streamSource: current['id'] as String,
          )),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search, onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search YouTube Live', prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.arrow_forward)),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final category in ['All', 'News', 'Sports', 'Music', 'Devotional'])
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                label: Text(category), selected: _category == category,
                onSelected: (_) { setState(() => _category = category); _load(); },
              )),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final language in ['All', 'Telugu', 'Hindi', 'English', 'Tamil', 'Kannada'])
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                label: Text(language), selected: _language == language,
                onSelected: (_) { setState(() => _language = language); _load(); },
              )),
          ]),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ]))
            : _streams.isEmpty
              ? const Center(child: Text('No live broadcasts found.'))
              : ListView.builder(
                  itemCount: _streams.length,
                  itemBuilder: (context, index) {
                    final stream = _streams[index];
                    return ListTile(
                      selected: current?['id'] == stream['id'],
                      leading: stream['thumbnail'] is String
                        ? Image.network(stream['thumbnail'] as String, width: 88, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.live_tv))
                        : const Icon(Icons.live_tv),
                      title: Text(stream['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(stream['creator'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => setState(() => _selected = stream),
                    );
                  },
                )),
      ]),
    );
  }
}
