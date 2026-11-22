import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../chat/presentation/chat_screen.dart';
import '../live_tv/models/live_tv_models.dart';
import '../live_tv/screens/live_tv_player_screen.dart';
import '../live_tv/widgets/shared_live_tv_chat_card.dart';
import '../reels/models/reel_models.dart';
import '../reels/screens/reels_feed_screen.dart';
import '../reels/widgets/shared_reel_chat_card.dart';

import '../live_tv/screens/youtube_live_screen.dart';

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
  Navigator.push(context, MaterialPageRoute(builder: (_) => const YouTubeLiveScreen()));
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
