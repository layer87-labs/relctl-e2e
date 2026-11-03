#!/usr/bin/env bash
# A repository whose tags carry a prefix ("v1.2.3"): the latest release is found behind the
# prefix, the version stays plain and the tag gets the prefix.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

printf 'tag_prefix: v\n' > "$SANDBOX_DIR/.relctl.yaml"
git -C "$SANDBOX_DIR" add .relctl.yaml
git -C "$SANDBOX_DIR" commit --quiet -m "chore: tag prefix v"
git -C "$SANDBOX_DIR" push --quiet origin "HEAD:$SANDBOX_BRANCH"
sandbox_sync

# release <expected-version> <expected-latest> [relctl create args...]
release() {
  local version="$1" latest="$2" envf out id
  shift 2
  envf="$(mktemp)"
  out=$(cd "$SANDBOX_DIR" && GITHUB_ENV="$envf" GITHUB_OUTPUT="$envf.out" relctl release create --release-branch "$SANDBOX_BRANCH" --merge-sha "$(merge_sha)" "$@" 2>&1) \
    || { echo "$out" >&2; fail "release create failed"; }
  assert_eq "$(echo "$out" | parse_version)" "$version" "version"
  assert_eq "$(exported RELCTL_VERSION "$envf")" "$version" "RELCTL_VERSION is plain"
  assert_eq "$(exported RELCTL_TAG "$envf")" "v$version" "RELCTL_TAG has the prefix"
  assert_eq "$(exported RELCTL_LATEST_VERSION "$envf")" "$latest" "latest release behind the prefix"
  id=$(echo "$out" | parse_release_id)
  (cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null)
  sandbox_sync
  wait_release_listed "v$version" false
}

# the sandbox only has the unprefixed release 0.1.0: ignored, the repository starts at v1.0.0
open_and_merge "fix/first" "fix: first change"
release 1.0.0 "" --version 1.0.0

# SemVer finds v1.0.0 behind the prefix and bumps it
open_and_merge "feature/second" "feat: second change"
release 1.1.0 1.0.0

open_and_merge "fix/third" "fix: third change"
release 1.1.1 1.1.0

tags=$(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags" --jq '.[].ref' | sed 's#refs/tags/##' | sort | tr '\n' ' ')
assert_eq "$tags" "0.1.0 v1.0.0 v1.1.0 v1.1.1 " "tags carry the prefix"
log "tag prefix scenario passed"
