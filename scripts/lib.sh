#!/usr/bin/env bash
# Shared helpers for the relctl end-to-end scenarios.
# shellcheck shell=bash

set -euo pipefail

# The sandbox branch is the integration branch of the playground. `main` only
# holds this tooling and is never reset.
SANDBOX_BRANCH="${SANDBOX_BRANCH:-sandbox}"
SANDBOX_DIR="${SANDBOX_DIR:-$PWD/.sandbox}"

log()  { echo "[e2e] $*" >&2; }
fail() { echo "[e2e] FAIL: $*" >&2; exit 1; }

assert_eq() { # actual expected message
  [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
  log "ok: $3 = $1"
}

assert_match() { # actual regex message
  [[ "$1" =~ $2 ]] || fail "$3: '$1' does not match /$2/"
  log "ok: $3 = $1"
}

# parse_version reads relctl output on stdin and prints the version it reports.
parse_version() {
  grep -oE 'release with version: [^[:space:]]+' | tail -1 | awk '{print $NF}'
}

# parse_release_id reads relctl output on stdin and prints the created release id.
parse_release_id() {
  grep -oE 'Create release successful\. ID: [0-9]+' | tail -1 | awk '{print $NF}'
}

require_env() {
  local v
  for v in "$@"; do
    [ -n "${!v:-}" ] || fail "environment variable $v is required"
  done
}

# configure_git sets the committer used in the sandbox.
configure_git() {
  git config --global user.name "relctl-e2e"
  git config --global user.email "relctl-e2e@users.noreply.github.com"
}

remote_url() {
  echo "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
}

# sandbox_clone (re)creates the local sandbox working copy on the sandbox branch.
sandbox_clone() {
  rm -rf "$SANDBOX_DIR"
  git clone --quiet "$(remote_url)" "$SANDBOX_DIR"
  git -C "$SANDBOX_DIR" checkout --quiet "$SANDBOX_BRANCH"
  git -C "$SANDBOX_DIR" fetch --quiet --tags
}

sandbox_sync() {
  git -C "$SANDBOX_DIR" fetch --quiet --tags origin
  git -C "$SANDBOX_DIR" checkout --quiet "$SANDBOX_BRANCH"
  git -C "$SANDBOX_DIR" reset --quiet --hard "origin/$SANDBOX_BRANCH"
}

# open_and_merge <branch> <title> [comment...]
# Creates a commit on a topic branch, opens a pull request against the sandbox
# branch, posts the given comments, squash-merges it and syncs the sandbox.
open_and_merge() {
  local branch="$1" title="$2"
  shift 2
  git -C "$SANDBOX_DIR" checkout --quiet -B "$branch" "origin/$SANDBOX_BRANCH"
  echo "$title $(date +%s%N)" >> "$SANDBOX_DIR/changes.txt"
  git -C "$SANDBOX_DIR" add changes.txt
  git -C "$SANDBOX_DIR" commit --quiet -m "$title"
  git -C "$SANDBOX_DIR" push --quiet origin "HEAD:refs/heads/$branch"

  local pr
  pr=$(gh pr create --base "$SANDBOX_BRANCH" --head "$branch" --title "$title" --body "e2e" | grep -oE '[0-9]+$')
  local c
  for c in "$@"; do
    gh pr comment "$pr" --body "$c" > /dev/null
  done
  gh pr merge "$pr" --squash --delete-branch --subject "$title" --body "" > /dev/null
  sandbox_sync
  log "merged PR #$pr ($branch) at $(git -C "$SANDBOX_DIR" rev-parse --short HEAD)"
}

# publish_release <release-id>
publish_release() {
  relctl release publish --release-id "$1" --release-branch "$SANDBOX_BRANCH" > /dev/null
  sandbox_sync
}

# release_publish <relctl release create args...>
# Creates a release with the given arguments in the sandbox, publishes it and
# prints the version.
release_publish() {
  local out version id
  out=$(cd "$SANDBOX_DIR" && relctl release create --release-branch "$SANDBOX_BRANCH" "$@" 2>&1) || {
    echo "$out" >&2
    fail "relctl release create $* failed"
  }
  version=$(echo "$out" | parse_version)
  id=$(echo "$out" | parse_release_id)
  [ -n "$version" ] || { echo "$out" >&2; fail "no version in relctl output"; }
  [ -n "$id" ] || { echo "$out" >&2; fail "no release id in relctl output"; }
  (cd "$SANDBOX_DIR" && relctl release publish --release-id "$id" --release-branch "$SANDBOX_BRANCH" > /dev/null) \
    || fail "relctl release publish $id failed"
  sandbox_sync
  echo "$version"
}

# merge_sha prints the current head of the sandbox branch.
merge_sha() { git -C "$SANDBOX_DIR" rev-parse HEAD; }

# release_count <tag> prints how many releases (draft or published) carry the tag.
release_count() {
  gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate --jq "[.[] | select(.tag_name == \"$1\")] | length" \
    | awk '{s+=$1} END {print s+0}'
}

# dump_releases prints all releases (draft or published) for diagnosis.
dump_releases() {
  gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
    --jq '.[] | "id=\(.id) tag=\(.tag_name) draft=\(.draft) created=\(.created_at)"' >&2 || true
}

# wait_release_published <tag>
# GitHub's release listing is eventually consistent for a short time after a release
# is published. Wait until it shows the published release before asserting on it.
wait_release_published() {
  local tag="$1" i n
  for i in $(seq 1 20); do
    n=$(gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
      --jq "[.[] | select(.tag_name == \"$tag\" and .draft == false)] | length" | awk '{s+=$1} END {print s+0}')
    if [ "$n" -ge 1 ]; then
      return 0
    fi
    sleep 2
  done
  dump_releases
  fail "release $tag was not listed as published within 40s"
}
