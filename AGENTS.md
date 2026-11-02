# AGENTS.md

This repository is the automated end-to-end test bed for relctl. It is **public**.

- Never make changes to the `sandbox` branch, tags or releases by hand or from an agent session:
  they are owned by `scripts/reset.sh` and the scenarios.
- Change tooling only on a descriptively named branch (`feat/…`, `fix/…`, `chore/…`) through a
  pull request to `main`.
- No internal information from private projects, no links to private repositories, English only.
- Commits carry no AI attribution: no `Co-Authored-By` trailers for tools, no session links.
- Run `scripts/test-lib.sh` before pushing. Scenarios are verified by running the workflow.
- A new scenario is a script in `scenarios/` named `NN-name.sh`; it uses the helpers in
  `scripts/lib.sh` and must work from a freshly reset sandbox.
