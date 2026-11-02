#!/usr/bin/env bash
# CI systems that relctl cannot detect from the environment: `relctl connect github` first.
# A GitLab CI environment without a connection must give a clear error; with a connection
# (server and repository in a file, the token in GITHUB_TOKEN) the same environment works,
# and so does an environment without any CI variables.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "$here/../scripts/lib.sh"
require_env GH_TOKEN GITHUB_REPOSITORY GITHUB_TOKEN
configure_git
sandbox_clone

open_and_merge "fix/connect" "fix: connect check"
sha="$(merge_sha)"

# run relctl with a clean environment: only PATH and HOME, optionally GitLab CI variables
clean() { (cd "$SANDBOX_DIR" && env -i PATH="$PATH" HOME="$HOME" "$@" 2>&1); }
gitlab_env=(CI=true CI_SERVER_URL=https://gitlab.example.com CI_PROJECT_URL=https://gitlab.example.com/org/repo CI_JOB_TOKEN=not-a-real-token)
preview=(relctl release create --dry-run --release-branch "$SANDBOX_BRANCH" --merge-sha "$sha")

# 1. GitLab CI variables, no connection: unsupported SCM with a helpful message, not a crash
if out=$(clean "${gitlab_env[@]}" "${preview[@]}"); then
  echo "$out" >&2
  fail "a GitLab CI environment without a connection must fail"
fi
assert_match "$out" "GitLab is not supported" "message for GitLab"
assert_match "$out" "relctl connect github" "hint for GitLab CI with a GitHub repository"
assert_match "$out" "open an issue" "hint to open an issue"
if [[ "$out" == *"panic"* || "$out" == *"nil pointer"* ]]; then fail "relctl crashed: $out"; fi

# 2. no CI variables at all, no connection: a clear message, not a crash
if out=$(clean "${preview[@]}"); then
  echo "$out" >&2
  fail "without any CI variables and without a connection relctl must fail"
fi
if [[ "$out" == *"panic"* || "$out" == *"nil pointer"* ]]; then fail "relctl crashed: $out"; fi
log "ok: no crash without a connection"

# 3. connect, then everything works. The connection file holds server and repository only:
# the token is used to verify the connection and is never written.
out=$(clean relctl connect github --server https://github.com --repository "$GITHUB_REPOSITORY" --token "$GH_TOKEN") \
  || { echo "$out" >&2; fail "relctl connect github failed"; }
conn="$SANDBOX_DIR/.relctl-connection.yaml"
[ -f "$conn" ] || fail "the connection file was not written"
if grep -q -e "$GH_TOKEN" -e "token" "$conn"; then fail "the connection file must not contain a token"; fi
grep -q "$GITHUB_REPOSITORY" "$conn" || fail "the connection file does not name the repository"
[ ! -f "$SANDBOX_DIR/.awesomerc.yaml" ] || fail "no legacy connection file may be written"
log "ok: connection file written without a token"

# the token comes from GITHUB_TOKEN on every call - with GitLab CI variables and without any
out=$(clean GITHUB_TOKEN="$GH_TOKEN" "${gitlab_env[@]}" "${preview[@]}") \
  || { echo "$out" >&2; fail "release preview with GitLab CI variables and a connection failed"; }
assert_eq "$(echo "$out" | parse_version)" "0.1.1" "version with GitLab CI variables and a connection"

out=$(clean GITHUB_TOKEN="$GH_TOKEN" "${preview[@]}") \
  || { echo "$out" >&2; fail "release preview without CI variables and with a connection failed"; }
assert_eq "$(echo "$out" | parse_version)" "0.1.1" "version without CI variables and with a connection"

# 4. a connection without a token is refused with a message that names GITHUB_TOKEN
if out=$(clean "${preview[@]}"); then
  echo "$out" >&2
  fail "a connection without GITHUB_TOKEN must fail"
fi
assert_match "$out" "GITHUB_TOKEN" "message names GITHUB_TOKEN"
if [[ "$out" == *"panic"* || "$out" == *"nil pointer"* ]]; then fail "relctl crashed: $out"; fi

# 5. remove the connection again
clean relctl connect remove > /dev/null || fail "relctl connect remove failed"
[ ! -f "$conn" ] || fail "the connection file was not removed"
log "connect scenario passed"
