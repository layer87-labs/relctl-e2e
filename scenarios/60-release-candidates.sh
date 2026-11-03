#!/usr/bin/env bash
# Flow 3 on a development branch: release candidates X.Y.Z-rc.N with a computed counter,
# then the release, then no candidate for an already released version.
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

# candidate <candidate-version> <next-release> <latest-release>: create and publish a candidate
# and check it, including what it exports: the candidate is RELCTL_VERSION, the release it is
# a candidate for is RELCTL_NEXT_VERSION, and the latest release is never a candidate.
candidate() {
  local expected="$1" next="$2" latest="$3" out version id envf
  envf="$(mktemp)"
  out=$(cd "$SANDBOX_DIR" && GITHUB_ENV="$envf" GITHUB_OUTPUT="$envf.out" relctl release create --prerelease --release-branch "$SANDBOX_BRANCH" 2>&1) \
    || { echo "$out" >&2; fail "release create --prerelease failed"; }
  version=$(echo "$out" | parse_version)
  id=$(echo "$out" | parse_release_id)
  assert_eq "$version" "$expected" "candidate version"
  assert_eq "$(exported RELCTL_VERSION "$envf")" "$expected" "RELCTL_VERSION of a candidate"
  assert_eq "$(exported RELCTL_NEXT_VERSION "$envf")" "$next" "RELCTL_NEXT_VERSION is the release, not the candidate"
  assert_eq "$(exported RELCTL_LATEST_VERSION "$envf")" "$latest" "RELCTL_LATEST_VERSION is a published release"
  assert_eq "$(exported RELCTL_PRERELEASE "$envf")" "true" "RELCTL_PRERELEASE of a candidate"
  (cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null)
  sandbox_sync
  wait_release_listed "$expected" false
  assert_eq "$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/$expected" --jq .prerelease)" "true" "$expected is marked as prerelease"
}

# an upcoming version on the development branch
push_changelog $'# Changelog\n\n## 1.0.0\n\n- upcoming notes' "docs: start 1.0.0"

# the sandbox starts with the published release 0.1.0
candidate 1.0.0-rc.1 1.0.0 0.1.0
candidate 1.0.0-rc.2 1.0.0 0.1.0
candidate 1.0.0-rc.3 1.0.0 0.1.0

# release it: date the heading, create and publish the real release
today="$(date -u +%F)"
push_changelog $'# Changelog\n\n## 1.0.0 — '"$today"$'\n\n- upcoming notes' "docs: release 1.0.0"
out=$(cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" 2>&1) \
  || { echo "$out" >&2; fail "release of 1.0.0 failed"; }
assert_eq "$(echo "$out" | parse_version)" "1.0.0" "released version"
(cd "$SANDBOX_DIR" && relctl release publish --release-id "$(echo "$out" | parse_release_id)" --release-branch "$SANDBOX_BRANCH" > /dev/null)
sandbox_sync
wait_release_listed 1.0.0 false

# the latest release is the real one, not a candidate
assert_eq "$(gh api "repos/${GITHUB_REPOSITORY}/releases/latest" --jq .tag_name)" "1.0.0" "latest release"
assert_eq "$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/1.0.0" --jq .prerelease)" "false" "1.0.0 is not a prerelease"

# a candidate for an already released version is not created
out=$(cd "$SANDBOX_DIR" && relctl release create --prerelease --release-branch "$SANDBOX_BRANCH" 2>&1) \
  || { echo "$out" >&2; fail "a repeated candidate run must succeed"; }
assert_match "$out" "already released" "message for an already released version"
settle
assert_eq "$(release_count 1.0.0-rc.4)" "0" "candidates after the release"

# the next cycle: the latest release is now 1.0.0, and the first candidate of 1.1.0 is rc.1
push_changelog $'# Changelog\n\n## 1.1.0\n\n- upcoming notes\n\n## 1.0.0 — '"$today"$'\n\n- upcoming notes' "docs: start 1.1.0"
candidate 1.1.0-rc.1 1.1.0 1.0.0
log "release candidate scenario passed"
