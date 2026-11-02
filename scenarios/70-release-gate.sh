#!/usr/bin/env bash
# The release gate: it passes only for a dated, notes-bearing, unreleased version
# that has a release candidate for exactly the commit being released.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

push_changelog() { # content, message
  printf '%s\n' "$1" > "$SANDBOX_DIR/CHANGELOG.md"
  printf 'version_scheme: changelog\n' > "$SANDBOX_DIR/.relctl.yaml"
  git -C "$SANDBOX_DIR" add CHANGELOG.md .relctl.yaml
  git -C "$SANDBOX_DIR" commit --quiet -m "$2"
  git -C "$SANDBOX_DIR" push --quiet origin "HEAD:$SANDBOX_BRANCH"
  sandbox_sync
}

gate() { (cd "$SANDBOX_DIR" && relctl release gate "$@" 2>&1); }

expect_gate_fail() { # description, relctl gate args...
  local what="$1"
  shift
  if out=$(gate "$@"); then
    echo "$out" >&2
    fail "the gate must fail: $what"
  fi
  log "ok: gate failed as expected: $what"
}

# 1. an undated heading fails even without the candidate requirement
push_changelog $'# Changelog\n\n## 1.0.0\n\n- notes' "docs: start 1.0.0"
expect_gate_fail "undated heading" --require-candidate=false

# 2. a dated heading passes the changelog checks, but no candidate exists for this commit
today="$(date -u +%F)"
push_changelog $'# Changelog\n\n## 1.0.0 — '"$today"$'\n\n- notes' "docs: date 1.0.0"
out=$(gate --require-candidate=false) || { echo "$out" >&2; fail "gate without candidate requirement must pass"; }
assert_match "$out" "release gate passed" "gate without candidate requirement"
expect_gate_fail "no candidate for this commit"

# 3. create and publish a candidate for exactly this commit: the gate passes
out=$(cd "$SANDBOX_DIR" && relctl release create --prerelease --release-branch "$SANDBOX_BRANCH" 2>&1) \
  || { echo "$out" >&2; fail "candidate creation failed"; }
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$(echo "$out" | parse_release_id)" --release-branch "$SANDBOX_BRANCH" > /dev/null)
sandbox_sync
wait_release_listed 1.0.0-rc.1 false
out=$(gate --sha "$(merge_sha)") || { echo "$out" >&2; fail "gate with a candidate for the commit must pass"; }
assert_match "$out" "1.0.0-rc.1" "gate names the candidate"

# 4. a candidate for another commit does not count
push_changelog $'# Changelog\n\n## 1.0.0 — '"$today"$'\n\n- notes\n- one more change' "docs: another change"
expect_gate_fail "candidate is for the previous commit"

# 5. once released, the gate fails
(cd "$SANDBOX_DIR" && relctl release create --prerelease --release-branch "$SANDBOX_BRANCH" > /tmp/rc2.out 2>&1)
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$(parse_release_id < /tmp/rc2.out)" --release-branch "$SANDBOX_BRANCH" > /dev/null)
sandbox_sync
out=$(cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" 2>&1) || { echo "$out" >&2; fail "release failed"; }
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$(echo "$out" | parse_release_id)" --release-branch "$SANDBOX_BRANCH" > /dev/null)
sandbox_sync
wait_release_listed 1.0.0 false
expect_gate_fail "version already released"
log "release gate scenario passed"
