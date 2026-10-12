#!/bin/bash
# Proves tools/check-before-publish.sh refuses every way a half-swapped config could slip through, and passes the
# intended one, in both modes (default = LIVE, and --paused = the first publish with no checkout configuration).
# Runs on scratch COPIES; touches nothing here. Usage: tools/test-guard.sh
# Set GUARD_TEST_VERBOSE=1 to see which check fired for each case.
# Run it under any locale (LC_ALL=C tools/test-guard.sh, then LC_ALL=en_US.UTF-8 tools/test-guard.sh). The guard pins the C locale
# itself; the invalid-UTF-8 cases start it from a UTF-8 caller on purpose, and this file's own checks run in the C locale.
# No secret-shaped literal sits in this file: every fake token, price id and secret is built at run time (GOODTOKEN, GOODPRICE and
# fake() below), because the unpushed history of a publish contains this file and the guard scans that history for them.
cd "$(dirname "$0")/.." || exit 2
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"   # a scratch copy that is not a git repo must never find a repo above it
SD="$T/s"                              # the scratch copy the guard runs in
GOODTOKEN=live_$(printf 'a%.0s' $(seq 1 27))   # fake: live_ + 27 characters, built at run time so this file never holds a live-shaped string
GOODPRICE=pri_$(printf 'b%.0s' $(seq 1 26))    # fake: pri_ + 26 characters, built at run time for the same reason
SANDBOXPRICE=pri_01m4k1ncbjqap9ppqre6mnbef6    # the public sandbox price id (the guard excludes it from the history scan by value)
fake() { # fake SHAPE: a secret-shaped string built at run time, one per alternative in the guard's SECRETS pattern
  case "$1" in
    pdl_live)   printf '%s_live_%s' pdl abcdefghij0123456789 ;;
    pdl_sdbx)   printf '%s_sdbx_%s' pdl abcdefghij0123456789 ;;
    pdl_ntfset) printf '%s_ntfset_%s' pdl abcdefghij0123456789 ;;
    sb_secret)  printf '%s_secret_%s' sb ABCDEFGHIJKLMNOPQRSTUVWX ;;
    sbp)        printf '%s_%s' sbp abcdefghij0123456789ABCD ;;
    jwt)        printf '%s%s.%s' eyJ hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 abcDEF123 ;;
    github_pat) printf '%s_pat_%s' github 11ABCDEFG0abcdefghijkl ;;
    whsec)      printf '%s_%s' whsec abcdefghijklmnopqrstuvwxyz ;;
    resend)     printf ' %s_%s' re abcdefghijklmnopqrstuvwxyz ;;   # this shape needs a non-alphanumeric character before it
  esac
}
SHAPES="pdl_live pdl_sdbx pdl_ntfset sb_secret sbp jwt github_pat whsec resend"
UTF8LOC=""   # a UTF-8 locale for the cases that start the guard from a UTF-8 caller (the guard must still see Latin-1 lines)
for l in en_US.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
  if locale -a 2>/dev/null | LC_ALL=C grep -qxF "$l"; then UTF8LOC=$l; break; fi
done
[ -n "$UTF8LOC" ] || echo "NOTE: no UTF-8 locale is installed here; the invalid-UTF-8 cases start the guard in the ambient locale instead"
fails=0
G() { LC_ALL=C grep "$@"; }   # this file's own greps run in the C locale, so a guard line holding an invalid UTF-8 byte is still matched
genv() { env ${GLOC:+LC_ALL=$GLOC} ${GPATH:+PATH=$GPATH} "$@"; }   # GLOC / GPATH: a per-case locale or PATH for the guard
why() { [ -n "$GUARD_TEST_VERBOSE" ] && printf '%s\n' "$out" | G -E -m3 '^(FAIL|usage|NOTE)' | cut -c1-150 | sed 's/^/          /'; return 0; }
fresh() { rm -rf "$SD"; mkdir "$SD"; rsync -a --exclude .git ./ "$SD/"; find "$SD" -name '*.html' -exec perl -pi -e 's/\[\[.*?\]\]//g' {} +; }
config() { cat > "$SD/assets/checkout-config.js" <<CFG
window.MODTECH_CHECKOUT = {
  environment: $1,
  token: $2,
  priceId: $3,
  gated: $4
};
CFG
}
rawcfg() { cat > "$SD/assets/checkout-config.js"; }   # the config exactly as piped in (spacing variants, duplicate keys)
restore() { # public-flip state: the held sentences back on four pages, the two "online ONLY" claims reworded to mention updates
  echo '<p>Works offline for up to 7 days.</p>' >> "$SD/pricing/index.html"
  echo '<p>It works offline for up to 7 days.</p>' >> "$SD/terms/index.html"
  echo '<p>A Mac that is offline switches over later.</p>' >> "$SD/refunds/index.html"
  echo '<p><strong>Update check.</strong> The app asks for updates.</p>' >> "$SD/privacy/index.html"
  sed -i.bak 's#ModTech goes online only to check your licence and to send feedback if you choose to.#ModTech goes online to check your licence, to look for updates and to send feedback if you choose to.#' "$SD/pricing/index.html"
  sed -i.bak 's#The app goes online only to check your license, and to send feedback if you choose to.#The app goes online to check your license, to look for updates and to send feedback if you choose to.#' "$SD/index.html"
  sed -i.bak 's#see the pricing</a>#see the pricing and subscribe</a>#' "$SD/index.html"
  rm -f "$SD/pricing/index.html.bak" "$SD/index.html.bak"
  # and the agreement note plus the delivery paragraph in their live state (publish #1 replaces both with the paragraph "Subscriptions are
  # not open yet"): no time promise. Whatever the branch carries is removed first, so these tests hold on pricing-v2 and on publish-1 alike.
  sed -i.bak -e '/^  <p class="note">By subscribing you agree/d' -e '/^  <p class="note">After you subscribe/d' -e '/^  <p class="note">Subscriptions are not open yet/d' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"
  echo '  <p class="note">By subscribing you agree to the <a href="/terms">Terms of Service</a> and the <a href="/refunds">Refund Policy</a>.</p>' >> "$SD/pricing/index.html"
  echo '  <p class="note">After you subscribe, your licence key is emailed to you automatically, usually within a few minutes, and your personal download link for the Mac app follows separately.</p>' >> "$SD/pricing/index.html"
}
# outcome LABEL NAME WANT [PATTERN] [FORBIDDEN]: judges the last guard run ($code, $out): exit code, optional output pattern, and an
# optional string the output must NOT contain (used to prove that nothing token-shaped is echoed).
outcome() {
  local label=$1 name=$2 want=$3 pat=$4 forbid=$5 ok=1
  [ "$code" = "$want" ] || ok=0
  [ -z "$pat" ] || printf '%s\n' "$out" | G -qE "$pat" || ok=0
  [ -z "$forbid" ] || ! printf '%s\n' "$out" | G -qF -- "$forbid" || ok=0
  if [ "$ok" = 1 ]; then echo "ok    $label$name"; why
  else echo "WRONG $label$name (exit $code, wanted $want${pat:+, output matching $pat}${forbid:+, output NOT containing the forbidden string})"; printf '%s\n' "$out" | sed 's/^/        /'; fails=$((fails+1)); fi
}
expect() { # name expected(0|1) [pattern] [forbidden]; runs the LIVE guard in the scratch copy as it stands (a plain folder unless mkrepo was called)
  out=$(genv "$SD/tools/check-before-publish.sh" 2>&1); code=$?; outcome "" "$1" "$2" "$3" "$4"
}
expect_paused_nogit() { # as expect_paused, but never turns the scratch copy into a git repo; GD overrides the folder the guard lives in
  out=$(genv "${GD:-$SD}/tools/check-before-publish.sh" --paused 2>&1); code=$?; outcome "PAUSED: " "$1" "$2" "$3" "$4"
}
expect_paused() { # name expected(0|1) [pattern] [forbidden]; --paused mode. The scratch copy becomes a clean git checkout with an origin/main ref unless mkrepo already ran
  [ -d "$SD/.git" ] || mkrepo clean
  expect_paused_nogit "$@"
}
expect_args() { # name expected-exit-code args... ; runs the guard with exactly these arguments
  name=$1; want=$2; shift 2
  out=$("$SD/tools/check-before-publish.sh" "$@" 2>&1); code=$?; outcome "" "$name" "$want"
}
expect_branch_sha() { # name live|paused: a passing run names the checked-out branch and the FULL sha of HEAD, on one line
  local want_sha want_br
  want_sha=$(git -C "$SD" rev-parse HEAD); want_br=$(git -C "$SD" symbolic-ref --short HEAD)
  if [ "$2" = paused ]; then expect_paused "$1" 0 "^branch: $want_br sha: $want_sha\$"; else expect "$1" 0 "^branch: $want_br sha: $want_sha\$"; fi
}
shim() { mkdir -p "$T/shim"; printf '#!/bin/bash\n%s\n' "$2" > "$T/shim/$1"; chmod +x "$T/shim/$1"; }   # shim NAME BODY: a stand-in program the guard finds first on PATH
REALGIT=$(command -v git); REALAWK=$(command -v awk); REALSED=$(command -v sed); REALGREP=$(command -v grep)   # the shims pass everything else through to these
PAUSEDP='  <p class="note">Subscriptions are not open yet. Email <a href="mailto:contact@modtech.app">contact@modtech.app</a> and we will tell you when the Mac app is ready.</p>'
pausedpage() { # the pricing page in its PAUSED state, whichever branch this copy was made from (pricing-v2 carries the live-state notes)
  sed -i.bak -e '/By subscribing you agree/d' -e '/After you subscribe/d' -e '/Subscriptions are not open yet/d' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"
  echo "$PAUSEDP" >> "$SD/pricing/index.html"
}
pfresh() { fresh; pausedpage; }   # a fresh copy whose pricing page is paused (--paused now enforces that), for cases that set their own config
pconfig() { config "'live'" "''" "''" true; pausedpage; }   # the PAUSED site: environment live, empty token, empty price id, gated, paused pricing page
edit() { sed -i.bak "$2" "$SD/$1"; rm -f "$SD/$1.bak"; }
# mkrepo MODE: turns the scratch copy into a throwaway git repo whose origin/main is its first commit (everything as it stands now is
# "already pushed"), then does what MODE says. After every mode except dirty-* and dates-uncommitted the working tree is clean.
mkrepo() {
  ( cd "$SD" || exit 2
    case "$PWD" in "$T"/*) ;; *) echo "refusing to run git outside the scratch directory"; exit 2 ;; esac
    g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
    g init -q . && find . -type f -not -path './.git/*' -print0 | xargs -0 git add -- && g commit -q -m base || exit 2
    g update-ref refs/remotes/origin/main HEAD
    case "$1" in
      token) # a live token in a commit AFTER origin/main, blanked again in the next one (HEAD's files are clean)
        config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; git add -- assets/checkout-config.js; g commit -q -m "add the live config"
        config "'live'" "''" "''" true;                      git add -- assets/checkout-config.js; g commit -q -m "blank the config again" ;;
      price) # only the live PRICE ID in an unpushed commit, blanked again
        config "'live'" "''" "'$GOODPRICE'" true;            git add -- assets/checkout-config.js; g commit -q -m "add the price id"
        config "'live'" "''" "''" true;                      git add -- assets/checkout-config.js; g commit -q -m "blank the config again" ;;
      binary) # a live token inside a file git treats as binary (NUL byte), deleted again in the next commit
        printf 'x\000%s\n' "$GOODTOKEN" > assets/blob.bin;   git add -- assets/blob.bin;            g commit -q -m "add a blob"
        git rm -q -- assets/blob.bin;                                                                  g commit -q -m "remove the blob" ;;
      message) # a live token only in a commit MESSAGE
        g commit -q --allow-empty -m "note: $GOODTOKEN" ;;
      sandbox) # the public sandbox price id in tools/test-guard.sh (one of the two exempt files), committed after origin/main (this is what publish-1 does)
        echo "# sandbox price $SANDBOXPRICE" >> tools/test-guard.sh;  git add -- tools/test-guard.sh;  g commit -q -m "add tools note" ;;
      sandbox-mixed) # the sandbox price id and a different price id on ONE line
        echo "# sandbox $SANDBOXPRICE and $GOODPRICE" >> tools/test-guard.sh; git add -- tools/test-guard.sh; g commit -q -m "add tools note" ;;
      secret) # a secret-shaped string ($2) in a file added by one unpushed commit and removed by the next (HEAD's files are clean)
        printf 'x %s\n' "$2" > assets/s.txt;                  git add -- assets/s.txt;                 g commit -q -m "add a file"
        git rm -q -- assets/s.txt;                                                                       g commit -q -m "remove the file" ;;
      secretmsg) # a secret-shaped string ($2) only in a commit MESSAGE
        g commit -q --allow-empty -m "note: $2" ;;
      latin1) # the string ($2, default a live token) on a LATIN-1 line (invalid UTF-8), added by one unpushed commit and removed by the next
        printf 'caf\351 %s\n' "${2:-$GOODTOKEN}" > assets/l1.txt; git add -- assets/l1.txt;          g commit -q -m "add a latin-1 file"
        git rm -q -- assets/l1.txt;                                                                      g commit -q -m "remove the file" ;;
      utf16) # the string ($2) as a UTF-16LE file (a NUL byte between its characters), added by one unpushed commit and removed by the next
        printf '%s\n' "$2" | iconv -f UTF-8 -t UTF-16LE > assets/u16.txt; git add -- assets/u16.txt;  g commit -q -m "add a utf-16 file"
        git rm -q -- assets/u16.txt;                                                                       g commit -q -m "remove the file" ;;
      textconv) # a textconv driver configured for *.txt shows only "hidden" in place of the file (git log -p would hide the token); token added, then removed
        printf '*.txt diff=hide\n' > .gitattributes; git add -- .gitattributes;                           g commit -q -m "attributes"
        git config diff.hide.textconv 'echo hidden'
        echo "$GOODTOKEN" > assets/t.txt; git add -- assets/t.txt;                                          g commit -q -m "add a text file"
        git rm -q -- assets/t.txt;                                                                          g commit -q -m "remove the file" ;;
      latin1-clean) # an unpushed commit whose file holds invalid UTF-8 but nothing secret, and stays in the tree
        printf 'caf\351 and na\357ve\n' > notes.txt;     git add -- notes.txt;                    g commit -q -m "add a latin-1 note" ;;
      fakemarker-empty) # a commit message with a line "@@commit " (empty hash, trailing space kept) and then a live token
        g commit -q --allow-empty --cleanup=verbatim -m "$(printf 'harmless\n@@commit \n%s' "$GOODTOKEN")" ;;
      fakemarker-full) # a commit message with a well-formed forged marker line and then a live token
        g commit -q --allow-empty --cleanup=verbatim -m "$(printf 'harmless\n@@commit 0123456789abcdef0123456789abcdef01234567\n%s' "$GOODTOKEN")" ;;
      merge) # a clean side branch merged into the mainline by a real merge commit (git log -m prints that merge once per parent)
        g checkout -q -b side;  echo s > side.txt; git add -- side.txt; g commit -q -m "side work"
        g checkout -q -;        echo m > main.txt; git add -- main.txt; g commit -q -m "mainline work"
        g merge -q --no-ff side -m "merge side" ;;
      merge-token) # as merge, but the side branch added a live token and removed it again before the merge
        g checkout -q -b side;  echo "$GOODTOKEN" > side.txt; git add -- side.txt; g commit -q -m "side token"
        git rm -q -- side.txt;                                                    g commit -q -m "side token gone"
        g checkout -q -;        echo m > main.txt; git add -- main.txt;           g commit -q -m "mainline work"
        g merge -q --no-ff side -m "merge side" ;;
      detached) echo '<!-- harmless -->' >> index.html; git add -- index.html; g commit -q -m "harmless edit"; g checkout -q --detach ;;
      none) ;;   # nothing unpushed: HEAD is origin/main
      tokenbranch) echo '<!-- harmless -->' >> index.html; git add -- index.html; g commit -q -m "harmless edit"; g checkout -q -b "br-$GOODTOKEN" ;;
      guardsecret) # a secret-shaped string ($2) appended to tools/test-guard.sh (exempt from the TREE scans) in an unpushed commit
        echo "# $2" >> tools/test-guard.sh; git add -- tools/test-guard.sh; g commit -q -m "edit the tests" ;;
      nomain) g update-ref -d refs/remotes/origin/main ;;
      dirty-mod) # a tracked file edited and not committed
        echo '<!-- edited -->' >> index.html ;;
      dirty-untracked) echo 'stray' > stray.txt ;;
      dirty-staged) echo '<!-- edited -->' >> index.html; git add -- index.html ;;
      dirty-dates|dates-committed) # HEAD still holds a [[SET the date ...]] placeholder; the working tree has the date filled in
        echo '<p class="lede">Last updated [[SET the date on the day this is published]].</p>' >> terms/index.html
        git add -- terms/index.html; g commit -q -m "placeholder"
        perl -pi -e 's/\[\[.*?\]\]/1 January 2027/g' terms/index.html
        [ "$1" = dates-committed ] && { git add -- terms/index.html; g commit -q -m "set the date"; } ;;
      clean|*) echo '<!-- harmless -->' >> index.html;        git add -- index.html;                g commit -q -m "harmless edit" ;;
    esac; true )
  [ $? = 0 ] || { echo "WRONG test setup failed: mkrepo $1"; fails=$((fails+1)); }
}
nested_repo() { # the site as a SUBDIRECTORY of a git repo that has an origin/main ref: a git checkout, but not the checkout root
  rm -rf "$T/n"; mkdir "$T/n"; mv "$SD" "$T/n/site"
  ( cd "$T/n" || exit 2
    g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
    g init -q . && git add -- site && g commit -q -m base && g update-ref refs/remotes/origin/main HEAD ) || { echo "WRONG test setup failed: nested_repo"; fails=$((fails+1)); }
}

# ---- LIVE mode (the default) ----
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;            expect "intended live config passes" 0
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore;  expect "intended live config, ungated, with the held sentences back, passes" 0
fresh; config "'sandbox'" "'$GOODTOKEN'" "'$GOODPRICE'" true;         expect "sandbox environment fails" 1
fresh; config "'live'" "'test_3c71564d483bc6f71f2f29dd271'" "'$GOODPRICE'" true; expect "sandbox token fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$SANDBOXPRICE'" true;         expect "live token with the sandbox price id fails" 1
fresh; config "'live'" "'test_zzzzzzzzzzzzzzzzzzzzzzzzzzz'" "'$GOODPRICE'" true; expect "a DIFFERENT sandbox-style token (test_...) fails" 1
fresh; config '"live"' "\"$GOODTOKEN\"" "\"$GOODPRICE\"" true;      expect "intended live config in DOUBLE quotes passes" 0
fresh; config "'live'" "''" "'$GOODPRICE'" true;                      expect "blank token fails" 1
fresh; config '"sandbox"' "\"$GOODTOKEN\"" "\"$GOODPRICE\"" true;     expect "double-quoted sandbox environment fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" "maybe";         expect "gated that is not true/false fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; sed -i.bak 's/<h1>/<h1>[[CONFIRM]] /' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"; expect "a leftover [[ ]] marker fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; sed -i.bak 's#cdn.paddle.com/paddle/v2/paddle.js#example.com/x.js#' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"; expect "a pricing page without Paddle.js fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<!-- $(fake pdl_live) -->" >> "$SD/terms/index.html"; expect "a secret-looking string in a page fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo 'var old = "test_3c71564d483bc6f71f2f29dd271";' > "$SD/assets/old.js"; expect "the sandbox token left in another file fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;                 expect "gated publish #1 passes WITHOUT the held sentences" 0
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false;                expect "ungated WITHOUT the held sentences fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; sed -i.bak 's#and subscribe#and read#' "$SD/index.html"; rm -f "$SD/index.html.bak"; expect "ungated: home page without the 'see the pricing and subscribe' invitation fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; sed -i.bak 's/offline/online/' "$SD/terms/index.html"; rm -f "$SD/terms/index.html.bak"; expect "ungated: terms without the offline sentence fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; echo '<p>ModTech goes online only to check your licence and to send feedback.</p>' >> "$SD/pricing/index.html"; expect "ungated: update paragraph back but pricing still says 'online only' fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; sed -i.bak 's#Update check#Updates#' "$SD/privacy/index.html"; rm -f "$SD/privacy/index.html.bak"; expect "ungated: privacy with neither the update paragraph nor the no-feed comment fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; sed -i.bak 's#Update check#Updates#' "$SD/privacy/index.html"; rm -f "$SD/privacy/index.html.bak"; echo '<!-- no-update-feed-confirmed 2026-10-20 -->' >> "$SD/privacy/index.html"; sed -i.bak 's#to look for updates and ##; s#to check your licence, #to check your licence and #' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"; expect "ungated: the no-update-feed comment is accepted instead of the paragraph" 0
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>HOLD until the build is out</p>' >> "$SD/pricing/index.html"; expect "an internal HOLD note with its brackets removed fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>(CONFIRM this on a live receipt)</p>' >> "$SD/refunds/index.html"; expect "an internal CONFIRM note in parentheses fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>per D-026</p>' >> "$SD/terms/index.html"; expect "a decision-record id (D-026) on a public page fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>Your household is covered. Hold on to your key.</p>' >> "$SD/pricing/index.html"; expect "ordinary words (household, Hold on) do not trip the leak check" 0
# ---- LIVE mode: the delivery sentence makes no time promise ----
fresh; pconfig;                                                         expect "live mode rejects the blank-token PAUSED config (a blank token is never inferred as paused)" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>We email your download link within one business day.</p>' >> "$SD/pricing/index.html"; expect "live, gated: 'one business day' on the pricing page fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo '<p>Within One  Business Day.</p>' >> "$SD/terms/index.html"; expect "live, gated: 'One  Business Day' (case, double space) on the terms page fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; echo '<p>within one business day</p>' >> "$SD/refunds/index.html"; expect "live, ungated: 'one business day' on any page fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; edit pricing/index.html 's/follows separately/follows/'; expect "live, ungated: pricing page without the 'follows separately' delivery sentence fails" 1
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;  edit pricing/index.html 's/follows separately/follows/'; expect "live, gated: the 'follows separately' sentence is not required yet" 0

# ---- LIVE mode: the paused paragraph must not survive into an open button; the key lines are checked exactly once ----
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; echo "$PAUSEDP" >> "$SD/pricing/index.html"; expect "live, ungated: the paused paragraph left on the pricing page fails" 1 'not open yet'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; echo "$PAUSEDP" >> "$SD/terms/index.html"; expect "live, ungated: the paused paragraph on ANY page (terms) fails" 1 'not open yet'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; echo '<p>subscriptions are not open yet</p>' >> "$SD/index.html"; expect "live, ungated: the paused wording in lower case on the home page is refused too" 1 'not open yet'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "$PAUSEDP" >> "$SD/pricing/index.html"; expect "live, gated (founder link only): the paused paragraph is allowed, the button is off for the public" 0
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" false; restore; edit pricing/index.html '/By subscribing you agree/d'; expect "live, ungated: the pricing page without the 'By subscribing you agree' note fails" 1 'By subscribing'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;  edit pricing/index.html '/By subscribing you agree/d'; expect "live, gated: the agreement note is not required yet" 0
fresh; rawcfg <<CFG
window.MODTECH_CHECKOUT = {
  environment: 'live',
  token: '$GOODTOKEN',
  token: '$GOODTOKEN',
  priceId: '$GOODPRICE',
  gated: true
};
CFG
expect "live: a duplicate token line fails (the later one would win in JavaScript)" 1 "'token' must appear exactly once"
fresh; rawcfg <<CFG
window.MODTECH_CHECKOUT = {
  environment: 'live',
  token: '$GOODTOKEN',
  priceId: '$GOODPRICE',
  priceId: '$GOODPRICE',
  gated: true
};
CFG
expect "live: a duplicate priceId line fails" 1 "'priceId' must appear exactly once"
fresh; rawcfg <<CFG
window.MODTECH_CHECKOUT = {
  environment: 'live',
  environment: 'live',
  token: '$GOODTOKEN',
  priceId: '$GOODPRICE',
  gated: true
};
CFG
expect "live: a duplicate environment line fails" 1 "'environment' must appear exactly once"
fresh; rawcfg <<CFG
window.MODTECH_CHECKOUT = {
  environment: 'live',
  token: '$GOODTOKEN',
  priceId: '$GOODPRICE',
  gated: true,
  gated: false
};
CFG
expect "live: a duplicate gated line fails" 1 "'gated' must appear exactly once"
fresh; rawcfg <<CFG
window.MODTECH_CHECKOUT = {
  environment: 'live',
  token: '$GOODTOKEN',
  priceId: '$GOODPRICE'
};
CFG
expect "live: a missing gated line fails" 1 "'gated' must appear exactly once"
fresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'live',\n  token  : '%s',\n  priceId\t: '%s',\n  gated : true\n};\n" "$GOODTOKEN" "$GOODPRICE" | rawcfg; expect "live: spaces or a tab before the colon are accepted" 0
fresh; printf "window.MODTECH_CHECKOUT = {\n  environment: 'live',\n  token: '%s',\n  token : '%s',\n  priceId: '%s',\n  gated: true\n};\n" "$GOODTOKEN" "$GOODTOKEN" "$GOODPRICE" | rawcfg; expect "live: a duplicate token line written with a space before the colon fails" 1 "'token' must appear exactly once"

# ---- LIVE mode: uncommitted changes (the guard reads the working tree, a push publishes HEAD) ----
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;                       expect "live, outside a git checkout: passes with a NOTE that uncommitted changes were not checked" 0 'NOT checked'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo clean;         expect "live, in a clean git checkout: passes" 0 'safe to publish'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo dirty-mod;     expect "live: an edited, uncommitted tracked file fails" 1 'uncommitted'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo dirty-untracked; expect "live: an untracked file fails" 1 'uncommitted'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo dirty-staged;  expect "live: a staged but uncommitted change fails" 1 'uncommitted'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo dirty-dates;   expect "live: dates filled in the working tree but not committed fails (HEAD still has the placeholder)" 1 'uncommitted'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo dates-committed; expect "live: the same dates, once committed, pass" 0 'safe to publish'

# ---- LIVE mode: nothing printed from the site is a token, a price id or a secret ----
fresh; config "'live'" "'test_3c71564d483bc6f71f2f29dd271'" "'$GOODPRICE'" true; expect "live: the failure for a sandbox token does not echo any part of it" 1 'found a test_ value of 32 characters' 'test_3c7'
fresh; config "'live'" "'$GOODTOKEN'" "'pri_shortvalue'" true;      expect "live: the failure for a malformed price id does not echo any part of it" 1 'found a pri_ value of 14 characters' 'shortvalue'
fresh; config "'live'" "'$GOODTOKEN'" "'$SANDBOXPRICE'" true;          expect "live: the sandbox price id is refused and printed redacted" 1 'SANDBOX' "$SANDBOXPRICE"
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<p>HOLD $GOODTOKEN</p>" >> "$SD/pricing/index.html"; expect "live: a leaked internal note carrying a token is printed redacted (leak check)" 1 'internal note' "$GOODTOKEN"
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<p>[[ $GOODTOKEN ]]</p>" >> "$SD/pricing/index.html"; expect "live: a placeholder line carrying a token is printed redacted (placeholder check)" 1 'placeholder' "$GOODTOKEN"
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<!-- $(fake pdl_live) -->" >> "$SD/terms/index.html"; expect "live: a secret-looking string is printed redacted (secrets check)" 1 'looks like a secret' 'abcdefghij0123456789'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<!-- $(fake whsec) -->" >> "$SD/terms/index.html"; expect "live: a webhook secret is printed redacted" 1 'looks like a secret' 'abcdefghijklmnopqrstuvwxyz'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo 'var old = "test_3c71564d483bc6f71f2f29dd271";' > "$SD/assets/old.js"; expect "live: the sandbox token left in a file is printed redacted (sandbox check)" 1 'SANDBOX' 'test_3c71564d483bc6f71f2f29dd271'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<p>within one business day $GOODTOKEN</p>" >> "$SD/terms/index.html"; expect "live: a delivery-time line carrying a token is printed redacted (business-day check)" 1 'business day' "$GOODTOKEN"

# ---- --paused mode: the first publish (no token, no price id, button off for everyone) ----
# Every case below runs in a scratch git checkout whose origin/main is the state before the case's last harmless commit and whose
# working tree is clean (expect_paused does this by itself) unless the case builds its own repo with mkrepo or says otherwise.
fresh; pconfig;                                                         expect_paused "paused config passes" 0 'PAUSED publish: no checkout configuration; the Subscribe button is off for everyone'
fresh; pconfig; mkrepo nomain;                                          expect_paused "with no origin/main ref the guard FAILS (the unpushed history cannot be scanned), it does not skip" 1 'no origin/main ref'
pfresh; config '"live"' '""' '""' true;                                  expect_paused "double-quoted empty values pass" 0
fresh; pconfig; edit pricing/index.html '/^  <p class="note">After you subscribe/d'; echo "$PAUSEDP" >> "$SD/pricing/index.html"; expect_paused "a pricing page with the paused delivery paragraph (no 'follows separately') passes" 0
pfresh; config "'live'" "'$GOODTOKEN'" "''" true;                       expect_paused "rejects a live token" 1
pfresh; config "'live'" "'test_zzzzzzzzzzzzzzzzzzzzzzzzzzz'" "''" true;  expect_paused "rejects a test_ token" 1
pfresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;              expect_paused "rejects the full live config" 1
pfresh; config "'live'" "''" "'$GOODPRICE'" true;                        expect_paused "rejects a non-empty priceId" 1
pfresh; config "'live'" "''" "'abc'" true;                               expect_paused "rejects a non-empty priceId that is not shaped like a price" 1
pfresh; config "'live'" "' '" "''" true;                                 expect_paused "rejects a token that is a single space (not exactly empty)" 1
pfresh; config "'live'" "''" "''" false;                                 expect_paused "rejects gated false" 1
pfresh; config "'live'" "''" "''" "maybe";                               expect_paused "rejects gated that is not a boolean" 1
pfresh; config "'live'" "''" "''" "'true'";                              expect_paused "rejects gated as the string 'true'" 1
pfresh; config "'sandbox'" "''" "''" true;                               expect_paused "rejects environment 'sandbox'" 1
pfresh; config '"sandbox"' '""' '""' true;                               expect_paused "rejects double-quoted environment sandbox" 1
fresh; pconfig; edit assets/checkout-config.js '/^  token:/d';          expect_paused "rejects a missing token line" 1
fresh; pconfig; edit assets/checkout-config.js '/^  priceId:/d';        expect_paused "rejects a missing priceId line" 1
fresh; pconfig; edit assets/checkout-config.js "s/token: ''/token: '' + ''/"; expect_paused "rejects a token line with anything after the empty string" 1
fresh; pconfig; edit assets/checkout-config.js "s/gated: true/gated: true,\n  gated: false/"; expect_paused "rejects a duplicate gated line (the later one would win in JavaScript)" 1 "'gated' must appear exactly once"
fresh; pconfig; echo "var t = \"$GOODTOKEN\";" > "$SD/assets/old.js";   expect_paused "rejects a live token in another file (.js)" 1 'redacted' "$GOODTOKEN"
fresh; pconfig; echo "{\"t\":\"$GOODTOKEN\"}" > "$SD/assets/x.json";    expect_paused "rejects a live token in a .json file" 1
fresh; pconfig; echo "token $GOODTOKEN" > "$SD/notes.txt";             expect_paused "rejects a live token in a .txt file" 1
fresh; pconfig; echo "<!-- $GOODTOKEN -->" >> "$SD/terms/index.html";  expect_paused "rejects a live token in an HTML comment" 1
fresh; pconfig; echo "/* $GOODTOKEN */" >> "$SD/assets/checkout-config.js"; expect_paused "rejects a live token in a comment inside the config file" 1
fresh; pconfig; echo "// test_zzzzzzzzzzzzzzzzzzzzzzzzzzz" >> "$SD/assets/checkout.js"; expect_paused "rejects a test_ token in a comment in checkout.js" 1
fresh; pconfig; echo "<!-- $GOODPRICE -->" >> "$SD/pricing/index.html"; expect_paused "rejects a price id anywhere on the site" 1
fresh; pconfig; echo 'var old = "test_3c71564d483bc6f71f2f29dd271";' > "$SD/assets/old.js"; expect_paused "rejects the sandbox token left in another file" 1
fresh; pconfig; mkrepo token;                                           expect_paused "rejects a live token only in an unpushed commit (HEAD files are clean)" 1 'unpushed history'
fresh; pconfig; mkrepo clean;                                           expect_paused "passes in a git repo with origin/main when the unpushed commits hold no live token" 0 'PAUSED publish'
fresh; pconfig; echo '<p>We email your download link within one business day.</p>' >> "$SD/pricing/index.html"; expect_paused "rejects 'one business day' left in the pricing page" 1 'business day'
fresh; pconfig; sed -i.bak 's#cdn.paddle.com/paddle/v2/paddle.js#example.com/x.js#' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"; expect_paused "rejects a pricing page without the Paddle.js tag" 1 'Paddle.js'
fresh; pconfig; sed -i.bak 's/<h1>/<h1>[[CONFIRM]] /' "$SD/pricing/index.html"; rm -f "$SD/pricing/index.html.bak"; expect_paused "still rejects a leftover [[ ]] marker" 1
fresh; pconfig; echo '<p>HOLD until the build is out</p>' >> "$SD/pricing/index.html"; expect_paused "still rejects an internal HOLD note" 1
fresh; pconfig; echo "<!-- $(fake pdl_live) -->" >> "$SD/terms/index.html"; expect_paused "still rejects a secret-looking string" 1

# ---- --paused mode: the working tree must be committed (the guard reads the working tree, a push publishes HEAD) ----
fresh; pconfig; mkrepo dirty-mod;                                       expect_paused "rejects an edited, uncommitted tracked file" 1 'uncommitted'
fresh; pconfig; mkrepo dirty-untracked;                                 expect_paused "rejects an untracked file" 1 'uncommitted'
fresh; pconfig; mkrepo dirty-staged;                                    expect_paused "rejects a staged but uncommitted change" 1 'uncommitted'
fresh; pconfig; mkrepo dirty-dates;                                     expect_paused "rejects dates filled in but not committed (the working tree passes every content check, HEAD still has the placeholder)" 1 'uncommitted'
fresh; pconfig; mkrepo dates-committed;                                 expect_paused "accepts the same dates once they are committed" 0 'safe to publish'

# ---- --paused mode: a git checkout with origin/main is required, and its unpushed history is scanned for live tokens AND live price ids ----
fresh; pconfig;                                                         expect_paused_nogit "rejects a folder that is not a git checkout at all" 1 'not the root of a git checkout'
fresh; pconfig; nested_repo; GD="$T/n/site" expect_paused_nogit "rejects a site that is a subdirectory of a git repo (not the checkout root)" 1 'not the root of a git checkout'
fresh; pconfig; mkrepo price;                                           expect_paused "rejects a live PRICE ID only in an unpushed commit" 1 'unpushed history'
fresh; pconfig; mkrepo binary;                                          expect_paused "rejects a live token inside a binary file in an unpushed commit (git log --text)" 1 'unpushed history'
fresh; pconfig; mkrepo message;                                         expect_paused "rejects a live token only in an unpushed commit message" 1 'unpushed history'
fresh; pconfig; mkrepo token;                                           expect_paused "the history failure lists the offending commits and prints no token" 1 'add the live config' "$GOODTOKEN"
fresh; pconfig; mkrepo sandbox;                                         expect_paused "the public sandbox price id in an unpushed commit (in tools/test-guard.sh, as publish-1 carries it) is excluded by value and passes" 0 'safe to publish'
fresh; pconfig; mkrepo sandbox-mixed;                                   expect_paused "the sandbox price id does not hide a different price id on the same line" 1 'unpushed history'
fresh; pconfig; mkdir -p "$SD/assets/tools"; echo "var t = \"$GOODTOKEN\";" > "$SD/assets/tools/x.js"; expect_paused "a directory named tools below the top level is scanned: a live token there fails" 1
fresh; pconfig; mkdir -p "$SD/terms/tools"; echo 'var old = "test_3c71564d483bc6f71f2f29dd271";' > "$SD/terms/tools/old.js"; expect_paused "a nested tools directory is scanned for the sandbox token too" 1 'SANDBOX'
fresh; pconfig; mkdir -p "$SD/terms/tools"; echo "<!-- $(fake pdl_live) -->" > "$SD/terms/tools/s.html"; expect_paused "a nested tools directory is scanned for secrets too" 1 'looks like a secret'
fresh; pconfig; mkdir -p "$SD/terms/tools"; echo '<p>HOLD until the build is out</p>' > "$SD/terms/tools/n.html"; expect_paused "a nested tools directory is scanned for internal notes too" 1 'internal note'
# Only the two exact files that hold the guard's own fake shapes are exempt from the TREE scans; the rest of tools/ is served by Pages too.
fresh; pconfig; echo "# token $GOODTOKEN and price $GOODPRICE and $(fake pdl_live)" >> "$SD/tools/test-guard.sh"; expect_paused "tools/test-guard.sh (an exact exempt file) may hold fake token and secret shapes in the tree" 0 'safe to publish'
fresh; pconfig; echo "# token $GOODTOKEN and price $GOODPRICE and $(fake pdl_live)" >> "$SD/tools/check-before-publish.sh"; expect_paused "tools/check-before-publish.sh (an exact exempt file) may hold fake token and secret shapes in the tree" 0 'safe to publish'
fresh; pconfig; echo "token $GOODTOKEN" > "$SD/tools/other.sh"; expect_paused "a live token in tools/other.sh FAILS (tools/ is no longer exempt as a whole)" 1 'client token or price id' "$GOODTOKEN"
fresh; pconfig; echo "price $GOODPRICE" > "$SD/tools/other.sh"; expect_paused "a price id in tools/other.sh FAILS" 1 'client token or price id' "$GOODPRICE"
fresh; pconfig; echo "# $(fake pdl_live)" > "$SD/tools/other.sh"; expect_paused "a fake secret in tools/other.sh FAILS" 1 'looks like a secret' "$(fake pdl_live)"
fresh; pconfig; echo "# $(fake whsec)" > "$SD/tools/test-checkout.js"; expect_paused "a fake secret added to tools/test-checkout.js FAILS" 1 'looks like a secret' "$(fake whsec)"
fresh; pconfig; echo "var old = \"test_3c71564d483bc6f71f2f29dd271\";" > "$SD/tools/other.js"; expect_paused "the sandbox token in tools/other.js FAILS" 1 'SANDBOX' 'test_3c71564d483bc6f71f2f29dd271'
fresh; pconfig; mkdir -p "$SD/tools/sub"; echo "token $GOODTOKEN" > "$SD/tools/sub/test-guard.sh"; expect_paused "a file NAMED test-guard.sh in a subdirectory of tools/ is not exempt (the exemption is exact paths)" 1 'client token or price id'
fresh; pconfig; echo "token $GOODTOKEN" > "$SD/assets/check-before-publish.sh"; expect_paused "a file NAMED check-before-publish.sh outside tools/ is not exempt" 1 'client token or price id'
fresh; pconfig; echo "token $GOODTOKEN" > "$SD/tools/check-before-publish.sh.bak"; expect_paused "tools/check-before-publish.sh.bak is not exempt" 1 'client token or price id'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "# $(fake pdl_live)" > "$SD/tools/other.sh"; expect "live: a fake secret in tools/other.sh FAILS" 1 'looks like a secret' "$(fake pdl_live)"
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "var p = '$SANDBOXPRICE';" > "$SD/tools/other.js"; expect "live: the sandbox price id in tools/other.js FAILS" 1 'SANDBOX'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "# $(fake pdl_live) $SANDBOXPRICE one business day" >> "$SD/tools/test-guard.sh"; expect "live: the two exact exempt files may hold fake shapes" 0 'safe to publish'

# ---- --paused mode: the config keys are matched with spaces or a tab before the colon ----
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'live',\n  token  : '',\n  priceId\t: '',\n  gated : true\n};\n" | rawcfg; expect_paused "spaces or a tab before the colon are accepted" 0
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment: 'live',\n  token: '',\n  token : '%s',\n  priceId: '',\n  gated: true\n};\n" "$GOODTOKEN" | rawcfg; expect_paused "a second token line written with a space before the colon is counted: fails" 1 "'token' must appear exactly once"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment: 'live',\n  token: '',\n  token\t: '',\n  priceId: '',\n  gated: true\n};\n" | rawcfg; expect_paused "a duplicate empty token line with a tab before the colon is counted: fails" 1 "'token' must appear exactly once"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'live',\n  token : '%s',\n  priceId : '',\n  gated : true\n};\n" "$GOODTOKEN" | rawcfg; expect_paused "a live token on a line written with a space before the colon fails" 1 "token line must be present and exactly"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'live',\n  token : '',\n  priceId : 'abc',\n  gated : true\n};\n" | rawcfg; expect_paused "a non-empty priceId with a space before the colon fails" 1 "priceId line must be present and exactly"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'live',\n  token : '',\n  priceId : '',\n  gated : false\n};\n" | rawcfg; expect_paused "gated false with a space before the colon fails" 1 "gated must be exactly true"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment : 'sandbox',\n  token : '',\n  priceId : '',\n  gated : true\n};\n" | rawcfg; expect_paused "environment sandbox with a space before the colon fails" 1 "environment must be exactly 'live'"
pfresh; printf "window.MODTECH_CHECKOUT = {\n  environment: 'live',\n  token: '',\n  priceId: '',\n  gated : true,\n  gated: false\n};\n" | rawcfg; expect_paused "a duplicate gated line, one with a space before the colon, is counted: fails" 1 "'gated' must appear exactly once"

# ---- --paused mode: assets/checkout.js must still switch the button off for an empty token ----
fresh; pconfig; edit assets/checkout.js '/!c.token/d';                  expect_paused "rejects a checkout.js whose empty-token early return was removed" 1 'early return'
fresh; pconfig; edit assets/checkout.js 's#^  if (!c.token)#  // if (!c.token)#'; expect_paused "rejects a checkout.js whose empty-token early return is commented out" 1 'early return'
fresh; pconfig; edit assets/checkout.js 's#if (!c.token) {[^}]*}#if (!c.token) { off("x"); }#'; expect_paused "rejects a checkout.js whose empty-token branch no longer returns" 1 'early return'
fresh; pconfig; rm "$SD/assets/checkout.js";                            expect_paused "rejects a missing checkout.js" 1 'early return'

# ---- --paused mode: nothing printed from the site is a token, a price id or a secret ----
fresh; pconfig; echo "<p>[[ $GOODTOKEN $GOODPRICE ]]</p>" >> "$SD/pricing/index.html"; expect_paused "placeholder check: a line carrying a token and a price id is printed redacted" 1 'placeholder' "$GOODTOKEN"
fresh; pconfig; echo "<p>[[ $GOODTOKEN $GOODPRICE ]]</p>" >> "$SD/pricing/index.html"; expect_paused "placeholder check: the price id is not printed either" 1 'placeholder' "$GOODPRICE"
fresh; pconfig; echo "<p>HOLD $GOODTOKEN</p>" >> "$SD/pricing/index.html"; expect_paused "leak check: a line carrying a token is printed redacted" 1 'internal note' "$GOODTOKEN"
fresh; pconfig; echo "<!-- $(fake pdl_live) -->" >> "$SD/terms/index.html"; expect_paused "secrets check: the secret is printed redacted" 1 'looks like a secret' 'abcdefghij0123456789'
fresh; pconfig; echo "<!-- $(fake sb_secret) -->" >> "$SD/terms/index.html"; expect_paused "secrets check: a Supabase secret is printed redacted" 1 'looks like a secret' 'ABCDEFGHIJKLMNOPQRSTUVWX'
fresh; pconfig; echo 'var old = "test_3c71564d483bc6f71f2f29dd271";' > "$SD/assets/old.js"; expect_paused "sandbox check: the sandbox token is printed redacted" 1 'SANDBOX' 'test_3c71564d483bc6f71f2f29dd271'
fresh; pconfig; echo "<p>within one business day $GOODTOKEN</p>" >> "$SD/terms/index.html"; expect_paused "business-day check: a line carrying a token is printed redacted" 1 'business day' "$GOODTOKEN"
fresh; pconfig; mkrepo dirty-untracked; echo "x" > "$SD/stray-$GOODTOKEN.txt"; expect_paused "the uncommitted-changes listing is printed redacted too (a file name that looks like a token)" 1 'uncommitted' "$GOODTOKEN"

# ---- invalid UTF-8: a Latin-1 line must not blind the guard, whichever locale it is started from (GLOC = a UTF-8 caller) ----
# printf '\351' is a lone Latin-1 byte, which is invalid UTF-8. Under a UTF-8 locale BSD grep skips such a line and sed and tr choke on it.
fresh; pconfig; printf 'caf\351 %s\n' "$GOODTOKEN" > "$SD/notes.txt";  GLOC=$UTF8LOC expect_paused "latin-1: a live token on an invalid-UTF-8 line in the tree fails (UTF-8 caller)" 1 'client token or price id' "$GOODTOKEN"
fresh; pconfig; printf 'caf\351 %s\n' "$GOODPRICE" > "$SD/notes.txt";  GLOC=$UTF8LOC expect_paused "latin-1: a live price id on an invalid-UTF-8 line in the tree fails (UTF-8 caller)" 1 'client token or price id' "$GOODPRICE"
fresh; pconfig; printf 'caf\351 %s\n' "$(fake sb_secret)" > "$SD/notes.txt"; GLOC=$UTF8LOC expect_paused "latin-1: a secret on an invalid-UTF-8 line in the tree fails (UTF-8 caller)" 1 'looks like a secret' "$(fake sb_secret)"
fresh; pconfig; printf 'caf\351 [[x]]\n' >> "$SD/terms/index.html";   GLOC=$UTF8LOC expect_paused "latin-1: a [[ ]] placeholder on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'placeholder'
fresh; pconfig; printf 'caf\351 HOLD this\n' >> "$SD/terms/index.html"; GLOC=$UTF8LOC expect_paused "latin-1: an internal HOLD note on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'internal note'
fresh; pconfig; printf 'caf\351 one business day\n' >> "$SD/terms/index.html"; GLOC=$UTF8LOC expect_paused "latin-1: 'one business day' on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'business day'
fresh; pconfig; mkrepo latin1;                                          GLOC=$UTF8LOC expect_paused "latin-1: a live token on an invalid-UTF-8 line, added and removed by unpushed commits, fails (UTF-8 caller)" 1 'unpushed history' "$GOODTOKEN"
fresh; pconfig; mkrepo latin1 "$GOODPRICE";                             GLOC=$UTF8LOC expect_paused "latin-1: a live price id in the unpushed history on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'unpushed history' "$GOODPRICE"
fresh; pconfig; mkrepo latin1 "$(fake whsec)";                          GLOC=$UTF8LOC expect_paused "latin-1: a secret in the unpushed history on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'unpushed history' "$(fake whsec)"
fresh; pconfig; mkrepo latin1;                                          GLOC=C expect_paused "latin-1: the same unpushed history fails when the caller is already in the C locale" 1 'unpushed history' "$GOODTOKEN"
fresh; pconfig; mkrepo utf16 "$GOODTOKEN";                               expect_paused "a live token inside a UTF-16 file (NUL bytes between the characters) in the unpushed history fails" 1 'unpushed history' "$GOODTOKEN"
fresh; pconfig; mkrepo utf16 "$(fake whsec)";                            expect_paused "a secret inside a UTF-16 file in the unpushed history fails" 1 'unpushed history' "$(fake whsec)"
fresh; pconfig; mkrepo textconv;                                         expect_paused "a textconv driver that hides a file's diff does not hide a live token in the unpushed history (git log --no-textconv)" 1 'unpushed history' "$GOODTOKEN"
fresh; pconfig; mkrepo latin1-clean;                                    GLOC=$UTF8LOC expect_paused "latin-1: invalid UTF-8 with nothing secret in it PASSES (the guard does not choke on it)" 0 'safe to publish'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; printf 'caf\351 %s\n' "$(fake whsec)" > "$SD/notes.txt"; GLOC=$UTF8LOC expect "live: latin-1: a secret on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'looks like a secret' "$(fake whsec)"
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; printf 'caf\351 [[x]]\n' >> "$SD/terms/index.html"; GLOC=$UTF8LOC expect "live: latin-1: a [[ ]] placeholder on an invalid-UTF-8 line fails (UTF-8 caller)" 1 'placeholder'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; printf 'caf\351 and na\357ve\n' > "$SD/notes.txt"; GLOC=$UTF8LOC expect "live: latin-1: invalid UTF-8 with nothing secret in it passes (UTF-8 caller)" 0 'safe to publish'

# ---- --paused mode: the history scan FAILS CLOSED ----
# Each case makes ONE step of the history scan fail (a stand-in program on PATH) and wants a FAIL that says the history was not scanned.
# The control passes everything through and must still pass, so the stand-ins themselves cannot be what fails the run.
fresh; pconfig; mkrepo clean; shim awk "exec $REALAWK \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed control: a pass-through stand-in for awk changes nothing" 0 'safe to publish'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim tr 'exit 1';                                                    GPATH="$T/shim:$PATH" expect_paused "fail-closed: tr failing on the history output is a FAIL, not a pass" 1 'tr failed.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim git "case \"\$*\" in *'log -p'*) exit 128;; esac; exec $REALGIT \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: git log failing is a FAIL" 1 'git log origin/main..HEAD failed.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim git "case \"\$*\" in *'rev-list --parents'*) exit 128;; esac; exec $REALGIT \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: git rev-list failing is a FAIL" 1 'rev-list.*failed.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim awk "case \"\$*\" in *'n += '*) exit 2;; esac; exec $REALAWK \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: awk failing while counting the commits is a FAIL" 1 'awk failed.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim grep "case \"\$*\" in *'-ac'*) exit 2;; esac; exec $REALGREP \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: grep failing while counting the markers is a FAIL" 1 'grep failed.*counting.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim sed "case \"\$*\" in *sandbox-price*) exit 3;; esac; exec $REALSED \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: sed failing on the history is a FAIL" 1 'sed failed.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim grep "case \"\$*\" in *'@@commit |'*) exit 2;; esac; exec $REALGREP \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: grep failing while scanning the history is a FAIL" 1 'grep failed while scanning.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim awk "case \"\$*\" in *'c = \$2'*) exit 2;; esac; exec $REALAWK \"\$@\""; GPATH="$T/shim:$PATH" expect_paused "fail-closed: awk failing while naming the offending commits is a FAIL" 1 'awk failed while naming.*not scanned'
fresh; pconfig; mkrepo clean; rm -rf "$T/shim"; shim sort 'exit 1';                                                  GPATH="$T/shim:$PATH" expect_paused "fail-closed: sort failing is a FAIL" 1 'sort failed.*not scanned'
rm -rf "$T/shim"
# A commit message can forge the marker line that names the commit. The marker count must match git's own count, so a forgery is a FAIL.
fresh; pconfig; mkrepo fakemarker-empty;                                expect_paused "forged marker: a message line '@@commit ' (empty hash) in front of a live token FAILS" 1 'forging a marker' "$GOODTOKEN"
fresh; pconfig; mkrepo fakemarker-full;                                 expect_paused "forged marker: a well-formed '@@commit <hash>' message line in front of a live token FAILS" 1 'forging a marker' "$GOODTOKEN"
fresh; pconfig; mkrepo merge;                                           expect_paused "a real merge commit is counted once per parent (git log -m) and a clean history passes" 0 'safe to publish'
fresh; pconfig; mkrepo merge-token;                                     expect_paused "a live token added and removed on a merged side branch FAILS" 1 'unpushed history' "$GOODTOKEN"
fresh; pconfig; mkrepo none;                                            expect_paused "nothing unpushed (HEAD is origin/main) passes" 0 'safe to publish'

# ---- --paused mode: the secret shapes are scanned in the unpushed history as well as the tree (each case builds its fake at run time) ----
for sh in $SHAPES; do
  v=$(fake "$sh"); bare=${v# }
  fresh; pconfig; echo "<!-- $v -->" >> "$SD/terms/index.html"; expect_paused "secret shape $sh in a page fails, printed redacted" 1 'looks like a secret' "$bare"
  fresh; pconfig; mkrepo secret "$v";                            expect_paused "secret shape $sh added and removed by unpushed commits fails (history), printed redacted" 1 'unpushed history' "$bare"
done
fresh; pconfig; mkrepo secretmsg "$(fake sb_secret)";             expect_paused "a secret only in an unpushed commit MESSAGE fails" 1 'unpushed history' "$(fake sb_secret)"
fresh; pconfig; mkrepo guardsecret "$(fake pdl_live)";            expect_paused "a secret appended to tools/test-guard.sh in an unpushed commit fails (the exemption is for the tree scans only)" 1 'unpushed history' "$(fake pdl_live)"
fresh; pconfig; mkrepo guardsecret "$GOODTOKEN";                  expect_paused "a live token appended to tools/test-guard.sh in an unpushed commit fails" 1 'unpushed history' "$GOODTOKEN"

# ---- the PAGES must be paused too (--paused enforces the paused pricing page) ----
fresh; pconfig; edit pricing/index.html '/Subscriptions are not open yet/d';        expect_paused "the pricing page without 'Subscriptions are not open yet' FAILS" 1 "does not say 'Subscriptions are not open yet'"
fresh; pconfig; edit pricing/index.html 's/Subscriptions are not open yet/subscriptions are not open yet/'; expect_paused "only the lower-case 'subscriptions are not open yet' is not the paused paragraph" 1 "does not say 'Subscriptions are not open yet'"
fresh; pconfig; rm "$SD/pricing/index.html";                                        expect_paused "no pricing page at all FAILS" 1 "does not say 'Subscriptions are not open yet'"
fresh; pconfig; echo '  <p class="note">By subscribing you agree to the <a href="/terms">Terms of Service</a>.</p>' >> "$SD/pricing/index.html"; expect_paused "the live-state agreement note ('By subscribing you agree') on the pricing page FAILS" 1 'live-state agreement note'
fresh; pconfig; echo '<p>by subscribing you agree to everything</p>' >> "$SD/terms/index.html"; expect_paused "the agreement note on ANOTHER page (terms), in lower case, FAILS" 1 'live-state agreement note'
fresh; pconfig; echo '  <p class="note">After you subscribe, your licence key is emailed to you automatically, usually within a few minutes.</p>' >> "$SD/pricing/index.html"; expect_paused "the live-state delivery paragraph ('After you subscribe, your licence key') on the pricing page FAILS" 1 'live-state delivery paragraph'
fresh; pconfig; echo '<p>After you subscribe, your licence key arrives.</p>' >> "$SD/refunds/index.html"; expect_paused "the live-state delivery paragraph on ANOTHER page (refunds) FAILS" 1 'live-state delivery paragraph'
fresh; pconfig; echo "<p>within one business day</p>" >> "$SD/terms/index.html"; expect_paused "the 'one business day' failure says this guard refuses that phrase" 1 'which this guard refuses'

# ---- the branch and the sha: a pass names the commit it approved; a detached HEAD is refused ----
fresh; pconfig; mkrepo clean;                                            expect_branch_sha "paused: a pass prints 'branch: <name> sha: <full sha>' for the checked-out commit" paused
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo clean; expect_branch_sha "live: a pass prints 'branch: <name> sha: <full sha>' for the checked-out commit" live
fresh; pconfig; mkrepo tokenbranch;                                      expect_paused "a branch named like a token is printed redacted" 0 'branch: br-live_<redacted> sha: [0-9a-f]{40}$' "$GOODTOKEN"
fresh; pconfig; mkrepo dirty-mod;                                        expect_paused "a failing run prints no branch/sha line" 1 'uncommitted' 'sha: '
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true;               expect "live, outside a git checkout: no branch/sha line is printed" 0 'NOT checked' 'branch:'
fresh; pconfig; mkrepo detached;                                         expect_paused "paused: a detached HEAD FAILS" 1 'HEAD is detached' 'sha: '
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; mkrepo detached; expect "live: a detached HEAD FAILS" 1 'HEAD is detached' 'sha: '
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; ( cd "$SD" && git init -q . ); expect "live: a git checkout with no commit yet FAILS" 1 'no commit yet'

# ---- the environment value is described, never echoed (LIVE mode) ----
fresh; config "'$GOODTOKEN'" "'$GOODTOKEN'" "'$GOODPRICE'" true;        expect "live: a token pasted into the environment field is not echoed" 1 'found a live_ value of 32 characters' "$GOODTOKEN"
fresh; config "'sandbox'" "'$GOODTOKEN'" "'$GOODPRICE'" true;           expect "live: a plain environment word is described by its length, not echoed" 1 'found a value of 7 characters' "found 'sandbox'"
fresh; config "''" "'$GOODTOKEN'" "'$GOODPRICE'" true;                  expect "live: an empty environment is described as nothing" 1 'found nothing'
fresh; config "'live'" "'$GOODTOKEN'" "'$GOODPRICE'" true; echo "<p>within one business day</p>" >> "$SD/terms/index.html"; expect "live: the 'one business day' failure says this guard refuses that phrase" 1 'which this guard refuses'

# ---- the guard and its tests hold no secret-shaped literal (their history is scanned, and so is every copy of their text) ----
S=$(sed -n "s/^SECRETS='\(.*\)'$/\1/p" tools/check-before-publish.sh)
if [ -z "$S" ]; then n="the SECRETS pattern could not be read"; else n=$(cat tools/check-before-publish.sh tools/test-guard.sh | sed "s/$SANDBOXPRICE//g" | G -cE "$S|live_[A-Za-z0-9]{27}|pri_[a-z0-9]{26}"); fi
out="lines shaped like a secret, a live token or a price id in the guard and its tests (sandbox price id excluded): $n"; code=1; [ "$n" = 0 ] && code=0
outcome "" "the guard and its tests hold no secret-shaped literal" 0

# ---- arguments ----
fresh; pconfig; expect_args "an unknown flag exits 2" 2 --bogus
fresh; pconfig; expect_args "an unknown flag after --paused exits 2" 2 --paused --bogus
fresh; pconfig; expect_args "a bare word instead of the flag exits 2" 2 paused
fresh; pconfig; expect_args "a short flag exits 2" 2 -p
fresh; pconfig; mkrepo clean; expect_args "--paused on the paused config exits 0" 0 --paused
echo; [ "$fails" = 0 ] && echo "ALL GUARD TESTS PASSED" || echo "$fails GUARD TEST(S) WRONG"
exit $fails
