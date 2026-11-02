#!/usr/bin/env bash
# The tag of a release points to the merge commit the version was computed from, even
# if another commit lands on the branch between `release create` and `release publish`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

# first change: merge it and create (but do not publish) its release
open_and_merge "fix/first" "fix: first change"
first_sha="$(merge_sha)"
out=$(cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" --merge-sha "$first_sha" 2>&1) \
  || { echo "$out" >&2; fail "release create failed"; }
version=$(echo "$out" | parse_version)
id=$(echo "$out" | parse_release_id)
assert_eq "$version" "0.1.1" "version of the first change"

# a second commit lands before the first release is published
open_and_merge "fix/second" "fix: second change"
second_sha="$(merge_sha)"
[ "$first_sha" != "$second_sha" ] || fail "the branch did not move"

(cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null)
wait_release_listed "$version" false

tag_sha=$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/$version" --jq .object.sha)
assert_eq "$tag_sha" "$first_sha" "tag $version points to the merge commit it was computed from"
log "tag commit scenario passed"
