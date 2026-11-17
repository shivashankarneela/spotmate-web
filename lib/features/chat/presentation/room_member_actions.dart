import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showSpotmateMemberActions({
  required BuildContext context,
  required SupabaseClient client,
  required String hotspotId,
  required String memberId,
  required String memberName,
  required bool canModerate,
  required bool isOwner,
}) async {
  final uid=client.auth.currentUser?.id;
  if(uid==null||uid==memberId)return;
  Future<void> perform(String action) async {
    try{
      if(action=='report'){
        await client.from('user_reports').insert({
          'reporter_id':uid,'reported_id':memberId,
          'reason':'Inappropriate hotspot behaviour',
          'details':'Report from hotspot $hotspotId',
        });
        await client.from('hotspot_room_reports').insert({
          'hotspot_id':hotspotId,
          'reporter_id':uid,
          'reported_id':memberId,
          'reason':'Inappropriate hotspot behaviour',
        });
      }else if(action=='block'){
        await client.from('user_blocks').insert({
          'blocker_id':uid,'blocked_id':memberId,
        });
      }else{
        await client.rpc('manage_community_room',params:{
          'p_hotspot_id':hotspotId,'p_action':action,
          'p_target_id':memberId,'p_value':'Community rules violation',
        });
      }
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(action=='report'?'Report submitted':'Action completed')));
    }catch(e){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Action failed: $e')));
    }
  }
  await showModalBottomSheet<void>(
    context:context,
    showDragHandle:true,
    builder:(sheet)=>SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(18,8,18,28),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(memberName,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),
        ListTile(leading:const Icon(Icons.card_giftcard),
          title:const Text('Send a virtual gift'),
          onTap:() async{
            Navigator.pop(sheet);
            try{
              final gifts=await client.from('spotmate_gifts')
                .select('id,title,symbol,price_credits').eq('active',true).order('price_credits');
              if(!context.mounted)return;
              await showModalBottomSheet<void>(context:context,showDragHandle:true,
                builder:(giftSheet)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Text('Virtual gifts · Spotmate Credits',
                    style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
                  const Text('Gifts have no cash value.'),
                  ...gifts.map((gift)=>ListTile(
                    leading:Text(gift['symbol'].toString(),style:const TextStyle(fontSize:25)),
                    title:Text(gift['title'].toString()),
                    trailing:Text('${gift['price_credits']} SC'),
                    onTap:() async {
                      Navigator.pop(giftSheet);
                      try{
                        await client.rpc('send_spotmate_gift',params:{
                          'p_hotspot_id':hotspotId,
                          'p_recipient_id':memberId,
                          'p_gift_id':gift['id'],
                        });
                        if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content:Text('Gift sent successfully')));
                      }catch(e){
                        if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content:Text('Gift failed: $e')));
                      }
                    },
                  )),
                  const SizedBox(height:20),
                ])));
            }catch(e){
              if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content:Text('Gifts unavailable: $e')));
            }
          },
        ),
        ListTile(leading:const Icon(Icons.flag_outlined),title:const Text('Report user'),
          onTap:(){Navigator.pop(sheet);perform('report');}),
        ListTile(leading:const Icon(Icons.block),title:const Text('Block user'),
          onTap:(){Navigator.pop(sheet);perform('block');}),
        if(canModerate)ListTile(leading:const Icon(Icons.gavel_rounded),
          title:const Text('Ban from this room'),
          onTap:(){Navigator.pop(sheet);perform('ban');}),
        if(isOwner)ListTile(leading:const Icon(Icons.shield_outlined),
          title:const Text('Make room moderator'),
          onTap:(){Navigator.pop(sheet);perform('add_moderator');}),
      ]),
    )),
  );
}
