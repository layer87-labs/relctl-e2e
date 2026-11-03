#!/usr/bin/env bash
# `relctl pr info` per version scheme: the version the pull request would release, and a help
# comment that only offers what the scheme understands (comment commands are SemVer only).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

# open_pr <branch> <title> [config] [changelog]: a pull request that stays open; prints its number.
open_pr() {
  local branch="$1" title="$2" config="${3:-}" changelog="${4:-}"
  git -C "$SANDBOX_DIR" checkout --quiet -B "$branch" "origin/$SANDBOX_BRANCH"
  echo "$title $(date +%s%N)" >> "$SANDBOX_DIR/changes.txt"
  if [ -n "$config" ]; then printf '%s\n' "$config" > "$SANDBOX_DIR/.relctl.yaml"; fi
  if [ -n "$changelog" ]; then printf '%s\n' "$changelog" > "$SANDBOX_DIR/CHANGELOG.md"; fi
  git -C "$SANDBOX_DIR" add -A
  git -C "$SANDBOX_DIR" commit --quiet -m "$title"
  git -C "$SANDBOX_DIR" push --quiet origin "HEAD:refs/heads/$branch"
  gh pr create --base "$SANDBOX_BRANCH" --head "$branch" --title "$title" --body "e2e" | grep -oE '[0-9]+$'
}

# check_pr <branch> <title> <scheme> <expected-version> <comment-mentions-commands: yes|no> [config] [changelog]
check_pr() {
  local branch="$1" title="$2" scheme="$3" expected="$4" commands="$5" config="${6:-}" changelog="${7:-}"
  local pr envf out comments
  pr=$(open_pr "$branch" "$title" "$config" "$changelog")
  envf="$(mktemp)"
  out=$(cd "$SANDBOX_DIR" && GITHUB_ENV="$envf" GITHUB_OUTPUT="$envf.out" relctl pr info -n "$pr" 2>&1) \
    || { echo "$out" >&2; fail "relctl pr info failed for scheme $scheme"; }
  assert_eq "$(exported RELCTL_VERSION_SCHEME "$envf")" "$scheme" "$scheme: scheme"
  assert_eq "$(exported RELCTL_NEXT_VERSION "$envf")" "$expected" "$scheme: version the pull request would release"
  assert_eq "$(exported RELCTL_LATEST_VERSION "$envf")" "0.1.0" "$scheme: latest release"
  assert_match "$out" "Version scheme: $scheme" "$scheme: printed scheme"

  # the help comment is written asynchronously to the API; read it back
  local i
  for i in 1 2 3 4 5; do
    comments=$(gh pr view "$pr" --json comments --jq '.comments[].body')
    [ -n "$comments" ] && break
    sleep 3
  done
  [ -n "$comments" ] || fail "$scheme: relctl wrote no help comment"
  if [ "$commands" = "yes" ]; then
    assert_match "$comments" "relctl_patch_level" "$scheme: the comment offers the comment commands"
  else
    if [[ "$comments" == *"relctl_patch_level:"* ]]; then fail "$scheme: the comment offers commands that have no effect: $comments"; fi
    assert_match "$comments" "Version scheme: \*\*$scheme\*\*" "$scheme: the comment names the scheme"
  fi
}

today_prefix="$(date -u +%Y%m).$(date -u +%-d)"

check_pr feature/pr-info "feat: pr info for semver" semver 0.2.0 yes
check_pr topic/calver-info "chore: pr info for calver" calver "$today_prefix.1" no \
  'version_scheme: calver'
check_pr topic/cc-info "feat: pr info for conventional commits" conventional-commits 0.2.0 no \
  'version_scheme: conventional-commits'
check_pr topic/changelog-info "docs: start 3.0.0" changelog 3.0.0 no \
  'version_scheme: changelog' $'# Changelog\n\n## 3.0.0\n\n- upcoming notes'
log "pr info scenario passed"
