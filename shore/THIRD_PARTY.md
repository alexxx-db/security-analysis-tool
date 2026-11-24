# Third-party component: Databricks Security Analysis Tool (SAT)

| Item | Value |
|---|---|
| Project | security-analysis-tool |
| Upstream repository | https://github.com/databricks-industry-solutions/security-analysis-tool |
| Pinned release | tag `v0.8.0` |
| Pinned commit | `9714352935628e675a68315aab88dec818187dad` (verified) |
| License | Databricks License — see `LICENSE` and `NOTICE` at repo root |
| Support | Provided AS-IS; no Databricks support commitment. Upstream contact: `sat@databricks.com` (upstream's own FAQ) |

## Modifications

None. All upstream files are unchanged at `v0.8.0`; Shore-specific material
lives only under `shore/`. Deployment-time edits are applied to the *generated*
bundle output (`./SAT`), not to this checkout — see `RUNBOOK.md` step 5.

`LICENSE` and `NOTICE` must be retained in any copy or deployment of this code.

## Provenance note

The remote used for this PR is a fork (`alexxx-db`) whose default branch is
ahead of upstream `v0.8.0`. This branch is built directly on the upstream tag;
the fork's extra commits are not included. Moving the remote to a Shore-owned
repository before install is the first item in the handoff.
