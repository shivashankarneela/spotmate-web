import 'dart:async';
import 'dart:js_interop';

@JS('spotmateOpenRazorpayTest')
external void _openCheckout(JSAny? config, JSFunction onResult);

Future<Map<String, dynamic>> openRazorpayTestCheckout({
  required String keyId,
  required String providerOrderId,
  required int amount,
}) async {
  final result = Completer<Map<String, dynamic>>();

  void onResult(JSAny? payload) {
    final data = payload.dartify();
    if (data is Map && !result.isCompleted) {
      result.complete(Map<String, dynamic>.from(data));
    }
  }

  _openCheckout({
    'keyId': keyId,
    'providerOrderId': providerOrderId,
    'amount': amount,
  }.jsify(), onResult.toJS);

  return result.future.timeout(
    const Duration(minutes: 12),
    onTimeout: () => {'kind': 'timeout'},
  );
}
