import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js;

Future<Map<String, dynamic>> openRazorpayTestCheckout({
  required String keyId,
  required String providerOrderId,
  required int amount,
}) async {
  final token = DateTime.now().microsecondsSinceEpoch.toString();
  final result = Completer<Map<String,dynamic>>();
  late final StreamSubscription<html.MessageEvent> subscription;
  subscription = html.window.onMessage.listen((event) {
    if (event.origin != html.window.location.origin) return;
    final raw = js.dartify(event.data);
    if (raw is! Map || raw['source'] != 'spotmate-razorpay-test' || raw['token'] != token) return;
    if (!result.isCompleted) result.complete(Map<String,dynamic>.from(raw));
  });
  try {
    js.callMethod(html.window,'spotmateOpenRazorpayTest', [
      js.jsify({'keyId':keyId,'providerOrderId':providerOrderId,'amount':amount,'token':token}),
    ]);
    return await result.future.timeout(const Duration(minutes:12),
      onTimeout:()=>{'kind':'timeout'});
  } finally {
    await subscription.cancel();
  }
}
