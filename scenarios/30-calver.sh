#!/usr/bin/env bash
# Flow 2b: CalVer (YYYYMM.DD.N), N counts the releases of the day.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

prefix="$(date -u +%Y%m).$(date -u +%-d)"

open_and_merge "topic/calver-1" "chore: first change"
first=$(release_publish --version-scheme calver)
assert_eq "$first" "$prefix.1" "first calver release"

open_and_merge "topic/calver-2" "chore: second change"
second=$(release_publish --version-scheme calver)
assert_eq "$second" "$prefix.2" "second calver release"
log "calver scenario passed"
