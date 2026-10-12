/*
 * Which Paddle account the Subscribe button talks to, and who may use it. This file has exactly two valid states, and
 * tools/check-before-publish.sh refuses to pass for anything in between.
 *
 * PAUSED (checked with: tools/check-before-publish.sh --paused). This is how the first publish goes out.
 *   The environment is 'live', the token is empty (''), the price id is empty (''), and gated is true.
 *   Nothing in the page can open a checkout: the button is switched off for everyone, the founder link included, and
 *   Paddle.js is never initialised. The Paddle.js script tag stays on the pricing page; only this file is blank.
 *
 * LIVE (checked with: tools/check-before-publish.sh, no flag).
 *   The environment is 'live' (exactly that word).
 *   The token is the LIVE client-side token from Paddle, Developer tools, Authentication. An empty token is refused in
 *   this mode: a blank token is never read as "paused" unless --paused is given.
 *   The price id is the LIVE price from Paddle, Catalog, Prices. Never the sandbox one.
 *   gated is true while only the founder may buy (checkout opens only at /pricing/#founder), or false to open it to all.
 *   A client-side token is meant to be public: it can only open a checkout and preview prices.
 *
 * The live token and price id must not be committed on any branch that gets pushed. Never put an API key (a secret)
 * in this file.
 */
window.MODTECH_CHECKOUT = {
  environment: 'live',
  token: '',
  priceId: '',
  gated: true
};
