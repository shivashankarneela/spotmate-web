Future<Map<String, dynamic>> openRazorpayCheckout({
  required bool live,
  required String keyId,
  required String providerOrderId,
  required int amount,
}) async => throw UnsupportedError('Razorpay checkout currently supports Flutter web only');
