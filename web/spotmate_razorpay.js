// Public UI bridge. Never place API secrets here: only the Razorpay key ID is public.
(function () {
  'use strict';
  window.spotmateOpenRazorpay = function (cfg, notify) {
    const keyPrefix = cfg?.live === true ? 'rzp_live_' : 'rzp_test_';
    if (!window.Razorpay || !cfg || typeof notify !== 'function' ||
        typeof cfg.keyId !== 'string' || !cfg.keyId.startsWith(keyPrefix) || !/^order_/.test(cfg.providerOrderId)) {
      throw new Error('Razorpay checkout is unavailable');
    }
    const checkout = new window.Razorpay({
      key: cfg.keyId, amount: cfg.amount, currency: 'INR',
      order_id: cfg.providerOrderId,
      name: 'SpotMate', description: cfg.live === true ? 'SpotMate Credits' : 'SpotMate Credits (TEST MODE)',
      handler: (response) => notify({kind:'success',
        paymentId:response.razorpay_payment_id,
        providerOrderId:response.razorpay_order_id,
        signature:response.razorpay_signature}),
      modal: {ondismiss: () => notify({kind:'dismiss'})},
      theme: {color:'#162544'},
    });
    checkout.on('payment.failed', () => notify({kind:'failed'}));
    checkout.open();
  };
})();
