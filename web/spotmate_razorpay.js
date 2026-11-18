// Public UI bridge. Never place API secrets here: only rzp_test key ID is public.
(function () {
  'use strict';
  window.spotmateOpenRazorpayTest = function (cfg, notify) {
    if (!window.Razorpay || !cfg || typeof notify !== 'function' ||
        !/^rzp_test_/.test(cfg.keyId) || !/^order_/.test(cfg.providerOrderId)) {
      throw new Error('Razorpay test checkout is unavailable');
    }
    const checkout = new window.Razorpay({
      key: cfg.keyId, amount: cfg.amount, currency: 'INR',
      order_id: cfg.providerOrderId,
      name: 'SpotMate', description: 'SpotMate Credits (TEST MODE)',
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
