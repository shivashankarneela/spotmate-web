import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sandbox UI is compiled in only for explicitly configured test builds.
/// The deployed app remains read-only until this is verified end-to-end.
const _phonepeSandbox = bool.fromEnvironment(
  'SPOTMATE_PHONEPE_SANDBOX', defaultValue: false);

class SpotmateRechargeScreen extends StatefulWidget {
  const SpotmateRechargeScreen({super.key});
  @override
  State<SpotmateRechargeScreen> createState() => _SpotmateRechargeScreenState();
}

class _SpotmateRechargeScreenState extends State<SpotmateRechargeScreen>
    with WidgetsBindingObserver {
  final client = Supabase.instance.client;
  List<Map<String, dynamic>> packages = [];
  List<Map<String, dynamic>> orders = [];
  int balance = 0;
  bool loading = true;
  bool processing = false;
  String? pendingOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && pendingOrderId != null) {
      checkPayment(pendingOrderId!);
    }
  }

  Future<void> load() async {
    try {
      final uid = client.auth.currentUser!.id;
      final results = await Future.wait([
        client.from('spotmate_credit_packages')
            .select('id,credits,price_paise,currency,active')
            .order('price_paise'),
        client.from('spotmate_recharge_orders')
            .select('id,credits,amount_paise,status,created_at')
            .eq('user_id', uid).order('created_at', ascending: false).limit(10),
        client.from('wallets').select('balance').eq('user_id', uid).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        packages = List<Map<String, dynamic>>.from(results[0] as List);
        orders = List<Map<String, dynamic>>.from(results[1] as List);
        balance = ((results[2] as Map<String, dynamic>?)?['balance'] as num?)?.toInt() ?? 0;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      _show('Could not load wallet details.');
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  Future<void> recharge(Map<String, dynamic> pack) async {
    if (!_phonepeSandbox || processing) return;
    setState(() => processing = true);
    try {
      final result = await client.functions.invoke(
        'spotmate-phonepe-sandbox',
        body: {'action': 'create', 'packageId': pack['id']},
      );
      if (result.status != 200 || result.data is! Map) {
        throw StateError('Unable to start sandbox checkout');
      }
      final data = Map<String, dynamic>.from(result.data as Map);
      final checkoutUrl = Uri.tryParse(data['checkoutUrl']?.toString() ?? '');
      final orderId = data['orderId']?.toString();
      if (checkoutUrl == null || checkoutUrl.scheme != 'https' ||
          orderId == null || orderId.isEmpty) {
        throw StateError('Invalid sandbox checkout response');
      }
      pendingOrderId = orderId;
      await load();
      final launched = await launchUrl(checkoutUrl,
          mode: LaunchMode.externalApplication);
      if (!launched) _show('Open the payment link and check its status.');
    } catch (_) {
      _show('Sandbox checkout is unavailable. No credits were added.');
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> checkPayment(String orderId) async {
    if (!_phonepeSandbox || processing) return;
    setState(() => processing = true);
    try {
      final result = await client.functions.invoke(
        'spotmate-phonepe-sandbox',
        body: {'action': 'check', 'orderId': orderId},
      );
      if (result.status != 200 || result.data is! Map) {
        throw StateError('Could not verify transaction');
      }
      final data = Map<String, dynamic>.from(result.data as Map);
      final status = data['status']?.toString() ?? 'pending';
      if (status == 'paid') {
        pendingOrderId = null;
        _show('Sandbox payment verified. Credits updated.');
      } else if (status == 'failed') {
        pendingOrderId = null;
        _show('Sandbox payment failed. No credits added.');
      } else {
        _show('Payment is still pending. Check again shortly.');
      }
      await load();
    } catch (_) {
      _show('Could not verify payment. Credits have not been confirmed.');
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF162544);
    return Scaffold(
      appBar: AppBar(title: const Text('Recharge Spotmate Credits'),
        actions: [IconButton(onPressed: processing ? null : load,
          icon: const Icon(Icons.refresh), tooltip: 'Refresh wallet')]),
      body: loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(20), children: [
        Card(color: const Color(0xFFEAF8F4), child: Padding(
          padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.account_balance_wallet_outlined, color: ink),
            const SizedBox(height: 8),
            Text('$balance Spotmate Credits', style: const TextStyle(
              color: ink, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_phonepeSandbox
              ? 'PhonePe SANDBOX ONLY — simulated payments, no real charges.'
              : 'Secure recharge is not live yet. No money can be charged here.'),
          ]))),
        const SizedBox(height: 20),
        Text(_phonepeSandbox ? 'Test credit packs' : 'Planned credit packs',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        ...packages.map((p) => Card(child: ListTile(
          leading: const Icon(Icons.toll_rounded, color: ink),
          title: Text("${p['credits']} Spotmate Credits"),
          subtitle: Text("₹${((p['price_paise'] as num) / 100).toStringAsFixed(0)} · ${_phonepeSandbox ? 'Test payment' : 'Preview pricing'}"),
          trailing: _phonepeSandbox ?
            FilledButton(onPressed: processing ? null : () => recharge(p),
              child: const Text('Test recharge')) :
            const Text('Coming soon', style: TextStyle(color: Colors.grey)),
        ))),
        const SizedBox(height: 18),
        const Text('Recharge history', style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 17)),
        if (orders.isEmpty) const Padding(padding: EdgeInsets.all(14),
          child: Text('No recharge orders yet')),
        ...orders.map((order) => ListTile(
          title: Text("${order['credits']} SC"),
          subtitle: Text(order['status'].toString()),
          trailing: _phonepeSandbox && order['status'] == 'pending'
            ? TextButton(onPressed: processing ? null :
                () => checkPayment(order['id'].toString()),
                child: const Text('Check payment'))
            : Text("₹${((order['amount_paise'] as num) / 100).toStringAsFixed(0)}"),
        )),
        if (processing) const Center(child: Padding(
          padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
      ]),
    );
  }
}
