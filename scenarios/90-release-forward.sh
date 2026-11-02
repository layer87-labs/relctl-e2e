#!/usr/bin/env bash
# relctl release forward: bring the production branch back into the development branch.
# The sandbox branch is the production branch here; "dev" is the development branch.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

forward() { (cd "$SANDBOX_DIR" && relctl release forward --from "$SANDBOX_BRANCH" --to dev "$@" 2>&1); }

branch_sha() { gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/$1" --jq .object.sha; }

# development branch starts at the seed commit
# dev belongs to this scenario: a leftover from an earlier run is overwritten
git -C "$SANDBOX_DIR" push --quiet --force origin "HEAD:refs/heads/dev"
seed="$(branch_sha dev)"

# 1. identical: nothing to do
out=$(forward) || { echo "$out" >&2; fail "forward on identical branches failed"; }
assert_match "$out" "nothing to forward" "identical branches"

# 2. production moved on, development did not: fast-forward
open_and_merge "fix/released" "fix: released change"
production="$(merge_sha)"
out=$(forward --dry-run) || { echo "$out" >&2; fail "dry run failed"; }
assert_match "$out" "fast-forward" "dry run names the action"
assert_eq "$(branch_sha dev)" "$seed" "dry run does not move the branch"
out=$(forward) || { echo "$out" >&2; fail "fast-forward failed"; }
assert_match "$out" "Fast-forwarded" "fast-forward"
assert_eq "$(branch_sha dev)" "$production" "dev now points to the production commit"

# 3. run again: development contains production, nothing to do
out=$(forward) || { echo "$out" >&2; fail "repeated forward failed"; }
assert_match "$out" "nothing to forward" "repeated run"

# 4. both moved on (diverged): a pull request is opened, once
git -C "$SANDBOX_DIR" fetch --quiet origin dev   # dev was moved by the fast-forward above
git -C "$SANDBOX_DIR" checkout --quiet -B dev-work origin/dev
echo "dev change" >> "$SANDBOX_DIR/dev.txt"
git -C "$SANDBOX_DIR" add dev.txt
git -C "$SANDBOX_DIR" commit --quiet -m "feat: work on dev"
# dev belongs to this scenario: a leftover from an earlier run is overwritten
git -C "$SANDBOX_DIR" push --quiet --force origin "HEAD:refs/heads/dev"
open_and_merge "fix/released-2" "fix: second released change"
out=$(forward) || { echo "$out" >&2; fail "forward of diverged branches failed"; }
assert_match "$out" "Opened pull request #[0-9]+" "diverged branches open a pull request"
pr=$(echo "$out" | grep -oE 'pull request #[0-9]+' | head -1 | tr -dc '0-9')
assert_eq "$(gh pr view "$pr" --json baseRefName --jq .baseRefName)" "dev" "the pull request targets dev"

out=$(forward) || { echo "$out" >&2; fail "repeated forward with an open pull request failed"; }
assert_match "$out" "already open" "no second pull request"
assert_eq "$(gh pr list --state open --base dev --json number --jq length)" "1" "open pull requests into dev"
log "release forward scenario passed"
