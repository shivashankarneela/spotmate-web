import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Informational recharge catalog. No payment actions are active until
/// verified checkout and idempotent payment webhooks are configured.
class SpotmateRechargeScreen extends StatefulWidget {
  const SpotmateRechargeScreen({super.key});
  @override State<SpotmateRechargeScreen> createState()=>_SpotmateRechargeScreenState();
}
class _SpotmateRechargeScreenState extends State<SpotmateRechargeScreen> {
  final client=Supabase.instance.client;
  List<Map<String,dynamic>> packages=[];
  List<Map<String,dynamic>> orders=[];
  bool loading=true;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    try{
      final result=await client.from('spotmate_credit_packages')
        .select('id,credits,price_paise,currency,active').order('price_paise');
      final uid=client.auth.currentUser!.id;
      final history=await client.from('spotmate_recharge_orders')
        .select('id,credits,amount_paise,status,created_at')
        .eq('user_id',uid).order('created_at',ascending:false).limit(10);
      if(mounted)setState((){
        packages=List<Map<String,dynamic>>.from(result);
        orders=List<Map<String,dynamic>>.from(history);
        loading=false;
      });
    }catch(e){
      if(mounted){
        setState(()=>loading=false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('Could not load recharge options: $e')));
      }
    }
  }
  @override Widget build(BuildContext context){
    const ink=Color(0xFF162544);
    return Scaffold(
      appBar:AppBar(title:const Text('Recharge credits')),
      body:loading?const Center(child:CircularProgressIndicator()):
      ListView(padding:const EdgeInsets.all(20),children:[
        Card(color:const Color(0xFFEAF8F4),child:Padding(
          padding:const EdgeInsets.all(18),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Icon(Icons.verified_user_outlined,color:ink),
            const SizedBox(height:8),
            const Text('Secure recharge is not live yet',
              style:TextStyle(color:ink,fontSize:18,fontWeight:FontWeight.w800)),
            const SizedBox(height:8),
            const Text('No money can be charged here. We will enable checkout only after gateway verification, automatic payment confirmation, and refund controls are tested.'),
          ]),
        )),
        const SizedBox(height:20),
        const Text('Planned credit packs',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
        const SizedBox(height:8),
        ...packages.map((p)=>Card(child:ListTile(
          leading:const Icon(Icons.toll_rounded,color:ink),
          title:Text('${p['credits']} credits'),
          subtitle:Text('₹${((p['price_paise'] as num)/100).toStringAsFixed(0)} · Preview pricing'),
          trailing:const Text('Coming soon',style:TextStyle(color:Colors.grey)),
        ))),
        const SizedBox(height:18),
        const Text('Recharge history',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)),
        if(orders.isEmpty)const Padding(
          padding:EdgeInsets.all(14),child:Text('No recharge orders yet')),
        ...orders.map((order)=>ListTile(
          title:Text('${order['credits']} SC'),
          subtitle:Text(order['status'].toString()),
          trailing:Text('₹${((order['amount_paise'] as num)/100).toStringAsFixed(0)}'),
        )),
      ]),
    );
  }
}
