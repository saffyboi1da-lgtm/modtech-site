/*
 * The second half of the waitlist's double opt-in: the page the confirmation email links to.
 *
 * Why a page with a button, rather than a link that just works: Outlook/Defender Safe Links and
 * other mail gateways fetch the URLs in a message when it is delivered. A link that confirmed on
 * its own would be clicked by a robot, and the record would then claim the real addressee acted
 * when they had not even seen the email — which is worse than no record at all. So this page
 * writes nothing on load. Only pressing the button POSTs the token.
 *
 * Why the token is in the fragment (#) and not the query string: a fragment is never sent to a
 * server, so it stays out of GitHub Pages' logs, out of any Referer header, and out of anything
 * that records URLs. It is also removed from the address bar as soon as it has been read, so it
 * does not sit in the browser's history or get copied out of the bar by the next person.
 *
 * The only reply treated as success is one the function actually sent. Anything unclear is shown
 * as a failure, never as "confirmed".
 */
(function () {
  var cfg = window.MODTECH_WAITLIST;
  var panes = {
    confirm: document.getElementById('wl-confirm'),
    done: document.getElementById('wl-done'),
    expired: document.getElementById('wl-expired'),
    unknown: document.getElementById('wl-unknown'),
    error: document.getElementById('wl-error'),
    nolink: document.getElementById('wl-nolink')
  };
  var btn = document.getElementById('wl-confirm-btn');
  var msg = document.querySelector('.status-msg');

  function show(name) {
    Object.keys(panes).forEach(function (k) {
      if (panes[k]) panes[k].hidden = k !== name;
    });
  }
  function say(text, kind) {
    if (!msg) return;
    msg.textContent = text || '';
    msg.className = 'status-msg' + (kind ? ' ' + kind : '');
  }

  // Read the token, then take it out of the address bar. 64 hex characters, checked here so a
  // mistyped or truncated link is explained on the page instead of costing a request.
  var token = (window.location.hash || '').replace(/^#/, '').trim().toLowerCase();
  if (window.history && window.history.replaceState) {
    try {
      window.history.replaceState(null, '', window.location.pathname);
    } catch (e) {
      /* a browser that refuses is no reason to stop */
    }
  }

  if (!/^[0-9a-f]{64}$/.test(token)) {
    show('nolink');
    return;
  }
  if (!cfg || !cfg.endpoint) {
    // The backend is not switched on yet, so there is nothing to confirm against. Say so plainly
    // rather than showing a button that cannot work.
    show('error');
    say('Confirmation is not switched on yet. Email contact@modtech.app and we will add you by hand.', 'err');
    return;
  }

  // The confirm endpoint sits beside the join endpoint, so one configured URL covers both.
  var endpoint = cfg.endpoint.replace(/waitlist-join$/, 'waitlist-confirm');
  if (endpoint === cfg.endpoint) {
    show('error');
    return;
  }

  show('confirm');

  if (btn) {
    btn.addEventListener('click', function () {
      if (btn.disabled) return;
      btn.disabled = true;
      say('Confirming…', '');

      fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token: token })
      })
        .then(function (res) {
          return res
            .json()
            .catch(function () {
              return {};
            })
            .then(function (data) {
              return { status: res.status, data: data || {} };
            });
        })
        .then(function (r) {
          if (r.status === 200 && r.data.ok === true && r.data.state === 'confirmed') {
            say('');
            show('done');
            return;
          }
          if (r.status === 200 && r.data.state === 'expired') {
            say('');
            show('expired');
            return;
          }
          if (r.status === 200 && r.data.state === 'unknown') {
            say('');
            show('unknown');
            return;
          }
          btn.disabled = false;
          if (r.status === 429) {
            say('Too many tries just now. Wait a minute and press the button again.', 'err');
          } else {
            say('Not confirmed. Try again in a minute, or email contact@modtech.app', 'err');
          }
        })
        .catch(function () {
          btn.disabled = false;
          say('Not confirmed. Check your connection and try again, or email contact@modtech.app', 'err');
        });
    });
  }
})();
