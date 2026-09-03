#!/usr/bin/env bash
# Unit test for scripts/shape-feedback.jq against tests/fixtures/raw.json.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(jq -f "$HERE/../scripts/shape-feedback.jq" "$HERE/fixtures/raw.json")

check() {
  if ! printf '%s' "$OUT" | jq -e "$1" >/dev/null; then
    echo "shape_test FAIL: $1"
    exit 1
  fi
}

check '.pr.number == 66 and .pr.author == "psrvere" and .pr.head_sha == "deadbeef" and .pr.head_owner == "psrvere" and .pr.state == "OPEN"'
check '.items | length == 6'
check '[.items[] | .n] == [1,2,3,4,5,6]'
check '[.items[] | select(.kind == "thread") | .id] == ["T2","T4","T6"]'
check '.items[] | select(.id == "T2") | .author == "aufi" and .is_bot == false and .line == 5 and .reopened == false'
check '.items[] | select(.id == "T4") | .reopened == true and (.comments | length == 3)'
check '.items[] | select(.id == "T6") | .is_bot == true and .author == "coderabbitai"'
check '[.items[] | select(.kind == "review") | .id] == ["R1","R4"]'
check '.items[] | select(.id == "R4") | .is_deep_review == true and .author == "psrvere"'
check '.items[] | select(.id == "R1") | .is_deep_review == false and .state == "CHANGES_REQUESTED"'
check '[.items[] | select(.kind == "comment") | .id] == ["C3"]'
check '.skipped | length == 9'
check '(.skipped | map(select(.id == "T1")) | .[0].reason) == "resolved"'
check '(.skipped | map(select(.id == "T3")) | .[0].reason) == "answered"'
check '(.skipped | map(select(.id == "T5")) | .[0].reason) == "empty"'
check '(.skipped | map(select(.id == "C1")) | .[0].reason) == "boilerplate"'
check '(.skipped | map(select(.id == "C2")) | .[0].reason) == "own-reply"'
check '(.skipped | map(select(.id == "C4")) | .[0].reason) == "ci-bot"'
check '(.skipped | map(select(.id == "R2")) | .[0].reason) == "answered"'
check '(.skipped | map(select(.id == "R3")) | .[0].reason) == "boilerplate"'
check '(.skipped | map(select(.id == "R5")) | .[0].reason) == "empty"'
check '[.items[] | has("skip")] | any | not'
echo "shape_test: ok"
