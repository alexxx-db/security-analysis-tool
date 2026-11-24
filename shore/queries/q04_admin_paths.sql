-- q04_admin_paths.sql
-- Question: which principals have a path to workspace, account or metastore
-- admin — directly or through group membership?
--
-- Parameters:
--   :company_domain  Shore email domain, to flag external principals
--
-- Admin signals used (SAT v0.8.0 graph):
--   * edges.relationship = 'AccountAdmin'   (src -> account:<id>)
--   * edges.relationship = 'WorkspaceAccess' to admin-flagged workspaces is
--     not privilege-qualified; workspace admin comes from vertex
--     properties.roles where collected.
--   * metastore admin = membership in the metastore-admin group; surfaced as
--     MemberOf chains into groups named by :admin_group_patterns.
--
-- Parameters continued:
--   :admin_group_patterns  comma-separated LIKE patterns for admin groups
--                          (default 'admin%,metastore%admin%')
--
-- Known limits:
--   * Group chains expanded to 5 hops.
--   * Azure RBAC / Entra group membership outside Databricks is not visible.
--   * Point-in-time from the last collection run.

WITH memberof AS (
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', ''))    AS member,
    COALESCE(g.name, regexp_replace(e.dst, '^[a-z_0-9]+:', '')) AS parent_group
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` g ON g.id = e.dst
  WHERE e.relationship = 'MemberOf'
),
hop2 AS (
  SELECT DISTINCT m.member, p.parent_group AS reached
  FROM memberof m JOIN memberof p ON p.member = m.parent_group
),
hop3 AS (
  SELECT DISTINCT m.member, p.reached
  FROM memberof m JOIN hop2 p ON p.member = m.parent_group
),
hop4 AS (
  SELECT DISTINCT m.member, p.reached
  FROM memberof m JOIN hop3 p ON p.member = m.parent_group
),
hop5 AS (
  SELECT DISTINCT m.member, p.reached
  FROM memberof m JOIN hop4 p ON p.member = m.parent_group
),
chains AS (
  SELECT member, parent_group AS reached FROM memberof
  UNION SELECT member, reached FROM hop2
  UNION SELECT member, reached FROM hop3
  UNION SELECT member, reached FROM hop4
  UNION SELECT member, reached FROM hop5
),
direct_admins AS (
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')) AS principal,
    'AccountAdmin'                                          AS admin_kind
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  WHERE e.relationship = 'AccountAdmin'
),
admin_groups AS (
  -- groups matching the admin name patterns, plus groups that themselves
  -- carry an AccountAdmin edge
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')) AS group_name
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  WHERE e.relationship = 'AccountAdmin'
  UNION
  SELECT v.name
  FROM `sec_ops`.`security_analysis`.`vertices` v
  WHERE v.node_type IN ('Group', 'AccountGroup')
    AND EXISTS (
      SELECT 1
      FROM (SELECT explode(split(:admin_group_patterns, ',')) AS pat) p
      WHERE lower(v.name) LIKE lower(trim(p.pat))
    )
)
SELECT DISTINCT
  a.principal AS effective_principal, a.admin_kind, 'direct' AS path_type,
  a.principal LIKE concat('%', :company_domain) AS is_internal_domain
FROM direct_admins a
UNION ALL
SELECT DISTINCT
  c.member, 'AccountAdmin', concat('via ', c.reached), NULL
FROM chains c JOIN direct_admins a ON a.principal = c.reached
UNION ALL
SELECT DISTINCT
  c.member, 'admin-group member', concat('via ', c.reached),
  c.member LIKE concat('%', :company_domain)
FROM chains c JOIN admin_groups g ON g.group_name = c.reached
ORDER BY admin_kind, effective_principal;
