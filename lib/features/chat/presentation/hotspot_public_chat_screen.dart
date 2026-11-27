import '../../chat_keyboard/widgets/chat_expression_sheet.dart';
import 'room_presence.dart';
import '../../../core/widgets/horizontal_swipe_action.dart';
import '../../chat_games/models/chat_game_models.dart';
import '../../shared/connected_user_picker.dart';
import 'dart:convert';
import '../../chat_games/services/chat_game_service.dart';
import '../../chat_games/widgets/chat_game_bot_card.dart';
import '../../chat_games/widgets/chat_game_launcher_sheet.dart';
import '../../../core/optional_column.dart';
import 'city_visit_gate.dart';
import 'package:spotmate/features/store/presentation/store_avatar.dart';
import 'package:spotmate/features/store/presentation/fighter_artwork.dart';
import 'package:spotmate/features/store/presentation/store_screen.dart';
import 'chat_expression_picker.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:spotmate/core/utils/spotmate_image_upload.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';
import 'package:spotmate/core/widgets/halo_illustrated_avatar.dart';
import 'package:spotmate/core/widgets/avatar_profile_updates.dart';
import 'package:spotmate/features/profile/presentation/user_profile_detail_screen.dart';
import 'package:spotmate/features/chat/presentation/room_member_actions.dart';
import 'package:spotmate/features/hotspots/presentation/room_settings_screen.dart';

/// A public room conversation for active members.
class HotspotPublicChatScreen extends StatelessWidget {
  const HotspotPublicChatScreen({
    super.key,
    required this.hotspotId,
    required this.hotspotName,
    this.cityRegion,
    this.onPickRegion,
    this.onSearch,
  });

  final String hotspotId;
  final String hotspotName;
  final String? cityRegion;
  final VoidCallback? onPickRegion;
  final VoidCallback? onSearch;

  bool get isCityChat => cityRegion != null;

  @override
  Widget build(BuildContext context) {
    final content = _RoomBody(key: ValueKey(hotspotId), hotspotId: hotspotId,
      hotspotName: hotspotName, cityRegion: cityRegion, onPickRegion: onPickRegion, onSearch: onSearch);
    return isCityChat ? CityVisitGate(key: ValueKey(hotspotId), room: hotspotId, child: content) : content;
  }
}

class _RoomBody extends StatefulWidget {
  const _RoomBody({
    super.key,
    required this.hotspotId,
    required this.hotspotName,
    this.cityRegion,
    this.onPickRegion,
    this.onSearch,
  });

  final String hotspotId;
  final String hotspotName;
  final String? cityRegion;
  final VoidCallback? onPickRegion;
  final VoidCallback? onSearch;

  bool get isCityChat => cityRegion != null;

  @override
  State<_RoomBody> createState() => _RoomBodyState();
}

class _RoomBodyState extends State<_RoomBody> with WidgetsBindingObserver {
  static int _nextSubscription = 0;
  final _subscriptionId = _nextSubscription++;
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _composerFocus = FocusNode();
  late final RoomPresence _roomPresence;
  late final RoomPresenceListener _presenceListener;
  RealtimeChannel get _presenceChannel => _roomPresence.channel;
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;
  RealtimeChannel? _profileChannel;
  Timer? _typingTimer;
  Timer? _clearTypingTimer;
  bool _hasAnnouncedTyping=false;
  final Set<String> _typingUsers={};
  final _memberScroll = ScrollController();
  String? _focusedMember;
  double? _myPosition;
  String _pose = 'Relaxed';
  int _activeAt = DateTime.now().millisecondsSinceEpoch;
  Timer? _poseClock;
  String _poseSnapshot = '';
  final _memberPose = <String, Map<String, dynamic>>{};

  static const _props = <String,String>{
    'Beagle': 'beagle',
    'Tabby': 'tabby',
    'Lop Rabbit': 'lop_rabbit',
    'Cockatiel': 'cockatiel',
    'Guinea Pig': 'guinea_pig',
    'Red Panda': 'red_panda',
    'Snow Leopard': 'snow_leopard',
    'Fennec Fox': 'fennec_fox',
    'Clouded Leopard': 'clouded_leopard',
    'Arctic Wolf': 'arctic_wolf',
    'Motorbike': 'commuter',
    'Coast Cruiser': 'coast_cruiser',
    'Mint Hatch': 'mint_hatch',
    'Metro Sedan': 'metro_sedan',
    'Trail Compact': 'trail_compact',
    'Ember Sport': 'ember_sport',
    'Night Tourer': 'night_tourer',
    'Solar GT': 'solar_gt',
    'Pearl Roadster': 'pearl_roadster',
    'Summit SUV': 'summit_suv',
  };
  static const _pets = {'beagle', 'tabby', 'lop_rabbit', 'cockatiel', 'guinea_pig', 'red_panda', 'snow_leopard', 'fennec_fox', 'clouded_leopard', 'arctic_wolf'};
  String? _storeAvatar;
  final _layout = <String, Map<String, dynamic>>{};
  String? _editingProp;

  bool _publishing = false;
  bool _dirty = false;
  Timer? _syncRetry;
  int _retrySeconds = 1;

  Future<void> _shareLayout() async {
    _dirty = true;
    if (!mounted || !_canTrack || _publishing || _syncRetry != null) return;
    _publishing = true;
    try {
      while (mounted && _canTrack && _dirty) {
        _dirty = false;
        final response = await _roomPresence.publish(_presence);
        if (response != ChannelResponse.ok) throw StateError('Presence not acknowledged');
        _retrySeconds = 1;
      }
    } catch (_) {
      _dirty = true;
      if (mounted && _canTrack) {
        if (_retrySeconds == 4) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reconnecting to the room. Others may see your previous position.')));
        }
        _syncRetry = Timer(Duration(seconds:_retrySeconds), () {
          _syncRetry = null;
          if (mounted) unawaited(_shareLayout());
        });
        _retrySeconds = min(16, _retrySeconds * 2);
      }
    } finally {
      _publishing = false;
    }
  }

  final _enabledProps = <String>{};
  bool _canTrack = false;
  Timer? _expiry;
  int _inventoryRequest = 0;
  Future<void> _readEquipment() async {
    final user = _userId;
    if (user == null) return;
    final request = ++_inventoryRequest;
    try {
      final rows = await _supabase.from('store_inventory').select('item_id,expires_at')
        .eq('user_id',user).eq('equipped',true);
      if (!mounted || request != _inventoryRequest || _userId != user) return;
      final active = <String>{};
      DateTime? next;
      for (final row in rows) {
        final end = DateTime.tryParse(row['expires_at']?.toString() ?? '');
        if (end != null && !end.isAfter(DateTime.now())) continue;
        if (end != null && (next == null || end.isBefore(next))) next = end;
        active.add(row['item_id'].toString());
      }
      _expiry?.cancel();
      if (next != null) _expiry = Timer(next.difference(DateTime.now()),_readEquipment);
      setState(() {
        final equippedAvatar = active.where(storeAvatarIds.contains).firstOrNull;
        if (_storeAvatar != equippedAvatar) _pose = 'Relaxed';
        _storeAvatar = equippedAvatar;
        _enabledProps.clear();
        for (final entry in _props.entries) {
          if (active.contains(entry.value)) {
            _enabledProps.add(entry.key);
            _layout.putIfAbsent(entry.key,()=>{'x':_pets.contains(entry.value)?-.2:.6,'y':.96,'front':_pets.contains(entry.value)});
          } else {
            _layout.remove(entry.key);
            if (_editingProp==entry.key) _editingProp=null;
          }
        }
      });
      if (_canTrack) await _shareLayout();
    } on PostgrestException { /* Rooms also work before the store migration is installed. */ }
  }

  void _chooseProp(String action) {
    setState(() {
      if (_props.containsKey(action)) {
        _editingProp = action;
        _showPeople = true;
        _layout.putIfAbsent(action, () => {
          'x': _pets.contains(_props[action]) ? -.2 : .6, 'y': .96, 'front': _pets.contains(_props[action]),
        });
      } else if (action == 'Done') {
        _editingProp = null;
      } else if (action == 'Remove') {
        _layout.remove(_editingProp);
        _editingProp = null;
      } else if (_editingProp != null) {
        _layout[_editingProp]!['front'] = action == 'In front of me';
      }
    });
    unawaited(_shareLayout());
  }

  Iterable<Widget> _placedProps(List<int> indices, double width, double size, bool front) sync* {
    for (final index in indices) {
      final id = _roomPeople[index]['user_id']?.toString();
      final mine = id == _userId;
      final layout = mine ? _layout : _memberPose[id]?['props'];
      if (layout is! Map) continue;
      for (final entry in _props.entries) {
        final item = layout[entry.key];
        if (item is! Map || (item['front'] == true) != front) continue;
        final dx = item['x'], y = item['y'];
        if (dx is! num || y is! num || !dx.isFinite || !y.isFinite) continue;
        final pet = _pets.contains(entry.value);
        final w = size * (pet ? .48 : 1.06);
        final h = size * (pet ? .32 : .65);
        final origin = _avatarLeft(index, width) + size / 2;
        final left = (origin + dx * size - w / 2).clamp(0.0, width - w).toDouble();
        final top = (y * size - h).clamp(0.0, size - h).toDouble();
        final picture = _vivid(Image.asset('assets/store/${entry.value}.webp',
          fit: BoxFit.contain, alignment: Alignment.bottomCenter,
          semanticLabel: entry.key, filterQuality:FilterQuality.high));
        yield Positioned(key: ValueKey('$id-${entry.key}'), left: left, top: top + 25, width: w, height: h,
          child: mine && _editingProp == entry.key ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (event) => setState(() {
              final current = _layout[entry.key]!;
              final nextLeft = (left + event.delta.dx).clamp(0.0, width-w);
              final nextTop = (top + event.delta.dy).clamp(0.0, size-h);
              current['x'] = (nextLeft + w/2 - origin) / size;
              current['y'] = (nextTop + h) / size;
            }),
            onPanEnd: (_) => unawaited(_shareLayout()),
            child: picture,
          ) : IgnorePointer(child: picture));
      }
    }
  }

  Map<String, dynamic> get _presence => {'user_id': _userId, 'stage_x': _myPosition, 'pose': _pose, 'active_at': _activeAt, 'store_avatar': _storeAvatar, 'props': _layout};

  String _visiblePose(String id) {
    final payload = id == _userId ? _presence : _memberPose[id];
    final stamp = payload?['active_at'];
    final pose = payload?['pose'];
    final fighter = payload?['store_avatar'];
    if (fighter is String && storeAvatarIds.contains(fighter)) {
      return fighterPoseIndex(fighter, pose) != null || pose == 'Signature'
          ? pose as String : 'Relaxed';
    }
    if (stamp is! int || (!SpotmateAvatar.poses.containsKey(pose) && pose != 'Walk')) return 'Relaxed';
    final idle = DateTime.now().millisecondsSinceEpoch - stamp;
    if (idle >= 30000 || pose == 'Sit on chair') return 'Sit on chair';
    if (idle >= 15000) return pose == 'Namaste' ? 'Wave' : 'Namaste';
    return pose as String;
  }

  Future<void> _selectPose(String pose) async {
    if (!mounted) return;
    setState(() { _pose = pose; _activeAt = DateTime.now().millisecondsSinceEpoch; });
    await _shareLayout();
  }

  Future<void> _pickPose(String? animeId, Offset pressPosition) async {
    // Explore-style anchored popup: no bottom sheet or oversized preview.
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final tap = overlay.globalToLocal(pressPosition);
    final rect = RelativeRect.fromLTRB(
      tap.dx, tap.dy,
      (overlay.size.width - tap.dx).clamp(0.0, overlay.size.width).toDouble(),
      (overlay.size.height - tap.dy).clamp(0.0, overlay.size.height).toDouble(),
    );

    if (animeId == null) {
      final me = _roomPeople.where((row) => row['user_id'] == _userId);
      final profile = me.isEmpty ? null : me.first['user_profiles'] as Map?;
      final avatar = SpotmateAvatar.normalized(
        profile?['avatar_emoticon']?.toString() ?? 'boy_01');
      final character = HaloAvatarCatalog.characters[avatar] ??
          HaloAvatarCatalog.characters['boy_01']!;
      final index = (profile?['avatar_posture_index'] as num?)?.toInt() ?? 0;
      final rotate = profile?['avatar_posture_auto'] == true;
      final choice = await showMenu<int>(
        context: context,
        position: rect,
        constraints: const BoxConstraints(minWidth: 155, maxWidth: 215),
        items: [
          for (var i = 0; i < character.poses.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 34,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(i == index ? Icons.check_rounded : Icons.circle_outlined,
                    size: 14,
                    color: i == index
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent),
                const SizedBox(width: 7),
                Flexible(child: Text(
                  character.poses[i].substring(3).replaceAll('_', ' '),
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
          const PopupMenuDivider(height: 6),
          PopupMenuItem<int>(
            value: 5,
            height: 34,
            child: Row(children: [
              Icon(rotate ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded, size: 17),
              const SizedBox(width: 7),
              const Text('Auto · 30s', style: TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      );
      if (!mounted || choice == null || _userId == null) return;
      final nextIndex = choice == 5 ? index : choice;
      final nextRotate = choice == 5 ? !rotate : rotate;
      try {
        await _supabase.from('user_profiles').update({
          'avatar_posture_index': nextIndex,
          'avatar_posture_auto': nextRotate,
        }).eq('id', _userId!);
        if (!mounted) return;
        setState(() {
          for (final person in _roomPeople) {
            if (person['user_id'] == _userId &&
                person['user_profiles'] is Map) {
              (person['user_profiles'] as Map)['avatar_posture_index'] = nextIndex;
              (person['user_profiles'] as Map)['avatar_posture_auto'] = nextRotate;
            }
          }
        });
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save posture. Please retry.')));
      }
      return;
    }

    final poses = fighterPoses(animeId);
    final current = fighterPoseIndex(animeId, _pose);
    final selected = await showMenu<int>(
      context: context,
      position: rect,
      constraints: const BoxConstraints(minWidth: 155, maxWidth: 235),
      items: [
        for (var index = 0; index < poses.length; index++)
          PopupMenuItem<int>(
            value: index,
            height: 36,
            child: Row(children: [
              if (current == index) ...[
                const Icon(Icons.check, size: 14),
                const SizedBox(width: 7),
              ],
              Flexible(child: Text(poses[index], style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ],
    );
    if (selected != null && mounted && _storeAvatar == animeId) {
      await _selectPose('fighter:$selected');
    }
  }
  final Map<String, double> _positions = {};
  final _moveClock = Stopwatch()..start();
  int _lastMove = -3000;
  List<Map<String, dynamic>> _roomPeople = [];
  int _memberRequest = 0;
  bool _showPeople = true;
  bool _rosterReady = false;
  String? _activity;
  final List<({String message, DateTime time})> _roomActivityLog = [];
  bool _muteNotices = false;
  Timer? _activityTimer;
  String _cityPalette = 'teal';
  String _cityBackground = 'paper';
  String _cityBanner = 'none';
  bool _savingReaction = false;
  final Map<String, String> _myReactions = {};
  static const _reactionIcons = {
    'like':'👍', 'heart':'❤️', 'laugh':'😂', 'wow':'😮', 'sad':'😢', 'fire':'🔥',
  };
  List<Map<String, dynamic>> _messages = [];
  final Set<String> _pendingRequests = {};
  final Set<String> _connectedUsers = {};
  bool _loading = true;
  bool _sending = false;
  String? _replyId;
  String? _replyPreview;
  String? _replyAuthor;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _recordBytes = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _recordStream;
  StreamSubscription<void>? _playbackComplete;
  Timer? _voiceTimer;
  bool _recording = false;
  bool _mediaBusy = false;
  bool _clearing = false;
  String get _clearKey => 'room_clear_${widget.hotspotId}';
  bool _visibleMessage(Map<String,dynamic> row) {
    final value = _supabase.auth.currentUser?.userMetadata?[_clearKey];
    final cutoff = value is String ? DateTime.tryParse(value) : null;
    final time = DateTime.tryParse(row['created_at'].toString());
    return cutoff == null || time == null || time.isAfter(cutoff);
  }

  Future<void> _clearForMe() async {
    if (_clearing || _messages.isEmpty || _userId == null) return;
    final cutoff = _messages.last['created_at'].toString();
    _clearing = true;
    try {
      if (widget.isCityChat) {
        await _supabase.rpc('city_visit', params: {'p_room':widget.hotspotId,'p_action':'clear'});
        await _load(quiet:true);
      } else {
        await _supabase.auth.updateUser(UserAttributes(data: {_clearKey: cutoff}));
      }
      if (!mounted) return;
      setState(() { _messages.removeWhere((row) => !_visibleMessage(row)); _clearReply(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared for you')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not clear chat. Try again.')));
    } finally { _clearing = false; }
  }

  Future<void> _pickPack() async {
    if (_mediaBusy || _sending || _recording) return;
    final item = await chooseChatExpression(context);
    if (!mounted || item == null) return;
    if (item.path.startsWith('emoji/')) {
      final next = _messageController.text + item.symbol;
      if (next.length > 500) return;
      _messageController.value = TextEditingValue(text:next,selection:TextSelection.collapsed(offset:next.length));
      return;
    }
    setState(()=>_mediaBusy = true);
    try {
      final bytes = await item.bytes();
      await _uploadMedia(bytes, item.ext, item.mime, 'photo',
        label: item.path.startsWith('stickers/') ? 'Sticker' : 'GIF');
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not send chat media.')));
    } finally { if(mounted) setState(()=>_mediaBusy = false); }
  }
  Future<void> _showRichKeyboard() => showChatExpressionSheet(
    context,
    insertText: (text) {
      insertChatExpression(_messageController, text);
      _composerFocus.requestFocus();
    },
    sendSticker: (sticker) => _sendKeyboardImage(() => renderMemeSticker(sticker), 'image/png', sticker.label),
    sendGif: (gif) => _sendKeyboardImage(() => downloadChatGif(gif), 'image/gif', gif.title),
    openExistingPack: _pickPack,
  );

  Future<void> _sendKeyboardImage(
    Future<Uint8List> Function() load, String mime, String label,
  ) async {
    final extension = chatImageExtensions[mime];
    if (extension == null || _mediaBusy || _sending || _recording) return;
    setState(() => _mediaBusy = true);
    try {
      final bytes = await load();
      if (!mounted) return;
      if (bytes.isEmpty || bytes.length > 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 1 MB.');
      }
      await _uploadMedia(bytes, extension, mime, 'photo', label: label);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send this image. Try an image under 1 MB.')),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  String? _playingPath;
  final Map<String, Future<String>> _mediaLinks = {};
  final _messagesById = <String, Map<String, dynamic>>{};
  Timer? _reloadTimer;
  Future<void>? _loadingRoom;
  bool _reloadPending = false;

  void _scheduleRoomReload() {
    if (!mounted || _reloadTimer != null) return;
    _reloadTimer = Timer(const Duration(milliseconds: 350), () {
      _reloadTimer = null;
      unawaited(_load(quiet: true));
    });
  }

  void _refreshAvatarAfterAccountSave() {
    _rosterFetchedAt = null; // Bypass 20-second presence-roster cache.
    unawaited(_refreshPeople());
  }

  void _onProfileUpdated(PostgresChangePayload change) {
    final updated = change.newRecord;
    // A lobby member may not have sent any messages. Refresh the avatar
    // directly from user_profiles whenever their appearance is updated.
    if (_roomPeople.any((member) => member['user_id'] == updated['id']) &&
        const ['avatar_emoticon', 'avatar_type', 'profile_photo',
               'avatar_posture_index', 'avatar_posture_auto', 'profile_look']
            .any(updated.containsKey)) {
      _refreshAvatarAfterAccountSave();
    }
    for (final message in _messages.reversed) {
      if (message['sender_id'] != updated['id']) continue;
      final profile = message['user_profiles'] as Map?;
      if (const ['name', 'profile_photo', 'avatar_type', 'avatar_emoticon', 'username']
          .any((field) => updated.containsKey(field) && updated[field] != profile?[field])) {
        _scheduleRoomReload();
      }
      break;
    }
  }
  String? _roomOwnerId;
  bool _isRoomLocked=false;
  String _ownerName='Room owner';
  String _roomTheme='navy';
  bool _isModerator = false;
  final Map<String, Map<String,int>> _reactionCounts={};
  String? _loadError;

  String? get _userId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    avatarProfileUpdates.addListener(_refreshAvatarAfterAccountSave);
    if(widget.isCityChat){_displayGameRules();unawaited(_refreshGames());_gamePoll=Timer.periodic(const Duration(seconds:10),(_)=>_refreshGames());}
    storeChanges.addListener(_readEquipment);
    unawaited(_readEquipment());
    _playbackComplete = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
    _load();
    _loadRoomAccess();
    _profileChannel = _supabase.channel('hotspot-profiles-${widget.hotspotId}-$_subscriptionId')
      .onPostgresChanges(event:PostgresChangeEvent.update,schema:'public',
        table:'user_profiles', callback: _onProfileUpdated)
      .subscribe();
    _presenceListener = RoomPresenceListener(
      onRosterChanged: _refreshPeople,
      onTyping: _receiveTyping,
    );
    _roomPresence = RoomPresence.attach(
      client: _supabase,
      roomId: widget.hotspotId,
      isCity: widget.isCityChat,
      listener: _presenceListener,
    );
    unawaited(_refreshPeople());
    _channel = _supabase
        .channel('hotspot-messages-${widget.hotspotId}-$_subscriptionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspot_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'hotspot_id',
            value: widget.hotspotId,
          ),
          callback: (_) => _scheduleRoomReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspots',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.hotspotId,
          ),
          callback: (_) => _loadRoomAccess(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspot_message_reactions',
          callback: (payload) {
            final messageId = payload.newRecord['message_id'] ?? payload.oldRecord['message_id'];
            if (_messagesById.containsKey(messageId?.toString())) _scheduleRoomReload();
          },
        )
        .subscribe((status,error) async {
          _canTrack = status==RealtimeSubscribeStatus.subscribed;
          if(status==RealtimeSubscribeStatus.subscribed&&_userId!=null){
            // Recover missed changes after backgrounding or a network reconnect.
            _load(quiet: true);
            _loadRoomAccess();
            _syncRetry?.cancel();
            _syncRetry = null;
            await _shareLayout();
            if (!mounted) return;
            _poseClock ??= Timer.periodic(const Duration(seconds: 1), (_) { if (!mounted) return;
              final snapshot = _roomPeople.map((p) => _visiblePose(p['user_id'].toString())).join('|');
              if (snapshot != _poseSnapshot) setState(() => _poseSnapshot = snapshot); });
          }
        });
  }

  void _receiveTyping(Map<String, dynamic> payload) {
    final id = payload['user_id']?.toString();
    if (id == null || id == _userId || !mounted) return;
    setState(() {
      if (payload['active'] == true) {
        _typingUsers.add(id);
      } else {
        _typingUsers.remove(id);
      }
    });
    _clearTypingTimer?.cancel();
    _clearTypingTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(_typingUsers.clear);
    });
  }

  void _onTyping(String value){
    if(value.trim().isNotEmpty&&!_hasAnnouncedTyping){
      _hasAnnouncedTyping=true;
      _presenceChannel.sendBroadcastMessage(event:'typing',payload:{
        'user_id':_userId,'active':true,
      });
    }
    _typingTimer?.cancel();
    _typingTimer=Timer(const Duration(seconds:2),(){
      if(!_hasAnnouncedTyping)return;
      _hasAnnouncedTyping=false;
      _presenceChannel.sendBroadcastMessage(event:'typing',payload:{
        'user_id':_userId,'active':false,
      });
    });
  }

  Future<void> _loadRoomAccess() async {
    try {
      final row=await _supabase.from('hotspots')
        .select('owner_id,room_theme,is_locked,city_palette,city_background,city_banner').eq('id',widget.hotspotId).single();
      final roles=await _supabase.from('hotspot_room_roles')
        .select('user_id').eq('hotspot_id',widget.hotspotId)
        .eq('user_id',_userId!).limit(1);
      if(mounted)setState((){
        _roomOwnerId=row['owner_id']?.toString();
        _isRoomLocked=row['is_locked']==true;
        _roomTheme=row['room_theme']?.toString()??'navy';
        _isModerator=!widget.isCityChat && roles.isNotEmpty;
        _cityPalette=row['city_palette']?.toString() ?? 'teal';
        _cityBackground=row['city_background']?.toString() ?? 'paper';
        _cityBanner=row['city_banner']?.toString() ?? 'none';
      });
      if(_roomOwnerId!=null){
        final owner=await _supabase.from('user_profiles')
          .select('name').eq('id',_roomOwnerId!).maybeSingle();
        if(mounted)setState(()=>_ownerName=owner?['name']?.toString()??'Room owner');
      }
    }catch(_){}
  }
  Future<void> _toggleRoomLock() async {
    if(_roomOwnerId!=_userId)return;
    final desired=!_isRoomLocked;
    try{
      await _supabase.rpc('set_community_room_lock',params:{
        'p_hotspot_id':widget.hotspotId,'p_locked':desired,
      });
      if(mounted)setState(()=>_isRoomLocked=desired);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(desired
          ? 'Room locked to new members' : 'Room is open to everyone')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not change lock: $e')));
    }
  }
  bool get _canModerate=>!widget.isCityChat && _userId!=null &&
      (_roomOwnerId==_userId || _isModerator);

  Set<String> _rosterIds = const {};
  DateTime? _rosterFetchedAt;

  Future<void> _refreshPeople() async {
    final version = ++_memberRequest;
    final presence = _presenceChannel.presenceState();
    final ids = <String>{
      for (final group in presence ?? [])
        for (final entry in group.presences)
          if (entry.payload['user_id'] is String) entry.payload['user_id'] as String,
    };
    try {
      final fetchedAt = _rosterFetchedAt;
      final useCached = fetchedAt != null &&
          DateTime.now().difference(fetchedAt) < const Duration(seconds: 20) &&
          ids.length == _rosterIds.length && ids.containsAll(_rosterIds);
      final people = useCached ? List<Map<String, dynamic>>.of(_roomPeople) :
          ids.isEmpty ? <Map<String, dynamic>>[] : await selectOptionalColumn('profile_look',
          'user_id,user_profiles(id,name,profile_photo,profile_look,avatar_type,avatar_emoticon,avatar_posture_index,avatar_posture_auto)',
          (fields) => _supabase
          .from('hotspot_members')
          .select(fields)
          .eq('hotspot_id', widget.hotspotId)
          .eq('status', 'active')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .inFilter('user_id', ids.toList())
          .order('user_id'));
      if (!mounted || version != _memberRequest) return;
      if (!useCached) {
        _rosterIds = ids;
        _rosterFetchedAt = DateTime.now();
      }
      final positions = <String, double>{};
      final poses = <String, Map<String, dynamic>>{};
      for (final group in presence ?? []) {
        for (final entry in group.presences) {
          final id = entry.payload['user_id']?.toString();
          if (id != null) poses[id] = Map<String,dynamic>.from(entry.payload);
          final position = entry.payload['stage_x'];
          if (id != null && position is num && position.isFinite) {
            positions[id] = position.toDouble().clamp(0.0, 1.0).toDouble();
          }
        }
      }
      people.sort((a, b) => a['user_id'].toString().compareTo(b['user_id'].toString()));
      final previous = {for (final person in _roomPeople) person['user_id']: person};
      final current = {for (final person in people) person['user_id']: person};
      final entered = current.keys.where((id) => id != _userId && !previous.containsKey(id));
      final left = previous.keys.where((id) => id != _userId && !current.containsKey(id));
      final notices = <String>[
        for (final id in entered) "${current[id]?['user_profiles']?['name'] ?? 'Someone'} joined",
        for (final id in left) "${previous[id]?['user_profiles']?['name'] ?? 'Someone'} left",
      ];
      setState(() {
        _roomPeople = people;
        _positions..clear()..addAll(positions);
        _memberPose..clear()..addAll(poses);
        if (!_rosterReady && people.isNotEmpty) {
          final now = DateTime.now();
          _roomActivityLog.addAll(people.map((person) => (
            message: "${person['user_profiles']?['name'] ?? 'Someone'} is in the room",
            time: now,
          )));
        }
        if (_rosterReady && notices.isNotEmpty) {
          final now = DateTime.now();
          _roomActivityLog.insertAll(0, notices.map((notice) => (message: notice, time: now)));
          if (_roomActivityLog.length > 200) _roomActivityLog.removeRange(200, _roomActivityLog.length);
          _activity = notices.length <= 2 ? notices.join(' · ') : '${notices.length} room activity updates';
          _activityTimer?.cancel();
          _activityTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _activity = null);
          });
        }
        _rosterReady = true;
      });
    } catch (_) {
      // The next presence event retries the roster.
    }
  }

  Future<void> _inviteConnectionToCity() async {
    final person = await pickConnectedUser(context,
      excludedUserIds: _roomPeople.map((row) => row['user_id'].toString()).toSet());
    if (person == null || !mounted) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Sign in required');
      final data = jsonEncode({
        'room_id': widget.hotspotId,
        'room_name': widget.hotspotName,
        'region': widget.cityRegion,
      });
      await _supabase.from('messages').insert({
        'conversation_id': person.conversationId,
        'sender_id': user.id,
        'message': 'City room invite · ' + data,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${person.name}.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the invitation.')));
    }
  }

  void _showRoomActivity() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .55,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Room activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Joins and departures observed during this visit.',
                style: TextStyle(fontSize: 12, color: Color(0xFF746B74))),
            ),
            Expanded(child: _roomActivityLog.isEmpty
              ? const Center(child: Text('No room activity yet.'))
              : ListView.builder(
                  itemCount: _roomActivityLog.length,
                  itemBuilder: (context, index) {
                    final entry = _roomActivityLog[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(entry.message.endsWith(' joined') ? Icons.login :
                          entry.message.endsWith(' left') ? Icons.logout : Icons.person_outline),
                      title: Text(entry.message),
                      trailing: Text(TimeOfDay.fromDateTime(entry.time).format(context)),
                    );
                  },
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickReaction(String messageId) async {
    if (_userId == null || _savingReaction) return;
    final selected = _myReactions[messageId];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final reaction in _reactionIcons.entries)
            TextButton(
              onPressed: () => Navigator.pop(sheet, reaction.key),
              child: Text(reaction.value, style: const TextStyle(fontSize: 24)),
            ),
          if (selected != null)
            TextButton(onPressed: () => Navigator.pop(sheet, 'remove'),
              child: const Text('Remove reaction')),
        ],
      )),
    );
    if (!mounted || choice == null || _savingReaction) return;
    _savingReaction = true;
    try {
      await _supabase.rpc('spotmate_set_room_reaction', params: {
        'p_message': messageId,
        'p_reaction': choice == 'remove' || choice == selected ? null : choice,
      });
      await _load(quiet: true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save reaction. Try again.')));
    } finally {
      _savingReaction = false;
    }
  }

  double _avatarSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return min(MediaQuery.sizeOf(context).height * .21, width >= 700 ? 168.0 : width * .37).clamp(74.0, 180.0).toDouble();
  }

  void _focusPerson(String id) {
    final index = _roomPeople.indexWhere((person) => person['user_id'] == id);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This member is no longer in the room.')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _showPeople = true;
      _focusedMember = id;
    });
    _scrollToPerson(id);
  }

  void _scrollToPerson(String id, [int retries = 6]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedMember != id) return;
      if (!_memberScroll.hasClients) {
        if (retries > 0) Timer(const Duration(milliseconds: 70), () {
          if (!mounted || _focusedMember != id) return;
          _scrollToPerson(id, retries - 1);
          WidgetsBinding.instance.ensureVisualUpdate();
        });
        return;
      }
      final index = _roomPeople.indexWhere((person) => person['user_id'] == id);
      if (index < 0) return;
      final position = _memberScroll.position;
      final target = (_avatarLeft(index, position.viewportDimension + position.maxScrollExtent) -
          (position.viewportDimension - _avatarSize(context)) / 2)
          .clamp(0.0, position.maxScrollExtent).toDouble();
      _memberScroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  double _avatarLeft(int index, double stageWidth) {
    final size = _avatarSize(context);
    final id = _roomPeople[index]['user_id'].toString();
    final offset = id == _userId ? (_myPosition ?? _positions[id]) : _positions[id];
    return offset == null ? (12 + index * (size + 10)) % (stageWidth - size) : offset * (stageWidth - size);
  }

  Future<void> _moveAvatarTo(double fraction) async {
    final me = _userId;
    final channel = _channel;
    if (me == null || channel == null || !_roomPeople.any((p) => p['user_id'] == me)) return;
    final now = _moveClock.elapsedMilliseconds;
    if (now - _lastMove < 3000) return;
    _lastMove = now;
    if (_memberScroll.hasClients) {
      final view = _memberScroll.position;
      final size = _avatarSize(context);
      final center = fraction * (view.viewportDimension + view.maxScrollExtent - size) + size / 2;
      final relative = center - view.pixels;
      if (relative < view.viewportDimension * .25 || relative > view.viewportDimension * .75) {
        final target = (center - view.viewportDimension / 2).clamp(0.0, view.maxScrollExtent).toDouble();
        unawaited(_memberScroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic));
      }
    }
    setState(() {
      _myPosition = fraction;
      if (_storeAvatar == null) _pose = 'Relaxed';
      _activeAt = DateTime.now().millisecondsSinceEpoch;
      _positions[me] = fraction;
      _focusedMember = null;
    });
    await _shareLayout();
  }

  Widget _peopleStrip(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final size = _avatarSize(context);
    final colors = Theme.of(context).colorScheme;
    final indices = List<int>.generate(_roomPeople.length, (i) => i);
    final myIndex = indices.indexWhere((i) => _roomPeople[i]['user_id'] == _userId);
    if (myIndex >= 0) indices.insert(0, indices.removeAt(myIndex));
    final focused = indices.indexWhere((i) =>
        _roomPeople[i]['user_id'] == _focusedMember && _focusedMember != _userId);
    if (focused >= 0) indices.add(indices.removeAt(focused));
    return Material(
      color: colors.secondaryContainer,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 4, 0),
          child: Row(children: [
            Expanded(child: Text('In this room · ${_roomPeople.length}',
              style: Theme.of(context).textTheme.labelLarge)),
            if (myIndex >= 0 && _enabledProps.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Arrange lobby items',
                icon: const Icon(Icons.tune, size: 19),
                onSelected: _chooseProp,
                itemBuilder: (_) => [
                  for (final item in _enabledProps)
                    PopupMenuItem(value: item, child: Text('Position $item')),
                  if (_editingProp != null)
                    for (final action in ['Behind me', 'In front of me', 'Remove', 'Done'])
                      PopupMenuItem(value: action, child: Text(action)),
                ],
              ),
            IconButton(
              tooltip: _showPeople ? 'Hide room members' : 'Show room members',
              icon: Icon(_showPeople ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showPeople = !_showPeople),
            ),
          ]),
        ),
        if (_showPeople && !keyboardOpen && indices.isNotEmpty)
          SizedBox(
            height: size + 27,
            child: LayoutBuilder(builder: (context, constraints) {
              final stageWidth = _wallpaperCity == null
                  ? max(constraints.maxWidth, 24 + (indices.length + 2) * (size + 10))
                  : max(constraints.maxWidth, (size + 27) * 2928 / 352);
              double? tapX;
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus, PointerDeviceKind.trackpad}),
                child: SingleChildScrollView(
                  controller: _memberScroll,
                  scrollDirection: Axis.horizontal,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _editingProp == null || myIndex < 0 ? null : (details) {
                      final origin = _avatarLeft(myIndex, stageWidth) + size / 2;
                      setState(() {
                        final item = _layout[_editingProp]!;
                        item['x'] = (details.localPosition.dx - origin) / size;
                        item['y'] = ((details.localPosition.dy - 25) / size).clamp(0.0, 1.0);
                      });
                      unawaited(_shareLayout());
                    },
                    onDoubleTapDown: (details) => tapX = details.localPosition.dx,
                    onDoubleTap: () {
                      final x = tapX;
                      if (x != null) {
                        _moveAvatarTo(((x - size / 2) / (stageWidth - size))
                            .clamp(0.0, 1.0).toDouble());
                      }
                    },
                    child: SizedBox(
                      width: stageWidth,
                      height: size + 27,
                      child: Stack(children: [
                        if (_wallpaperCity case final city?) Positioned.fill(child: _wallpaper(city, lobby:true)),
                        ..._placedProps(indices, stageWidth, size, false),
                        for (final index in indices)
                          Positioned(
                            left: _avatarLeft(index, stageWidth),
                            bottom: 2,
                            width: size,
                            child: _roomAvatar(context, _roomPeople[index], size),
                          ),
                        ..._placedProps(indices, stageWidth, size, true),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          ),
      ]),
    );
  }

  String? get _wallpaperCity {
    final city = widget.cityRegion?.split('/').last.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    const aliases = {'delhi':'new_delhi','bangalore':'bengaluru','vizag':'visakhapatnam','cochin':'kochi'};
    final key = aliases[city] ?? city;
    return const {'kolkata', 'lucknow', 'coimbatore', 'chennai', 'jaipur', 'pune', 'mumbai', 'kochi', 'bengaluru', 'ahmedabad', 'new_delhi', 'vijayawada', 'visakhapatnam', 'warangal', 'hyderabad'}.contains(key) ? key : null;
  }

  Widget _wallpaper(String city, {required bool lobby}) {
    final file = lobby ? 'lobby/${city}_lobby_8x1' : 'chat/${city}_chat_16x9';
    return IgnorePointer(child: Image.asset('assets/wallpapers/$file.jpg', fit: BoxFit.cover,
      filterQuality: FilterQuality.high, excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink()));
  }

  Widget _vivid(Widget child) => ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      1.08,-.065,-.015,0,0,
      -.025,1.04,-.015,0,0,
      -.025,-.065,1.09,0,0,
      0,0,0,1,0,
    ]),
    child: child,
  );

  Widget _roomAvatar(BuildContext context, Map<String, dynamic> member, double size) {
    final profile = member['user_profiles'] as Map?;
    final id = member['user_id'].toString();
    final name = profile?['name']?.toString() ?? 'Room member';
    final look = id == _userId ? _storeAvatar : _memberPose[id]?['store_avatar'];
    final anime = look is String && storeAvatarIds.contains(look);
    final visiblePose = _visiblePose(id);
    final combatIndex = anime ? fighterPoseIndex(look, visiblePose) : null;

    final colors = Theme.of(context).colorScheme;
    // GestureDetector supports onLongPressStart (InkWell does not).
    // Keep the global press position for the anchored, Explore-style popup.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: id == _userId
          ? (details) => _pickPose(anime ? look : null, details.globalPosition)
          : null,
      onTap: id == _userId ? null : () => _showMember(id, name),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _focusedMember == id ? colors.primary : Colors.transparent),
        ),
        child: Column(mainAxisSize:MainAxisSize.min,children: [
          DecoratedBox(decoration:BoxDecoration(color:const Color(0xDC202524),borderRadius:BorderRadius.circular(10)),
            child:Padding(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
              child:Text(id == _userId ? 'You' : name,maxLines:1,overflow:TextOverflow.ellipsis,
                style:const TextStyle(color:Colors.white,fontSize:11)))),
          SizedBox.square(dimension:size,child:Stack(alignment:Alignment.bottomCenter,children:[
            Container(width:size*.33,height:3,decoration:const BoxDecoration(color:Color(0x33221C16),borderRadius:BorderRadius.all(Radius.elliptical(30,3)))),
            _vivid(anime ? (combatIndex == null
              ? StoreAvatar(look, size: size, signature: visiblePose == 'Signature')
              : SizedBox.square(dimension: size, child: FighterArtwork(look, pose: combatIndex)))
              : SpotmateAvatar(size: size, fullPortrait: true, posture: visiblePose,
            avatarType: 'emoticon',
            photoUrl: profile?['profile_photo'] as String?,
            emoticon: profile?['avatar_emoticon']?.toString() ?? 'boy_01',
            postureIndex:(profile?['avatar_posture_index'] as num?)?.toInt() ?? 0,
            autoChangePosture:profile?['avatar_posture_auto'] == true)),
          ])),
        ]),
      ),
    );
  }

  Future<void> _load({bool quiet = false}) async {
    final inFlight = _loadingRoom;
    if (inFlight != null) {
      _reloadPending = true;
      return inFlight;
    }
    final request = _fetchRoom(quiet: quiet);
    _loadingRoom = request;
    try {
      await request;
    } finally {
      _loadingRoom = null;
      if (_reloadPending) {
        _reloadPending = false;
        _scheduleRoomReload();
      }
    }
  }

  Future<void> _fetchRoom({required bool quiet}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final rows = await selectOptionalColumn('username',
          'id, sender_id, body, created_at, reply_to, deleted_at, media_path, media_kind, user_profiles!hotspot_messages_sender_id_fkey(name, profile_photo, avatar_type, avatar_emoticon, username)',
          (fields) => _supabase.from('hotspot_messages').select(fields)
              .eq('hotspot_id', widget.hotspotId)
              .order('created_at', ascending: false)
              .limit(100),
      );
      final ids=rows.map((r)=>r['id'].toString()).toList();
      final reactRows=ids.isEmpty ? <Map<String,dynamic>>[] :
        List<Map<String,dynamic>>.from(
          await _supabase.from('hotspot_message_reactions')
            .select('message_id,user_id,reaction').inFilter('message_id',ids));
      final counts=<String,Map<String,int>>{};
      final mine = <String, String>{};
      for(final react in reactRows){
        final id=react['message_id'].toString();
        final emoji=react['reaction'].toString();
        if (react['user_id'] == _userId) mine[id] = emoji;
        final group=counts.putIfAbsent(id,()=>{});
        group[emoji]=(group[emoji]??0)+1;
      }
      if (!mounted) return;
      setState(() {
        _reactionCounts..clear()..addAll(counts);
        _myReactions..clear()..addAll(mine);
        _messages = List<Map<String, dynamic>>.from(rows.reversed.where(_visibleMessage));
        _messagesById
          ..clear()
          ..addEntries(_messages.map((message) => MapEntry(message['id'].toString(), message)));
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load the conversation. Try again.';
        });
      }
    }
  }

  void _clearReply() {
    _replyId = null;
    _replyPreview = null;
    _replyAuthor = null;
  }

  Future<String> _signedMedia(String path) => _mediaLinks.putIfAbsent(path,
    () => _supabase.storage.from('room_media').createSignedUrl(path, 3600));

  Future<void> _uploadMedia(Uint8List bytes, String extension, String mime, String kind, {String? label}) async {
    final user = _userId;
    if (user == null) throw StateError('Sign in required');
    final reply = _replyId;
    final path = '${widget.hotspotId}/$user/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final bucket = _supabase.storage.from('room_media');
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    try {
      await _supabase.from('hotspot_messages').insert({
        'hotspot_id': widget.hotspotId, 'sender_id': user, 'reply_to': reply,
        'body': kind == 'voice' ? 'Voice note' : (label ?? 'Photo'),
        'media_path': path, 'media_kind': kind,
      });
    } catch (_) {
      try { await bucket.remove([path]); } catch (_) {}
      rethrow;
    }
    if (!mounted) return;
    if (_replyId == reply) setState(_clearReply);
    await _load(quiet: true);
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Future<void> _pickRoomPhoto({bool gifOnly = false}) async {
    if (_mediaBusy || _recording || _sending) return;
    setState(() => _mediaBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(withData: true, type: gifOnly ? FileType.custom : FileType.any, allowedExtensions: gifOnly ? ['gif'] : null);
      if (result == null || !mounted) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) throw const FormatException('Could not read image.');
      const maxSize = 5 * 1024 * 1024;
      if (bytes.length > maxSize) throw const FormatException('Choose an image under 5 MB.');
      final signature = bytes.length >= 6 ? String.fromCharCodes(bytes.take(6)) : '';
      if (signature == 'GIF87a' || signature == 'GIF89a') {
        await _uploadMedia(bytes, 'gif', 'image/gif', 'photo');
      } else {
        if (gifOnly) throw const FormatException('Choose a GIF file.');
        final image = await prepareSpotmateImage(bytes, maxBytes: maxSize);
        await _uploadMedia(image.bytes, image.extension, image.mimeType, 'photo');
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is FormatException ? error.message : 'Could not send photo.')));
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _startVoice() async {
    if (_mediaBusy || _recording || _sending) return;
    setState(() => _mediaBusy = true);
    try {
      if (!await _recorder.hasPermission()) throw StateError('Microphone permission is required.');
      if (!mounted) return;
      _recordBytes.clear();
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      if (!mounted) return;
      _recordStream = stream.listen(_recordBytes.add);
      setState(() => _recording = true);
      _voiceTimer = Timer(const Duration(seconds: 15), () => _finishVoice());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording. Check microphone permission.')));
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Uint8List _makeWav(Uint8List pcm) {
    final output = Uint8List(44 + pcm.length);
    final d = ByteData.sublistView(output);
    void ascii(int offset, String value) {
      for (var i=0; i<value.length; i++) output[offset+i]=value.codeUnitAt(i);
    }
    ascii(0,'RIFF'); d.setUint32(4,36+pcm.length,Endian.little);
    ascii(8,'WAVE'); ascii(12,'fmt ');
    d.setUint32(16,16,Endian.little);
    d.setUint16(20,1,Endian.little);
    d.setUint16(22,1,Endian.little);
    d.setUint32(24,16000,Endian.little);
    d.setUint32(28,32000,Endian.little);
    d.setUint16(32,2,Endian.little);
    d.setUint16(34,16,Endian.little);
    ascii(36,'data'); d.setUint32(40,pcm.length,Endian.little);
    output.setRange(44,output.length,pcm);
    return output;
  }

  Future<void> _finishVoice({bool cancel = false}) async {
    if (!_recording) return;
    _voiceTimer?.cancel();
    setState(() {
      _recording = false;
      _mediaBusy = true;
    });
    try {
      await _recorder.stop();
      await _recordStream?.cancel();
      _recordStream = null;
      final raw = _recordBytes.takeBytes();
      if (cancel || !mounted) return;
      if (raw.length < 3200) throw const FormatException('Record a longer voice note.');
      await _uploadMedia(_makeWav(raw), 'wav', 'audio/wav', 'voice');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is FormatException ? error.message : 'Could not send voice note.')));
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _playVoice(String path) async {
    try {
      if (_playingPath == path) {
        await _player.stop();
        if (mounted) setState(() => _playingPath = null);
        return;
      }
      final url = await _signedMedia(path);
      if (!mounted) return;
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playingPath = path);
    } catch (_) {
      _mediaLinks.remove(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play this voice note.')));
    }
  }

  final Set<String> _revealedImages = {};

  Widget _roomMedia(String path, String kind, String label) {
    if (kind == 'voice') return TextButton.icon(
      onPressed: () => _playVoice(path),
      icon: Icon(_playingPath == path ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: const Text('Voice note'),
    );
    if (label != 'Sticker' && label != 'GIF' && !_revealedImages.contains(path)) {
      return TextButton.icon(
        onPressed: () => setState(() => _revealedImages.add(path)),
        icon: const Icon(Icons.image_outlined),
        label: const Text('Show image'),
      );
    }
    return FutureBuilder<String>(
      key: ValueKey(path), future: _signedMedia(path),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Photo unavailable');
        if (!snapshot.hasData) return const SizedBox.square(
          dimension: 24, child: CircularProgressIndicator(strokeWidth: 2));
        final url = snapshot.data!;
        return InkWell(
          onTap: () => showDialog<void>(context: context, builder: (_) =>
            Dialog(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)))),
          child: ClipRRect(borderRadius: BorderRadius.circular(10),
            child: Image.network(url, width: 260, height: 180, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('Photo unavailable'))),
        );
      },
    );
  }

  Widget _quotedReply(String author, String text, Color accent) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .08),
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(author, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
      Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall),
    ]),
  );

  Future<void> _messageActions(Map<String, dynamic> message, String author) async {
    final id = message['id'].toString();
    final choice = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.add_reaction_outlined), title: const Text('React'),
          onTap: () => Navigator.pop(sheet, 'react')),
        ListTile(leading: const Icon(Icons.reply_outlined), title: const Text('Reply'),
          onTap: () => Navigator.pop(sheet, 'reply')),
        if (widget.isCityChat && _userId != null && message['sender_id'] == _userId)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete message'),
            onTap: () => Navigator.pop(sheet, 'delete'),
          ),
      ])),
    );
    if (!mounted) return;
    if (choice == 'react') await _pickReaction(id);
    if (choice == 'reply') _selectReply(message, author);
    if (choice == 'delete') await _deleteOwnMessage(id);
  }

  Future<void> _deleteOwnMessage(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed from the public chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final deleted = await _supabase.rpc('delete_own_city_message', params: {
        'p_room': widget.hotspotId,
        'p_message': id,
      });
      if (!mounted) return;
      if (_replyId == id) setState(_clearReply);
      await _load(quiet: true);
      if (deleted != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This message is no longer available.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete message. Try again.')),
      );
    }
  }

  void _mentionSender(String? displayName) {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) return;

    final prefix = '@$name ';
    final draft = _messageController.text;
    if (draft.trimRight() == '@$name' || draft.startsWith(prefix)) {
      _composerFocus.requestFocus();
      return;
    }
    if ((prefix + draft).characters.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shorten your message to add a mention.')),
      );
      return;
    }

    _messageController.value = TextEditingValue(
      text: prefix + draft,
      selection: TextSelection.collapsed(offset: prefix.length + draft.length),
    );
    _composerFocus.requestFocus();
  }

  void _selectReply(Map<String, dynamic> message, String author) {
    setState(() {
      _replyId = message['id'].toString();
      _replyAuthor = author;
      _replyPreview = message['body']?.toString() ?? 'Message';
    });
    _composerFocus.requestFocus();
  }

  void _displayGameRules() {
    _rulesTimer?.cancel();
    setState(() => _showGameRules = true);
    _rulesTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showGameRules = false);
    });
  }

  bool _showGameRules=false;
  bool _gameExpanded = false;
  Timer? _rulesTimer;
  String? _roundOutcome;
  final _games = ChatGameService();
  final _gameVisitStart = DateTime.now().toUtc();
  ChatGameSession? _game;
  List<String> _winnerLines = [];
  Timer? _gamePoll;
  bool _readingGames = false;
  Future<void> _refreshGames() async {
    if (_readingGames || !mounted) return;
    _readingGames = true;
    try {
      final state=await _gameAction('status');
      final raw=state['active_session'];
      final latest=raw is Map<String,dynamic>?ChatGameSession.fromJson(raw):null;
      final outcome=state['outcome'];
      if(mounted)setState((){
        _game=latest;
        if(outcome is Map && (DateTime.tryParse(outcome['at'].toString())?.isAfter(_gameVisitStart)??false)) {
          _roundOutcome=outcome['text']?.toString();
        }
      });
      final rows = await _supabase.from('chat_game_announcements').select()
        .eq('room_id',widget.hotspotId).gt('ends_at',_gameVisitStart.toIso8601String()).order('ends_at',ascending:false).limit(2);
      if(mounted)setState((){
        _game=latest;
        _winnerLines=rows.map((r)=>"${r['period']=='hour'?'Hourly':'Daily'} winners · ${(r['winners'] as List).join(', ')} · ${r['wins']} wins").toList();
      });
    } catch (_) { /* The next poll recovers after a reconnect. */ }
    finally { _readingGames=false; }
  }
  Future<Map<String,dynamic>> _gameAction(String action,{String? type}) async {
    return _games.roomAction(widget.hotspotId, action, gameType: type);
  }

  Future<void> _gameCommand(String action,{String? type}) async {
    try {
      final data=await _gameAction(action,type:type);
      if(!mounted)return;
      if(action=='results'){
        final rows=List<Map>.from(data['results'] as List);
        await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
          title:const Text('Room results'),
          content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
            children:[for(final period in ['hour','day']) ...[
              Text(period=='hour'?'This hour · Top 3':'Today · Top 3',style:Theme.of(dialog).textTheme.titleMedium),
              if(!rows.any((row)=>row['period']==period))const Text('No winners yet.'),
              for(final entry in rows.where((row)=>row['period']==period).toList().asMap().entries)
                Text('${entry.key+1}. ${entry.value['player']} · ${entry.value['wins']} wins'),
              const SizedBox(height:10),
            ]]),
          actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Close'))],
        ));
      }else{
        if(data['message'] case final String message){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
        }
        await _refreshGames();
      }
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Game request failed. Please try again.')));}
  }

  Future<void> _launchGames({bool change=false}) => ChatGameLauncherSheet.show(context,
    onSelectGame:(type)=>_gameCommand(change?'change':'start',type:type.id));
  Future<void> _guess(String text) async {
    try {
      final displayed = _game;
      if (displayed == null) return;
      final game = displayed.isActive
          ? displayed
          : await _games.fetchActiveSession(widget.hotspotId);
      if (game == null) return;
      await _games.submitGuessIfEligible(
        activeSession: game, messageText: text, displayName: 'Player',
      );
      await _refreshGames();
    }
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Message sent. The game could not score this answer.')));}
  }
  Future<void> _send() async {
    final body=_messageController.text.trim();
    final uid=_userId;
    if(uid==null||body.isEmpty||_sending||_mediaBusy||_recording||body.length>500)return;
    if(widget.isCityChat && const [r'\start',r'\stop',r'\change',r'\results',r'\rules'].contains(body.toLowerCase())){
      _messageController.clear();
      final command=body.substring(1).toLowerCase();
      if(command=='rules'){
        await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
          title: const Text('Chat game rules'),
          content: const SingleChildScrollView(child: Text(r'Use \start to play or resume and \stop to pause. Questions continue after a correct answer or timeout. Quiz questions last 90 seconds. Use \change after 5 completed questions, \results for the hourly and daily top 3, and \rules to see this again.')),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
        ));
        return;
      }
      if(command=='change'){await _launchGames(change:true);}else{await _gameCommand(command);}
      return;
    }
    setState(()=>_sending=true);
    try{
      await _supabase.from('hotspot_messages').insert({
        'hotspot_id':widget.hotspotId,
        'sender_id':uid,
        'body':body,
        'reply_to':_replyId,
      });
      if(!mounted)return;
      _messageController.clear();
      if (widget.isCityChat) unawaited(_guess(body));
      unawaited(_selectPose('Relaxed'));
      setState(_clearReply);
    }on PostgrestException catch(e){
      if(mounted){
        final text=e.message;
        final safeText=text.contains('Please slow down')
            ? 'Please allow a couple of seconds between messages.'
            : text.contains('Reply target is unavailable')
                ? 'That message is no longer available to reply to.'
                : text.contains('row-level security')||text.contains('permission denied')
                    ? 'You do not have permission to post here. Check whether the room is active.'
                    : 'Unable to send: $text';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(safeText)));
      }
      return;
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Connection error. Check your network and try again.')));
      return;
    }finally{
      if(mounted)setState(()=>_sending=false);
    }
    // Refresh errors must not be shown as failed sends after insertion succeeded.
    await _load(quiet:true);
    if(_scrollController.hasClients){
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration:const Duration(milliseconds:200),
        curve:Curves.easeOut);
    }
  }

  Future<void> _showMember(String targetId, String name) async {
    if (targetId.isEmpty || targetId == _userId) return;
    bool requested = _pendingRequests.contains(targetId);
    bool connected = _connectedUsers.contains(targetId);
    if (!requested && !connected) {
      try {
        final requests = await _supabase.from('connection_requests')
            .select('id')
            .eq('sender_id', _userId!)
            .eq('receiver_id', targetId)
            .eq('status', 'pending')
            .limit(1);
        final relationships = await _supabase.from('connections')
            .select('id')
            .or('and(user1_id.eq.${_userId!},user2_id.eq.$targetId),and(user1_id.eq.$targetId,user2_id.eq.${_userId!})')
            .limit(1);
        requested = requests.isNotEmpty;
        connected = relationships.isNotEmpty;
        if (requested) _pendingRequests.add(targetId);
        if (connected) _connectedUsers.add(targetId);
      } catch (_) {}
    }
    Map<String,dynamic>? freshProfile;
    try {
      freshProfile=await selectOptionalColumn('profile_look',
          'name,bio,profile_photo,profile_look,avatar_type,avatar_emoticon',
          (fields) => _supabase.from('user_profiles')
        .select(fields)
        .eq('id',targetId).maybeSingle());
    } catch (_) {}
    if (!mounted) return;
    final memberProfile=freshProfile;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(child:SpotmateAvatar(
              size:64,
              photoUrl:memberProfile?['profile_photo']?.toString(),
              avatarType:memberProfile?['avatar_type']?.toString() ?? 'emoticon',
              storeLook:memberProfile?['profile_look'] as String?,
              emoticon:memberProfile?['avatar_emoticon']?.toString() ?? 'boy_01',
            )),
            const SizedBox(height: 12),
            Text(memberProfile?['name']?.toString() ?? name,
              style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (requested || connected) ? null : () async {
                  Navigator.pop(ctx);
                  await _requestConnection(targetId, name);
                },
                icon: Icon(connected
                    ? Icons.check_circle_outline
                    : requested ? Icons.hourglass_bottom : Icons.person_add_alt_1),
                label: Text(connected
                    ? 'Already connected'
                    : requested ? 'Request pending' : 'Send private chat request'),
              ),
            ),
            if ((memberProfile?['bio']?.toString() ?? '').isNotEmpty)
              Padding(padding:const EdgeInsets.only(top:6),
                child:Text(memberProfile!['bio'].toString(),textAlign:TextAlign.center)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed:() {
                Navigator.pop(ctx);
                Navigator.push(context,MaterialPageRoute(
                  builder:(_)=>UserProfileDetailScreen(userId:targetId)));
              },
              icon:const Icon(Icons.account_circle_outlined),
              label:const Text('View full profile'),
            ),
            const Text('Private messages are available only after a connection request is accepted.',
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed:(){
                Navigator.pop(ctx);
                showSpotmateMemberActions(
                  context:context,client:_supabase,
                  hotspotId:widget.hotspotId,
                  memberId:targetId,memberName:name,
                  canModerate:_canModerate,isOwner:_roomOwnerId==_userId,
                );
              },
              icon:const Icon(Icons.more_horiz_rounded),
              label:const Text('Gift · Report · Block · Moderation'),
            ),
          ],
        ),
      ))),
    );
  }

  Future<void> _requestConnection(String targetId, String name) async {
    final uid = _userId;
    if (uid == null || uid == targetId || _pendingRequests.contains(targetId)) return;
    try {
      await _supabase.from('connection_requests').insert({
        'sender_id': uid,
        'receiver_id': targetId,
        'hotspot_id': widget.hotspotId,
        'status': 'pending',
      });
      _pendingRequests.add(targetId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection request sent to $name.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send request. You may already have a request with this person.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    avatarProfileUpdates.removeListener(_refreshAvatarAfterAccountSave);
    _reloadTimer?.cancel();
    _composerFocus.dispose();
    _rulesTimer?.cancel();
    _gamePoll?.cancel();
    storeChanges.removeListener(_readEquipment);
    _expiry?.cancel();
    _poseClock?.cancel();
    _typingTimer?.cancel();
    _clearTypingTimer?.cancel();
    _roomPresence.detach(_presenceListener);
    _channel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    _syncRetry?.cancel();
    _memberScroll.dispose();
    _voiceTimer?.cancel();
    _recordStream?.cancel();
    _playbackComplete?.cancel();
    _recorder.dispose();
    _player.dispose();
    _activityTimer?.cancel();
    super.dispose();
  }

  static const _styleOptions = <String, Map<String, String>>{
    'palette': {'teal': 'Muted teal', 'navy': 'Navy', 'charcoal': 'Charcoal'},
    'background': {'paper': 'Warm paper', 'mist': 'Cool mist', 'sand': 'Soft sand'},
    'banner': {'none': 'No banner', 'welcome': 'Welcome to the room', 'say_hello': 'Say hello'},
  };
  static const _styleCosts = {'palette': 10, 'background': 15, 'banner': 20};
  static const _styleLabels = {'palette': 'Room palette', 'background': 'Background', 'banner': 'Welcome banner'};
  static const _paletteColors = {'teal': Color(0xFFA8325C), 'navy': Color(0xFF315477), 'charcoal': Color(0xFF39434B)};
  static const _backgroundColors = {'paper': Color(0xFFFFF8F8), 'mist': Color(0xFFF1F5F5), 'sand': Color(0xFFF5EFE4)};

  String _purchaseId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _customize() async {
    final user = _userId;
    if (!widget.isCityChat || user == null) return;
    int? balance;
    try {
      final wallet = await _supabase.from('wallets').select('balance').eq('user_id', user).maybeSingle();
      balance = (wallet?['balance'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    if (!mounted) return;
    var category = 'palette';
    var option = _cityPalette;
    String currentFor(String key) => switch (key) {
      'background' => _cityBackground, 'banner' => _cityBanner, _ => _cityPalette,
    };
    final choice = await showModalBottomSheet<({String category, String value})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (context, update) {
        final cost = _styleCosts[category]!;
        final changed = option != currentFor(category);
        return SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Customize', style: Theme.of(context).textTheme.titleLarge),
            if (balance != null) Text('Balance: $balance SC'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Feature'),
              items: [for (final entry in _styleLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value))],
              onChanged: (key) {
                if (key == null) return;
                update(() {
                  category = key;
                  option = currentFor(key);
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: option,
              decoration: const InputDecoration(labelText: 'Style'),
              items: [for (final entry in _styleOptions[category]!.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value))],
              onChanged: (value) {
                if (value != null) update(() => option = value);
              },
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _backgroundColors[category == 'background' ? option : _cityBackground],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDADFD9)),
              ),
              child: Align(alignment: Alignment.centerLeft, child: Chip(
                backgroundColor: (_paletteColors[category == 'palette' ? option : _cityPalette] ??
                    const Color(0xFFA8325C)).withValues(alpha: .13),
                label: Text(category == 'banner' && option != 'none'
                    ? _styleOptions['banner']![option]! : 'Hello, everyone'),
              )),
            ),
            const SizedBox(height: 14),
            const Text('Changes are shared with everyone in this city chat.'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: !changed || (balance != null && balance < cost) ? null :
                () => Navigator.pop(sheet, (category: category, value: option)),
              child: Text('Apply · $cost SC'),
            ),
          ]),
        ));
      }),
    );
    if (!mounted || choice == null) return;
    final request = _purchaseId();
    try {
      await _supabase.rpc('customize_city_chat', params: {
        'p_room': widget.hotspotId, 'p_category': choice.category,
        'p_value': choice.value, 'p_request': request,
      });
      await _loadRoomAccess();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is PostgrestException && error.message == 'Insufficient credits'
          ? 'You don’t have enough credits.' : 'Could not apply this style.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF392733);
    const mint = Colors.white;
    final themeAccent=widget.isCityChat
        ? (_paletteColors[_cityPalette] ?? const Color(0xFFA8325C))
        : _roomTheme=='mint'
        ? const Color(0xFF176D5B)
        : _roomTheme=='sunset'
          ? const Color(0xFF974A3D)
          : _roomTheme=='violet'
            ? const Color(0xFF71429B)
            : ink;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _backgroundColors[_cityBackground] ?? const Color(0xFFFFF8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F8),
        automaticallyImplyLeading: !widget.isCityChat,
        title: widget.isCityChat ? TextButton.icon(
          onPressed: widget.onPickRegion,
          icon: const Icon(Icons.location_on_outlined),
          label: Text(widget.cityRegion!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.hotspotName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('${_roomPeople.length} online',
              style: const TextStyle(fontSize: 12, color: Color(0xFF746B74))),
        ]),
        actions:[
          if (widget.isCityChat) ...[
            IconButton(tooltip: 'Search', onPressed: widget.onSearch, icon: const Icon(Icons.search)),
            PopupMenuButton<String>(
              tooltip: 'Room options',
              onSelected: (choice) {
                if (choice == 'invite') {
                  _inviteConnectionToCity();
                } else if (choice == 'leave') {
                  CityVisitGate.leaveRoom(context);
                } else if (choice == 'activity') {
                  _showRoomActivity();
                } else if (choice == 'mute') { setState(()=>_muteNotices = !_muteNotices); } else if (choice == 'clear') { _clearForMe(); } else if (choice == 'customize') {
                  _customize();
                } else {
                  setState(() => _showPeople = !_showPeople);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value:'mute',child:Text(_muteNotices?'Unmute join and leave notices':'Mute join and leave notices')),
                const PopupMenuItem(value: 'invite', child: Text('Invite a connection')),
                const PopupMenuItem(value: 'activity', child: Text('Room activity')),
                const PopupMenuItem(value: 'leave', child: Text('Leave room')),
                const PopupMenuItem(value: 'customize', child: Text('Customize')),
                PopupMenuItem(value: 'members', child: Text('Room members')),
                PopupMenuItem(value: 'clear', child: Text('Clear chat for me')),
              ],
            ),
          ],
          if(!widget.isCityChat && _roomOwnerId!=null && _roomOwnerId==_userId) IconButton(
            tooltip:_isRoomLocked ? 'Unlock room' : 'Lock room',
            icon:Icon(_isRoomLocked?Icons.lock_rounded:Icons.lock_open_rounded),
            onPressed:_toggleRoomLock,
          ),
          if(!widget.isCityChat && _roomOwnerId!=null && _roomOwnerId==_userId) IconButton(
            tooltip:'Community settings',
            icon:const Icon(Icons.tune_rounded),
            onPressed:()=>Navigator.push(context,MaterialPageRoute(
              builder:(_)=>SpotmateRoomSettingsScreen(
                hotspotId:widget.hotspotId,roomName:widget.hotspotName),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isCityChat)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
              child: Row(children: [
                Expanded(child: Text(widget.hotspotName,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                Text('${_roomPeople.length} online',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF746B74))),
              ]),
            ),
          if (widget.isCityChat && _cityBanner != 'none')
            Padding(padding: const EdgeInsets.all(6),
              child: Text(_styleOptions['banner']?[_cityBanner] ?? '')),
          if (!widget.isCityChat) Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            color: const Color(0xFFE9F2EC),
            child:Row(children:[
              Icon(_isRoomLocked?Icons.lock_rounded:Icons.workspace_premium_rounded,
                color:const Color(0xFFB9821C),size:20),
              SizedBox(width: 9),
              const SizedBox(width:5),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('OWNER · $_ownerName',
                  style:const TextStyle(color:ink,fontSize:12,fontWeight:FontWeight.w800)),
                Text(_isRoomLocked
                  ? 'Locked: existing members can still chat'
                  : 'Open room · Tap a name for private connection requests',
                  style:const TextStyle(fontSize:11,color:ink)),
              ])),
            ]),
          ),
          Expanded(
            child: Stack(fit:StackFit.expand,children:[
              if (_wallpaperCity case final city?) Opacity(opacity:0.40,child:_wallpaper(city,lobby:false)),
              _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min, children: [
                          Text(_loadError!, textAlign: TextAlign.center),
                          TextButton(onPressed: () => _load(), child: const Text('Retry')),
                        ],
                      ))
                    : _messages.isEmpty
                        ? const Center(
                            child: Text('Say hi!', style: TextStyle(
                              fontWeight: FontWeight.w700, color: ink,
                            )),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final senderId = message['sender_id']?.toString() ?? '';
                              final mine = senderId == _userId;
                              final profile = message['user_profiles'] as Map<String, dynamic>?;
                              final name = profile?['name']?.toString() ?? 'Member';
                              final body = message['body']?.toString() ?? '';
                              final removed=message['deleted_at']!=null;
                              final replyId=message['reply_to']?.toString();
                              String? replyBody;
                              String? replyName;
                              final target = _messagesById[replyId];
                              if (target != null && _visibleMessage(target)) {
                                replyBody = target['deleted_at'] != null ? 'Message deleted' :
                                    target['body']?.toString();
                                final sender = target['user_profiles'] as Map?;
                                replyName = target['sender_id'] == _userId ? 'You' :
                                    sender?['name']?.toString();
                              }
                              final mediaPath = message['media_path'] as String?;
                              final mediaKind = message['media_kind'] as String?;
                              final counts=_reactionCounts[message['id']?.toString()] ?? {};
                              final created = DateTime.tryParse(
                                  message['created_at']?.toString() ?? '')?.toLocal();
                              final time = created == null ? '' :
                                  '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  if (!mine) ...[
                                    GestureDetector(
                                      onTap: () => _focusPerson(senderId),
                                      child:storeAvatarIds.contains(_memberPose[senderId]?['store_avatar']) ? StoreAvatar(_memberPose[senderId]!['store_avatar'] as String,size:26,portrait:true) : SpotmateAvatar(
                                        size:26,
                                        photoUrl:profile?['profile_photo']?.toString(),
                                        avatarType:profile?['avatar_type']?.toString() ?? 'photo',
                                        storeLook:profile?['profile_look'] as String?,
                                        emoticon:profile?['avatar_emoticon']?.toString() ?? 'smile',
                                      ),
                                    ),
                                    const SizedBox(width:8),
                                  ],
                                  Flexible(child: Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * .82),
                                  child: HorizontalSwipeAction(
                                    key: ValueKey(message['id']),
                                    onSwipe: removed ? null : () => _selectReply(message, mine ? 'You' : name),
                                    child: Container(
                                    margin: const EdgeInsets.only(bottom: 5),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: mine ? themeAccent.withOpacity(.12) : Colors.white,
                                      border: Border.all(color: const Color(0xFFE4ECEF)),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: mine || removed
                                              ? null
                                              : () => _mentionSender((profile?['username'] ?? profile?['name'])?.toString()),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            Text(mine ? 'You' : name,
                                              style: const TextStyle(color: ink,
                                                fontWeight: FontWeight.w800, fontSize: 12)),
                                            if(senderId==_roomOwnerId)...[
                                              const SizedBox(width:5),
                                              const Text('OWNER',style:TextStyle(
                                                color:Color(0xFFB9821C),fontSize:10,
                                                fontWeight:FontWeight.w900)),
                                            ],
                                          ]),
                                        ),
                                        const SizedBox(height: 2),
                                        if (replyId != null && !removed)
                                          _quotedReply(replyName ?? 'Earlier message',
                                            replyBody ?? (widget.isCityChat ? 'Earlier message' : 'Original message unavailable'), themeAccent),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: mine || removed || mediaPath != null
                                              ? null
                                              : () => _mentionSender((profile?['username'] ?? profile?['name'])?.toString()),
                                          onLongPress: removed ? null : () => _messageActions(message, mine ? 'You' : name),
                                          onSecondaryTap: removed ? null : () => _messageActions(message, mine ? 'You' : name),
                                          child: removed
                                            ? const Text('Message deleted', style: TextStyle(
                                                color: Colors.grey, fontStyle: FontStyle.italic))
                                            : mediaPath != null && mediaKind != null
                                              ? _roomMedia(mediaPath, mediaKind, body)
                                              : Text(body, style: const TextStyle(fontSize: 14, color: ink)),
                                        ),
                                        if (!removed && counts.isNotEmpty)
                                          Wrap(spacing: 4, children: [
                                            for (final entry in counts.entries)
                                              ActionChip(
                                                visualDensity: VisualDensity.compact,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                padding: EdgeInsets.zero,
                                                labelStyle: const TextStyle(fontSize: 11),
                                                label: Text('${_reactionIcons[entry.key] ?? entry.key} ${entry.value}'),
                                                onPressed: () => _pickReaction(message['id'].toString()),
                                              ),
                                          ]),
                                        if (time.isNotEmpty) ...[
                                          const SizedBox(height: 1),
                                          Text(time, style: const TextStyle(
                                              fontSize: 10, color: Color(0xFF746B74))),
                                        ],
                                      ],
                                    ),
                                  ),
                                )))),
                                ],
                              );
                            },
                          ),
          ])),
          if (_activity != null && !_muteNotices)
            Padding(padding: const EdgeInsets.all(4), child: Text(_activity!,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium)),
          if (_showGameRules)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFEAF5F0), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Expanded(child: Text(r'Games: \start to play, \stop to pause, \rules for help.',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12))),
                InkWell(onTap: () => setState(() => _showGameRules = false),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 17))),
              ]),
            ),
          if(_roundOutcome case final String outcome)Text(outcome,textAlign:TextAlign.center),
          for(final line in _winnerLines) Text(line,textAlign:TextAlign.center),
          if (_game case final game?)
            Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () => setState(() => _gameExpanded = !_gameExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.sports_esports_outlined, size: 18),
                    const SizedBox(width: 7),
                    Expanded(child: Text('${game.gameType.title} · tap to ${_gameExpanded ? 'hide' : 'show'} game',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    Icon(_gameExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                  ]),
                ),
              ),
              if (_gameExpanded)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .18),
                  child: SingleChildScrollView(child: ChatGameBotCard(
                    key: ValueKey(game.id), session: game, onExpired: _refreshGames,
                    onRequestHint: () async { await _games.requestHint(widget.hotspotId); await _refreshGames(); },
                  )),
                ),
            ]),
          _peopleStrip(context),
          if(_typingUsers.isNotEmpty)const Padding(
            padding:EdgeInsets.symmetric(vertical:4,horizontal:16),
            child:Align(alignment:Alignment.centerLeft,
              child:Text('Someone is typing...',style:TextStyle(
                color:Color(0xFF746B74),fontStyle:FontStyle.italic,fontSize:12))),
          ),
          if (_replyId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(child: _quotedReply(_replyAuthor ?? 'Message', _replyPreview ?? '', themeAccent)),
                IconButton(tooltip: 'Cancel reply', icon: const Icon(Icons.close),
                  onPressed: () => setState(_clearReply)),
              ]),
            ),
          if (_recording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Expanded(child: Text('Recording · up to 15 seconds')),
                TextButton(onPressed: () => _finishVoice(cancel: true), child: const Text('Discard')),
                TextButton(onPressed: _finishVoice, child: const Text('Send')),
              ]),
            ),
          if (_mediaBusy) const LinearProgressIndicator(),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              Expanded(child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD6E3DE))),
                child: Row(children: [
                  IconButton(tooltip: 'Emoji · hold for GIF and stickers',
                    visualDensity: VisualDensity.compact,
                    onLongPress: _pickPack,
                    onPressed: _showRichKeyboard,
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 21)),
                  Expanded(child: TextField(controller: _messageController, focusNode: _composerFocus, onChanged: _onTyping,
                    contentInsertionConfiguration: ContentInsertionConfiguration(
                        allowedMimeTypes: chatImageExtensions.keys.toList(growable: false),
                        onContentInserted: (content) {
                          final data = content.data;
                          if (data != null) {
                            _sendKeyboardImage(() async => data, content.mimeType, 'Image');
                          }
                        },
                      ),
                    minLines: 1, maxLines: 3, maxLength: 500, textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message',counterText: '',isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 9), border: InputBorder.none,
                      enabledBorder: InputBorder.none,focusedBorder: InputBorder.none),
                    onSubmitted: (_) => _send())),
                  if(widget.isCityChat) IconButton(tooltip:'Chat Games',visualDensity:VisualDensity.compact,onPressed:_launchGames,icon:const Icon(Icons.sports_esports_outlined,size:20)),
                  IconButton(tooltip: 'Attach image', visualDensity: VisualDensity.compact,
                    onPressed: _mediaBusy || _recording ? null : () => _pickRoomPhoto(),
                    icon: const Icon(Icons.attach_file, size: 20)),
                ]),
              )),
              const SizedBox(width: 4),
              ValueListenableBuilder<TextEditingValue>(valueListenable: _messageController,
                builder: (_, value, child) {
                  final send = value.text.trim().isNotEmpty;
                  return IconButton.filled(tooltip: send ? 'Send message' : 'Record voice note',
                    style: IconButton.styleFrom(backgroundColor: themeAccent,foregroundColor: mint),
                    onPressed: _sending || _mediaBusy || _recording ? null : send ? _send : _startVoice,
                    icon: Icon(send ? Icons.send_rounded : Icons.mic_none));
                }),
            ]),
          )),
        ],
      ),
    );
  }
}
