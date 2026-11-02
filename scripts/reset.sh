#!/usr/bin/env bash
# Resets the sandbox to a known state: no releases, no tags, no pull requests,
# no topic branches, and a sandbox branch containing a single seed commit with a
# published release 0.1.0.
#
# This destroys everything on the sandbox branch. `main` (the tooling) is not touched.
# Needs a token that may delete releases/tags/branches and force-push.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

require_env GH_TOKEN GITHUB_REPOSITORY
configure_git
repo="$GITHUB_REPOSITORY"

log "closing open pull requests"
for pr in $(gh pr list --state open --json number --jq '.[].number'); do
  gh pr close "$pr" > /dev/null || true
done

log "deleting releases"
for id in $(gh api "repos/$repo/releases" --paginate --jq '.[].id'); do
  gh api -X DELETE "repos/$repo/releases/$id" > /dev/null
done

log "deleting tags"
for ref in $(gh api "repos/$repo/git/matching-refs/tags" --paginate --jq '.[].ref'); do
  gh api -X DELETE "repos/$repo/git/$ref" > /dev/null
done

log "deleting topic branches"
for b in $(gh api "repos/$repo/branches" --paginate --jq '.[].name'); do
  case "$b" in
    main|"$SANDBOX_BRANCH") ;;
    *) gh api -X DELETE "repos/$repo/git/refs/heads/$b" > /dev/null || true ;;
  esac
done

log "recreating $SANDBOX_BRANCH from a seed commit"
work="$(mktemp -d)"
git -C "$work" init --quiet -b "$SANDBOX_BRANCH"
cat > "$work/README.md" <<'README'
# relctl-e2e sandbox

This branch is rewritten by the end-to-end tests. Do not work here.
README
git -C "$work" add README.md
git -C "$work" commit --quiet -m "seed"
git -C "$work" push --quiet --force "$(remote_url)" "$SANDBOX_BRANCH"
rm -rf "$work"

log "seeding release 0.1.0"
gh release create 0.1.0 --target "$SANDBOX_BRANCH" --title "Release 0.1.0" --notes "seed" > /dev/null

sandbox_clone
log "reset done"
