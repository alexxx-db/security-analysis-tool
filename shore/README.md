# Security Analysis Tool (SAT) at Shore Capital Partners

This directory contains Shore-specific configuration for Databricks' Security
Analysis Tool (SAT), pinned to upstream tag `v0.8.0`. Nothing here is installed
yet — this PR prepares the deployment package. The platform admin runs the
steps in `RUNBOOK.md`; the security owner runs the reviews in
`review_checklist.md`.

## What SAT does at Shore

- **Posture checks** — evaluates account and workspace configuration against
  Databricks security best practices (the `security_analysis` checks), on a
  weekly schedule, for every Shore workspace the SAT service principal has been
  added to.
- **Secret scanning** — runs TruffleHog over notebooks and job resources daily,
  writing findings into `sec_ops.security_analysis`.
- **Permissions Analysis (BrickHound)** — builds a vertices-and-edges graph in
  Unity Catalog of principals, groups, securables and the permissions between
  them. This is the main reason for installing SAT: it answers "who can reach
  what, directly or through group chains" — the kind of question that would
  have surfaced an outside firm's group holding manage rights on production.

SAT complements the hourly audit-log detections bundle
(`cybersec-detection-app`): detections react to events; SAT checks standing
configuration and standing access.

## What SAT does not do

- It does not remediate anything. It reports findings; people act on them.
- Permissions Analysis results are **incomplete and point-in-time** (upstream's
  own caveat). It is an audit aid, not a compliance determination. The
  permissions graph does not capture every relationship — notably some
  service-principal role assignments; see the query headers in `queries/` and
  the handoff.
- It does not replace Entra ID / Azure RBAC review. Azure-level access paths
  are out of SAT's view.
- No Gradio app is deployed. Review happens through the saved queries in
  `queries/` and the SAT Lakeview dashboards.

## How results are reviewed

| Role | Access | What they do |
|---|---|---|
| `scp-secops-admins` | CAN_MANAGE on SAT jobs; READ on `sat_scope`; `sec_ops` catalog owner | Runs the weekly 30-minute review (`review_checklist.md`), runs `queries/q01–q06`, manages exceptions |
| `scp-secops-triage` | CAN_VIEW on dashboards and results | Reads dashboards during triage; no job control |

Results describe weaknesses, so `sec_ops` stays restricted — no `account
users`, no broad read. Findings are recorded as restricted exceptions per
`review_checklist.md`.

## Layout

```
shore/
  README.md              this file
  RUNBOOK.md             deploy/rollback steps for the platform admin
  THIRD_PARTY.md         upstream provenance and license
  template_answers.json  answers for `databricks bundle init`
  queries/               q01–q06 parameterized review queries
  review_checklist.md    weekly review procedure
  tests/                 offline checks (answers schema, no literals, SQL parse)
```

## Run the tests

```bash
pip install sqlglot
python -m pytest -q shore/tests
```
