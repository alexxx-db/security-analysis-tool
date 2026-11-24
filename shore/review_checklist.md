# Weekly SAT review — security owner checklist

**Time:** Mondays after the 06:30 `sat_driver` run finishes (~30 minutes).
**Who:** a member of `scp-secops-admins`.
**Access needed:** CAN_VIEW on dashboards, SELECT on `sec_ops.security_analysis`.

## 1. Confirm the pipeline ran (5 min)

- All three scheduled jobs succeeded since Friday: `sat_driver` (Mon),
  `sat_secrets_scanner` (daily), `brickhound_data_collection` (daily).
  Failures go to the SecOps alert destination — check that nothing fired.
- `SELECT * FROM sec_ops.security_analysis.collection_metadata
   ORDER BY collected_at DESC LIMIT 5` — confirm a fresh run for
  `brickhound` and each workspace shows `analysis_enabled=true` in
  `security_analysis.workspace_configs` output.

## 2. Posture dashboard (10 min)

Open the SAT Lakeview dashboard (deployed under the bundle path). Review:

- **New failed checks** vs last week — anything whose status flipped to fail
  is a finding candidate. Pay attention to IA-* (identity), NS-* (network)
  and DP-* (data protection) checks on production workspaces.
- **Secrets scanner tile** — any new TruffleHog hits. A verified secret is a
  P1 finding; open a rotation ticket immediately.
- **Workspaces dropped out** — a workspace silently absent from results is
  worse than a failed check; see RUNBOOK "workspace skipped".

## 3. Permissions queries (10 min)

Run against `sec_ops.security_analysis` on `wh_secops` (SQL editor; set the
named parameters in the parameter bar):

- [ ] `queries/q01_manage_on_production.sql` — new principals with
      MANAGE/owner on `prod_next*`/`salesforce*` catalogs, especially via
      group chains.
- [ ] `queries/q03_external_members.sql` — privileged groups containing
      non-Shore-domain members. **This is the incident-prevention check.**
- [ ] `queries/q04_admin_paths.sql` — admin paths; any new account admins or
      admin-group members.
- Weekly alternates: `q02_external_use`, `q05_person_owned_production`,
  `q06_service_principal_users` — run each at least monthly.

## 4. What counts as a finding

| Signal | Severity |
|---|---|
| Verified secret in a notebook/job | **P1** — rotate now |
| External-domain member in a privileged group | **P1** — escalate to platform owner same day |
| New MANAGE/owner on production catalogs without a change ticket | High |
| New account-admin path | High |
| Posture check failed on a production workspace | Medium unless IA/DP |
| Human-owned production securable | Low — raise at next owner sync |

## 5. Recording findings

- Write findings into the **restricted** SecOps findings tracker — never a
  general channel; results describe exploitable weaknesses.
- Each finding: check/query that raised it, affected workspace/object,
  owner, due date, and status.
- **Exceptions:** a deliberate configuration (e.g. a sanctioned break-glass
  account) gets an exception record with approver, expiry ≤ 90 days, and
  re-review date. Expired exceptions automatically become findings again.
- If a query row is stale or wrong, check the `collection_metadata`
  timestamp first — the graph is point-in-time.

## 6. Monthly extras

- Re-run `notebooks/diagnosis/sat_diagnosis_azure.py` once — catches drift in
  secrets/connectivity silently degrading coverage.
- Review exception register expiry.
- Confirm the client-secret rotation date (≤180-day expiry) is still owned.
