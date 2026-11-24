-- q06_service_principal_users.sql
-- Question: who can act as each production service principal?
--
-- Parameters:
--   :protected_prefixes  comma-separated name prefixes identifying production
--                        service principals (default 'prod%,sp-%')
--
-- KNOWN LIMIT — read before trusting results:
--   SAT v0.8.0's collector does NOT record Entra app-role assignments or
--   "Service Principal User / Manager" equivalents as edges. This query only
--   returns workspace-level permission edges the graph happens to carry
--   (e.g. CanUse/CanManage on the SP object). A person able to request tokens
--   for an SP through Entra will NOT appear here. Treat results as a lower
--   bound; the Entra-side check must be reviewed separately in Azure —
--   flagged in the handoff.

SELECT DISTINCT
  sp.name                                                    AS service_principal,
  COALESCE(v.name, regexp_replace(e.src, '^[a-z_]+:', ''))   AS principal,
  e.relationship                                             AS privilege
FROM `sec_ops`.`security_analysis`.`vertices` sp
JOIN `sec_ops`.`security_analysis`.`edges` e
  ON e.dst = sp.id OR e.dst = sp.name
LEFT JOIN `sec_ops`.`security_analysis`.`vertices` v ON v.id = e.src
WHERE sp.node_type IN ('ServicePrincipal', 'AccountServicePrincipal')
  AND e.relationship IN ('CAN_MANAGE', 'CAN_USE', 'MANAGE', 'Owns')
  AND EXISTS (
      SELECT 1
      FROM (SELECT explode(split(:protected_prefixes, ',')) AS prefix) p
      WHERE sp.name LIKE concat(trim(p.prefix), '%')
  )
ORDER BY service_principal, principal;
