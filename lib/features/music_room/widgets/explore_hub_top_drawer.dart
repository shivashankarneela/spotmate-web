import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ExploreLongPressTrigger extends StatelessWidget {
  const ExploreLongPressTrigger({super.key,required this.child,required this.onGamesSelected,required this.onLiveSelected,required this.onReelsSelected,required this.onMusicRoomSelected, this.onStoreSelected});
  final VoidCallback onLiveSelected,onReelsSelected;
  final Widget child;
  final VoidCallback onGamesSelected;
  final VoidCallback onMusicRoomSelected;
  final VoidCallback? onStoreSelected;

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    final entries = [
      ('Games Arena', Icons.sports_esports_outlined),
      ('Music Room', Icons.headphones_outlined),
      ('Live TV', Icons.live_tv_outlined),
      ('Reels', Icons.video_collection_outlined),
      if (onStoreSelected != null) ('Store', Icons.storefront_outlined),
    ];
    final int? choice;
    if (MediaQuery.sizeOf(context).width >= 700) {
      final anchor = context.findRenderObject() as RenderBox;
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final point = anchor.localToGlobal(Offset.zero, ancestor: overlay);
      choice = await showMenu<int>(
        context: context, color: Colors.white,
        position: RelativeRect.fromLTRB(point.dx,point.dy-216,overlay.size.width-point.dx-anchor.size.width,overlay.size.height-point.dy),
        items: [for (var i=0;i<entries.length;i++) PopupMenuItem(
          value:i,child:Row(children:[Icon(entries[i].$2,color:const Color(0xff147d72)),const SizedBox(width:12),Text(entries[i].$1)]))],
      );
    } else {
      choice = await showModalBottomSheet<int>(context:context,showDragHandle:true,backgroundColor:Colors.white,
        builder:(sheet)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.fromLTRB(16,0,16,16),children:[
          Text('Explore more',style:Theme.of(sheet).textTheme.titleLarge),
          for (var i=0;i<entries.length;i++) ListTile(
            leading:Icon(entries[i].$2,color:const Color(0xff147d72)), title:Text(entries[i].$1),
            trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.pop(sheet,i)),
        ])));
    }
    if (!context.mounted || choice==null) return;
    [onGamesSelected,onMusicRoomSelected,onLiveSelected,onReelsSelected,if (onStoreSelected != null) onStoreSelected!][choice]();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior:HitTestBehavior.opaque,onLongPress:()=>_open(context),child:child);
}
