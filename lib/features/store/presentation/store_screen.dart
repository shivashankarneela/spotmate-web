import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
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
 final pendingPurchases = SharedPreferencesAsync();
 List<Map<String,dynamic>> items=[], owned=[];
 bool busy=false;
 String? error;
 int balance=0;
 static const groups=['Avatars','Pets','Vehicles'];
 static const closets=['My avatars','My pets','My vehicles'];
 @override void initState(){super.initState();refresh();}
 Future<void> refresh() async {
  try{
   final u=db.auth.currentUser!.id;
   final rows=await db.from('store_items').select().inFilter('category',groups).order('title');
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
    final on = stock?['equipped'] != true;
    if (item['category']=='Avatars') {
      final everywhere = on ? await showDialog<bool>(context:context,builder:(ctx)=>SimpleDialog(
        title:const Text('Where should this look appear?'),
        children:[
          SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Use in rooms')),
          if (stock?.containsKey('show_on_profile') == true) SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Use everywhere · rooms, profile and chats')),
        ])) : false;
      if(everywhere==null || !mounted)return;
      if (stock?.containsKey('show_on_profile') != true) {
        await db.rpc('equip_store_item', params:{'p_item':id,'p_on':on});
      } else {
        try {
          await db.rpc('set_store_appearance',params:{'p_item':id,'p_on':on,'p_everywhere':everywhere});
        } on PostgrestException catch (error) {
          if (error.code != 'PGRST202' || !error.message.contains('set_store_appearance')) rethrow;
          if (everywhere) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Profile styling is unavailable. Choose Use in rooms to wear this item.')));
            return;
          }
          await db.rpc('equip_store_item',params:{'p_item':id,'p_on':on});
        }
      }
    }else{
      await db.rpc('equip_store_item',params:{'p_item':id,'p_on':on});
    }
   }else{
    const days=[1,3,7,0];
    final prices=item['prices'] as List;
    final user = db.auth.currentUser!.id;
    final pending = await pendingPurchases.getKeys();
    if (!mounted || db.auth.currentUser?.id != user) return;
    final duration=await showDialog<int>(context:context,builder:(ctx)=>SimpleDialog(title:Text('Buy ${item['title']}'),children:[
     Padding(padding:const EdgeInsets.symmetric(horizontal:24),child:Text('Balance: $balance credits')),
     for(var i=0;i<days.length;i++) SimpleDialogOption(onPressed:balance<(prices[i] as int) && !pending.contains('store.pending.$user.$id.${days[i]}')?null:()=>Navigator.pop(ctx,days[i]),child:Text('${days[i]==0?'Permanent':"${days[i]} day${days[i]==1?'':'s'}"} · ${prices[i]} credits')),
     SimpleDialogOption(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
    ]));
    if(duration==null||!mounted)return;
    final key = 'store.pending.$user.$id.$duration';
    final saved = await pendingPurchases.getString(key);
    final request = saved ?? requestId();
    if (saved == null) await pendingPurchases.setString(key, request);
    if (db.auth.currentUser?.id != user) return;
    await db.rpc('buy_store_item',params:{'p_item':id,'p_days':duration,'p_request':request});
    if (await pendingPurchases.getString(key) == request) await pendingPurchases.remove(key);
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
  final label=widget.owned?(equipped?'Remove':category=='Avatars'?'Use avatar':'Show in lobby'):(permanent?'Owned':stock==null?'Buy':'Extend');
  final action = TextButton(onPressed:busy||(!widget.owned&&permanent)?null:()=>act(item,stock),child:Text(label));
  final subtitle=stock==null?'From ${(item['prices'] as List).first} credits':permanent?'Permanent':'Until ${DateTime.parse(stock['expires_at'] as String).toLocal().toString().split('.').first}';
  final title=item['title'] as String;
  final asset='assets/store/${item['id']}.webp';
  void preview(){
    showDialog<void>(context:context,builder:(ctx)=>SimpleDialog(title:Text(title),children:[
      SizedBox(width:400,height:MediaQuery.sizeOf(ctx).height*.48,child:InteractiveViewer(maxScale:4,child:Image.asset(asset,fit:BoxFit.contain))),
      Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))),
    ]));
  }
  if(widget.owned)return ListTile(onTap:preview,leading:Image.asset(asset,width:50),title:Text(title),subtitle:Text(subtitle),trailing:action);
  return SizedBox(width:164,child:Card(clipBehavior:Clip.antiAlias,child:Column(children:[
    Expanded(child:InkWell(onTap:preview,child:SizedBox.expand(child:Image.asset(asset,fit:BoxFit.contain)))),
    InkWell(onTap:preview,child:Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Text(title,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center))),
    Text(stock==null?subtitle:permanent?'Permanent':'Owned',style:Theme.of(context).textTheme.bodySmall),
    action,
  ])));
 }
 @override Widget build(BuildContext context){
 final byId={for(final o in owned)o['item_id']:o};
 if(!widget.owned)return Scaffold(appBar:AppBar(title:const Text('Store')),body:ListView(padding:const EdgeInsets.all(12),children:[
   if(error!=null) ListTile(title:Text(error!),trailing:TextButton(onPressed:refresh,child:const Text('Retry'))),
   for(final group in groups)...[
     Padding(padding:const EdgeInsets.fromLTRB(4,12,4,6),child:Text(group,style:Theme.of(context).textTheme.titleLarge)),
     SizedBox(height:244,child:Scrollbar(child:ListView(scrollDirection:Axis.horizontal,primary:false,children:[
       for(final item in items.where((item)=>item['category']==group))row(item,byId[item['id']]),
     ]))),
   ],
 ]));
 return DefaultTabController(length:groups.length,child:Scaffold(appBar:AppBar(title:Text(widget.owned?'Owned items':'Store'),bottom:TabBar(isScrollable:true,tabs:[for(final name in widget.owned?closets:groups)Tab(text:name)])),
 body:TabBarView(children:[for(var i=0;i<groups.length;i++)ListView(padding:const EdgeInsets.all(12),children:[
 if(error!=null)ListTile(title:Text(error!),trailing:TextButton(onPressed:refresh,child:const Text('Retry'))),
 for(final item in items.where((e)=>e['category']==groups[i]&&(!widget.owned||byId.containsKey(e['id']))))row(item,byId[item['id']]),
 if(widget.owned&&error==null&&!items.any((e)=>e['category']==groups[i]&&byId.containsKey(e['id'])))const Center(child:Text('No owned items here yet')),
 ])])));
 }
}