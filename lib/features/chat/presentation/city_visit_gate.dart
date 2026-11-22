import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CityVisitGate extends StatefulWidget {
  const CityVisitGate({super.key, required this.room, required this.child});
  final String room;
  final Widget child;
  @override State<CityVisitGate> createState() => _CityVisitGateState();
}
class _CityVisitGateState extends State<CityVisitGate> with WidgetsBindingObserver {
  DateTime? joined;
  Timer? warning, expiry, trailing;
  bool waiting=true, idleWarning=false, foreground=true, failed=false;
  int generation=0;
  Future<void> queue=Future.value();
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);request('open');}
  void stopTimers(){warning?.cancel();expiry?.cancel();trailing?.cancel();}
  void request(String action){
    final version=generation;
    queue=queue.then((_)async{
      if(!mounted || version!=generation)return;
      try{
        final latency=Stopwatch()..start();
        final result=await Supabase.instance.client.rpc('city_visit',params:{'p_room':widget.room,'p_action':action});
        if(!mounted || version!=generation)return;
        warning?.cancel();expiry?.cancel();
        if(result==null){
          trailing?.cancel();
          setState((){joined=null;waiting=false;failed=false;idleWarning=false;});
          return;
        }
        final ms=(result['remaining_ms'] as num).toInt()-latency.elapsedMilliseconds;
        if(ms<=0){setState((){joined=null;waiting=false;});return;}
        setState((){waiting=false;failed=false;joined=DateTime.parse(result['joined'] as String).toLocal();idleWarning=ms<=30000;});
        if(ms>30000)warning=Timer(Duration(milliseconds:ms-30000),(){if(mounted)setState(()=>idleWarning=true);});
        expiry=Timer(Duration(milliseconds:ms),(){if(mounted){setState(()=>waiting=true);request('check');}});
      }catch(_){
        if(mounted&&version==generation){stopTimers();setState((){waiting=false;failed=true;});}
      }
    });
  }
  void activity(){
    if(!foreground||joined==null||waiting)return;
    if(idleWarning){if(mounted)setState(()=>idleWarning=false);request('touch');return;}
    if(trailing?.isActive??false)return;
    trailing=Timer(const Duration(seconds:2),()=>request('touch'));
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){
      if(!foreground){foreground=true;request('open');}
    }else if(foreground){
      foreground=false;generation++;stopTimers();setState(()=>waiting=true);
    }
  }
  @override void dispose(){generation++;stopTimers();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context){
    if(waiting && joined==null)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(joined==null)return Scaffold(
      backgroundColor: const Color(0xFFFAF8F3),
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(color: const Color(0xFFDDF3EB), borderRadius: BorderRadius.circular(24)),
              child: const Icon(Icons.forum_rounded, size: 38, color: Color(0xFF147D72)),
            ),
            const SizedBox(height: 24),
            Text(failed ? 'Unable to open the room' : 'Ready to join the conversation?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xFF202B30))),
            const SizedBox(height: 12),
            Text(failed ? 'Check your connection and try again.' : 'Your visit ended after a period of inactivity. Rejoin to catch up with everyone.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF64748B))),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF147D72), padding: const EdgeInsets.symmetric(vertical: 15)),
              onPressed: () { setState(() => waiting=true); request(failed ? 'open' : 'join'); },
              icon: const Icon(Icons.login_rounded),
              label: Text(failed ? 'Try again' : 'Rejoin room'),
            )),
          ]),
        ),
      ))),
    );
    final time=TimeOfDay.fromDateTime(joined!).format(context);
    return Stack(fit:StackFit.expand, children:[Offstage(offstage:waiting || failed,child:ExcludeFocus(excluding:waiting || failed,child:Material(child:Column(children:[
      SafeArea(bottom:false,child:SizedBox(height:32,child:Row(children:[
        const SizedBox(width:12),
        Expanded(child:Text(idleWarning?'Room clears in 30 seconds':'Joined $time', style: const TextStyle(fontSize: 12))),
        if(idleWarning)TextButton(onPressed:()=>request('touch'),child:const Text('Stay in room')),
        TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 30)), onPressed:(){stopTimers();generation++;setState(()=>waiting=true);request('leave');},child:const Text('Leave')),
      ]))),
      Expanded(child:Focus(onKeyEvent:(_,event){activity();return KeyEventResult.ignored;},
        child:Listener(onPointerDown:(_)=>activity(),onPointerSignal:(_)=>activity(),
          child:NotificationListener<ScrollUpdateNotification>(onNotification:(event){
            if(event.dragDetails!=null)activity();return false;},child:widget.child)))),
    ])))), if(failed && !waiting) Material(child:Center(child:TextButton(onPressed:(){setState(()=>waiting=true);request('open');},child:const Text('Retry city room')))), if(waiting) const Material(child:Center(child:CircularProgressIndicator()))]);
  }
}