#!/usr/bin/env bash
# Release text: without --body the release carries the notes GitHub generates (merged pull
# requests, grouped by .github/release.yml), a given --body is never replaced, and the
# uploaded assets are appended as a table.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

release_body() { gh api "repos/${GITHUB_REPOSITORY}/releases/$1" --jq .body; }

create() { # extra args; prints relctl output
  (cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" --merge-sha "$(merge_sha)" "$@" 2>&1)
}

# 1. the repository configures the categories of its release notes
git -C "$SANDBOX_DIR" checkout --quiet -B chore/release-config "origin/$SANDBOX_BRANCH"
mkdir -p "$SANDBOX_DIR/.github"
cat > "$SANDBOX_DIR/.github/release.yml" <<'YAML'
changelog:
  categories:
    - title: Changes in this release
      labels:
        - "*"
YAML
git -C "$SANDBOX_DIR" add .github/release.yml
git -C "$SANDBOX_DIR" commit --quiet -m "chore: configure release notes"
git -C "$SANDBOX_DIR" push --quiet origin "HEAD:refs/heads/chore/release-config"
pr=$(gh pr create --base "$SANDBOX_BRANCH" --head chore/release-config --title "chore: configure release notes" --body "e2e" | grep -oE '[0-9]+$')
merge_with_retry "$pr" "chore: configure release notes"
sandbox_sync

# 2. a merged pull request must appear in the generated notes, in its category
open_and_merge "fix/visible-in-notes" "fix: visible in the release notes"
out=$(create) || { echo "$out" >&2; fail "release create failed"; }
id=$(echo "$out" | parse_release_id)
[ -n "$id" ] || { echo "$out" >&2; fail "no release id"; }
body=$(release_body "$id")
assert_match "$body" "visible in the release notes" "generated notes list the merged pull request"
assert_match "$body" "Changes in this release" "generated notes use the category of .github/release.yml"

# 3. publishing with an asset appends a table and keeps the notes
asset="$(mktemp -d)/app.bin"
head -c 3000 /dev/urandom > "$asset"
sum=$(sha256sum "$asset" | awk '{print $1}')
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" --asset "file=$asset" > /dev/null) \
  || fail "release publish failed"
body=$(release_body "$id")
assert_match "$body" "visible in the release notes" "notes survive publishing"
assert_match "$body" "### Assets" "assets heading"
assert_match "$body" "\| File \| Size \| SHA-256 \|" "assets are a table"
assert_match "$body" "app\.bin" "asset name in the table"
assert_match "$body" "$sum" "asset checksum in the table"

# 4. a text given with --body is never replaced by generated notes
sandbox_sync
open_and_merge "fix/second-change" "fix: second change"
out=$(create --body "Hand written notes") || { echo "$out" >&2; fail "release create with --body failed"; }
id2=$(echo "$out" | parse_release_id)
assert_eq "$(release_body "$id2")" "Hand written notes" "a given --body is kept"
log "release notes scenario passed"
