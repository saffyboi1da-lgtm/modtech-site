// Exercises assets/checkout.js with stubbed browser objects: the pause switch, the founder gate, and the normal path.
// Usage: node tools/test-checkout.js   (no dependencies)
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'assets', 'checkout.js'), 'utf8');
let failures = 0;
function run(name, { config, hash = '', paddle = true }, expectFn) {
  const btn = { disabled: false, textContent: 'Subscribe for US$29 / month', handlers: {}, addEventListener(e, f) { this.handlers[e] = f; } };
  const banner = { hidden: true };
  const calls = { init: null, env: null, opened: null };
  const win = {
    MODTECH_CHECKOUT: config,
    location: { hash },
    Paddle: paddle ? {
      Environment: { set: (e) => { calls.env = e; } },
      Initialize: (o) => { calls.init = o; },
      Checkout: { open: (o) => { calls.opened = o; } }
    } : undefined
  };
  const doc = { getElementById: (id) => (id === 'buy' ? btn : id === 'sandbox-banner' ? banner : null) };
  new Function('window', 'document', src)(win, doc);
  const ok = expectFn({ btn, banner, calls });
  console.log((ok ? 'ok    ' : 'WRONG ') + name);
  if (!ok) failures++;
}
const live = { environment: 'live', token: 'live_x', priceId: 'pri_x' };
run('no config: button off, Paddle untouched', { config: undefined }, ({ btn, calls }) => btn.disabled && /unavailable/.test(btn.textContent) && !calls.init);
run('empty token pauses sales without initialising Paddle', { config: { ...live, token: '', gated: false } }, ({ btn, calls }) => btn.disabled && /not open yet/.test(btn.textContent) && !calls.init);
// PAUSED publish: token and price id both empty. Off for everyone, the founder link included; Paddle never touched.
const paused = { environment: 'live', token: '', priceId: '' };
const stayedOff = ({ btn, banner, calls }) => btn.disabled === true && btn.textContent === 'Subscriptions are not open yet. Email contact@modtech.app' && calls.init === null && calls.env === null && calls.opened === null && !btn.handlers.click && banner.hidden === true;
run('PAUSED (empty token + empty priceId), gated, #founder: button off, Paddle never initialised, no click handler', { config: { ...paused, gated: true }, hash: '#founder' }, stayedOff);
run('PAUSED, gated, public visitor: button off', { config: { ...paused, gated: true } }, stayedOff);
run('PAUSED but gated false, #founder: still off, Paddle never initialised, no click handler', { config: { ...paused, gated: false }, hash: '#founder' }, stayedOff);
run('PAUSED but gated false, public visitor: still off', { config: { ...paused, gated: false } }, stayedOff);
run('token key missing entirely, gated, #founder: off, Paddle never initialised, no click handler', { config: { environment: 'live', priceId: '', gated: true }, hash: '#founder' }, stayedOff);
run('token key missing entirely, gated false: off, Paddle never initialised, no click handler', { config: { environment: 'live', priceId: '', gated: false }, hash: '#founder' }, stayedOff);
run('PAUSED: clicking is impossible (a stray click event cannot open checkout)', { config: { ...paused, gated: true }, hash: '#founder' }, ({ btn, calls }) => { if (btn.handlers.click) btn.handlers.click(); return calls.opened === null; });
run('gated, public visitor: off, Paddle untouched', { config: { ...live, gated: true } }, ({ btn, calls }) => btn.disabled && /not open yet/.test(btn.textContent) && !calls.init);
run('gated, wrong hash: still off', { config: { ...live, gated: true }, hash: '#other' }, ({ btn, calls }) => btn.disabled && !calls.init);
run('gated, #founder: opens checkout with the live price', { config: { ...live, gated: true }, hash: '#founder' }, ({ btn, calls }) => {
  if (btn.disabled || !calls.init || calls.init.token !== 'live_x') return false;
  btn.handlers.click();
  return calls.opened && calls.opened.items[0].priceId === 'pri_x' && calls.opened.items[0].quantity === 1 && calls.env === null;
});
run('ungated: open to everyone, no sandbox banner in live', { config: { ...live, gated: false } }, ({ btn, banner, calls }) => !btn.disabled && !!calls.init && banner.hidden === true && calls.env === null);
run('sandbox environment: switches Paddle to sandbox and shows the banner', { config: { environment: 'sandbox', token: 'test_x', priceId: 'pri_x', gated: false } }, ({ btn, banner, calls }) => !btn.disabled && calls.env === 'sandbox' && banner.hidden === false);
run('Paddle.js failed to load: button off', { config: { ...live, gated: false }, paddle: false }, ({ btn }) => btn.disabled && /unavailable/.test(btn.textContent));
console.log(failures ? failures + ' CHECKOUT TEST(S) WRONG' : 'ALL CHECKOUT TESTS PASSED');
process.exit(failures ? 1 : 0);
