-- ============================================================
-- CRÍTICO (misma familia que solicitudes_epp) — perfiles filtraba cross-org.
--
-- Causa: perfiles tenía RLS ON y la policy scoped `perfiles_select_org`
-- (org_id = get_user_org_id()), PERO coexistían policies PERMISIVAS del template
-- de Supabase ("allow all authenticated": *_auth_perfiles con USING/CHECK = true).
-- Como las permisivas se combinan con OR, cualquier autenticado veía perfiles de
-- TODAS las orgs. El dashboard lista perfiles sin filtrar por org (confía en RLS)
-- → un admin de una empresa nueva veía usuarios de otra. No se notaba antes
-- porque solo había una org con datos. Las mismas policies permisivas eran las
-- que "permitían" al admin editar/suspender/eliminar a OTROS usuarios (la policy
-- scoped `perfiles_update_self` solo cubre user_id = auth.uid()).
--
-- Fix robusto: eliminar TODAS las policies de perfiles (con RAISE NOTICE para
-- dejar registro) y recrear SOLO las scoped por org, preservando las operaciones
-- legítimas del admin (editar/suspender/eliminar dentro de su propia org).
--
-- Compatibilidad de flujos (dashboard):
--  - SELECT: admin y usuarios ven solo perfiles de su org.
--  - INSERT: bloqueado; la creación va por RPC crear_perfil_usuario (SECURITY
--    DEFINER, ignora RLS) y por provision-organizacion (service_role).
--  - UPDATE: cada quien edita lo suyo; el admin edita a otros de SU org
--    (notif, rol, activo). No puede mover un perfil a otra org (WITH CHECK).
--  - DELETE: solo admin, y solo perfiles de SU org.
--  - service_role (Edge Functions) omite RLS por diseño.
-- ============================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT policyname, permissive, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'perfiles'
  LOOP
    RAISE NOTICE 'policy previa: % | permissive=% | cmd=% | qual=% | check=%',
      r.policyname, r.permissive, r.cmd, r.qual, r.with_check;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.perfiles', r.policyname);
  END LOOP;
END $$;

ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

-- SELECT: solo perfiles de la propia org.
CREATE POLICY "perfiles_select_org" ON perfiles FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

-- UPDATE: el propio usuario (sus preferencias) o un admin sobre otros de su org.
-- WITH CHECK impide sacar/mover un perfil a otra org.
CREATE POLICY "perfiles_update_org" ON perfiles FOR UPDATE TO authenticated
  USING (
    org_id = get_user_org_id()
    AND (user_id = auth.uid() OR user_is_admin())
  )
  WITH CHECK (
    org_id = get_user_org_id()
    AND (user_id = auth.uid() OR user_is_admin())
  );

-- DELETE: solo admin, solo perfiles de su org.
CREATE POLICY "perfiles_delete_admin_org" ON perfiles FOR DELETE TO authenticated
  USING (org_id = get_user_org_id() AND user_is_admin());

-- INSERT: bloqueado por RLS. La creación de perfiles va por SECURITY DEFINER
-- (crear_perfil_usuario) o service_role (provision-organizacion).
CREATE POLICY "perfiles_no_insert" ON perfiles FOR INSERT WITH CHECK (false);
