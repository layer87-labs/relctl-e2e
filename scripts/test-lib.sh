#!/usr/bin/env bash
# Offline self-test of the helper functions and a syntax check of all scripts.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

fails=0
check() { # name, actual, expected
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$3', got '$2'"; fails=$((fails+1)); fi
}

out=$'INFO[0000] something\nWriting new release with version: 1.2.3\nCreate release successful. ID: 4242'
check "parse_version"    "$(echo "$out" | parse_version)" "1.2.3"
check "parse_release_id" "$(echo "$out" | parse_release_id)" "4242"
check "parse_version dry-run" "$(echo 'Would create new release with version: 202611.2.1' | parse_version)" "202611.2.1"
check "parse_version none" "$(echo 'nothing here' | parse_version)" ""

check "assert_eq pass" "$( (assert_eq a a x) 2>/dev/null && echo yes)" "yes"
check "assert_eq fail" "$( (assert_eq a b x) 2>/dev/null && echo yes || echo no)" "no"
check "assert_match pass" "$( (assert_match 1.2.3 '^[0-9.]+$' v) 2>/dev/null && echo yes)" "yes"
check "assert_match fail" "$( (assert_match abc '^[0-9.]+$' v) 2>/dev/null && echo yes || echo no)" "no"
check "require_env missing" "$( (unset NOPE; require_env NOPE) 2>/dev/null && echo yes || echo no)" "no"

for f in "$root"/scripts/*.sh "$root"/scenarios/*.sh; do
  if bash -n "$f"; then echo "ok   syntax $(basename "$f")"; else echo "FAIL syntax $f"; fails=$((fails+1)); fi
done

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all checks passed"
