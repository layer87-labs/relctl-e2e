#!/usr/bin/env bash
# Flow 1: SemVer from the branch prefix of the merged pull request, including
# the "!" breaking prefix and the pull request comment overrides.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

# case: branch, title, expected version, comments...
run_case() {
  local branch="$1" title="$2" expected="$3"
  shift 3
  open_and_merge "$branch" "$title" "$@"
  local version
  version=$(release_publish --merge-sha "$(merge_sha)")
  assert_eq "$version" "$expected" "$branch"
}

run_case fix/null-pointer        "fix: null pointer"            0.1.1
run_case feature/new-flag        "feat: new flag"               0.2.0
run_case major/drop-old-api      "major change"                 1.0.0
run_case feat-bang/x             "unknown prefix is a patch"    1.0.1
run_case "feat!/rename-command"  "feat!: rename command"        2.0.0
run_case fix/override-level      "fix: override via comment"    3.0.0 "relctl_patch_level: major"
run_case fix/legacy-comment      "fix: legacy comment prefix"   3.1.0 "aci_patch_level: minor"
run_case fix/pin-version         "fix: pinned version"          9.9.9 "relctl_version_override: 9.9.9"
log "semver scenario passed"
