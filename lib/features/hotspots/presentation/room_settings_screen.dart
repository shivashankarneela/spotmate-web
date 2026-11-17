import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpotmateRoomSettingsScreen extends StatefulWidget {
  const SpotmateRoomSettingsScreen({super.key,required this.hotspotId,required this.roomName});
  final String hotspotId;
  final String roomName;
  @override State<SpotmateRoomSettingsScreen> createState()=>_SpotmateRoomSettingsScreenState();
}
class _SpotmateRoomSettingsScreenState extends State<SpotmateRoomSettingsScreen>{
  final client=Supabase.instance.client;
  Map<String,dynamic>? room;
  List<Map<String,dynamic>> bans=[];
  List<Map<String,dynamic>> moderators=[];
  List<Map<String,dynamic>> reports=[];
  bool loading=true;
  bool busy=false;
  String? message;

  Future<void> refresh() async {
    try{
      final r=await client.from('hotspots').select('id,name,room_theme,promoted_until,owner_id,expires_at')
        .eq('id',widget.hotspotId).single();
      final b=await client.from('hotspot_room_bans').select('user_id,reason,created_at').eq('hotspot_id',widget.hotspotId);
      final mods=await client.from('hotspot_room_roles').select('user_id').eq('hotspot_id',widget.hotspotId);
      final reportRows=await client.from('hotspot_room_reports')
        .select('id,reported_id,reason,created_at').eq('hotspot_id',widget.hotspotId)
        .eq('status','open').order('created_at',ascending:false).limit(30);
      if(mounted)setState((){
        room=r; bans=List<Map<String,dynamic>>.from(b);
        moderators=List<Map<String,dynamic>>.from(mods);
        reports=List<Map<String,dynamic>>.from(reportRows);
        loading=false;message=null;
      });
    }catch(e){if(mounted)setState((){loading=false;message='Unable to load room settings: $e';});}
  }
  @override void initState(){super.initState();refresh();}

  Future<void> customize(String action,String? value) async {
    setState(()=>busy=true);
    try{
      await client.rpc('customize_community_hotspot',params:{
        'p_hotspot_id':widget.hotspotId,'p_action':action,'p_value':value});
      await refresh();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Room updated. The credit charge is recorded in Account.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> manage(String action,String target) async{
    setState(()=>busy=true);
    try{
      await client.rpc('manage_community_room',params:{
        'p_hotspot_id':widget.hotspotId,'p_action':action,
        'p_target_id':target,'p_value':null});
      await refresh();
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    const ink=Color(0xFF162544);
    return Scaffold(
      appBar:AppBar(title:const Text('Community room settings')),
      body:loading?const Center(child:CircularProgressIndicator()):
      SingleChildScrollView(padding:const EdgeInsets.all(20),child:
        Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:540),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Text(widget.roomName,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800,color:ink)),
            const SizedBox(height:8),
            const Text('Only the owner can buy upgrades or appoint moderators. All changes are recorded.'),
            if(message!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(message!,style:const TextStyle(color:Colors.red))),
            const SizedBox(height:20),
            Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Text('Room themes · 30 SC',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
                const SizedBox(height:10),
                Wrap(spacing:9,runSpacing:9,children:['navy','mint','sunset','violet'].map((x)=>ChoiceChip(
                  label:Text(x.toUpperCase()),
                  selected:room?['room_theme']==x,
                  onSelected:busy||room?['room_theme']==x?null:(_)=>customize('theme',x),
                )).toList()),
              ],
            ))),
            const SizedBox(height:12),
            Card(child:ListTile(
              leading:const Icon(Icons.campaign_rounded),
              title:const Text('Promote room for one day'),
              subtitle:const Text('50 SC · Highlight in discovery, until room expiry'),
              trailing:FilledButton(onPressed:busy?null:()=>customize('promote',null),child:const Text('Promote')),
            )),
            const SizedBox(height:15),
            const Text('Moderators',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            if(moderators.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('No moderators assigned')),
            ...moderators.map((m)=>ListTile(
              leading:const Icon(Icons.shield_outlined),
              title:Text(m['user_id']?.toString()??'Unknown member'),
              trailing:IconButton(tooltip:'Remove moderator',onPressed:busy?null:()=>manage('remove_moderator',m['user_id'].toString()),
                icon:const Icon(Icons.remove_circle_outline)),
            )),
            const SizedBox(height:15),
            const Text('Reports to review',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            if(reports.isEmpty)const Padding(
              padding:EdgeInsets.all(12),child:Text('No open reports')),
            ...reports.map((report)=>Card(child:ListTile(
              title:Text('Member: ${report['reported_id']}',
                maxLines:1,overflow:TextOverflow.ellipsis),
              subtitle:Text(report['reason']?.toString()??'Room rules report'),
              trailing:TextButton(
                onPressed:busy?null:() async{
                  setState(()=>busy=true);
                  try{
                    await client.rpc('resolve_room_report',
                      params:{'p_report_id':report['id']});
                    await refresh();
                  }catch(e){
                    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content:Text('Review failed: $e')));
                  }finally{if(mounted)setState(()=>busy=false);}
                },
                child:const Text('Resolve'),
              ),
            ))),
            const SizedBox(height:18),
            const Text('Banned users',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            if(bans.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('No banned members')),
            ...bans.map((b)=>ListTile(
              title:Text(b['user_id']?.toString()??'Unknown member'),
              subtitle:Text(b['reason']?.toString()??'Room rules violation'),
              trailing:TextButton(onPressed:busy?null:()=>manage('unban',b['user_id'].toString()),child:const Text('Unban')),
            )),
            const SizedBox(height:12),
            const Text('To appoint a moderator or ban someone, open that member’s profile from the public chat and use the moderation menu.',style:TextStyle(color:Color(0xFF657087),fontSize:12)),
          ])),
        ),
      ),
    );
  }
}
