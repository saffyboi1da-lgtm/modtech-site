(function () {
  var c = window.MODTECH_CHECKOUT;
  var btn = document.getElementById('buy');
  var banner = document.getElementById('sandbox-banner');
  if (!btn) return;
  function off(message) {
    btn.disabled = true;
    btn.textContent = message;
  }
  if (!c) { off('Checkout is unavailable right now. Email contact@modtech.app'); return; }
  // Pause switch: an empty (or missing) token turns the button off for everyone, the founder link included, without touching Paddle.
  if (!c.token) { off('Subscriptions are not open yet. Email contact@modtech.app'); return; }
  // Founder gate: while gated, only a visit to /pricing/#founder opens checkout. It keeps the button off the public
  // page until the first purchase has proved the chain; it is not security (anyone who types #founder can buy).
  if (c.gated === true && window.location.hash !== '#founder') { off('Subscriptions are not open yet. Email contact@modtech.app'); return; }
  if (!window.Paddle) { off('Checkout is unavailable right now. Email contact@modtech.app'); return; }
  if (c.environment === 'sandbox') {
    window.Paddle.Environment.set('sandbox');
    if (banner) banner.hidden = false;
  }
  window.Paddle.Initialize({ token: c.token });
  btn.addEventListener('click', function () {
    window.Paddle.Checkout.open({ items: [{ priceId: c.priceId, quantity: 1 }] });
  });
})();
