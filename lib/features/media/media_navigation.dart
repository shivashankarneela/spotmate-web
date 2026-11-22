import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat/presentation/chat_screen.dart';
import '../chat/presentation/hotspot_public_chat_screen.dart';
import '../live_tv/models/live_tv_models.dart';
import '../live_tv/screens/live_tv_player_screen.dart';
import '../live_tv/widgets/shared_live_tv_chat_card.dart';
import '../reels/models/reel_models.dart';
import '../reels/screens/reels_feed_screen.dart';
import '../reels/widgets/shared_reel_chat_card.dart';
import '../reels/widgets/youtube_shorts_player.dart';

import '../music_room/screens/music_room_hub_screen.dart';
import '../music_room/screens/music_room_live_screen.dart';
import '../music_room/services/music_room_service.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _name => _db.auth.currentUser?.userMetadata?['name']?.toString() ?? 'Listener';
Future<List<ConnectedSpotmateUser>> _contacts() async {
  final rows=await _db.rpc('spotmate_direct_inbox');
  return [for(final row in rows)
    ConnectedSpotmateUser(userId:row['other_id'],displayName:row['other_name']??'Connection',
      spotmateHandle:row['other_spotmate_id']??'',avatarUrl:row['other_photo'],chatThreadId:row['conversation_id'])];
}

void openReels(BuildContext context,String city,{String? reelId}) {
  Navigator.push(context,MaterialPageRoute(builder: (screen)=>ReelsFeedScreen(activeCity:city,initialReelId:reelId,
    loadConnectedUsers:_contacts,onOpenPrivateChat:(person)=>Navigator.push(screen,MaterialPageRoute(builder:(_)=>
      ChatScreen(conversationId:person.chatThreadId!,otherUserName:person.displayName,otherUserId:person.userId,otherUserPhoto:person.avatarUrl))))));
}

void openLiveTv(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => MusicRoomHubScreen(isTv: true, currentDisplayName: _name)));
}
Future<void> _shareChannel(BuildContext context,SharedLiveTvPayload payload) async {
  try {
    final people=await _contacts();
    if(!context.mounted)return;
    final person=await showModalBottomSheet<ConnectedSpotmateUser>(context:context,showDragHandle:true,
      builder:(sheet)=>SafeArea(child:ListView(shrinkWrap:true,children:[
        const ListTile(title:Text('Share channel')),
        if(people.isEmpty)const ListTile(title:Text('No connected chats yet')),
        for(final p in people)ListTile(title:Text(p.displayName),onTap:()=>Navigator.pop(sheet,p)),
      ])));
    if(person==null)return;
    await _db.from('messages').insert({'conversation_id':person.chatThreadId,'sender_id':_db.auth.currentUser!.id,
      'message':'Live TV · '+jsonEncode(payload.toJson())});
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Shared with ${person.displayName}')));
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not share channel.')));}
}

Widget? sharedMediaCard(BuildContext context,String text){
  if (text.startsWith('City room invite · ')) {
    try {
      final data = jsonDecode(text.substring('City room invite · '.length)) as Map<String, dynamic>;
      final roomId = data['room_id'] as String?;
      final roomName = data['room_name'] as String?;
      final region = data['region'] as String?;
      if (roomId == null || region == null ||
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(roomId)) return null;
      return Card(child: ListTile(
        leading: const Icon(Icons.forum_outlined),
        title: Text(roomName ?? 'City chat'),
        subtitle: Text(region),
        trailing: TextButton(child: const Text('Join'), onPressed: () async {
          try {
            final row = await _db.from('hotspots').select('id,name,is_city_chat')
              .eq('id', roomId).eq('is_city_chat', true).single();
            await _db.rpc('join_hotspot_room', params: {'p_hotspot_id': roomId});
            if (!context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) =>
              HotspotPublicChatScreen(hotspotId: roomId, hotspotName: row['name'].toString(), cityRegion: region)));
          } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not join this city room.')));
          }
        }),
      ));
    } on FormatException { return null; }
      on TypeError { return null; }
  }
  if (text.startsWith('YouTube reel · ')) {
    try {
      final data = jsonDecode(text.substring('YouTube reel · '.length)) as Map<String, dynamic>;
      final videoId = data['video_id'] as String?;
      if (videoId == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) return null;
      final title = data['title']?.toString() ?? 'YouTube video';
      final thumbnail = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      return Card(child: ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: const Text('YouTube video'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('YouTube video')),
          body: Center(child: AspectRatio(aspectRatio: 9 / 16, child:
            YouTubeShortsPlayer(youtubeVideoId: videoId, thumbnailUrl: thumbnail, isActive: true, isMuted: false))),
        ))),
      ));
    } on FormatException { return null; }
      on TypeError { return null; }
  }
  if (text.startsWith('Room invite · ')) {
    try {
      final data = jsonDecode(text.substring('Room invite · '.length)) as Map<String, dynamic>;
      final code = data['code'] as String?;
      final kind = data['kind'] as String?;
      final title = data['title'] as String?;
      if (code == null || code.isEmpty || (kind != 'tv' && kind != 'music')) return null;
      return Card(child: ListTile(
        leading: Icon(kind == 'tv' ? Icons.live_tv : Icons.headphones),
        title: Text(title ?? (kind == 'tv' ? 'Live TV room' : 'Music room')),
        subtitle: const Text('Room invitation'),
        trailing: TextButton(
          child: const Text('Join'),
          onPressed: () async {
            try {
              final service = MusicRoomService(roomKind: kind!);
              final room = await service.joinByCode(roomCode: code, displayName: _name);
              if (!context.mounted) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                MusicRoomLiveScreen(initialRoom: room, isTv: kind == 'tv', currentDisplayName: _name)));
            } catch (_) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not join. The room may be full or closed.')));
            }
          },
        ),
      ));
    } on FormatException { return null; }
      on TypeError { return null; }
  }
  final reel=text.startsWith('Reel · ');
  if(!reel && !text.startsWith('Live TV · '))return null;
  try{
    final data=jsonDecode(text.substring(text.indexOf(' · ')+3)) as Map<String,dynamic>;
    if(reel){
      final p=SharedReelPayload.tryParse(data);
      if(p!=null)return SharedReelChatCard(payload:p,onOpenReel:(id)=>openReels(context,p.cityTag,reelId:id));
    }else{
      final p=SharedLiveTvPayload.tryParse(data);
      if(p!=null)return SharedLiveTvChatCard(payload:p,onOpenChannel:(_)async{
        try{
          final row=await _db.from('spotmate_live_channels').select().eq('id',p.channelId).eq('is_live',true).single();
          if(context.mounted)Navigator.push(context,MaterialPageRoute(builder:(screen)=>LiveTvPlayerScreen(
            channel:LiveTvChannel.fromJson(row),currentDisplayName:_name,onShareChannel:(payload)=>_shareChannel(screen,payload))));
        }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Channel unavailable.')));}
      });
    }
  }on FormatException{return null;}on TypeError{return null;}
  return null;
}
