#!/usr/bin/env bash
# Runs every scenario in scenarios/ in order. Each scenario starts from a freshly
# reset sandbox. Usage: run-all.sh [scenario-name-filter]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
filter="${1:-}"

results=()
failed=0
for scenario in "$root"/scenarios/*.sh; do
  name="$(basename "$scenario" .sh)"
  if [ -n "$filter" ] && [[ "$name" != *"$filter"* ]]; then
    continue
  fi
  echo "::group::$name"
  if bash "$here/reset.sh" && bash "$scenario"; then
    results+=("| $name | pass |")
  else
    results+=("| $name | **FAIL** |")
    failed=1
  fi
  echo "::endgroup::"
done

summary="| scenario | result |
| --- | --- |
$(printf '%s\n' "${results[@]}")"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "relctl $(relctl --version 2>&1 | head -1)" >> "$GITHUB_STEP_SUMMARY"
  echo "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
exit "$failed"
