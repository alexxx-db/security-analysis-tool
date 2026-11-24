-- q05_person_owned_production.sql
-- Question: which production securables are owned by a human identity rather
-- than a group or service principal?
--
-- Parameters:
--   :protected_prefixes  comma-separated catalog-name prefixes
--                        (default 'prod_next,salesforce')
--
-- Rationale: an owner containing '@' is treated as a human identity; groups
-- and service principals do not use email-form identifiers in the graph.
--
-- Known limits (SAT v0.8.0 graph):
--   * Ownership is read from vertices.owner where the collector recorded it;
--     objects whose owners were not collected are absent (not "unowned").
--   * Point-in-time from the last collection run.

SELECT
  v.node_type,
  v.name        AS object_name,
  v.owner       AS owner_identity,
  'Owns'        AS relation
FROM `sec_ops`.`security_analysis`.`vertices` v
WHERE v.node_type IN ('Catalog', 'Schema', 'Table')
  AND v.owner LIKE '%@%'
  AND EXISTS (
      SELECT 1
      FROM (SELECT explode(split(:protected_prefixes, ',')) AS prefix) p
      WHERE v.name LIKE concat(trim(p.prefix), '%')
  )
UNION ALL
SELECT
  'edge',
  e.dst,
  COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')),
  'Owns'
FROM `sec_ops`.`security_analysis`.`edges` e
LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
WHERE e.relationship = 'Owns'
  AND COALESCE(v.name, e.src) LIKE '%@%'
ORDER BY node_type, object_name;
