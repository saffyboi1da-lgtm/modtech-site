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
# Three more things are checked in both modes (each is explained where it is checked, below):
#   WHICH WEBSITE this tree is. The CNAME must be exactly modtech.app or modtechstudios.com, and every canonical, og:url and og:image tag,
#   every sitemap <loc>, the robots.txt Sitemap line and every visible host label must agree with it. Both hosts as URLs in one tree, or a
#   contact address other than contact@modtech.app, is refused.
#   DATES. Nothing is published before 2026-11-17 (the hold on the v2 package). Until 2026-11-26 the held business-name operator wording
#   must be in neither the tree nor the unpushed history. The date is Melbourne's today, from `date`; a wrong system clock defeats this
#   (it is a backstop, not a gate), and there is deliberately no override variable here.
#   THE SECOND DOMAIN. A tree whose CNAME is modtechstudios.com is refused unless tools/notice2-sent.txt ('sent: YYYY-MM-DD', committed)
#   records the written notice to Paddle. With it, --paused is allowed from the later of 2026-11-17 and that date; a live (checkout-on)
#   build also needs 31 days since that date and a committed tools/website-approval-seen.txt ('approved: YYYY-MM-DD').
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

# ---- The waitlist switch -------------------------------------------------------------------------------------------
# assets/waitlist-config.js holds the single line that decides whether this site collects personal data. Nothing else in
# this guard looked at that file: a Supabase function URL is neither secret-shaped nor an unresolved placeholder, so a
# one-character edit plus a push used to print "safe to publish" and start collecting strangers' addresses.
# Switching the form on is not a config tweak. The notice sent to legal@paddle.com under MSA clause 9.5 on 17 Oct 2026
# promises a SEPARATE written heads-up before "the waitlist starts collecting anything", so turning it on takes a second,
# committed file that records the date that heads-up was sent. Two files, one commit, a record left behind.
wcfg=assets/waitlist-config.js
WMARKER=tools/WAITLIST-LIVE
# The waitlist part of the privacy page: everything between the "The waitlist" heading and the next heading.
wsection() { awk '/id="waitlist"/ { f = 1; next } f && /<h2/ { f = 0 } f' privacy/index.html 2>/dev/null; }
wendpoint=""
if [ ! -f "$wcfg" ]; then
  fail "$wcfg is missing, so whether this site collects personal data cannot be determined"
else
  wn=$(grep -cE "^[[:space:]]*endpoint[[:space:]]*:" "$wcfg" 2>/dev/null); wn=${wn:-0}
  if [ "$wn" != 1 ]; then
    fail "'endpoint' must appear exactly once in $wcfg (found $wn): a later duplicate would win in JavaScript"
  else
    # The ON/OFF decision below reads the value with a regex that needs a quote straight after the colon. A backtick string or a
    # parenthesised value would be read as OFF here while the browser still POSTs to it, so any shape but a plain quoted
    # string is refused outright (fail closed) instead of being guessed at.
    grep -qE "^[[:space:]]*endpoint[[:space:]]*:[[:space:]]*(''|\"\"|'[^']*'|\"[^\"]*\"),?[[:space:]]*$" "$wcfg" || fail "$wcfg: the 'endpoint' line must be a plain quoted string ('' or \"\" or '...' or \"...\") and nothing else on the line, so that whether the form is on can be read reliably"
    wendpoint=$(sed -nE "s/^[[:space:]]*endpoint[[:space:]]*:[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" "$wcfg" | head -1)
    if [ -n "$wendpoint" ] && ! printf '%s' "$wendpoint" | grep -qE '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?\.supabase\.co/functions/v1/waitlist-join$'; then
      fail "$wcfg: 'endpoint' must be either '' (the form off, visitors are pointed at the contact address) or exactly https://<project-ref>.supabase.co/functions/v1/waitlist-join — found $(shape "$wendpoint")"
    fi
  fi
fi
if [ -n "$wendpoint" ]; then
  # The form is ON. Everything the public pages promise about it has to be true on this same commit.
  [ -f "$WMARKER" ] || fail "the waitlist form is ON ($wcfg sets an endpoint) but $WMARKER does not exist. That switch is what the clause 9.5 notice calls 'the waitlist starts collecting': send Paddle the written heads-up first, then create $WMARKER recording the date it was sent, and commit both in one change"
  # The marker also records that the scheduled clean-up was SEEN to remove a test entry (runbook section 13 step 6). The
  # guard cannot see the database, so this is an attestation, but a missing line stops a same-day flip.
  if [ -f "$WMARKER" ]; then
    grep -qE '^purge-job-verified: 20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[[:space:]]*$' "$WMARKER" || fail "the waitlist form is ON but $WMARKER has no 'purge-job-verified: YYYY-MM-DD' line. The privacy page says unconfirmed entries are removed by a daily clean-up; that is only true once the scheduled job has been seen to run (docs/LICENSE_BACKEND_RUNBOOK.md section 13 step 6): record the day you saw it"
  fi
  grep -q 'id="waitlist-off-notice"' privacy/index.html && fail "the waitlist form is ON but privacy/index.html still carries the opening paragraph that says 'The sign-up form on this website is not switched on yet' (id waitlist-off-notice): delete that whole paragraph in the same change"
  wsection | grep -q 'Resend' || fail "the waitlist form is ON but the waitlist section of privacy/index.html does not name Resend: that page promises the sending provider 'will be named here before we use it to send you anything'"
  wsection | grep -q 'will be named here before we use it' && fail "the waitlist form is ON but the waitlist section of privacy/index.html still says the sending provider 'will be named here before we use it to send you anything': name the provider and delete that sentence"
else
  grep -q 'id="waitlist-off-notice"' privacy/index.html 2>/dev/null || fail "the waitlist form is OFF but privacy/index.html does not say so: the page describes the sign-up form, its emails and its clean-up as if they ran, so it must open the waitlist section with the paragraph (id waitlist-off-notice) that says 'The sign-up form on this website is not switched on yet'"
  [ ! -f "$WMARKER" ] || fail "$WMARKER exists but $wcfg sets no endpoint. A stale marker would silently authorise the next flip: delete it, or set the endpoint in the same change"
fi

# ---- Which website this tree is, and whether every part of it agrees -----------------------------------------------------------------
# The site is served from two hosts that never redirect to each other (the notice sent to Paddle on 26 Oct 2026): modtech.app, which
# Paddle has approved, and modtechstudios.com. GitHub Pages serves ONE domain per repo, named by its CNAME file, so each repo carries one
# variant of the same tree. Nothing here used to read a host at all, so a half-swapped tree, or the modtechstudios.com variant pushed to
# the modtech.app repo (which would detach the approved domain), printed "safe to publish". This block reads the CNAME and demands that
# everything that names a host agrees with it. The contact address is the one thing that does NOT follow the host: it stays
# contact@modtech.app on both variants (the sent notice says the contact address on the website remains that one).
HOST_APP=modtech.app
HOST_STUDIOS=modtechstudios.com
CONTACT_DOMAIN=modtech.app
# The files a push publishes: everything except .git (a FILE in a linked worktree, a directory elsewhere), .claude/, the top-level tools/
# and README.md, which is the list _config.yml excludes. NUL-separated; the optional argument is a -name glob.
pubfiles() {
  if [ -n "$1" ]; then find . \( -name .git -o -path ./.claude -o -path ./tools -o -path ./README.md \) -prune -o -type f -name "$1" -print0 2>/dev/null
  else find . \( -name .git -o -path ./.claude -o -path ./tools -o -path ./README.md \) -prune -o -type f -print0 2>/dev/null; fi
}
# pubgrep / htmlgrep GREP-ARGS: grep over the published files (htmlgrep: the .html ones only), printing "path:..." lines. Read the output,
# not the status: a check that needs something to be there asks for it explicitly, so a grep that finds nothing can never pass by itself.
pubgrep() { pubfiles | xargs -0 grep -aH "$@" 2>/dev/null; }
htmlgrep() { pubfiles '*.html' | xargs -0 grep -aH "$@" 2>/dev/null; }

host=""
if [ ! -f CNAME ]; then
  fail "domain: CNAME is missing, so which website this tree is cannot be determined"
else
  # Exactly the host, with at most one trailing newline: no spaces, no second line, no carriage return.
  cn=$(cat CNAME); cnsize=$(wc -c <CNAME | tr -d '[:space:]'); cnok=0
  [ "$cnsize" = "${#cn}" ] && cnok=1
  [ "$cnsize" = "$(( ${#cn} + 1 ))" ] && [ "$(tail -c 1 CNAME | od -An -tx1 | tr -d '[:space:]')" = 0a ] && cnok=1
  if [ "$cnok" = 1 ] && { [ "$cn" = "$HOST_APP" ] || [ "$cn" = "$HOST_STUDIOS" ]; }; then
    host=$cn
  else
    fail "domain: CNAME must be exactly $HOST_APP or $HOST_STUDIOS (the host alone, one line, at most one trailing newline); found '$(printf '%s' "$cn" | cut -c1-60)' in $cnsize bytes"
  fi
fi
if [ -n "$host" ]; then
  if [ "$host" = "$HOST_APP" ]; then other=$HOST_STUDIOS; else other=$HOST_APP; fi
  hre=$(printf '%s' "$host" | sed 's/\./\\./g'); ore=$(printf '%s' "$other" | sed 's/\./\\./g')
  Q="[\"']"
  # tagcheck KIND TAG-REGEX ATTRIBUTE: every such tag in every published page must carry a URL that starts with https://<host>/, and each of
  # the five pages must carry exactly one (so a tag that is deleted, split over two lines or written some other way is a FAIL, not a skip).
  tagcheck() {
    local kind=$1 re=$2 attr=$3 all vals offenders ntag nval n p
    all=$(htmlgrep -oiE "$re")
    vals=$(printf '%s\n' "$all" | sed -nE "s/^([^:]*):.*[[:space:]]$attr=[\"']([^\"']*)[\"'].*\$/\1|\2/p")
    ntag=$(printf '%s' "$all" | grep -c ''); nval=$(printf '%s' "$vals" | grep -c '')
    [ "$ntag" = "$nval" ] || fail "domain: $ntag $kind tag(s) found but only $nval with a readable $attr=\"...\" value, so which host they name cannot be checked"
    for p in index.html pricing/index.html terms/index.html privacy/index.html refunds/index.html; do
      n=$(printf '%s\n' "$all" | grep -c "^\./$p:")
      [ "$n" = 1 ] || fail "domain: $p must carry exactly one $kind tag (found $n)"
    done
    offenders=$(printf '%s\n' "$vals" | awk -F'|' -v p="https://$host/" 'NF && index($2, p) != 1')
    [ -z "$offenders" ] || fail_hits "domain: a $kind tag does not start with https://$host/ (the CNAME names $host):" "$offenders"
  }
  tagcheck canonical "<link[^>]*rel=${Q}?canonical${Q}?[^>]*>" href
  tagcheck og:url "<meta[^>]*property=${Q}og:url${Q}[^>]*>" content
  tagcheck og:image "<meta[^>]*property=${Q}og:image${Q}[^>]*>" content

  if [ ! -f sitemap.xml ]; then
    fail "domain: sitemap.xml is missing"
  else
    nloc=$(( $(grep -ao '<loc' sitemap.xml | wc -l) ))
    locs=$(grep -aoE '<loc>[^<]*</loc>' sitemap.xml | sed -E 's#^<loc>(.*)</loc>$#\1#'); nlocs=$(printf '%s' "$locs" | grep -c '')
    { [ "$nloc" -ge 1 ] && [ "$nloc" = "$nlocs" ]; } || fail "domain: sitemap.xml must hold at least one <loc>, each readable as <loc>URL</loc> on one line (found $nloc <loc tags, $nlocs readable)"
    offenders=$(printf '%s\n' "$locs" | awk -v p="https://$host/" 'NF && index($0, p) != 1')
    [ -z "$offenders" ] || fail_hits "domain: sitemap.xml has a <loc> that does not start with https://$host/ (the CNAME names $host):" "$offenders"
  fi
  if [ ! -f robots.txt ]; then
    fail "domain: robots.txt is missing"
  else
    rl=$(grep -aiE '^[[:space:]]*sitemap[[:space:]]*:' robots.txt)
    if [ -z "$rl" ]; then
      fail "domain: robots.txt has no Sitemap: line"
    else
      offenders=$(printf '%s\n' "$rl" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//' | awk -v p="https://$host/" 'NF && index($0, p) != 1')
      [ -z "$offenders" ] || fail_hits "domain: robots.txt has a Sitemap line that does not start with https://$host/ (the CNAME names $host):" "$offenders"
    fi
  fi

  # The visible host labels: the grey bar on the Terms, Privacy and Refund pages (<span>host</span>) and the 404 sentence. Each must be there,
  # which also proves the pattern still matches the markup, and none may name the other host.
  for p in terms privacy refunds; do
    grep -aqE "<span>[[:space:]]*$hre[[:space:]]*</span>" $p/index.html 2>/dev/null || fail "domain: $p/index.html has no <span>$host</span> host label in its header bar (the CNAME names $host)"
  done
  grep -aqE "exist on $hre" 404.html 2>/dev/null || fail "domain: 404.html does not say 'does not exist on $host' (the CNAME names $host)"
  hits=$(htmlgrep -niE "<span[^>]*>[[:space:]]*(www\.)?$ore[[:space:]]*</span>|exists? on (www\.)?$ore")
  [ -z "$hits" ] || fail_hits "domain: a visible host label names $other, but the CNAME names $host:" "$hits"

  # One site names one host: both hosts as URLs anywhere in the published files means a half-swapped tree or a mixed-up copy.
  UP='(https?:)?//([A-Za-z0-9-]+\.)*'; UE='([^A-Za-z0-9-]|$)'
  ha=$(pubgrep -niE "${UP}modtech\.app${UE}"); hs=$(pubgrep -niE "${UP}modtechstudios\.com${UE}")
  if [ -n "$ha" ] && [ -n "$hs" ]; then
    fail "domain: both $HOST_APP and $HOST_STUDIOS appear as URLs in the published files (one site names one host). First hits for each:"
    printf '%s\n' "$ha" | head -3 | redact | cut -c1-140; printf '%s\n' "$hs" | head -3 | redact | cut -c1-140
  fi

  # The contact address does not follow the host: every contact@ address, every mailto: target and every address at the second domain.
  CD=$(printf '%s' "$CONTACT_DOMAIN" | sed 's/\./\\./g')
  hits=$(pubgrep -noiE 'contact@[A-Za-z0-9._-]*[A-Za-z0-9]' | grep -aviE ":contact@$CD\$")
  [ -z "$hits" ] || fail_hits "domain: a contact address is not contact@$CONTACT_DOMAIN (it stays that one on both websites):" "$hits"
  hits=$(pubgrep -noiE "mailto:[^\"' <>?#)]*" | grep -aviE ":mailto:contact@$CD\$")
  [ -z "$hits" ] || fail_hits "domain: a mailto: link does not point at contact@$CONTACT_DOMAIN (the only contact address on either website):" "$hits"
  hits=$(pubgrep -noiE '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)*modtechstudios\.com')
  [ -z "$hits" ] || fail_hits "domain: an email address at $HOST_STUDIOS is in the published files (there is no mail address there yet, and the privacy page names only the one at $CONTACT_DOMAIN):" "$hits"
fi

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

# ---- Dates, the held wording, and the markers that lift the second domain's hold --------------------------------------------------------
SITE_NOT_BEFORE=2026-11-17        # the hold on this whole v2 package (the notices sent to Paddle under MSA clause 9.5)
OPERATOR_NOT_BEFORE=2026-11-26    # the hold on the business-name operator wording in the Terms and the Privacy Policy
NOTICE2_NOT_BEFORE=2026-10-26     # the second notice (the domain move) cannot have been sent before the move was decided
NOTICE2_WAIT_DAYS=31              # a checkout-on build for modtechstudios.com: this many days after the second notice
# isodate_add DATE DAYS: prints DATE plus DAYS days as YYYY-MM-DD (DAYS may be 0), or nothing and status 1 when DATE is not a real calendar date.
isodate_add() {
  awk -v d="$1" -v n="${2:-0}" '
    function days(y, m, dd,    era, yoe, doy, doe) {
      if (m <= 2) y = y - 1
      era = int(y / 400); yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    function civil(z,    era, doe, yoe, y, doy, mp) {
      z = z + 719468
      era = int(z / 146097); doe = z - era * 146097
      yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
      y = yoe + era * 400
      doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
      mp = int((5 * doy + 2) / 153)
      cd = doy - int((153 * mp + 2) / 5) + 1
      cm = mp + (mp < 10 ? 3 : -9)
      cy = y + (cm <= 2 ? 1 : 0)
    }
    BEGIN {
      if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
      y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
      if (m < 1 || m > 12 || dd < 1) exit 1
      z = days(y, m, dd); civil(z)
      if (cy != y || cm != m || cd != dd) exit 1
      civil(z + n)
      printf "%04d-%02d-%02d\n", cy, cm, cd
    }'
}
before() { [[ "$1" < "$2" ]]; }   # ISO dates compare as strings (this script runs in the C locale)
# Melbourne's today. A date that cannot be read is a FAIL, never a skip, and every date floor below is then treated as not met.
today=$(TZ=Australia/Melbourne date +%F 2>/dev/null)
if [ -z "$today" ] || [ "$(isodate_add "$today" 0)" != "$today" ]; then
  fail "dates: today's date could not be read as a real YYYY-MM-DD (got '$(printf '%s' "$today" | cut -c1-30)'), so no date floor can be checked"
  today=""
elif before "$today" "$SITE_NOT_BEFORE"; then
  fail "dates: today is $today, before $SITE_NOT_BEFORE. Nothing from this v2 package is published before then (the hold stated in the notices sent to Paddle)"
fi

# The held operator wording. The Terms and the Privacy Policy do not take the business name before OPERATOR_NOT_BEFORE: the name must be in
# neither the files nor the added lines and messages of the unpushed commits (a push publishes all of them). The phrase is matched with any
# separator between its two words (space, line break, &nbsp;, &#160;, any byte that is not printable ASCII, which covers a no-break or
# zero-width space in UTF-8, hyphen, underscore, plus, %20), in any case. The hostname has no separator, so it never matches. NOTHING is
# exempt, the guard and its tests included: neither file may hold the phrase, and the pattern below keeps one letter in brackets so that its
# own text is not the phrase. The two words never appear together in this script.
HELD_RE="modtech([[:space:]]|&nbsp;|&#160;|&#[xX][aA]0;|[^[:print:]]|[-_+]|%20)+[s]tudios"
hold=1
{ [ -n "$today" ] && ! before "$today" "$OPERATOR_NOT_BEFORE"; } && hold=0
held_history() {
  local cant="so the unpushed history was not scanned for the held wording" hd rc
  git rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1 \
    || { fail "held wording: there is no origin/main ref here (run git fetch), $cant"; return; }
  hd=$(mktemp -d) || { fail "held wording: mktemp failed, $cant"; return; }
  git log --format='%B' origin/main..HEAD >"$hd/msg" 2>/dev/null \
    || { fail "held wording: git log origin/main..HEAD failed, $cant"; rm -rf "$hd"; return; }
  git log --root -p --text -m --no-textconv --format= origin/main..HEAD >"$hd/patch" 2>/dev/null \
    || { fail "held wording: git log -p origin/main..HEAD failed, $cant"; rm -rf "$hd"; return; }
  grep -a '^+' "$hd/patch" >"$hd/added"; rc=$?
  [ "$rc" -le 1 ] || { fail "held wording: grep failed while reading the added lines, $cant"; rm -rf "$hd"; return; }
  sed 's/^+//' "$hd/added" >"$hd/added2" \
    || { fail "held wording: sed failed while reading the added lines, $cant"; rm -rf "$hd"; return; }
  cat "$hd/msg" "$hd/added2" | tr '\r\n\t\f\v' '     ' >"$hd/flat" \
    || { fail "held wording: tr failed while joining the lines, $cant"; rm -rf "$hd"; return; }
  grep -aiqE "$HELD_RE" "$hd/flat"; rc=$?
  if [ "$rc" = 0 ]; then
    fail "held wording: the business-name operator wording is in the unpushed history (origin/main..HEAD, an added line or a commit message). A push publishes every commit, so it cannot go out before $OPERATOR_NOT_BEFORE even if the files are clean. Commits whose own lines hold it:"
    git log -i -E -G"$HELD_RE" --format='        %h %s' origin/main..HEAD 2>/dev/null | redact | cut -c1-120
  elif [ "$rc" -gt 1 ]; then
    fail "held wording: grep failed while scanning the history, $cant"
  fi
  rm -rf "$hd"
}
if [ "$hold" = 1 ]; then
  held_files=""
  while IFS= read -r -d '' f; do
    if printf '%s' "$f" | grep -aiqE "$HELD_RE" || tr '\r\n\t\f\v' '     ' <"$f" | grep -aiqE "$HELD_RE"; then held_files="$held_files$f"$'\n'; fi
  done < <(find . -name .git -prune -o -type f -print0 2>/dev/null)
  [ -z "$held_files" ] || fail_hits "held wording: the business-name operator wording is in the files below. It is not published before $OPERATOR_NOT_BEFORE (or any later date Paddle states in writing), so it stays on its own unmerged branch until then:" "${held_files%$'\n'}"
  if [ "$at_root" = 1 ] && [ -n "$sha" ]; then
    held_history
  elif [ "$at_root" != 1 ] && [ "$paused" != 1 ]; then
    echo "NOTE: this is not the root of a git checkout, so the unpushed history was NOT scanned for the held operator wording (before $OPERATOR_NOT_BEFORE)"
  fi
fi

# The second domain. A tree that serves modtechstudios.com is refused until the written second notice to Paddle (the domain move) is on
# record, and a checkout-on build waits 31 days after it and needs Paddle's website approval seen. The two markers are attestations: the
# guard cannot see the mailbox or the dashboard. Each must be COMMITTED (the guard approves HEAD, not the working tree), unchanged since,
# and hold exactly one well-formed line, so an edited, stale, duplicated or half-typed marker is a FAIL.
# marker_read FILE KEY: sets mdate to the date on the one 'KEY: YYYY-MM-DD' line of FILE; returns 1, with the reason in mwhy, otherwise.
marker_read() {
  local f=$1 key=$2 content n
  mdate=""; mwhy=""
  [ -f "$f" ] || { mwhy="$f does not exist"; return 1; }
  { [ "$at_root" = 1 ] && [ -n "$sha" ]; } || { mwhy="this is not the root of a git checkout with a commit, so it cannot be shown that $f is committed"; return 1; }
  content=$(git show "HEAD:$f" 2>/dev/null) || { mwhy="$f is not committed in HEAD (the guard approves the commit, not the working tree: commit it first)"; return 1; }
  git show "HEAD:$f" 2>/dev/null | cmp -s - "$f" || { mwhy="$f differs from the committed copy"; return 1; }
  n=$(printf '%s\n' "$content" | grep -aEc "^$key:")
  [ "$n" = 1 ] || { mwhy="$f must hold exactly one line that starts '$key:' (found $n)"; return 1; }
  mdate=$(printf '%s\n' "$content" | grep -aE "^$key:" | sed -nE "s/^$key: (20[0-9][0-9]-[0-9][0-9]-[0-9][0-9])[[:space:]]*\$/\1/p")
  [ -n "$mdate" ] || { mwhy="the '$key:' line in $f must read exactly '$key: YYYY-MM-DD'"; return 1; }
  [ "$(isodate_add "$mdate" 0)" = "$mdate" ] || { mwhy="the date in $f ($mdate) is not a real calendar date"; mdate=""; return 1; }
  return 0
}
if [ "$host" = "$HOST_STUDIOS" ]; then
  if ! marker_read tools/notice2-sent.txt sent; then
    fail "studios: the CNAME names $HOST_STUDIOS, and that variant is refused until the second written notice to Paddle (the domain move) has been sent: $mwhy. After sending it, create tools/notice2-sent.txt with one line 'sent: YYYY-MM-DD' (the day it was sent) and commit it"
  else
    nd=$mdate
    if before "$nd" "$NOTICE2_NOT_BEFORE"; then
      fail "studios: tools/notice2-sent.txt says $nd, before $NOTICE2_NOT_BEFORE (the day the move was decided), so it cannot be the day the second notice was sent"
    elif [ -n "$today" ]; then
      floor=$SITE_NOT_BEFORE; before "$floor" "$nd" && floor=$nd
      if [ "$paused" = 1 ]; then
        before "$today" "$floor" && fail "studios: today is $today; a paused publish of $HOST_STUDIOS waits for the later of $SITE_NOT_BEFORE and the day the second notice was sent ($nd), so not before $floor"
      else
        live_from=$(isodate_add "$nd" "$NOTICE2_WAIT_DAYS")
        if [ -z "$live_from" ]; then
          fail "studios: could not add $NOTICE2_WAIT_DAYS days to the notice date $nd"
        elif before "$today" "$live_from"; then
          fail "studios: today is $today; a checkout-on (non-paused) build for $HOST_STUDIOS waits $NOTICE2_WAIT_DAYS days after the second notice ($nd), so not before $live_from"
        fi
        if ! marker_read tools/website-approval-seen.txt approved; then
          fail "studios: a checkout-on (non-paused) build for $HOST_STUDIOS also needs Paddle's website approval seen in the dashboard: $mwhy. Create tools/website-approval-seen.txt with one line 'approved: YYYY-MM-DD' and commit it"
        else
          ad=$mdate
          before "$ad" "$NOTICE2_NOT_BEFORE" && fail "studios: tools/website-approval-seen.txt says $ad, before $NOTICE2_NOT_BEFORE (the day the move was decided)"
          before "$today" "$ad" && fail "studios: tools/website-approval-seen.txt says $ad, which is after today ($today)"
        fi
      fi
    fi
  fi
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
