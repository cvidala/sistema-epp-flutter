-- ============================================================
-- CRÍTICO — Fuga cross-org: solicitudes_epp sin RLS.
--
-- solicitudes_epp nunca tuvo Row Level Security habilitada ni políticas
-- (ausente de toda migración de RLS; la auditoría 2026-08-21 no la incluyó).
-- Con RLS apagado, PostgREST devolvía TODAS las filas a cualquier usuario
-- autenticado, y el dashboard no filtra por org (confía en RLS) → un admin de
-- una empresa veía solicitudes de otras. Confirmado funcionalmente: un
-- supervisor con acceso a 1 obra veía solicitudes de 2 obras (1 ajena).
--
-- Fix: habilitar RLS + políticas scoped por obra→org, con el patrón canónico
-- del proyecto (get_user_org_id() + EXISTS sobre obras). solicitudes_epp tiene
-- obra_id (no org_id), así que el scope es vía la org de la obra.
--
-- Compatibilidad de flujos:
--  - SELECT: dashboard (admin) y app ven solo solicitudes de su org.
--  - INSERT: la app (supervisor) crea solicitudes para SU obra (auto por falta
--    de stock y manual) — pasa porque la obra es de su org.
--  - UPDATE: el admin "atiende" (cambia estado) dentro de su org.
--  - Las RPC/Edge Functions con service_role omiten RLS (no se ven afectadas).
-- ============================================================
ALTER TABLE solicitudes_epp ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "solicitudes_epp_select_org" ON solicitudes_epp;
DROP POLICY IF EXISTS "solicitudes_epp_insert_org" ON solicitudes_epp;
DROP POLICY IF EXISTS "solicitudes_epp_update_org" ON solicitudes_epp;
DROP POLICY IF EXISTS "solicitudes_epp_no_delete"  ON solicitudes_epp;

CREATE POLICY "solicitudes_epp_select_org" ON solicitudes_epp FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM obras
      WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id()
    )
  );

CREATE POLICY "solicitudes_epp_insert_org" ON solicitudes_epp FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM obras
      WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id()
    )
  );

CREATE POLICY "solicitudes_epp_update_org" ON solicitudes_epp FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM obras
      WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM obras
      WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id()
    )
  );

CREATE POLICY "solicitudes_epp_no_delete" ON solicitudes_epp FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- VERIFICACIÓN (SQL Editor) — RLS + policies por tabla:
-- ─────────────────────────────────────────────────────────────
/*
SELECT c.relname AS tabla, c.relrowsecurity AS rls_on, COUNT(p.polname) AS policies
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policy p ON p.polrelid = c.oid
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY c.relname, c.relrowsecurity
ORDER BY c.relrowsecurity, tabla;
*/
