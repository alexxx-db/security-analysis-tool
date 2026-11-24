-- q01_manage_on_production.sql
-- Question: which principals, directly or through any chain of groups, hold
-- MANAGE, ALL PRIVILEGES or ownership on catalogs matching :protected_prefixes?
--
-- Parameters:
--   :protected_prefixes  comma-separated catalog-name prefixes
--                        (default 'prod_next,salesforce')
--
-- Known limits (SAT v0.8.0 graph):
--   * Group chains are expanded to 5 hops; deeper nesting is not traversed.
--   * Grant edge src is a principal *name*, not an id; names that changed
--     since collection will not join back to vertices.
--   * Results are point-in-time from the last brickhound_data_collection run.

WITH memberof AS (
  -- member (normalized) -> immediate parent group (normalized name)
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', ''))        AS member,
    COALESCE(g.name, regexp_replace(e.dst, '^[a-z_0-9]+:', ''))     AS parent_group
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
grants AS (
  -- manage-class privileges on catalogs matching the protected prefixes
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')) AS principal,
    regexp_replace(e.dst, '^ws_\\d+_catalog:', '')           AS catalog_name,
    e.relationship                                          AS privilege
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  WHERE e.relationship IN ('MANAGE', 'ALL PRIVILEGES', 'Owns')
    AND EXISTS (
      SELECT 1
      FROM (SELECT explode(split(:protected_prefixes, ',')) AS prefix) p
      WHERE regexp_replace(e.dst, '^ws_\\d+_catalog:', '')
            LIKE concat(trim(p.prefix), '%')
    )
)
SELECT DISTINCT
  gr.catalog_name, gr.privilege,
  c.member AS effective_principal, gr.principal AS granted_to, 'via group' AS path_type
FROM grants gr
JOIN chains c ON c.reached = gr.principal
UNION ALL
SELECT DISTINCT catalog_name, privilege, principal, principal, 'direct'
FROM grants
ORDER BY catalog_name, privilege, effective_principal;
