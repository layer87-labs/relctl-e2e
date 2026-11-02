#!/usr/bin/env bash
# Flow 3: the version comes from the topmost CHANGELOG.md heading. An undated
# heading is refused, a dated one is released, and the release is idempotent.
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

create() { (cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" 2>&1); }

# 1. an upcoming (undated) heading must not be released
push_changelog $'# Changelog\n\n## 1.0.0\n\n- first release notes' "docs: start 1.0.0"
if out=$(create); then
  echo "$out" >&2
  fail "an undated heading must be refused"
fi
log "ok: undated heading refused"

# 2. date it and release
today="$(date -u +%F)"
push_changelog $'# Changelog\n\n## 1.0.0 — '"$today"$'\n\n- first release notes' "docs: release 1.0.0"
out=$(create) || { echo "$out" >&2; fail "dated heading must be released"; }
assert_eq "$(echo "$out" | parse_version)" "1.0.0" "changelog version"
id=$(echo "$out" | parse_release_id)
body=$(gh api "repos/${GITHUB_REPOSITORY}/releases/$id" --jq .body)
assert_match "$body" "first release notes" "release notes come from the changelog"

# 3. running again creates nothing new while the release is still a draft
create > /dev/null || fail "second run must succeed"
assert_eq "$(release_count 1.0.0)" "1" "releases for 1.0.0 after a repeated run"

# 4. publish, then run again: still nothing new
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null)
sandbox_sync
wait_release_published 1.0.0
create > /dev/null || fail "run after publishing must succeed"
count=$(release_count 1.0.0)
if [ "$count" != "1" ]; then dump_releases; fi
assert_eq "$count" "1" "releases for 1.0.0 after publishing and a repeated run"
log "changelog scenario passed"
