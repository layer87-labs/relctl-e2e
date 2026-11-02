#!/usr/bin/env bash
# Migration aid: RELCTL_LEGACY_ACI_ENV=true additionally exports ACI_* variables.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

open_and_merge "fix/compat" "fix: compat check"

env_file="$(mktemp)"
(cd "$SANDBOX_DIR" && GITHUB_ENV="$env_file" RELCTL_LEGACY_ACI_ENV=true \
  relctl release create --dry-run --release-branch "$SANDBOX_BRANCH" --merge-sha "$(merge_sha)" > /dev/null)

grep -q '^RELCTL_VERSION=' "$env_file" || fail "RELCTL_VERSION was not exported"
grep -q '^ACI_VERSION=' "$env_file" || fail "ACI_VERSION alias was not exported"
assert_eq "$(grep '^ACI_VERSION=' "$env_file" | cut -d= -f2)" "0.1.1" "legacy ACI_VERSION"

# without the switch no alias is written
: > "$env_file"
(cd "$SANDBOX_DIR" && GITHUB_ENV="$env_file" \
  relctl release create --dry-run --release-branch "$SANDBOX_BRANCH" --merge-sha "$(merge_sha)" > /dev/null)
if grep -q '^ACI_' "$env_file"; then fail "ACI_* must not be exported without RELCTL_LEGACY_ACI_ENV"; fi
log "awesome-ci compatibility scenario passed"
