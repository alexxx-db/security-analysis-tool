-- q02_external_use.sql
-- Question: which principals hold EXTERNAL USE LOCATION or EXTERNAL USE SCHEMA,
-- and on which objects?
--
-- Parameters: none.
--
-- Known limits (SAT v0.8.0 graph):
--   * EXTERNAL USE grants are collected only where SHOW GRANTS / the grants
--     API covered the object; unvisited schemas/locations are absent.
--   * Results are point-in-time from the last collection run.

SELECT
  COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', '')) AS principal,
  e.relationship                                          AS privilege,
  e.dst                                                   AS object_ref,
  e.created_at                                            AS collected_at
FROM `sec_ops`.`security_analysis`.`edges` e
LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
WHERE e.relationship IN ('EXTERNAL USE LOCATION', 'EXTERNAL USE SCHEMA')
ORDER BY principal, object_ref;
