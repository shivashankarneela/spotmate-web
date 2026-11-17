import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateCommunityHotspotScreen extends StatefulWidget {
  const CreateCommunityHotspotScreen({super.key,required this.cityId});
  final String cityId;
  @override
  State<CreateCommunityHotspotScreen> createState() => _CreateCommunityHotspotScreenState();
}

class _CreateCommunityHotspotScreenState extends State<CreateCommunityHotspotScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _client = Supabase.instance.client;
  int? _balance;
  bool _busy=false;
  @override
  void initState(){super.initState();_loadWallet();}
  Future<void> _loadWallet() async {
    final user=_client.auth.currentUser;
    if(user==null)return;
    try {
      final row=await _client.from('wallets').select('balance').eq('user_id',user.id).maybeSingle();
      if(mounted)setState(()=>_balance=(row?['balance'] as num?)?.toInt());
    }catch(_){}
  }
  Future<void> _create() async {
    final name=_name.text.trim(), description=_description.text.trim();
    if(name.length<4||name.length>60){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Use a room name between 4 and 60 characters.')));
      return;
    }
    if(description.length>300){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Description must be under 300 characters.')));
      return;
    }
    setState(()=>_busy=true);
    try{
      await _client.rpc('create_community_hotspot',params:{
        'p_city_id':widget.cityId,
        'p_name':name,
        'p_description':description,
      });
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Your community room is live for 7 days. 100 SC deducted.')));
      Navigator.of(context).pop(true);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not create room: $e')));
      await _loadWallet();
    }finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  void dispose(){_name.dispose();_description.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    const ink=Color(0xFF162544);
    return Scaffold(
      appBar:AppBar(title:const Text('Create community hotspot')),
      body:SingleChildScrollView(
        padding:const EdgeInsets.all(20),
        child: Center(child:ConstrainedBox(
          constraints:const BoxConstraints(maxWidth:540),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Container(
              padding:const EdgeInsets.all(18),
              decoration:BoxDecoration(color:ink,borderRadius:BorderRadius.circular(20)),
              child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Icon(Icons.forum_rounded,color:Color(0xFF35D6B4),size:34),
                SizedBox(height:12),
                Text('Your people. Your room.',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),
                SizedBox(height:6),
                Text('Create a community conversation for 7 days. Anyone signed in can discover and join the public chat.',style:TextStyle(color:Color(0xFFD6E0E9))),
              ]),
            ),
            const SizedBox(height:20),
            TextField(controller:_name,maxLength:60,textCapitalization:TextCapitalization.words,
              decoration:const InputDecoration(labelText:'Room name',hintText:'Hyderabad Night Owls')),
            const SizedBox(height:12),
            TextField(controller:_description,maxLength:300,maxLines:3,
              decoration:const InputDecoration(labelText:'About your room',hintText:'Who is this community for?')),
            const SizedBox(height:12),
            ListTile(
              tileColor:const Color(0xFFEAF8F4),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
              leading:const Icon(Icons.account_balance_wallet_outlined,color:ink),
              title:const Text('Creation cost: 100 SC'),
              subtitle:Text('Available: ${_balance == null ? 'Checking wallet...' : '$_balance SC'}'),
              trailing:const Text('7 DAYS',style:TextStyle(color:ink,fontWeight:FontWeight.bold)),
            ),
            const SizedBox(height:12),
            const Text('You will be charged only when the room is successfully created. Rooms cannot claim to be verified physical venues.',style:TextStyle(fontSize:12,color:Color(0xFF657087))),
            const SizedBox(height:25),
            FilledButton.icon(
              onPressed:_busy||(_balance!=null&&_balance!<100)?null:_create,
              icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.add_circle_outline),
              label:const Text('Create for 100 credits'),
              style:FilledButton.styleFrom(backgroundColor:ink,padding:const EdgeInsets.all(16)),
            ),
          ]),
        )),
      ),
    );
  }
}
