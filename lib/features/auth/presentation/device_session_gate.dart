import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceSessionGate extends StatefulWidget {
  const DeviceSessionGate({super.key,required this.child});
  final Widget child;
  @override State<DeviceSessionGate> createState()=>_DeviceSessionGateState();
}
class _DeviceSessionGateState extends State<DeviceSessionGate> with WidgetsBindingObserver {
  final db=Supabase.instance.client;
  StreamSubscription<AuthState>? sub;
  Timer? timer;
  String? verifiedToken, checkingToken;
  String? admittedUser;
  bool foreground=true, replaced=false, unavailable=false;
  String? get token=>db.auth.currentSession?.accessToken;
  @override void initState(){
    super.initState();WidgetsBinding.instance.addObserver(this);
    sub=db.auth.onAuthStateChange.listen((_){if(mounted){setState((){});unawaited(check());}});
    timer=Timer.periodic(const Duration(seconds:8),(_)=>check());
    unawaited(check());
  }
  Future<void> check() async {
    final key=token;
    if(!foreground||key==null||checkingToken==key)return;
    checkingToken=key;
    try{
      final active=await db.rpc('spotmate_session_active');
      if(!mounted||token!=key)return;
      if(active!=true){await endSession(key);return;}
      if(verifiedToken!=key||unavailable||replaced)setState((){verifiedToken=key;admittedUser=db.auth.currentUser?.id;unavailable=false;replaced=false;});
    }on PostgrestException catch(e){
      if(!mounted||token!=key)return;
      if(e.message=='SESSION_REPLACED'){await endSession(key);}
      else {setState((){verifiedToken=null;unavailable=true;});}
    }catch(_){if(mounted&&token==key)setState((){verifiedToken=null;unavailable=true;});}
    finally{if(checkingToken==key)checkingToken=null;}
  }
  Future<void> endSession(String key)async{
    if(token!=key)return;
    setState((){verifiedToken=null;admittedUser=null;replaced=true;});
    await db.auth.signOut(scope:SignOutScope.local);
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    foreground=state==AppLifecycleState.resumed;
    if(!foreground){setState(()=>verifiedToken=null);}else{unawaited(check());}
  }
  @override void dispose(){timer?.cancel();sub?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context){
    if(replaced&&token==null)return Material(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('You signed in on another device.'),
      TextButton(onPressed:()=>setState(()=>replaced=false),child:const Text('Back to sign in')),
    ])));
    final locked = token != null && (verifiedToken != token || !foreground);
    final retain = token == null || admittedUser == db.auth.currentUser?.id;
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: locked, child: ExcludeFocus(excluding: locked,
        child: TickerMode(enabled: !locked, child: retain ? widget.child : const SizedBox.shrink()))),
      if (locked) Material(child: Center(child: unavailable
        ? TextButton(onPressed: check, child: const Text('Retry session check'))
        : const CircularProgressIndicator())),
    ]);
  }
}