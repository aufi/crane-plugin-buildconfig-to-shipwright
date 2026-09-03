#!/usr/bin/env bash
# Usage-level tests for the three write-side scripts. No network, nothing is posted.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/../scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

expect_usage() {  # script, expected usage prefix, args...
  local script=$1 prefix=$2 out
  shift 2
  if bash "$script" "$@" >/dev/null 2>&1; then echo "FAIL: $script $* should exit 1"; exit 1; fi
  # capture first, then grep: under pipefail the script's exit 1 would mask grep's match
  out=$(bash "$script" "$@" 2>&1 || true)
  if ! printf '%s\n' "$out" | grep -qE "^$prefix"; then echo "FAIL: $script usage line missing"; exit 1; fi
}

expect_usage "$S/reply-to-thread" "usage: reply-to-thread"
expect_usage "$S/reply-to-thread" "usage: reply-to-thread" PRRT_x
expect_usage "$S/resolve-thread" "usage: resolve-thread"

: > "$TMP/empty.md"
if bash "$S/reply-to-thread" PRRT_x "$TMP/empty.md" >/dev/null 2>&1; then echo "FAIL: empty body file should exit 1"; exit 1; fi
if bash "$S/reply-to-thread" PRRT_x "$TMP/missing.md" >/dev/null 2>&1; then echo "FAIL: missing body file should exit 1"; exit 1; fi

# The reply body must reach gh as JSON data, never as a shell string: check the request shape offline.
printf 'a "quoted" reply with $(dangerous) `text`\n' > "$TMP/body.md"
PAYLOAD=$(bash "$S/reply-to-thread" --print-payload PRRT_x "$TMP/body.md")
printf '%s' "$PAYLOAD" | jq -e '.variables.threadId == "PRRT_x" and (.variables.body | contains("$(dangerous)")) and (.query | contains("addPullRequestReviewThreadReply"))' >/dev/null \
  || { echo "FAIL: payload shape"; exit 1; }
echo "write_scripts_usage_test: ok"
