#!/bin/bash
# Refuses to pass while the site points at Paddle's SANDBOX, carries a half-swapped checkout config, an unresolved
# placeholder, or anything that looks like a secret. Run before every push to main: tools/check-before-publish.sh
# The config is read value by value (single or double quotes, spaces before the colon allowed), so a live token paired with
# the sandbox price id, a blank token or a quoted-differently line cannot slip through.
#
# Two modes. Default = LIVE: the real token, the real price id and a boolean gate must all be present.
#   tools/check-before-publish.sh --paused = PAUSED: the first publish, which goes out with NO checkout configuration (empty token,
#   empty price id, gated true, so the Subscribe button is off for everyone). The flag is explicit and is never inferred from a blank
#   token: live mode keeps refusing a blank token. Any other argument exits 2.
#   --paused also enforces the paused PAGES: the pricing page must say "Subscriptions are not open yet", and no page may still carry
#   the live-state agreement note or the licence-key delivery paragraph that sit next to an open button.
#
# The guard reads the WORKING TREE, but a push publishes HEAD. So both modes fail while `git status --porcelain` reports any change
# under the site (commit the dates and every other edit first), and both fail when HEAD is detached (the guard approves the commit
# that is checked out, so it must be on a branch). On success it prints "branch: <name> sha: <full sha>": push exactly that commit
# (git push origin HEAD:main from this checkout). --paused also needs the root of a git checkout with an origin/main ref (run
# `git fetch` first), because it scans every unpushed commit (patches, binary files and commit messages) for a live token, a live
# price id or a secret-shaped string. That history scan FAILS CLOSED: every step is checked, and a step that cannot be completed is
# a FAIL, never a skip.
#
# LC_ALL=C: under a UTF-8 locale BSD grep skips (and sed and tr choke on) any line holding an invalid UTF-8 byte, so a token on a
# Latin-1 line would be invisible. In the C locale every byte is a character and no line is skipped.
export LC_ALL=C
cd "$(dirname "$0")/.." || exit 2
paused=0
for arg in "$@"; do
  case "$arg" in
    --paused) paused=1 ;;
    *) echo "usage: tools/check-before-publish.sh [--paused]   (unknown argument: $arg)" >&2; exit 2 ;;
  esac
done
bad=0
fail() { echo "FAIL: $1"; bad=1; }
cfg=assets/checkout-config.js
SANDBOX_PRICE=pri_01m4k1ncbjqap9ppqre6mnbef6
# Anything that looks like a secret: this repo is public and every tracked file is served. A few letters sit in [x] brackets so that
# this file's own text does not match its own patterns: the unpushed history contains this file, and it must hold no secret-shaped text.
SECRETS='pdl_(live|sdbx)_|pdl_[n]tfset_|sb_[s]ecret_|sbp_[A-Za-z0-9]{20}|eyJ[A-Za-z0-9_-]{20,}\.|github_[p]at_|wh[s]ec_|(^|[^A-Za-z0-9])re_[A-Za-z0-9]{24,}'
TOKEN_RE='(live|test)_[A-Za-z0-9]{27}|pri_[a-z0-9]{26}'
LIVE_RE='live_[A-Za-z0-9]{27}|pri_[a-z0-9]{26}'
HIST_RE="$LIVE_RE|$SECRETS"
# Every line this script prints from the site goes through redact, so a failure message never shows a token, a price id or a secret.
redact() { sed -E "s/($SECRETS)[A-Za-z0-9_.=-]*/<redacted-secret>/g; s/(live|test)_[A-Za-z0-9]{27}/\1_<redacted>/g; s/pri_[a-z0-9]{26}/pri_<redacted>/g"; }
# fail_hits "message" "grep output" [width]: a FAIL line, then the matching lines, redacted first and cut second.
fail_hits() { fail "$1"; printf '%s\n' "$2" | redact | cut -c1-"${3:-140}"; }
# Describes a config value without echoing any of it (not even a prefix of a token).
shape() { case "$1" in '') echo "nothing" ;; live_*) echo "a live_ value of ${#1} characters" ;; test_*) echo "a test_ value of ${#1} characters" ;; pri_*) echo "a pri_ value of ${#1} characters" ;; *) echo "a value of ${#1} characters" ;; esac; }
# Greps the whole site except the two files that hold the guard's own test shapes: exactly tools/check-before-publish.sh and
# tools/test-guard.sh. Any other file under tools/ (Pages serves it) is scanned, and so is a copy of those names anywhere else.
# Exit status is that of the last grep: 0 means there were hits outside the two files.
EXEMPT='^\./tools/(check-before-publish\.sh|test-guard\.sh):'
scan() { grep -r "$@" . --exclude-dir=.git | grep -vE "$EXEMPT"; }
val() { sed -nE "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" "$cfg" 2>/dev/null | head -1; }

hits=$(grep -rn --include='*.html' '\[\[' . 2>/dev/null)
[ -z "$hits" ] || { fail_hits "unresolved [[ ]] placeholder:" "$hits"; }

env=$(val environment); token=$(val token); price=$(val priceId)
gated=$(sed -nE 's/^[[:space:]]*gated[[:space:]]*:[[:space:]]*(true|false).*/\1/p' "$cfg" 2>/dev/null | head -1)
# Each key must appear exactly once (a later duplicate would win in JavaScript), whichever mode this is.
cfgcount() { local n; n=$(grep -cE "^[[:space:]]*$1[[:space:]]*:" "$cfg" 2>/dev/null); echo "${n:-0}"; }
cfgline_ok() { grep -qE "^[[:space:]]*$1[[:space:]]*:[[:space:]]*($2),?[[:space:]]*$" "$cfg" 2>/dev/null; }
mode=live; [ "$paused" = 1 ] && mode=paused
for k in environment token priceId gated; do
  [ "$(cfgcount $k)" = 1 ] || fail "$mode: '$k' must appear exactly once in $cfg (found $(cfgcount $k))"
done

# Git state. The guard reads the working tree, but a push publishes HEAD, so uncommitted changes make every other check unreliable.
top=$(git rev-parse --show-toplevel 2>/dev/null)
at_root=0
[ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ] && at_root=1
br=""; sha=""
if [ "$at_root" = 1 ]; then
  st=$(git --no-optional-locks status --porcelain --untracked-files=all -- . 2>&1); strc=$?
  if [ "$strc" != 0 ]; then
    fail "git status failed, so uncommitted changes cannot be ruled out: $(printf '%s' "$st" | head -1 | redact | cut -c1-120)"
  elif [ -n "$st" ]; then
    fail_hits "the working tree has uncommitted changes (this guard reads the working tree, but a push publishes HEAD): commit them (the dates too), then run the guard again:" "$st" 120
  fi
  # The guard approves the commit that is checked out, so that commit must be named by a branch: a detached HEAD could be any commit.
  sha=$(git rev-parse --verify -q HEAD 2>/dev/null)
  br=$(git symbolic-ref -q --short HEAD 2>/dev/null)
  if [ -z "$sha" ]; then
    fail "this git checkout has no commit yet, so there is nothing to approve"
  elif [ -z "$br" ]; then
    fail "HEAD is detached (it is not on a branch), so it is unclear which commit would be pushed: switch to the branch you mean to publish, then run the guard again"
  fi
elif [ "$paused" = 1 ]; then
  fail "paused: this is not the root of a git checkout, so uncommitted changes and the unpushed history cannot be checked (run the guard from the root of the site checkout)"
else
  echo "NOTE: this is not the root of a git checkout, so uncommitted changes were NOT checked"
fi

# Scans every commit the push would publish (origin/main..HEAD): patches (--text makes git show binary files too, --no-textconv shows
# the raw bytes even if a textconv driver is configured), merge diffs against each parent (-m) and commit messages, for a live token, a live price id or a secret-shaped string. Needs $tmpd.
# FAILS CLOSED: each step is checked, and the scan is abandoned with a FAIL if any step cannot be completed. The public sandbox
# price id is excluded by value. Each commit is announced by a marker line so a hit can be named; because a commit message could
# forge a marker line, the number of markers must equal the number git should have printed (one per commit, one per PARENT for a
# merge, because git log -m prints a merge once for each parent); git only ever adds markers, so any forged line changes the count.
scan_history() {
  local cant="so the unpushed history was not scanned" nc nm rc c
  git log -p --text -m --no-textconv --format='@@commit %H%n%B' origin/main..HEAD >"$tmpd/raw" 2>/dev/null \
    || { fail "paused: git log origin/main..HEAD failed, $cant"; return; }
  # NUL bytes are dropped (a UTF-16 file then reads as ASCII, and the lines stay greppable).
  tr -d '\000' <"$tmpd/raw" >"$tmpd/log" \
    || { fail "paused: the history output could not be read (tr failed), $cant"; return; }
  git rev-list --parents origin/main..HEAD >"$tmpd/rl" 2>/dev/null \
    || { fail "paused: git rev-list origin/main..HEAD failed, $cant"; return; }
  nc=$(awk '{ n += (NF > 2 ? NF - 1 : 1) } END { print n + 0 }' "$tmpd/rl") \
    || { fail "paused: could not count the unpushed commits (awk failed), $cant"; return; }
  nm=$(grep -ac '^@@commit ' "$tmpd/log"); rc=$?
  [ "$rc" -le 1 ] || { fail "paused: grep failed while counting the commit markers, $cant"; return; }
  if [ "$nm" != "$nc" ]; then
    fail "paused: the history output holds $nm commit markers but origin/main..HEAD should give $nc: a commit message is forging a marker line, or git's output changed, so hits cannot be attributed to commits and the unpushed history is not trusted"
    return
  fi
  sed "s/$SANDBOX_PRICE/<sandbox-price>/g" "$tmpd/log" >"$tmpd/log2" \
    || { fail "paused: sed failed while reading the history, $cant"; return; }
  grep -aE "^@@commit |$HIST_RE" "$tmpd/log2" >"$tmpd/hits"; rc=$?
  [ "$rc" -le 1 ] || { fail "paused: grep failed while scanning the history, $cant"; return; }
  awk '/^@@commit /{ c = $2; next } { print c }' "$tmpd/hits" >"$tmpd/off" \
    || { fail "paused: awk failed while naming the offending commits, $cant"; return; }
  sort -u "$tmpd/off" >"$tmpd/off2" \
    || { fail "paused: sort failed while naming the offending commits, $cant"; return; }
  if [ -s "$tmpd/off2" ]; then
    fail "paused: a live token, a live price id or a secret-shaped string appears in the unpushed history (origin/main..HEAD); publishing would put it in public history. Publish from a squashed branch built from main. Commits:"
    while IFS= read -r c; do
      git log -1 --format='        %h %s' "$c" 2>/dev/null | redact | cut -c1-120
    done <"$tmpd/off2"
  fi
}

if [ "$paused" = 1 ]; then
  # PAUSED: the config must hold exactly these four lines, each once:
  #   environment: 'live'   token: ''   priceId: ''   gated: true      (single or double quotes)
  cfgline_ok environment "'live'|\"live\"" || fail "paused: checkout environment must be exactly 'live' in $cfg"
  cfgline_ok token "''|\"\"" || fail "paused: the token line must be present and exactly '' (empty) in $cfg"
  cfgline_ok priceId "''|\"\"" || fail "paused: the priceId line must be present and exactly '' (empty) in $cfg"
  cfgline_ok gated "true" || fail "paused: gated must be exactly true in $cfg"

  # The pages must be in their paused state too: the pricing page says the subscriptions are not open, and nothing promises a purchase
  # or a delivery next to a button that is off. (The mirror image, no paused paragraph once the button opens, is checked below.)
  grep -q 'Subscriptions are not open yet' pricing/index.html 2>/dev/null \
    || fail "paused: pricing/index.html does not say 'Subscriptions are not open yet' (the paused paragraph must be on the pricing page while the button is off)"
  hits=$(scan -in --include='*.html' 'By subscribing you agree')
  [ -z "$hits" ] || fail_hits "paused: a page still carries the live-state agreement note 'By subscribing you agree' (it sits next to an open Subscribe button, and the button is off):" "$hits"
  hits=$(scan -in --include='*.html' 'After you subscribe, your licence key')
  [ -z "$hits" ] || fail_hits "paused: a page still carries the live-state delivery paragraph 'After you subscribe, your licence key ...' (nothing can be delivered while the button is off):" "$hits"

  # No client token or price id may sit anywhere on the site (any text file, not just the config); only the guard and its tests are exempt.
  hits=$(scan -In -E "$TOKEN_RE")
  [ -z "$hits" ] || fail_hits "paused: a client token or price id appears in the site (a paused publish carries none):" "$hits" 120

  # Nothing the push is about to publish may contain a live token, a live price id or a secret in its history either: pushing to the
  # public branch publishes every commit in origin/main..HEAD, not just the final files. Needs the ref origin/main (run git fetch
  # first); a missing ref is a FAIL, never a skip.
  if [ "$at_root" = 1 ]; then
    if git rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1; then
      tmpd=$(mktemp -d) || exit 2
      trap 'rm -rf "$tmpd"' EXIT
      scan_history
    else
      fail "paused: there is no origin/main ref here (run git fetch), so the unpushed history cannot be scanned for a live token, a live price id or a secret"
    fi
  fi

  # The pause switch lives in assets/checkout.js (an empty token returns before Paddle is touched). If a later edit removes it, the
  # empty config would no longer keep the button off, so the guard looks for the line itself. node tools/test-checkout.js tests the behaviour.
  grep -qE '^[[:space:]]*if[[:space:]]*\([[:space:]]*![[:space:]]*c\.token[[:space:]]*\).*return' assets/checkout.js 2>/dev/null \
    || fail "paused: assets/checkout.js has no empty-token early return ('if (!c.token) ... return'), so an empty token would not keep the Subscribe button off"
else
  [ "$env" = "live" ] || fail "checkout environment must be 'live' (found $(shape "$env")) in $cfg"
  [[ "$token" =~ ^live_[A-Za-z0-9]{27}$ ]] || fail "the client token must be a LIVE one (live_ then 27 characters); found $(shape "$token") in $cfg"
  [[ "$price" =~ ^pri_[a-z0-9]{26}$ ]] || fail "the price id must be pri_ then 26 characters; found $(shape "$price") in $cfg"
  [ -n "$gated" ] || fail "gated must be true or false in $cfg"
fi

# No page may promise a delivery time: the live system cannot keep "one business day" (the key email is being reworded), and a paused
# publish delivers nothing at all. This guard matches that one phrase only, so that is what the message says.
BD='one[[:space:]]+business[[:space:]]+day'
hits=$(scan -IiEn "$BD")
[ -z "$hits" ] || fail_hits "a page contains the phrase 'one business day', which this guard refuses (a delivery time must not be promised):" "$hits"

# Nothing from the sandbox may survive anywhere on the site (the guard and its tests are exempt).
hits=$(scan -In --include='*.js' --include='*.html' -e 'test_3c71564d' -e "$SANDBOX_PRICE")
[ -z "$hits" ] || fail_hits "the SANDBOX client token or SANDBOX price id appears in the site:" "$hits" 120

grep -q 'cdn.paddle.com/paddle/v2/paddle.js' pricing/index.html 2>/dev/null || fail "the pricing page does not load Paddle.js"

# An internal note whose [[ ]] brackets were removed would pass the placeholder check above, so the words that mark a note are refused too.
LEAK='(^|[^A-Za-z])(HOLD|CONFIRM)([^A-Za-z]|$)|SET the date|then remove the brackets|D-0[0-9][0-9]'
hits=$(scan -nE --include='*.html' "$LEAK")
[ -z "$hits" ] || fail_hits "an internal note (HOLD / CONFIRM / SET the date / D-0xx) is on a public page:" "$hits"

# The paused paragraph ("Subscriptions are not open yet") must not survive into an open button: when gated is false it is on no page.
if [ "$gated" = "false" ]; then
  hits=$(scan -in --include='*.html' 'Subscriptions are not open yet')
  [ -z "$hits" ] || fail_hits "gated is false (the Subscribe button is open) but a page still says 'Subscriptions are not open yet' (the paused paragraph must go when the button opens):" "$hits"
fi

# Publish #1 (gated: true) goes out BEFORE the installer exists, so four sentences about the installer were held out of the pages
# (full text and where each goes back: tribevault-backend docs/SITE_HELD_SENTENCES.md). The public flip (gated: false) must not happen without them.
if [ "$gated" = "false" ]; then
  need() { grep -qi "$2" "$1" 2>/dev/null || fail "gated is false but $1 does not mention '$2': ${3:-the sentence held out of publish #1 is not back (tribevault-backend docs/SITE_HELD_SENTENCES.md)}"; }
  need pricing/index.html 'follows separately' "the delivery sentence without a time promise (the download link 'follows separately') is missing"
  need pricing/index.html 'By subscribing you agree' "the agreement note next to the open Subscribe button is missing"
  need pricing/index.html offline
  need terms/index.html offline
  need refunds/index.html offline
  need index.html 'pricing and subscribe'
  if ! grep -q 'Update check' privacy/index.html 2>/dev/null && ! grep -q 'no-update-feed-confirmed' privacy/index.html 2>/dev/null; then
    fail "gated is false but privacy/index.html has neither the 'Update check' paragraph nor the comment <!-- no-update-feed-confirmed --> (confirm what the shipped build does about updates first)"
  fi
  if grep -q 'Update check' privacy/index.html 2>/dev/null && grep -qi 'online only to check your licen' pricing/index.html index.html 2>/dev/null; then
    fail "privacy says the app checks for updates, but pricing/index.html or index.html still says it goes online ONLY to check the licence and send feedback:"; grep -ni 'online only to check your licen' pricing/index.html index.html | redact | cut -c1-140
  fi
fi

# This repo is public and every tracked file is served: nothing that looks like a secret may be in it.
hits=$(scan -In -E "$SECRETS")
[ -z "$hits" ] || fail_hits "something that looks like a secret is in the site:" "$hits" 100

if [ "$bad" = 0 ]; then
  if [ "$paused" = 1 ]; then echo "NOTE: PAUSED publish: no checkout configuration; the Subscribe button is off for everyone"
  elif [ "$gated" = "true" ]; then echo "NOTE: gated is true: only the #founder link opens checkout; the public button stays off"
  else echo "NOTE: gated is false: the Subscribe button is open to everyone"; fi
  # Which commit this approval is for. Push exactly this one: git push origin HEAD:main, from this checkout.
  [ -z "$sha" ] || echo "branch: $(printf '%s' "$br" | redact) sha: $sha"
  echo "OK: safe to publish"
else
  echo "NOT safe to publish"
fi
exit $bad
