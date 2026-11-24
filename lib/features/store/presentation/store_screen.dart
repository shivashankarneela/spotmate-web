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
  return Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: preview,
        child: AspectRatio(
          aspectRatio: 1.12,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: RadialGradient(
              colors: [Color(0xFFF9F1DD), Color(0xFFD7C8AD)],
              center: Alignment(0, -.35), radius: 1,
            )),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.asset(asset, fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => const Icon(Icons.inventory_2_outlined)),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall)),
      Align(alignment: Alignment.centerRight, child: action),
    ]),
  );
 }

 @override
 Widget build(BuildContext context) {
  final byId = {for (final entry in owned) entry['item_id']: entry};
  return DefaultTabController(
    length: groups.length,
    child: Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F5F8),
        title: Text(widget.owned ? 'Owned items' : 'Store'),
        actions: [
          if (!widget.owned) IconButton(
            tooltip: 'Owned items',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const StoreScreen(owned: true)));
              if (mounted) await refresh();
            },
          ),
        ],
        bottom: TabBar(isScrollable: true,
          tabs: [for (final label in widget.owned ? closets : groups) Tab(text: label)]),
      ),
      body: TabBarView(children: [
        for (final group in groups)
          LayoutBuilder(builder: (context, constraints) {
            final catalog = items.where((item) => item['category'] == group &&
                (!widget.owned || byId.containsKey(item['id']))).toList();
            final available = min(constraints.maxWidth, 1100.0);
            final columns = (available / 210).floor().clamp(1, 5).toInt();
            final width = (available - 32 - (columns - 1) * 12) / columns;
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1068),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (!widget.owned) Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFF203044),
                          borderRadius: BorderRadius.circular(16)),
                        child: Text('$balance SpotMate Credits',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      if (error != null)
                        ListTile(title: Text(error!),
                          trailing: TextButton(onPressed: refresh, child: const Text('Retry')))
                      else if (catalog.isEmpty)
                        Padding(padding: const EdgeInsets.all(16), child: Text(
                          widget.owned ? 'No owned items in this category yet.' : 'No items available.')),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        for (final item in catalog)
                          SizedBox(width: width, child: row(item, byId[item['id']])),
                      ]),
                    ]),
                  )),
                ],
              ),
            );
          }),
      ]),
    ),
  );
 }
}