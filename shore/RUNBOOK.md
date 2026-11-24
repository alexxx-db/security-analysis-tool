# SAT Deploy Runbook — Shore Capital Partners

Deploys SAT `v0.8.0` (commit `9714352935628e675a68315aab88dec818187dad`) into
Shore's Azure Databricks environment. Nothing in this repo has been run yet —
this runbook is the entire deployment.

**Roles used below.** "Platform admin" = the person holding Databricks account
admin and workspace admin. "Security owner" = the `scp-secops-admins` lead.
"Entra admin" = whoever can create app registrations.

**Values the platform admin must supply** (none are committed to this repo):

| Placeholder | What it is | Where it comes from |
|---|---|---|
| `[TENANT_ID]` | Azure tenant ID | Entra portal → Overview |
| `[SUBSCRIPTION_ID]` | Azure subscription hosting the workspaces | Azure portal |
| `[ACCOUNT_ID]` | Databricks account ID | Account console URL / Accounts API |
| `[CLIENT_ID]` | App registration application (client) ID | Step 1 |
| `[CLIENT_SECRET]` | App registration client secret value | Step 1 (shown once) |
| `[SAT_SP_NAME]` | Display name of the SAT service principal | Step 2 |
| `[WORKSPACE_URL]` | The deployment workspace URL | Workspace browser URL |
| `[SECOPS_ALERT_EMAIL]` | Job failure destination — same as detections bundle | Security owner provides at deploy time |
| `[COST_CENTER]` | Cost center tag value | FinOps |

Already decided: `catalog=sec_ops`, schema `security_analysis`, warehouse
`wh_secops` (`eda6b2cb326f8e46`), timezone `America/Chicago`.

> **Privilege requirements upstream asks for** (from
> `docs/sat/docs/installation/standard/azure.mdx` at v0.8.0): the SAT service
> principal must hold **Account Admin**, **Workspace Admin in every analyzed
> workspace**, and **metastore admin** membership, plus Azure **Reader** on the
> subscription. Those are broad grants; the platform owner signs off on them in
> step 2 before anything else proceeds.

---

## Step 1 — Entra app registration and client secret

**Who:** Entra admin.
**Where:** Entra portal → App registrations → New registration.

1. Name: `sat-secops` (single tenant is sufficient).
2. After registration, open **Certificates & secrets → New client secret**.
   Description `sat-secops`. **Expiry must be ≤ 180 days** — pick 180 days,
   not "recommended" or longer custom periods.
3. Copy the secret **value** immediately — it is shown once.
4. Record the expiry date in Shore's secret-rotation register the same day,
   with the renewal owner set to `scp-secops-admins`. The runbook will fail
   six months from now if nobody owns the renewal.
5. Grant the app **Reader** on `[SUBSCRIPTION_ID]`: Azure portal →
   Subscription → Access control (IAM) → Add role assignment → Reader → select
   the app registration.

**Expected result:** an app registration with one client secret expiring
≤ 180 days, Reader on the subscription, and a rotation-register entry.

**Undo:** delete the client secret, then delete the app registration. Nothing
else depends on it until step 5.

## Step 2 — Service principal in Databricks

**Who:** Platform admin.
**Where:** Account console → User management → Service principals → Add.

1. Add service principal, paste `[CLIENT_ID]`, name `[SAT_SP_NAME]`
   (e.g. `sat-secops`).
2. Grant **Account Admin** — upstream requires it for account-level APIs
   (listing workspaces, account users/groups, workspace settings). This is the
   broadest grant in this runbook; it is the platform owner's call.
3. Add the principal as **Workspace Admin** in **each Shore workspace to be
   analyzed** — for Shore that is all workspaces. Add it nowhere else; an SP
   in a workspace is the analysis boundary.
4. Add the principal to the **metastore admin** role/group — upstream requires
   it to read Unity Catalog metadata and grants.

**Expected result:** the SP appears under account service principals with the
three admin assignments.

**Undo:** remove the SP's workspace memberships, then delete the SP from the
account. Remove the metastore-admin assignment.

## Step 3 — Secret scope and secrets

**Who:** Platform admin.
**Where:** workspace CLI (`databricks secrets ...`) with an admin profile for
`[WORKSPACE_URL]`.

```bash
databricks secrets create-scope sat_scope --initial-manage-principal users

# Scope ACL: SAT SP can read; secops admins can rotate
databricks secrets put-acl sat_scope "[SAT_SP_NAME]"    READ
databricks secrets put-acl sat_scope "scp-secops-admins" MANAGE

# Application secrets — values never committed, never echoed to chat
databricks secrets put-secret sat_scope client-id          --string-value "[CLIENT_ID]"
databricks secrets put-secret sat_scope client-secret      --string-value "[CLIENT_SECRET]"
databricks secrets put-secret sat_scope tenant-id          --string-value "[TENANT_ID]"
databricks secrets put-secret sat_scope subscription-id    --string-value "[SUBSCRIPTION_ID]"
databricks secrets put-secret sat_scope account-console-id --string-value "[ACCOUNT_ID]"

# SAT configuration values the notebooks read as secrets
databricks secrets put-secret sat_scope sql-warehouse-id     --string-value "eda6b2cb326f8e46"
databricks secrets put-secret sat_scope analysis_schema_name --string-value '`sec_ops`.security_analysis'
databricks secrets put-secret sat_scope proxies              --string-value '{}'
databricks secrets put-secret sat_scope use-sp-auth          --string-value "false"
```

If the upstream initializer expects any additional key it will name it in the
run's exception; add it the same way (source of truth for key names:
`notebooks/Utils/initialize.py`).

**Expected result:** `databricks secrets list-acls sat_scope` shows the SP
READ and `scp-secops-admins` MANAGE; `list-secrets` shows the nine keys.

**Undo:** `databricks secrets delete-scope sat_scope`.

## Step 4 — Unity Catalog grants

**Who:** Platform admin (metastore admin).
**Where:** SQL editor on `wh_secops` or `databricks sql` — this step runs SQL
against the workspace but creates only grants, no compute.

```sql
CREATE SCHEMA IF NOT EXISTS `sec_ops`.`security_analysis`;

GRANT USE CATALOG ON CATALOG `sec_ops` TO `[SAT_SP_NAME]`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY
  ON SCHEMA `sec_ops`.`security_analysis` TO `[SAT_SP_NAME]`;

-- System tables SAT's collections read where accessible
GRANT SELECT ON TABLE `system`.`access`.`audit`            TO `[SAT_SP_NAME]`;
GRANT SELECT ON SCHEMA `system`.`information_schema`       TO `[SAT_SP_NAME]`;
GRANT SELECT ON TABLE `system`.`billing`.`usage`           TO `scp-secops-admins`;
```

`SELECT`/`MODIFY`/`CREATE TABLE` on the schema are what the bootstrap writes
and the control tables need. If the first driver run logs access errors naming
other `system.*` objects, grant `SELECT` on those objects the same way —
system-catalog grants require metastore admin.

**Expected result:** `SHOW GRANTS ON SCHEMA sec_ops.security_analysis` lists
the SP.

**Undo:** `REVOKE` each grant; `DROP SCHEMA sec_ops.security_analysis CASCADE`
only during full removal (step 9).

## Step 5 — Initialize, validate, deploy the bundle

**Who:** Platform admin, running as their own identity or a deploy SP with
`CAN_MANAGE` on the target path — never as an interactive user under
`/Workspace/Users/` for deployed assets.
**Where:** the Git folder checkout (or a local clone) of this repo at branch
`shore/sat-config`. Run `bundle init`/`validate` there; generated output goes
to a working directory, deployed artifacts land on the shared path.

```bash
# From the repo root checkout (or the Git folder)
databricks bundle init dabs/dabs_template \
  --config-file shore/template_answers.json \
  --output-dir ./SAT
```

The initializer prints prompts for anything the answers file did not cover;
accept the defaults.

Then, **in the generated `./SAT` bundle** (this is deployable output, not
upstream source):

1. `databricks.yml` — set `workspace.root_path` to
   `/Shared/sec_ops/sat` (default is `/Applications/${bundle.name}/`;
   either is acceptable as long as it is a shared path — Shore uses
   `/Shared/sec_ops/sat` to match the detections layout).
2. `resources/brickhound_job.yml` — **delete the `apps:` section**. Shore does
   not deploy the Permissions Analysis Gradio app in this phase (no extra app
   identity; the saved queries cover review). Leave the
   `brickhound_data_collection` job intact.
3. Optionally add per-job `tags:` (`owner_team=security`, `env=prod`,
   `sensitivity=restricted`, `domain=security`,
   `cost_center=[COST_CENTER]`) and a `permissions:` block granting
   `scp-secops-admins` CAN_MANAGE and `scp-secops-triage` CAN_VIEW — or apply
   them post-deploy in step 6. Doing them here keeps the bundle the single
   source of truth.

```bash
cd SAT
databricks bundle validate
databricks bundle deploy
```

**Expected result:** `validate` prints the resolved job graph with no errors;
`deploy` uploads files under `/Shared/sec_ops/sat` and creates the four jobs:
`sat_initializer`, `sat_driver`, `sat_secrets_scanner`,
`brickhound_data_collection`. No app is created (step 5.2 removed it).

**Undo:** `databricks bundle destroy` removes every resource the bundle
created.

## Step 6 — Post-deploy hardening (not expressible in the v0.8.0 template)

The v0.8.0 bundle template has no notification or permission properties, so
apply these after deploy (skip whichever you added to the generated YAML):

```bash
# Job failure notifications — same destination as the detections bundle.
# Repeat for each job id shown by `databricks jobs list`.
databricks jobs update <JOB_ID> --json '{
  "new_settings": {
    "email_notifications": { "on_failure": ["[SECOPS_ALERT_EMAIL]"] }
  }
}'

# Job ACLs
databricks permissions update jobs/<JOB_ID> --json '{
  "access_control_list": [
    {"group_name": "scp-secops-admins", "permission_level": "CAN_MANAGE"},
    {"group_name": "scp-secops-triage", "permission_level": "CAN_VIEW"}
  ]
}'
```

Note: `databricks jobs update` `new_settings` merges settings but confirm the
existing task list remains — `databricks jobs get <JOB_ID>` before and after.

## Step 7 — First run order and verification

**Who:** Platform admin triggers; security owner observes.

1. `sat_initializer` — creates control tables and the `sec_ops.security_analysis`
   objects. Expect success; check the run output for workspace discovery.
2. `sat_driver` — first posture analysis across all enabled workspaces. First
   run may take an hour or more depending on workspace count.
3. `sat_secrets_scanner` — TruffleHog scan; writes secret findings.
4. `brickhound_data_collection` — populates `vertices`, `edges`,
   `collection_metadata` in `sec_ops.security_analysis`.
5. Diagnosis notebook: run `notebooks/diagnosis/sat_diagnosis_azure.py`
   manually in the deploy workspace attached to `wh_secops`/a small cluster.
   It verifies secrets, connectivity, workspace enablement and permissions —
   resolve anything it flags before declaring done.
6. Lakeview dashboards: SAT imports dashboard templates during the
   initializer/Setup notebooks (`5. import_dashboard_template_lakeview.py`
   if it was not run automatically). Share them CAN_VIEW to
   `scp-secops-triage`, CAN_MANAGE to `scp-secops-admins`.

**Expected result:** `security_analysis` workspace tables populated;
`collection_metadata` shows a successful run row; dashboards render.

**Undo:** `databricks bundle destroy` + steps 9 rollback.

## Step 8 — Cost

Four scheduled jobs on one shared job cluster each (classic compute —
serverless analyzes only the current workspace, which does not meet Shore's
all-workspaces scope), plus `wh_secops` for dashboards and queries:

| Job | Cadence | Schedule (America/Chicago) |
|---|---|---|
| `sat_driver` | Weekly | Mon 06:30 |
| `sat_secrets_scanner` | Daily | 05:30 |
| `brickhound_data_collection` | Daily | 05:00 |
| `sat_initializer` | Manual | — |

Do not estimate spend — after one full week, measure from the warehouse:

```sql
SELECT usage_metadata.job_name, sku_name, SUM(usage_quantity) AS dbus
FROM `system`.`billing`.`usage`
WHERE usage_date >= date_sub(current_date(), 7)
  AND usage_metadata.job_name LIKE 'sat%'
GROUP BY ALL ORDER BY dbus DESC;
```

`scp-secops-admins` already has `SELECT` on `system.billing.usage` (step 4).
If a job's weekly DBU share is disproportionate, first look at
`secrets_scanner` frequency — daily is a decision, not a requirement.

## Step 9 — Removal (full rollback)

**Who:** Platform admin, in order:

1. `databricks bundle destroy` in the generated bundle — deletes jobs, app
   bindings and deployed files under `/Shared/sec_ops/sat`.
2. `databricks secrets delete-scope sat_scope`.
3. `DROP SCHEMA sec_ops.security_analysis CASCADE;` — destroys all SAT result
   tables including the permissions graph. Export anything needed first.
4. Revoke the SP's system-table grants (`REVOKE SELECT ON TABLE
   system.access.audit FROM "[SAT_SP_NAME]";` etc.).
5. Remove the SP's workspace memberships and metastore-admin role; delete the
   SP from the account console.
6. Remove the rotation-register entry and delete the Entra app registration.

---

## If `bundle init` or `deploy` fails

- **Unknown variable in answers file** — the file keys must match
  `dabs/dabs_template/databricks_template_schema.json` at v0.8.0; run
  `python -m pytest shore/tests/test_answers.py` to check.
- **Secret scope not found / empty secret at runtime** — a key name typo; the
  initializer notebook exception names the missing key.
- **Workspace skipped in driver output** — the SP is not a workspace admin in
  that workspace (step 2.3).
- **Empty permissions graph** — metastore admin missing (step 2.4) or UC grant
  read failures; check `brickhound_data_collection` run logs.
