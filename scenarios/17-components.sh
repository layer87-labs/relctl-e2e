#!/usr/bin/env bash
# Components: independently released parts of one repository. Each has its own tags, its own
# latest release and its own counter, and `release changed` says whether its paths changed
# since its latest release.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

day="$(date -u +%Y%m).$(date -u +%-d)"

push_files() { # message, then file=content pairs
  local message="$1" pair
  shift
  for pair in "$@"; do
    mkdir -p "$SANDBOX_DIR/$(dirname "${pair%%=*}")"
    printf '%s\n' "${pair#*=}" > "$SANDBOX_DIR/${pair%%=*}"
  done
  git -C "$SANDBOX_DIR" add -A
  git -C "$SANDBOX_DIR" commit --quiet -m "$message"
  git -C "$SANDBOX_DIR" push --quiet origin "HEAD:$SANDBOX_BRANCH"
  sandbox_sync
}

# changed <component>: runs `release changed` and prints "<true|false> <files>"
changed() {
  local envf out
  envf="$(mktemp)"
  out=$(cd "$SANDBOX_DIR" && GITHUB_ENV="$envf" GITHUB_OUTPUT="$envf.out" relctl release changed --component "$1" 2>&1) \
    || { echo "$out" >&2; fail "release changed --component $1 failed"; }
  echo "$(exported RELCTL_CHANGED "$envf") $(exported RELCTL_CHANGED_FILES "$envf")"
}

# release <component> <expected-version> <expected-tag> <expected-latest>
# Creates and publishes a release of the component and checks what it exports.
release() {
  local comp="$1" version="$2" tag="$3" latest="$4" envf out id
  envf="$(mktemp)"
  out=$(cd "$SANDBOX_DIR" && GITHUB_ENV="$envf" GITHUB_OUTPUT="$envf.out" relctl release create --component "$comp" --release-branch "$SANDBOX_BRANCH" 2>&1) \
    || { echo "$out" >&2; fail "release create --component $comp failed"; }
  assert_eq "$(echo "$out" | parse_version)" "$version" "$comp: version"
  assert_eq "$(exported RELCTL_VERSION "$envf")" "$version" "$comp: RELCTL_VERSION is plain"
  assert_eq "$(exported RELCTL_TAG "$envf")" "$tag" "$comp: RELCTL_TAG carries the prefix"
  assert_eq "$(exported RELCTL_COMPONENT "$envf")" "$comp" "$comp: RELCTL_COMPONENT"
  assert_eq "$(exported RELCTL_LATEST_VERSION "$envf")" "$latest" "$comp: latest release of the component only"
  id=$(echo "$out" | parse_release_id)
  [ -n "$id" ] || { echo "$out" >&2; fail "$comp: no release id"; }
  (cd "$SANDBOX_DIR" && relctl release publish --component "$comp" --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null) \
    || fail "$comp: release publish failed"
  sandbox_sync
  wait_release_listed "$tag" false
  assert_eq "$(gh api "repos/${GITHUB_REPOSITORY}/releases/tags/$tag" --jq .tag_name)" "$tag" "$comp: release $tag exists"
}

push_files "chore: components" \
  '.relctl.yaml=version_scheme: calver
components:
  whisper:
    paths: ["deploy/whisper/**", "deploy/Containerfile.whisper"]
  router:
    tag_prefix: "router-v"
    paths: ["cmd/router/**"]' \
  'deploy/whisper/server.py=print("whisper 1")' \
  'deploy/Containerfile.whisper=FROM scratch' \
  'cmd/router/main.go=package main' \
  'docs/readme.md=docs'

# 1. nothing is released yet: both components count as changed
assert_eq "$(changed whisper)" "true 0" "whisper has no release yet"
assert_eq "$(changed router)" "true 0" "router has no release yet"

# 2. first releases: own tag prefix, own counter; the repository's release 0.1.0 is nobody's latest
release whisper "$day.1" "whisper/$day.1" ""
release router "$day.1" "router-v$day.1" ""

# 3. right after its release a component is unchanged, whatever happens elsewhere
assert_eq "$(changed whisper)" "false 0" "whisper right after its release"
push_files "docs: unrelated change" 'docs/readme.md=docs changed'
assert_eq "$(changed whisper)" "false 0" "a change outside its paths"
assert_eq "$(changed router)" "false 0" "router after a change outside its paths"

# 4. a change inside the paths of one component only changes that one
push_files "fix: whisper" 'deploy/whisper/server.py=print("whisper 2")'
assert_eq "$(changed whisper)" "true 1" "whisper after a change in its paths"
assert_eq "$(changed router)" "false 0" "router is not affected by a change of whisper"

# 5. the counters are independent
release whisper "$day.2" "whisper/$day.2" "$day.1"
release router "$day.2" "router-v$day.2" "$day.1"
assert_eq "$(changed whisper)" "false 0" "whisper after its second release"

# 6. every component keeps to its own tags
tags=$(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags" --jq '.[].ref' | sed 's#refs/tags/##' | sort | tr '\n' ' ')
assert_eq "$tags" "0.1.0 router-v$day.1 router-v$day.2 whisper/$day.1 whisper/$day.2 " "tags of the repository"

# 7. a component that does not exist is refused with the list of the known ones
if out=$(cd "$SANDBOX_DIR" && relctl release create --component nope --release-branch "$SANDBOX_BRANCH" 2>&1); then
  echo "$out" >&2
  fail "an unknown component must be refused"
fi
assert_match "$out" "known components: router, whisper" "message lists the components"

# 8. --since compares with a given commit instead of the latest release
first_commit=$(git -C "$SANDBOX_DIR" rev-list --max-parents=0 HEAD | tail -1)
assert_eq "$(cd "$SANDBOX_DIR" && GITHUB_ENV="$(mktemp)" relctl release changed --component whisper --since "$first_commit" 2>&1 | grep -c 'Changed: true')" "1" "--since an old commit"
log "components scenario passed"
