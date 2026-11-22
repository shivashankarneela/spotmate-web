import '../../../core/optional_column.dart';
import 'city_visit_gate.dart';
import 'package:spotmate/features/store/presentation/store_avatar.dart';
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

class _RoomBodyState extends State<_RoomBody> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
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
        final response = await _channel?.track(_presence);
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
        _storeAvatar = active.where(storeAvatarIds.contains).firstOrNull;
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
    if (stamp is! int || (!SpotmateAvatar.poses.containsKey(pose) && pose != 'Walk')) return 'Relaxed';
    final idle = DateTime.now().millisecondsSinceEpoch - stamp;
    if (idle >= 30000 || pose == 'Sit on chair') return 'Sit on chair';
    if (idle >= 15000) return payload?['store_avatar'] == null ? (pose == 'Namaste' ? 'Wave' : 'Namaste') : (pose == 'Signature' ? 'Relaxed' : 'Signature');
    return pose as String;
  }

  Future<void> _selectPose(String pose) async {
    if (!mounted) return;
    setState(() { _pose = pose; _activeAt = DateTime.now().millisecondsSinceEpoch; });
    await _shareLayout();
  }

  Future<void> _pickPose([String? animeId]) async {
    final result = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Change posture')),
        for (final pose in animeId == null ? SpotmateAvatar.poses.keys : const ['Relaxed', 'Signature'])
          ListTile(title: Text(animeId != null && pose == 'Signature' ? storeSignatureName(animeId) : pose), onTap: () => Navigator.pop(sheet, pose)),
      ])));
    if (result != null && mounted) await _selectPose(result);
  }
  final Map<String, double> _positions = {};
  final _moveClock = Stopwatch()..start();
  int _lastMove = -3000;
  List<Map<String, dynamic>> _roomPeople = [];
  int _memberRequest = 0;
  bool _showPeople = true;
  bool _rosterReady = false;
  String? _activity;
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
  bool _emojiTray = false;
  bool _stickers = false;
  bool _clearing = false;
  static const _stickerLabels = ['Hello!', 'High five!', 'Thanks!', 'Good vibes'];
  String get _clearKey => 'room_clear_${widget.hotspotId}';
  bool _visibleMessage(Map<String,dynamic> row) {
    final value = _supabase.auth.currentUser?.userMetadata?[_clearKey];
    final cutoff = value is String ? DateTime.tryParse(value) : null;
    final time = DateTime.tryParse(row['created_at'].toString());
    return cutoff == null || time == null || time.isAfter(cutoff);
  }

  String get _cityTitle {
    final city = (widget.cityRegion ?? '').split('/').last.trim();
    final title = widget.hotspotName.trim();
    if (city.isEmpty || title.toLowerCase().contains(city.toLowerCase())) return title;
    return title.isEmpty ? city : '$city · $title';
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
      await _uploadMedia(bytes,item.ext,item.mime,'photo');
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not send chat media.')));
    } finally { if(mounted) setState(()=>_mediaBusy = false); }
  }
  Future<void> _pickExpression() async {
    final kind = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final name in ['Chat media pack','Emoji','GIF','Sticker'])
          ListTile(title: Text(name), onTap: () => Navigator.pop(sheet,name)),
      ])));
    if (!mounted || kind == null) return;
    if (kind == 'Chat media pack') { await _pickPack(); return; }
    if (kind == 'GIF') { await _pickRoomPhoto(gifOnly: true); return; }
    setState(() { _stickers = kind == 'Sticker'; _emojiTray = true; });
  }

  Future<void> _sendSticker(String label) async {
    if (_mediaBusy || _sending || _recording) return;
    setState(() { _mediaBusy = true; _emojiTray = false; });
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final palette = [Colors.teal, Colors.deepPurple, Colors.indigo, Colors.pink];
      final index = _stickerLabels.indexOf(label);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(8,8,304,144),const Radius.circular(48)), Paint()..color=palette[index]);
      final painter = TextPainter(text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas,Offset((320-painter.width)/2,(160-painter.height)/2));
      final picture = recorder.endRecording();
      final image = await picture.toImage(320,160);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose(); picture.dispose(); painter.dispose();
      if (bytes == null) throw StateError('Sticker unavailable');
      await _uploadMedia(bytes.buffer.asUint8List(bytes.offsetInBytes,bytes.lengthInBytes),'png','image/png','photo');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send sticker.')));
    } finally { if (mounted) setState(() => _mediaBusy = false); }
  }
  String? _playingPath;
  final Map<String, Future<String>> _mediaLinks = {};
  int _loadVersion = 0;
  static const _emojis = ['😀','😂','❤️','👍','🙌','🎉','😍','👋','🔥','😮','😢','✨'];
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
    storeChanges.addListener(_readEquipment);
    unawaited(_readEquipment());
    _playbackComplete = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
    _load();
    _loadRoomAccess();
    _profileChannel = _supabase.channel('hotspot-profiles-${widget.hotspotId}')
      .onPostgresChanges(event:PostgresChangeEvent.update,schema:'public',
        table:'user_profiles',callback:(_)=>_load(quiet:true))
      .subscribe();
    _channel = _supabase
        .channel('hotspot-chat-${widget.hotspotId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspot_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'hotspot_id',
            value: widget.hotspotId,
          ),
          callback: (_) => _load(quiet: true),
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
            if (_messages.any((message) => message['id'] == messageId)) _load(quiet: true);
          },
        )
        .onPresenceSync((_) => _refreshPeople())
        .onBroadcast(event:'typing',callback:(payload){
          final id=payload['user_id']?.toString();
          if(id==null||id==_userId||!mounted)return;
          final active=payload['active']==true;
          setState((){
            if(active)_typingUsers.add(id);
            else _typingUsers.remove(id);
          });
          _clearTypingTimer?.cancel();
          _clearTypingTimer=Timer(const Duration(seconds:5),(){
            if(mounted)setState(()=>_typingUsers.clear());
          });
        })
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

  void _onTyping(String value){
    if(value.trim().isNotEmpty&&!_hasAnnouncedTyping){
      _hasAnnouncedTyping=true;
      _channel?.sendBroadcastMessage(event:'typing',payload:{
        'user_id':_userId,'active':true,
      });
    }
    _typingTimer?.cancel();
    _typingTimer=Timer(const Duration(seconds:2),(){
      if(!_hasAnnouncedTyping)return;
      _hasAnnouncedTyping=false;
      _channel?.sendBroadcastMessage(event:'typing',payload:{
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

  Future<void> _refreshPeople() async {
    final version = ++_memberRequest;
    final presence = _channel?.presenceState();
    final ids = <String>{
      for (final group in presence ?? [])
        for (final entry in group.presences)
          if (entry.payload['user_id'] is String) entry.payload['user_id'] as String,
    };
    try {
      final people = ids.isEmpty ? <Map<String, dynamic>>[] : await selectOptionalColumn('profile_look',
          'user_id,user_profiles(id,name,profile_photo,profile_look,avatar_type,avatar_emoticon)',
          (fields) => _supabase
          .from('hotspot_members')
          .select(fields)
          .eq('hotspot_id', widget.hotspotId)
          .eq('status', 'active')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .inFilter('user_id', ids.toList())
          .order('user_id'));
      if (!mounted || version != _memberRequest) return;
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
        if (_rosterReady && notices.isNotEmpty) {
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
      _pose = 'Relaxed';
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

    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onLongPress: id == _userId ? () => _pickPose(anime ? look : null) : null,
      onTap: id == _userId ? null : () => _showMember(id, name),
      borderRadius: BorderRadius.circular(12),
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
            _vivid(anime ? StoreAvatar(look, size:size, signature: _visiblePose(id) == 'Signature') : SpotmateAvatar(size: size, fullPortrait: true, posture: _visiblePose(id),
            avatarType: 'emoticon',
            photoUrl: profile?['profile_photo'] as String?,
            emoticon: profile?['avatar_emoticon']?.toString() ?? 'boy_01')),
          ])),
        ]),
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text('This removes the message from the room for everyone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
      ],
    ));
    if (!mounted || confirm != true) return;
    try{
      await _supabase.rpc('remove_hotspot_message',
        params:{'p_message_id':messageId});
      if (mounted && _replyId == messageId) setState(_clearReply);
      await _load(quiet:true);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not remove message: $e')));
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final version = ++_loadVersion;
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('hotspot_messages')
          .select('id, sender_id, body, created_at, reply_to, deleted_at, media_path, media_kind, user_profiles!hotspot_messages_sender_id_fkey(name, profile_photo, avatar_type, avatar_emoticon)')
          .eq('hotspot_id', widget.hotspotId)
          .order('created_at', ascending: false)
          .limit(100);
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
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _reactionCounts..clear()..addAll(counts);
        _myReactions..clear()..addAll(mine);
        _messages = List<Map<String, dynamic>>.from(rows.reversed.where(_visibleMessage));
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted && version == _loadVersion) {
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

  Future<void> _uploadMedia(Uint8List bytes, String extension, String mime, String kind) async {
    final user = _userId;
    if (user == null) throw StateError('Sign in required');
    final reply = _replyId;
    final path = '${widget.hotspotId}/$user/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final bucket = _supabase.storage.from('room_media');
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    try {
      await _supabase.from('hotspot_messages').insert({
        'hotspot_id': widget.hotspotId, 'sender_id': user, 'reply_to': reply,
        'body': kind == 'voice' ? 'Voice note' : 'Photo',
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

  Widget _roomMedia(String path, String kind) {
    if (kind == 'voice') return TextButton.icon(
      onPressed: () => _playVoice(path),
      icon: Icon(_playingPath == path ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: const Text('Voice note'),
    );
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
    final canRemove = message['sender_id'] == _userId || _canModerate;
    final choice = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.add_reaction_outlined), title: const Text('React'),
          onTap: () => Navigator.pop(sheet, 'react')),
        ListTile(leading: const Icon(Icons.reply_outlined), title: const Text('Reply'),
          onTap: () => Navigator.pop(sheet, 'reply')),
        if (canRemove) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'),
          onTap: () => Navigator.pop(sheet, 'delete')),
      ])),
    );
    if (!mounted) return;
    if (choice == 'react') await _pickReaction(id);
    if (choice == 'delete') await _deleteMessage(id);
    if (choice == 'reply') setState(() {
      _replyId = id;
      _replyAuthor = author;
      _replyPreview = message['body']?.toString() ?? 'Message';
    });
  }

  Future<void> _send() async {
    final body=_messageController.text.trim();
    final uid=_userId;
    if(uid==null||body.isEmpty||_sending||_mediaBusy||_recording||body.length>500)return;
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
  void dispose() {
    storeChanges.removeListener(_readEquipment);
    _expiry?.cancel();
    _poseClock?.cancel();
    _typingTimer?.cancel();
    _clearTypingTimer?.cancel();
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
  static const _paletteColors = {'teal': Color(0xFF147D72), 'navy': Color(0xFF315477), 'charcoal': Color(0xFF39434B)};
  static const _backgroundColors = {'paper': Color(0xFFFAF8F3), 'mist': Color(0xFFF1F5F5), 'sand': Color(0xFFF5EFE4)};

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
                    const Color(0xFF147D72)).withValues(alpha: .13),
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
    const ink = Color(0xFF202B30);
    const mint = Colors.white;
    final themeAccent=widget.isCityChat
        ? (_paletteColors[_cityPalette] ?? const Color(0xFF147D72))
        : _roomTheme=='mint'
        ? const Color(0xFF176D5B)
        : _roomTheme=='sunset'
          ? const Color(0xFF974A3D)
          : _roomTheme=='violet'
            ? const Color(0xFF71429B)
            : ink;
    return Scaffold(
      backgroundColor: _backgroundColors[_cityBackground] ?? const Color(0xFFFAF8F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F3),
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF657087))),
        ]),
        actions:[
          if (widget.isCityChat) ...[
            IconButton(tooltip: 'Search', onPressed: widget.onSearch, icon: const Icon(Icons.search)),
            PopupMenuButton<String>(
              tooltip: 'Room options',
              onSelected: (choice) {
                if (choice == 'mute') { setState(()=>_muteNotices = !_muteNotices); } else if (choice == 'clear') { _clearForMe(); } else if (choice == 'customize') {
                  _customize();
                } else {
                  setState(() => _showPeople = !_showPeople);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value:'mute',child:Text(_muteNotices?'Unmute join and leave notices':'Mute join and leave notices')),
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
            ListTile(
              dense: true,
              title: Text(_cityTitle, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text('${_roomPeople.length} online'),
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
                            child: Padding(
                              padding: EdgeInsets.all(25),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      color: ink, size: 46),
                                  SizedBox(height: 12),
                                  Text('Start the conversation',
                                      style: TextStyle(fontSize: 18,
                                          fontWeight: FontWeight.w700, color: ink)),
                                  SizedBox(height: 6),
                                  Text('Say hello, ask what is happening, or share a friendly recommendation.',
                                      textAlign: TextAlign.center),
                                ],
                              ),
                            ),
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
                              if (replyId != null) {
                                for (final target in _messages) {
                                  if (target['id']?.toString() != replyId) continue;
                                  replyBody = target['deleted_at'] != null ? 'Message deleted' :
                                      target['body']?.toString();
                                  final sender = target['user_profiles'] as Map?;
                                  replyName = target['sender_id'] == _userId ? 'You' :
                                      sender?['name']?.toString();
                                  break;
                                }
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
                                          onTap: mine ? null : () => _focusPerson(senderId),
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
                                          onTap: mine ? null : () => _focusPerson(senderId),
                                          onLongPress: removed ? null : () => _messageActions(message, mine ? 'You' : name),
                                          onSecondaryTap: removed ? null : () => _messageActions(message, mine ? 'You' : name),
                                          child: removed
                                            ? const Text('Message deleted', style: TextStyle(
                                                color: Colors.grey, fontStyle: FontStyle.italic))
                                            : mediaPath != null && mediaKind != null
                                              ? _roomMedia(mediaPath, mediaKind)
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
                                              fontSize: 10, color: Color(0xFF657087))),
                                        ],
                                      ],
                                    ),
                                  ),
                                ))),
                                ],
                              );
                            },
                          ),
          ])),
          if (_activity != null && !_muteNotices)
            Padding(padding: const EdgeInsets.all(4), child: Text(_activity!,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium)),
          _peopleStrip(context),
          if(_typingUsers.isNotEmpty)const Padding(
            padding:EdgeInsets.symmetric(vertical:4,horizontal:16),
            child:Align(alignment:Alignment.centerLeft,
              child:Text('Someone is typing...',style:TextStyle(
                color:Color(0xFF657087),fontStyle:FontStyle.italic,fontSize:12))),
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
          if (_emojiTray)
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                if (_stickers) for (final label in _stickerLabels) ActionChip(label: Text(label), onPressed: () => _sendSticker(label)),
                if (!_stickers) for (final emoji in _emojis)
                  TextButton(onPressed: () {
                    final next = _messageController.text + emoji;
                    if (next.length <= 500) {
                      _messageController.value = TextEditingValue(
                        text: next, selection: TextSelection.collapsed(offset: next.length));
                    }
                  }, child: Text(emoji, style: const TextStyle(fontSize: 20))),
              ]),
            ),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              Expanded(child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD6E3DE))),
                child: Row(children: [
                  IconButton(tooltip: 'Emoji · hold for GIF and stickers',
                    visualDensity: VisualDensity.compact,
                    onLongPress: _pickExpression,
                    onPressed: () => setState(() { _emojiTray = _stickers || !_emojiTray; _stickers = false; }),
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 21)),
                  Expanded(child: TextField(controller: _messageController, onChanged: _onTyping,
                    minLines: 1, maxLines: 3, maxLength: 500, textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message',counterText: '',isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 9), border: InputBorder.none,
                      enabledBorder: InputBorder.none,focusedBorder: InputBorder.none),
                    onSubmitted: (_) => _send())),
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
