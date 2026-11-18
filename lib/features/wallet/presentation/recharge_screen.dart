import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import 'razorpay_checkout.dart';

/// Each checkout mode is bound to its own Supabase project.
const razorpayTestBuild = bool.fromEnvironment('SPOTMATE_RAZORPAY_TEST') &&
    SupabaseConstants.supabaseUrl == 'https://psifvzftfnfhsvjlskte.supabase.co';
const razorpayLiveBuild = bool.fromEnvironment('SPOTMATE_RAZORPAY_LIVE') &&
    SupabaseConstants.supabaseUrl == 'https://mepulcdlighuiwgbutnx.supabase.co';
const checkoutEnabled = kIsWeb && (razorpayTestBuild || razorpayLiveBuild);
class SpotmateRechargeScreen extends StatefulWidget {
  const SpotmateRechargeScreen({super.key});
  @override State<SpotmateRechargeScreen> createState()=>_SpotmateRechargeScreenState();
}
class _SpotmateRechargeScreenState extends State<SpotmateRechargeScreen> {
  final client=Supabase.instance.client;
  List<Map<String,dynamic>> packages=[];
  List<Map<String,dynamic>> orders=[];
  int balance=0;
  bool loading=true;
  bool busy=false;

  @override void initState(){ super.initState();load(); }
  Future<void> load() async {
    try {
      final uid=client.auth.currentUser!.id;
      final packs=await client.from('spotmate_credit_packages')
        .select('id,credits,price_paise,currency,active').order('price_paise');
      final history=await client.from('spotmate_recharge_orders')
        .select('id,credits,amount_paise,status,created_at,provider')
        .eq('user_id',uid).order('created_at',ascending:false).limit(15);
      final wallet=await client.from('wallets').select('balance').eq('user_id',uid).maybeSingle();
      if(!mounted)return;
      setState((){
        packages=List<Map<String,dynamic>>.from(packs);
        orders=List<Map<String,dynamic>>.from(history);
        balance=(wallet?['balance'] as num?)?.toInt()??0;
        loading=false;
      });
    }catch(_){
      if(!mounted)return;
      setState(()=>loading=false);
      show('Could not refresh recharge information.');
    }
  }
  void show(String message){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }
  Future<Map<String,dynamic>> call(Map<String,dynamic> input) async {
    final response=await client.functions.invoke(
      razorpayLiveBuild ? 'spotmate-razorpay-live' : 'spotmate-razorpay-test',
      body: input,
    );
    if(response.status!=200||response.data is! Map)throw StateError('Payment service unavailable');
    return Map<String,dynamic>.from(response.data as Map);
  }
  Future<void> start(Map<String,dynamic> pack) async {
    if (!checkoutEnabled || busy || (razorpayLiveBuild && pack['active'] != true)) return;
    setState(()=>busy=true);
    try{
      final created=await call({'action':'create','packageId':pack['id']});
      final id=created['orderId'] as String;
      final result=await openRazorpayCheckout(
        live: razorpayLiveBuild,
        keyId:created['keyId'] as String,
        providerOrderId:created['providerOrderId'] as String,
        amount:(created['amount'] as num).toInt(),
      );
      if(result['kind']=='success'){
        final verified=await call({'action':'verify','orderId':id,
          'paymentId':result['paymentId'],'providerOrderId':result['providerOrderId'],
          'signature':result['signature']});
        if(verified['status']=='paid'){
          show('Payment verified. Credits added.');
        }else{
          show('Payment is still pending verification.');
        }
      }else{
        // User may close modal after a successful gateway payment; reconcile
        // against the trusted Razorpay server instead of declaring failure.
        await check(id,refresh:false);
      }
      await load();
    }catch(_){show('Checkout could not be completed. No credits were confirmed.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> check(String id,{bool refresh=true}) async {
    if (!checkoutEnabled) return;
    if(refresh){if(busy)return;setState(()=>busy=true);}
    try {
      final status=await call({'action':'check','orderId':id});
      if(status['status']=='paid')show('Payment captured and credits verified.');
      else if(status['status']=='pending')show('Payment is pending. Check again later.');
      else show('Payment status: ${status['status']}');
      if(refresh)await load();
    }catch(_){show('Unable to confirm payment status.');}
    finally{if(refresh&&mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    const ink=Color(0xFF162544);
    final test=razorpayTestBuild&&kIsWeb;
    return Scaffold(
      appBar:AppBar(title:const Text('Recharge Spotmate Credits'),
        actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):
      ListView(padding:const EdgeInsets.all(20),children:[
        Card(color:const Color(0xFFEAF8F4),child:Padding(
          padding:const EdgeInsets.all(18),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Icon(Icons.account_balance_wallet_outlined,color:ink),
            const SizedBox(height:8),
            Text('$balance Spotmate Credits',style:const TextStyle(
              color:ink,fontSize:22,fontWeight:FontWeight.w800)),
            const SizedBox(height:8),
            Text(test?'RAZORPAY TEST MODE — no real money is charged.': razorpayLiveBuild && kIsWeb ? 'Recharge your wallet with Razorpay.' :
              'Secure recharge is not live yet. No payments can be made here.'),
          ]))),
        const SizedBox(height:18),
        Text(test?'Test credit packs':checkoutEnabled?'Credit packs':'Planned credit packs',style:const TextStyle(
          fontWeight:FontWeight.w800,fontSize:17)),
        const SizedBox(height:8),
        ...packages.map((pack)=>Card(child:ListTile(
          leading:const Icon(Icons.toll_rounded,color:ink),
          title:Text("${pack['credits']} Spotmate Credits"),
          subtitle:Text("₹${((pack['price_paise'] as num)/100).toStringAsFixed(0)} · ${test?'Test payment':checkoutEnabled?'Razorpay':'Preview pricing'}"),
          trailing:checkoutEnabled && (test || pack['active'] == true)?FilledButton(onPressed:busy?null:()=>start(pack),
            child:Text(test ? 'Test recharge' : 'Recharge')):
            const Text('Coming soon',style:TextStyle(color:Colors.grey)),
        ))),
        const SizedBox(height:18),
        const Text('Recharge history',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
        if(orders.isEmpty)const Padding(padding:EdgeInsets.all(14),child:Text('No recharge orders yet')),
        ...orders.map((order)=>ListTile(
          title:Text("${order['credits']} SC · ₹${((order['amount_paise'] as num)/100).toStringAsFixed(0)}"),
          subtitle:Text(order['status'].toString()),
          trailing:checkoutEnabled&&order['provider']==(test?'razorpay_test':'razorpay_live')&&order['status']=='pending'
            ?TextButton(onPressed:busy?null:()=>check(order['id'].toString()),
                child:const Text('Check payment')):null,
        )),
        if(busy)const Center(child:Padding(padding:EdgeInsets.all(12),
          child:CircularProgressIndicator())),
      ]),
    );
  }
}
