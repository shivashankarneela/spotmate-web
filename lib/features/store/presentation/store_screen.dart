import 'dart:math';
import 'fighter_artwork.dart';
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
 static const _berry = Color(0xFF960D42);
 static const _ink = Color(0xFF550D29);
 static const _paper = Color(0xFFFFF5ED);

 Widget artwork(String asset, {BoxFit fit = BoxFit.contain}) => Image.asset(
   asset, fit: fit, alignment: Alignment.bottomCenter,
   filterQuality: FilterQuality.high,
   errorBuilder: (_, error, stack) => const Center(child: Icon(Icons.inventory_2_outlined)),
 );

 Future<void> preview(Map<String,dynamic> item, Map<String,dynamic>? stock) async {
   final id = item['id'] as String;
   final avatar = fighterPoses(id).isNotEmpty;
   final poses = fighterPoses(id);
   int? pose;
   final confirmed = await showModalBottomSheet<bool>(
     context: context, isScrollControlled: true, useSafeArea: true,
     showDragHandle: true, backgroundColor: _paper,
     builder: (sheet) => StatefulBuilder(builder: (context, update) {
       final asset = 'assets/store/$id.webp';
       return SingleChildScrollView(
         padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.paddingOf(context).bottom),
         child: Center(child: ConstrainedBox(
           constraints: const BoxConstraints(maxWidth: 480),
           child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
             Text(item['title'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
               color: _ink, fontWeight: FontWeight.w800,
             )),
             const SizedBox(height: 12),
             Container(
               height: MediaQuery.sizeOf(context).height * .42,
               decoration: BoxDecoration(color: const Color(0xFFFBE0E2), borderRadius: BorderRadius.circular(24)),
               padding: const EdgeInsets.all(12),
               child: InteractiveViewer(maxScale: 4,
                 child: avatar ? FighterArtwork(id, pose: pose) : artwork(asset)),
             ),
             if (avatar) ...[
               const SizedBox(height: 16),
               Text('Signature poses', style: Theme.of(context).textTheme.titleMedium),
               Wrap(spacing: 8, children: [
                 ChoiceChip(label: const Text('Original'), selected: pose == null,
                   onSelected: (_) => update(() => pose = null)),
                 for (var index = 0; index < poses.length; index++)
                   ChoiceChip(label: Text(poses[index]), selected: pose == index,
                     onSelected: (_) => update(() => pose = index)),
               ]),
             ],
             const SizedBox(height: 16),
             FilledButton(
               style: FilledButton.styleFrom(backgroundColor: _berry),
               onPressed: busy || (!widget.owned && stock != null && stock['expires_at'] == null)
                 ? null : () => Navigator.pop(sheet, true),
               child: Text(widget.owned
                 ? (stock?['equipped'] == true ? 'Remove' : avatar ? 'Equip avatar' : 'Show in lobby')
                 : stock != null && stock['expires_at'] == null ? 'Owned' : 'Choose duration'),
             ),
           ]),
         )),
       );
     }),
   );
   if (confirmed == true && mounted) await act(item, stock);
 }

 Widget row(Map<String,dynamic> item, Map<String,dynamic>? stock, {bool featured = false}) {
   final id = item['id'] as String;
   final avatar = fighterPoses(id).isNotEmpty;
   final equipped = stock?['equipped'] == true;
   final permanent = stock != null && stock['expires_at'] == null;
   final label = widget.owned ? (equipped ? 'Remove' : avatar ? 'Equip' : 'Show in lobby')
       : permanent ? 'Owned' : stock == null ? 'Buy' : 'Extend';
   final subtitle = equipped ? 'Equipped' : stock == null
       ? 'From ${(item['prices'] as List).first} credits'
       : permanent ? 'Permanent' : 'Until ${DateTime.parse(stock['expires_at'] as String).toLocal().toString().split(' ').first}';
   final colors = featured
       ? const [Color(0xFFFFE4E7), Color(0xFFF4A9C2)]
       : const [Color(0xFFFFF0E2), Color(0xFFFCE1D5)];
   return Material(
     color: colors.first,
     borderRadius: BorderRadius.circular(22),
     clipBehavior: Clip.antiAlias,
     child: Ink(
       decoration: BoxDecoration(
         gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
         borderRadius: BorderRadius.circular(22),
         border: equipped ? Border.all(color: _berry) : null,
       ),
       child: InkWell(
         onTap: () => preview(item, stock),
         child: Padding(
           padding: const EdgeInsets.all(14),
           child: Row(children: [
             Expanded(child: SizedBox(
               height: featured ? 220 : 110,
               child: avatar ? FighterArtwork(id) : artwork('assets/store/$id.webp'),
             )),
             const SizedBox(width: 12),
             Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
               Text(item['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                 style: (featured ? Theme.of(context).textTheme.headlineSmall : Theme.of(context).textTheme.titleMedium)
                   ?.copyWith(color: _ink, fontWeight: FontWeight.w800)),
               const SizedBox(height: 4),
               Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _ink)),
               if (equipped && widget.owned && avatar)
                 SwitchListTile.adaptive(
                   contentPadding: EdgeInsets.zero, title: const Text('Show in lobby'),
                   value: true, onChanged: busy ? null : (_) => act(item, stock),
                 )
               else ...[
                 const SizedBox(height: 8),
                 OutlinedButton(
                   style: OutlinedButton.styleFrom(foregroundColor: _berry),
                   onPressed: busy || (!widget.owned && permanent) ? null : () => act(item, stock),
                   child: Text(label),
                 ),
               ],
             ])),
           ]),
         ),
       ),
     ),
   );
 }

 @override
 Widget build(BuildContext context) {
   final byId = {for (final entry in owned) entry['item_id']: entry};
   return DefaultTabController(
     length: groups.length,
     child: Scaffold(
       backgroundColor: _paper,
       appBar: AppBar(
         backgroundColor: _paper, foregroundColor: _ink,
         title: Text(widget.owned ? 'Owned items' : 'Store'),
         actions: [
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: 8),
             child: Center(child: Chip(
               backgroundColor: _berry, side: BorderSide.none,
               label: Text('$balance credits', style: const TextStyle(color: Colors.white)),
             )),
           ),
           if (!widget.owned)
             IconButton(
               tooltip: 'Owned items', icon: const Icon(Icons.inventory_2_outlined),
               onPressed: () async {
                 await Navigator.of(context).push(MaterialPageRoute<void>(
                   builder: (_) => const StoreScreen(owned: true),
                 ));
                 if (mounted) await refresh();
               },
             ),
         ],
         bottom: const TabBar(
           labelColor: _berry, indicatorColor: _berry,
           tabs: [Tab(text: 'Avatars'), Tab(text: 'Pets'), Tab(text: 'Vehicles')],
         ),
       ),
       body: TabBarView(children: [
         for (final group in groups)
           LayoutBuilder(builder: (context, constraints) {
             final catalog = items.where((item) => item['category'] == group &&
               (!widget.owned || byId.containsKey(item['id']))).toList();
             final highlighted = catalog.where((item) => item['id'] == 'naruto_uzumaki_normal').firstOrNull;
             final featured = !widget.owned && group == 'Avatars' && catalog.isNotEmpty
                 ? highlighted ?? catalog.first : null;
             final available = (constraints.maxWidth - 32).clamp(0.0, 1068.0).toDouble();
             final width = available >= 650 ? (available - 12) / 2 : available;
             return RefreshIndicator(
               onRefresh: refresh,
               child: ListView(
                 physics: const AlwaysScrollableScrollPhysics(),
                 padding: const EdgeInsets.all(16),
                 children: [
                   Center(child: SizedBox(
                     width: available,
                     child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                       if (error != null)
                         ListTile(title: Text(error!),
                           trailing: TextButton(onPressed: refresh, child: const Text('Retry')))
                       else if (catalog.isEmpty)
                         Padding(padding: const EdgeInsets.all(16), child: Text(
                           widget.owned ? 'No owned items in this category yet.' : 'No items available.',
                         )),
                       if (featured != null) ...[
                         row(featured, byId[featured['id']], featured: true),
                         const SizedBox(height: 12),
                       ],
                       Wrap(spacing: 12, runSpacing: 12, children: [
                         for (final item in catalog)
                           if (item != featured)
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
