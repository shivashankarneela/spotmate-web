import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spotmate/core/widgets/spotmate_avatar.dart';
import 'package:spotmate/features/chat/presentation/room_member_actions.dart';
import 'package:spotmate/features/hotspots/presentation/room_settings_screen.dart';

/// A public, per-venue conversation. Members can read and post with a
/// Spotmate account; one-to-one chats still require an accepted request.
class HotspotPublicChatScreen extends StatefulWidget {
  const HotspotPublicChatScreen({
    super.key,
    required this.hotspotId,
    required this.hotspotName,
  });

  final String hotspotId;
  final String hotspotName;

  @override
  State<HotspotPublicChatScreen> createState() => _HotspotPublicChatScreenState();
}

class _HotspotPublicChatScreenState extends State<HotspotPublicChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;
  Timer? _typingTimer;
  Timer? _clearTypingTimer;
  bool _hasAnnouncedTyping=false;
  final Set<String> _typingUsers={};
  int _onlineMembers=0;
  List<Map<String, dynamic>> _messages = [];
  final Set<String> _pendingRequests = {};
  final Set<String> _connectedUsers = {};
  bool _loading = true;
  bool _sending = false;
  String? _replyId;
  String? _replyPreview;
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
    _load();
    _loadRoomAccess();
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
        .onPresenceSync((_){
          if(!mounted)return;
          final presenceData=_channel?.presenceState();
          setState(()=>_onlineMembers=presenceData?.length ?? 0);
        })
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
          if(status==RealtimeSubscribeStatus.subscribed&&_userId!=null){
            // Recover missed changes after backgrounding or a network reconnect.
            _load(quiet: true);
            _loadRoomAccess();
            await _channel?.track({
              'user_id':_userId,
              'online_at':DateTime.now().toIso8601String(),
            });
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
        .select('owner_id,room_theme,is_locked').eq('id',widget.hotspotId).single();
      final roles=await _supabase.from('hotspot_room_roles')
        .select('user_id').eq('hotspot_id',widget.hotspotId)
        .eq('user_id',_userId!).limit(1);
      if(mounted)setState((){
        _roomOwnerId=row['owner_id']?.toString();
        _isRoomLocked=row['is_locked']==true;
        _roomTheme=row['room_theme']?.toString()??'navy';
        _isModerator=roles.isNotEmpty;
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
  bool get _canModerate=>_userId!=null &&
      (_roomOwnerId==_userId || _isModerator);

  Future<void> _react(String messageId,String reaction) async {
    final uid=_userId;
    if(uid==null)return;
    try{
      await _supabase.from('hotspot_message_reactions')
        .delete().eq('message_id',messageId).eq('user_id',uid);
      await _supabase.from('hotspot_message_reactions').insert({
        'message_id':messageId,'user_id':uid,'reaction':reaction});
      await _load(quiet:true);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Unable to react: $e')));
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try{
      await _supabase.rpc('remove_hotspot_message',
        params:{'p_message_id':messageId});
      await _load(quiet:true);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not remove message: $e')));
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final rows = await _supabase
          .from('hotspot_messages')
          .select('id, sender_id, body, created_at, reply_to, deleted_at, user_profiles!hotspot_messages_sender_id_fkey(name, profile_photo, avatar_type, avatar_emoticon)')
          .eq('hotspot_id', widget.hotspotId)
          .order('created_at', ascending: false)
          .limit(100);
      final ids=rows.map((r)=>r['id'].toString()).toList();
      final reactRows=ids.isEmpty ? <Map<String,dynamic>>[] :
        List<Map<String,dynamic>>.from(
          await _supabase.from('hotspot_message_reactions')
            .select('message_id,reaction').inFilter('message_id',ids));
      final counts=<String,Map<String,int>>{};
      for(final react in reactRows){
        final id=react['message_id'].toString();
        final emoji=react['reaction'].toString();
        final group=counts.putIfAbsent(id,()=>{});
        group[emoji]=(group[emoji]??0)+1;
      }
      if (!mounted) return;
      setState(() {
        _reactionCounts..clear()..addAll(counts);
        _messages = List<Map<String, dynamic>>.from(rows.reversed);
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load the hotspot conversation. Try again.';
        });
      }
    }
  }

  Future<void> _send() async {
    final body=_messageController.text.trim();
    final uid=_userId;
    if(uid==null||body.isEmpty||_sending||body.length>500)return;
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
      setState((){
        _replyId=null;
        _replyPreview=null;
      });
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
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFE0F7F0),
              child: Icon(Icons.person_outline_rounded,
                  color: Color(0xFF162544), size: 30),
            ),
            const SizedBox(height: 12),
            Text(name, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
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
    _typingTimer?.cancel();
    _clearTypingTimer?.cancel();
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF162544);
    const mint = Color(0xFF35D6B4);
    final themeAccent=_roomTheme=='mint'
        ? const Color(0xFF176D5B)
        : _roomTheme=='sunset'
          ? const Color(0xFF974A3D)
          : _roomTheme=='violet'
            ? const Color(0xFF71429B)
            : ink;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F9),
      appBar: AppBar(
        backgroundColor:themeAccent.withOpacity(.08),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.hotspotName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('Public chat · $_onlineMembers online',
              style: const TextStyle(fontSize: 12, color: Color(0xFF657087))),
        ]),
        actions:[
          if(_roomOwnerId==_userId) IconButton(
            tooltip:_isRoomLocked ? 'Unlock room' : 'Lock room',
            icon:Icon(_isRoomLocked?Icons.lock_rounded:Icons.lock_open_rounded),
            onPressed:_toggleRoomLock,
          ),
          if(_roomOwnerId==_userId) IconButton(
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            color: const Color(0xFFEAF8F4),
            child:Row(children:[
              Icon(_isRoomLocked?Icons.lock_rounded:Icons.workspace_premium_rounded,
                color:const Color(0xFFB9821C),size:20),
              SizedBox(width: 9),
              const SizedBox(width:8),
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
            child: _loading
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
                              final name = profile?['name']?.toString() ?? 'Spotmate member';
                              final body = message['body']?.toString() ?? '';
                              final removed=message['deleted_at']!=null;
                              final replyId=message['reply_to']?.toString();
                              String? replyBody;
                              if(replyId!=null){
                                for(final m in _messages){
                                  if(m['id']?.toString()==replyId){
                                    replyBody=m['body']?.toString();
                                    break;
                                  }
                                }
                              }
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
                                      onTap:()=>_showMember(senderId,name),
                                      child:SpotmateAvatar(
                                        size:32,
                                        photoUrl:profile?['profile_photo']?.toString(),
                                        avatarType:profile?['avatar_type']?.toString() ?? 'photo',
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
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: mine ? themeAccent.withOpacity(.12) : Colors.white,
                                      border: Border.all(color: const Color(0xFFE4ECEF)),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: mine ? null : () => _showMember(senderId, name),
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
                                            if (!mine) ...[
                                              const SizedBox(width: 5),
                                              const Icon(Icons.person_add_alt_1,
                                                  size: 14, color: ink),
                                            ],
                                          ]),
                                        ),
                                        const SizedBox(height: 5),
                                        if(replyId!=null) Container(
                                          padding:const EdgeInsets.all(7),
                                          margin:const EdgeInsets.only(bottom:6),
                                          decoration:BoxDecoration(
                                            color:const Color(0xFFE8EEF3),
                                            borderRadius:BorderRadius.circular(8)),
                                          child:Text('Reply: ${replyBody??'Earlier message'}',
                                            maxLines:2,overflow:TextOverflow.ellipsis,
                                            style:const TextStyle(fontSize:11)),
                                        ),
                                        Text(body,style:TextStyle(fontSize:14,
                                          color:removed?Colors.grey:ink,
                                          fontStyle:removed?FontStyle.italic:FontStyle.normal)),
                                        if(!removed) Wrap(spacing:2,runSpacing:0,children:[
                                          for(final reaction in const ['like','heart','laugh','wow'])
                                            TextButton(
                                              onPressed:()=>_react(message['id'].toString(),reaction),
                                              child:Text('${{'like':'👍','heart':'❤️','laugh':'😄','wow':'😮'}[reaction]} ${counts[reaction]??''}',
                                                style:const TextStyle(fontSize:11)),
                                            ),
                                          IconButton(
                                            tooltip:'Reply',
                                            onPressed:()=>setState((){
                                              _replyId=message['id'].toString();
                                              _replyPreview=body;
                                            }),
                                            icon:const Icon(Icons.reply_rounded,size:18)),
                                          if(mine||_canModerate)IconButton(
                                            tooltip:'Remove message',
                                            onPressed:()=>_deleteMessage(message['id'].toString()),
                                            icon:const Icon(Icons.delete_outline,size:17)),
                                        ]),
                                        if (time.isNotEmpty) ...[
                                          const SizedBox(height: 5),
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
          ),
          if(_typingUsers.isNotEmpty)const Padding(
            padding:EdgeInsets.symmetric(vertical:4,horizontal:16),
            child:Align(alignment:Alignment.centerLeft,
              child:Text('Someone is typing...',style:TextStyle(
                color:Color(0xFF657087),fontStyle:FontStyle.italic,fontSize:12))),
          ),
          if(_replyId!=null) Container(
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),
            color:const Color(0xFFEAF8F4),
            child:Row(children:[
              const Icon(Icons.reply_rounded,color:ink),
              const SizedBox(width:8),
              Expanded(child:Text('Replying to: ${_replyPreview??''}',
                maxLines:1,overflow:TextOverflow.ellipsis)),
              IconButton(icon:const Icon(Icons.close),
                onPressed:()=>setState((){
                  _replyId=null;_replyPreview=null;
                })),
            ]),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(child: TextField(
                    controller: _messageController,
                    onChanged:_onTyping,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Say something to the hotspot...',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: themeAccent,
                      foregroundColor: mint,
                    ),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
