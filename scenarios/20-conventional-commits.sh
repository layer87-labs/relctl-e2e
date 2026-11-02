#!/usr/bin/env bash
# Flow 2a: version from Conventional Commit titles of squash-merged pull requests.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

run_case() {
  local title="$1" expected="$2"
  open_and_merge "topic/$(date +%s%N)" "$title"
  local version
  version=$(release_publish --version-scheme conventional-commits)
  assert_eq "$version" "$expected" "$title"
}

run_case "fix: handle empty input"        0.1.1
run_case "feat: add export"               0.2.0
run_case "docs: explain export"           0.2.1
run_case "feat(api)!: remove v1 endpoint" 1.0.0
log "conventional-commits scenario passed"
