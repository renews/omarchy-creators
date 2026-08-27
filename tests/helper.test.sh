#!/usr/bin/env bash
# Contract tests for the two shell-facing helpers. Nothing here touches the
# network or the compositor: the QML side can only ever see stdout, so what is
# worth pinning down is that stdout stays valid JSON and that bad input is
# refused before anything is launched.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/creators"
PIP="$ROOT/creators-pip"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_jq() { jq -e "$1" <<<"$2" >/dev/null || fail "$3"; }
refuses() { "$@" >/dev/null 2>&1 && fail "accepted bad input: $*" || true; }

# Run against a scratch HOME so a developer's real token and seen-state are
# neither read nor written by the tests.
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export XDG_STATE_HOME="$sandbox/state" XDG_CACHE_HOME="$sandbox/cache"

bash -n "$PIP" || fail "creators-pip has a syntax error"
bash -n "$ROOT/creators-notify" || fail "creators-notify has a syntax error"
/usr/bin/env python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$HELPER" \
  || fail "creators has a syntax error"

# --- creators ---------------------------------------------------------

out=$("$HELPER" browsers)
assert_jq '.schemaVersion == 1 and .state == "ready"' "$out" "browsers did not report ready"
assert_jq '.browsers | type == "array"' "$out" "browsers is not a list"
assert_jq '.browsers | all(.id | test("^(firefox|chrome|chromium|brave|vivaldi|edge|opera):"))' \
  "$out" "a browser id is not a yt-dlp BROWSER:PROFILE spec"

# A malformed channel id must be reported, not fetched.
out=$("$HELPER" youtube check --channel "../etc/passwd" --channel "not-a-channel")
assert_jq '.state == "ready"' "$out" "a bad channel id broke the whole check"
assert_jq '.warnings | length == 2' "$out" "bad channel ids were not both warned about"
assert_jq '.fresh | length == 0' "$out" "a bad channel id produced an alert"

# No channels at all is a valid, quiet answer.
out=$("$HELPER" youtube check)
assert_jq '.items == [] and .fresh == []' "$out" "an empty check was not empty"

# A machine with no route out must say so plainly instead of blaming YouTube or
# the user's cookies. unshare gives us a network namespace with only loopback;
# where unprivileged namespaces are disabled there is no way to test it offline,
# so the check is skipped rather than faked.
if unshare -rn true 2>/dev/null; then
  out=$(unshare -rn "$HELPER" youtube check --channel "UCXuqSBlHAE6Xw-yeJA0Tunw")
  assert_jq '.state == "offline"' "$out" "an unreachable network was not reported as offline"
  assert_jq '.warnings == []' "$out" "being offline produced per-channel warnings"

  out=$(unshare -rn "$HELPER" --client-id test twitch check --login someone)
  assert_jq '.state == "offline" or .state == "signed-out"' "$out" \
    "an unreachable network confused the twitch check"
else
  echo "helper.test.sh: skipping offline checks (unprivileged namespaces unavailable)"
fi

# Twitch without a client id has to say so rather than fail opaquely.
out=$("$HELPER" twitch catalog)
assert_jq '.state == "no-client-id"' "$out" "missing client id was not reported"
out=$("$HELPER" twitch login)
assert_jq '.state == "no-client-id"' "$out" "login without a client id was not reported"
out=$("$HELPER" twitch check --login someone)
assert_jq '.state == "no-client-id" and .items == []' "$out" "check without a client id misreported"

# Signed out, with a client id present, is a distinct state from missing one.
out=$("$HELPER" --client-id abc123 twitch catalog)
assert_jq '.state == "signed-out"' "$out" "a missing token was not reported as signed out"

# Logout is idempotent and safe on a clean profile.
out=$("$HELPER" twitch logout)
assert_jq '.state == "ready"' "$out" "logout on a clean profile failed"

# Every subcommand must emit exactly one JSON document.
for args in "browsers" "youtube check" "twitch logout"; do
  # shellcheck disable=SC2086
  lines=$("$HELPER" $args | grep -c .)
  [[ $lines == 1 ]] || fail "'$args' emitted $lines lines instead of one JSON document"
done

refuses "$HELPER" nonsense
refuses "$HELPER" youtube nonsense

# --- creators-pip ------------------------------------------------------------

[[ $("$PIP" positions | grep -c .) == 9 ]] || fail "there should be nine anchors"
"$PIP" positions | grep -qx "bottom-right" || fail "bottom-right is not an anchor"

out=$("$PIP" status)
assert_jq '.position and .size and (.running | type == "boolean")' "$out" "pip status is not shaped right"

refuses "$PIP" open "ftp://example.com/x"
refuses "$PIP" open "file:///etc/passwd"
refuses "$PIP" open
refuses "$PIP" position "somewhere-else"

echo "helper.test.sh: all checks passed"
