import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../music_room/models/music_room_models.dart';
import '../../music_room/services/music_room_service.dart';
import '../models/live_tv_models.dart';
import 'live_tv_player.dart';

class TvRoomPlayer extends StatefulWidget {
  const TvRoomPlayer({super.key, required this.room, required this.service});
  final MusicRoom room;
  final MusicRoomService service;

  @override
  State<TvRoomPlayer> createState() => _TvRoomPlayerState();
}

class _TvRoomPlayerState extends State<TvRoomPlayer> {
  final _search = TextEditingController();
  String _language = 'All';
  bool _loading = false;
  String? _error;
  int _request = 0;
  VoidCallback? _refreshSheet;
  List<Map<String, dynamic>> _channels = [];

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    final version = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client.functions.invoke('youtube-live-tv', body: {
        'language': _language, 'category': 'All', 'search': _search.text.trim(),
      });
      final payload = Map<String, dynamic>.from(response.data as Map);
      if (payload['error'] != null) throw StateError(payload['error'].toString());
      final channels = (payload['reels'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted || version != _request) return;
      setState(() { _channels = channels; _loading = false; });
      _refreshSheet?.call();
    } catch (_) {
      if (!mounted || version != _request) return;
      setState(() { _loading = false; _error = 'Could not load live channels. Try again.'; });
      _refreshSheet?.call();
    }
  }

  Future<void> _changeChannel(Map<String, dynamic> channel) async {
    try {
      await widget.service.changeTvChannel(widget.room.id, channel['id'] as String);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change channel. It may no longer be live.')),
        );
      }
    }
  }

  void _showChannels() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, updateSheet) {
        _refreshSheet = () { if (context.mounted) updateSheet(() {}); };
        Future<void> refresh() async {
          final operation = _loadChannels();
          updateSheet(() {});
          await operation;
        }
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('Choose a live channel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final language in ['All','Telugu','Hindi','English','Tamil','Kannada','Malayalam'])
                    Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                      label: Text(language), selected: language == _language,
                      onSelected: (_) { _language = language; refresh(); },
                    )),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(controller: _search, onSubmitted: (_) => refresh(),
                decoration: InputDecoration(hintText: 'Search live channels', prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(onPressed: refresh, icon: const Icon(Icons.arrow_forward)))),
            ),
            Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
              : _error != null ? Center(child: TextButton(onPressed: refresh, child: Text(_error!)))
              : _channels.isEmpty ? const Center(child: Text('No live channels found.'))
              : ListView.builder(
                  itemCount: _channels.length,
                  itemBuilder: (context, index) {
                    final channel = _channels[index];
                    return ListTile(
                      title: Text(channel['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(channel['creator'] as String),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _changeChannel(channel);
                      },
                    );
                  },
                )),
          ]),
        );
      }),
    ).whenComplete(() => _refreshSheet = null);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.room.currentSourceRef;
    return Column(children: [
      if (source == null)
        Container(
          height: 130, width: double.infinity, color: const Color(0xFF0F172A),
          child: const Center(child: Text('Choose a live channel to watch together',
            style: TextStyle(color: Colors.white))),
        )
      else
        LiveTvPlayer(channel: LiveTvChannel(id: source, name: widget.room.currentTitle ?? 'Live TV',
          category: 'Live', language: _language, streamType: 'youtube_live', streamSource: source)),
      Row(children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(widget.room.currentTitle ?? 'Live TV',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        )),
        TextButton.icon(onPressed: _showChannels, icon: const Icon(Icons.live_tv),
          label: const Text('Channels')),
      ]),
    ]);
  }
}
