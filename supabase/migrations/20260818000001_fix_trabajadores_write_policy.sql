-- Fix: trabajadores_write_org usaba FOR ALL (incluye SELECT), lo que
-- cortocircuitaba la restricción de obra para SUPERVISOR.
-- En PostgreSQL, políticas permissivas se combinan con OR — la política
-- FOR ALL más laxa ganaba sobre la FOR SELECT más estricta.
--
-- Solución: separar en INSERT/UPDATE/DELETE (no SELECT).

DROP POLICY IF EXISTS "trabajadores_write_org" ON trabajadores;

CREATE POLICY "trabajadores_insert_org"
  ON trabajadores FOR INSERT TO authenticated
  WITH CHECK (org_id = get_user_org_id());

CREATE POLICY "trabajadores_update_org"
  ON trabajadores FOR UPDATE TO authenticated
  USING (org_id = get_user_org_id())
  WITH CHECK (org_id = get_user_org_id());

CREATE POLICY "trabajadores_delete_org"
  ON trabajadores FOR DELETE TO authenticated
  USING (org_id = get_user_org_id());
