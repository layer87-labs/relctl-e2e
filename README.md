# relctl-e2e

> **This is a fully automated test repository for [relctl](https://github.com/layer87-labs/relctl).**
> Do not make manual changes here. Everything on the `sandbox` branch, all tags, releases,
> branches and pull requests are created and **destroyed by scripts**. If you need a change,
> change the scripts on `main` through a pull request.

It runs relctl against the real GitHub API through every release flow, so that behaviour which
unit tests cannot cover (pull request lookup, comments, drafts, publishing, tags) is verified
before and after a release.

## Layout

| Branch | Purpose |
| --- | --- |
| `main` | The tooling: workflows, scripts, scenarios. Never reset. |
| `sandbox` | The playground and integration branch of the tests. **Rewritten from a single seed commit before every scenario.** |

```
scripts/lib.sh        shared helpers (pull request + merge helpers, version parsing)
scripts/reset.sh      hard reset of the sandbox (releases, tags, pull requests, branches, sandbox branch)
scripts/run-all.sh    runs all scenarios, each from a fresh reset
scripts/test-lib.sh   offline self-test of the helpers and a syntax check
scenarios/            one script per flow
```

## Scenarios

| Scenario | What it verifies |
| --- | --- |
| `10-semver` | Flow 1: bump from the branch prefix (`fix/`, `feature/`, `major/`, `feat!/`, unknown prefix), pull request comment overrides (`relctl_patch_level`, `relctl_version_override`, legacy `aci_patch_level`) |
| `20-conventional-commits` | Flow 2: bump from Conventional Commit titles of squash-merged pull requests, including `!` |
| `30-calver` | Flow 2: `YYYYMM.D.N`, `N` increments within a day |
| `40-changelog` | Flow 3: version and notes from `CHANGELOG.md`, undated heading refused, idempotent release |
| `50-awesome-ci-compat` | `RELCTL_LEGACY_ACI_ENV=true` exports `ACI_*` aliases, and not without the switch |

## Running

Run the **End-to-end** workflow (Actions → *End-to-end* → *Run workflow*). Inputs: the relctl
version to test (`latest` by default) and an optional scenario filter. It also runs weekly.

Locally (needs `gh`, `git`, and `relctl` on the `PATH`):

```bash
export GITHUB_REPOSITORY=layer87-labs/relctl-e2e
export GH_TOKEN=<token>            # see below
export GITHUB_TOKEN="$GH_TOKEN"
scripts/test-lib.sh                # offline self-test
scripts/run-all.sh 40-changelog    # one scenario
```

**The reset deletes all releases, tags and non-`main` branches of the repository it points at.**
`GITHUB_REPOSITORY` must be this repository.

## Requirements

- The repository setting *Settings → Actions → General → Allow GitHub Actions to create and approve
  pull requests* must be enabled, **or** a token secret `E2E_TOKEN` (a fine-grained token with
  *Contents*, *Pull requests* and *Administration: read* on this repository) is provided.
- No branch protection on `sandbox`: the reset force-pushes it.
