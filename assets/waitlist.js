/*
 * The waitlist form. Progressive enhancement: the markup is a real form, this file only
 * upgrades it. With no endpoint configured (see waitlist-config.js) every form is switched
 * off and says what to do instead, rather than pretending to accept an address.
 *
 * A page may carry more than one of these (the home page has one in the hero and one at the
 * foot), so every form.wl is wired, each with its own message line.
 *
 * DOUBLE OPT-IN. Submitting adds nothing to the list: the server emails a link to the address
 * and only clicking it joins. That is why the success message never says "you are on the list"
 * (untrue for every single submission, including one where somebody typed a stranger's address)
 * and never says that an email was sent (see the 200 branch below).
 *
 * What is sent: the address, the two optional fields, the honeypot, and the ID of the consent
 * wording shown above the button (not the wording itself — the server keeps the id, and the
 * text it refers to lives in the repository). `source` is NOT sent: the server takes it from
 * the request's own origin, so a caller cannot label their rows.
 *
 * The only reply treated as success is a 200. A network error, a 4xx or a 5xx says "not saved".
 * A 200 does not always mean mail was sent (opted out, already confirmed, one sent in the last
 * 24 hours, capped), and the page must not reveal which, so the success line is conditional.
 */
(function () {
  var cfg = window.MODTECH_WAITLIST;
  var forms = document.querySelectorAll('form.wl');
  if (!forms.length) return;

  Array.prototype.forEach.call(forms, function (form) {
    var email = form.querySelector('input[name="email"]');
    var btn = form.querySelector('button');
    var msg = form.querySelector('.status-msg');

    function say(text, kind) {
      if (!msg) return;
      msg.textContent = text;
      msg.className = 'status-msg' + (kind ? ' ' + kind : '');
    }

    function lock() {
      Array.prototype.forEach.call(form.querySelectorAll('input'), function (i) { i.disabled = true; });
      if (btn) btn.disabled = true;
    }

    if (!cfg || !cfg.endpoint) {
      // Nothing to POST to yet. A disabled box beside a plain-text address is a
      // dead end, so the whole form is replaced by the one thing that does work:
      // a mailto link you can click. Nobody is invited to type into a void.
      var fallback = document.createElement('p');
      fallback.className = 'wl-fallback';
      fallback.innerHTML =
        'The list is not taking sign-ups through the site yet. Email ' +
        '<a href="mailto:contact@modtech.app?subject=ModTech%20waitlist">contact@modtech.app</a>' +
        ' and we will add you, and tell you when ModTech opens.';
      form.parentNode.replaceChild(fallback, form);
      return;
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (btn && btn.disabled) return;

      var address = ((email && email.value) || '').trim();
      // The browser checks type="email" too; this is the message, not the gate.
      if (!address || address.indexOf('@') < 1 || address.lastIndexOf('.') < address.indexOf('@')) {
        say('That email address does not look right.', 'err');
        if (email) email.focus();
        return;
      }

      function field(name) {
        var el = form.querySelector('input[name="' + name + '"]');
        return el ? el.value : '';
      }
      var consent = form.querySelector('.consent');
      // The ID of the wording, not the wording. If the attribute is ever missing the server
      // refuses the submission, which is the right way round: better a visible failure than a
      // row stored against a consent record nobody can reconstruct.
      var consentVersion = consent ? (consent.getAttribute('data-consent-version') || '') : '';

      var body = {
        email: address,
        brand: field('brand'),
        makes: field('makes'),
        // Honeypot: off-screen, aria-hidden and not tabbable, so a real person
        // never fills it. Named wl_ref in the markup — "company" would be a
        // plausible field for a password manager to autofill for a real visitor.
        honeypot: field('wl_ref'),
        consent_version: consentVersion
      };

      if (btn) btn.disabled = true;
      say('Sending…', '');

      fetch(cfg.endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body)
      }).then(function (res) {
        if (res.ok) {
          lock();
          // Shown for EVERY 200, including the branches where no mail goes out (opted out, already confirmed,
          // sent one in the last 24 hours, capped, honeypot). The page must not reveal which, so this one line
          // has to stay conditional: it never says an email was sent.
          say('If this address can be confirmed, a link is on its way. Click it to confirm. If nothing arrives within a few minutes, check your spam folder or email contact@modtech.app', 'ok');
          return;
        }
        if (btn) btn.disabled = false;
        if (res.status === 429) {
          say('Too many tries just now. Wait a minute, or email contact@modtech.app', 'err');
        } else {
          say('Not saved. Email contact@modtech.app and we will add you.', 'err');
        }
      }).catch(function () {
        if (btn) btn.disabled = false;
        say('Not saved. Email contact@modtech.app and we will add you.', 'err');
      });
    });
  });
})();
