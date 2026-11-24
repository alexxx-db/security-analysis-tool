-- q03_external_members.sql
-- Question: which groups holding any privilege on protected catalogs contain
-- members whose email domain is not :company_domain?
--
-- Parameters:
--   :protected_prefixes  comma-separated catalog-name prefixes
--                        (default 'prod_next,salesforce')
--   :company_domain      Shore email domain (e.g. 'shorecp.com')
--
-- Known limits (SAT v0.8.0 graph):
--   * Membership edges use the user's email as the member identifier where
--     available; members without an email vertex are compared by name.
--   * Nested external groups appear as a group member, not expanded here —
--     run q01 for full chain expansion.
--   * Point-in-time from the last collection run.

WITH memberof AS (
  SELECT
    COALESCE(v.email, regexp_replace(e.src, '^[a-z_]+:', '')) AS member_id,
    COALESCE(g.name, regexp_replace(e.dst, '^[a-z_0-9]+:', '')) AS group_name
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` g ON g.id = e.dst
  WHERE e.relationship = 'MemberOf'
),
privileged_groups AS (
  SELECT DISTINCT
    COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')) AS group_name,
    regexp_replace(e.dst, '^ws_\\d+_catalog:', '')           AS catalog_name,
    e.relationship                                          AS privilege
  FROM `sec_ops`.`security_analysis`.`edges` e
  LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
  WHERE EXISTS (
      SELECT 1
      FROM (SELECT explode(split(:protected_prefixes, ',')) AS prefix) p
      WHERE regexp_replace(e.dst, '^ws_\\d+_catalog:', '')
            LIKE concat(trim(p.prefix), '%')
    )
    AND e.relationship NOT IN ('MemberOf', 'Contains', 'WorkspaceAccess')
)
SELECT DISTINCT
  pg.group_name,
  pg.catalog_name,
  pg.privilege,
  m.member_id AS external_member
FROM privileged_groups pg
JOIN memberof m ON m.group_name = pg.group_name
WHERE m.member_id NOT LIKE concat('%', :company_domain)
ORDER BY pg.group_name, external_member;
