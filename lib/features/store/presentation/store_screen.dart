import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final storeChanges = ValueNotifier<int>(0);

class StoreScreen extends StatefulWidget {
 const StoreScreen({super.key,this.owned=false});
 final bool owned;
 @override State<StoreScreen> createState()=>_StoreState();
}

class _StoreState extends State<StoreScreen> {
 final db=Supabase.instance.client;
 final requests=<String,String>{};
 List<Map<String,dynamic>> items=[], owned=[];
 bool busy=false;
 String? error;
 int balance=0;
 static const groups=['Avatars','Costumes','Pets','Vehicles'];
 static const closets=['My avatars','Closet','My pets','My vehicles'];
 static const sheets=[['anime_male','anime_female'],['wardrobe','wardrobe_extra'],['pets'],['vehicles']];
 @override void initState(){super.initState();refresh();}
 Future<void> refresh() async {
  try{
   final u=db.auth.currentUser!.id;
   final rows=await db.from('store_items').select().order('title');
   final inventory=await db.from('store_inventory').select().eq('user_id',u);
   final wallet=await db.from('wallets').select('balance').eq('user_id',u).maybeSingle();
   if(mounted)setState((){items=rows;owned=inventory.where((row)=>row['expires_at']==null || DateTime.parse(row['expires_at'] as String).isAfter(DateTime.now())).toList();balance=wallet?['balance'] as int? ?? 0;error=null;});
  }catch(_){if(mounted)setState(()=>error='Store inventory is unavailable.');}
 }
 String requestId(){
  final r=Random.secure();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.split('').map((c)=>c=='x'?r.nextInt(16).toRadixString(16):c=='y'?(8+r.nextInt(4)).toRadixString(16):c).join();
 }
 Future<void> act(Map<String,dynamic> item,Map<String,dynamic>? stock) async {
  if(busy)return;
  setState(()=>busy=true);
  try{
   final id=item['id'] as String;
   if(widget.owned){
    await db.rpc('equip_store_item',params:{'p_item':id,'p_on':stock?['equipped']!=true});
   }else{
    const days=[1,3,7,0];
    final prices=item['prices'] as List;
    final duration=await showDialog<int>(context:context,builder:(ctx)=>SimpleDialog(title:Text('Buy ${item['title']}'),children:[
     Padding(padding:const EdgeInsets.symmetric(horizontal:24),child:Text('Balance: $balance credits')),
     for(var i=0;i<days.length;i++) SimpleDialogOption(onPressed:balance<(prices[i] as int)?null:()=>Navigator.pop(ctx,days[i]),child:Text('${days[i]==0?'Permanent':"${days[i]} day${days[i]==1?'':'s'}"} · ${prices[i]} credits')),
     SimpleDialogOption(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
    ]));
    if(duration==null||!mounted)return;
    final key='$id-$duration';
    await db.rpc('buy_store_item',params:{'p_item':id,'p_days':duration,'p_request':requests.putIfAbsent(key,requestId)});
    requests.remove(key);
   }
   storeChanges.value++;
   await refresh();
   if(mounted && !widget.owned)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Added to Owned items')));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is PostgrestException?e.message:'Could not complete the request. Please retry.')));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Widget row(Map<String,dynamic> item,Map<String,dynamic>? stock){
  final category=item['category'];
  final equipped=stock?['equipped']==true;
  final permanent=stock!=null&&stock['expires_at']==null;
  final label=widget.owned?(equipped?'Remove':category=='Costumes'?'Put on':'Show in lobby'):(permanent?'Owned':stock==null?'Buy':'Extend');
  return ListTile(title:Text(item['title'] as String),leading:category=='Costumes'?const Icon(Icons.checkroom):Image.asset('assets/store/${item['id']}.webp',width:50),
   subtitle:stock==null?null:Text(permanent?'Permanent':'Until ${DateTime.parse(stock['expires_at'] as String).toLocal().toString().split('.').first}'),
   trailing:TextButton(onPressed:busy||(!widget.owned&&permanent)?null:()=>act(item,stock),child:Text(label)));
 }
 @override Widget build(BuildContext context){
 final byId={for(final o in owned)o['item_id']:o};
 return DefaultTabController(length:4,child:Scaffold(appBar:AppBar(title:Text(widget.owned?'Owned items':'Store'),bottom:TabBar(isScrollable:true,tabs:[for(final name in widget.owned?closets:groups)Tab(text:name)])),
 body:TabBarView(children:[for(var i=0;i<4;i++)ListView(padding:const EdgeInsets.all(12),children:[
 if(error!=null)ListTile(title:Text(error!),trailing:TextButton(onPressed:refresh,child:const Text('Retry'))),
 for(final item in items.where((e)=>e['category']==groups[i]&&(!widget.owned||byId.containsKey(e['id']))))row(item,byId[item['id']]),
 if(widget.owned&&error==null&&!items.any((e)=>e['category']==groups[i]&&byId.containsKey(e['id'])))const Center(child:Text('No owned items here yet')),
 if(!widget.owned)for(final sheet in sheets[i])InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Scaffold(appBar:AppBar(title:Text(groups[i])),body:Center(child:InteractiveViewer(maxScale:8,child:Image.asset('assets/store/$sheet.webp')))))),child:Image.asset('assets/store/$sheet.webp')),
 ])])));
 }
}