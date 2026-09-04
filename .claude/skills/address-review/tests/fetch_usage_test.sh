#!/usr/bin/env bash
# Usage-level tests for the fetch script. No network.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/../scripts/get-pr-feedback"

if bash "$S" >/dev/null 2>&1; then echo "fetch_usage_test FAIL: no-arg call should exit 1"; exit 1; fi
# Captured rather than piped straight into grep: under pipefail, `bash "$S" | grep -q ...`
# reports bash's own exit 1 even when grep matches, so the negated `if !` always fires.
usage_out=$(bash "$S" 2>&1 || true)
if ! grep -qE '^usage: get-pr-feedback' <<<"$usage_out"; then echo "fetch_usage_test FAIL: usage line missing"; exit 1; fi
if bash "$S" 12 "not-a-slug" >/dev/null 2>&1; then echo "fetch_usage_test FAIL: malformed slug should exit 1"; exit 1; fi
echo "fetch_usage_test: ok"
