-- ============================================================
-- CRÍTICO (fix 2) — solicitudes_epp seguía filtrando tras habilitar RLS.
--
-- Causa: existía al menos una policy PERMISIVA preexistente (p. ej. el template
-- de Supabase "Enable read access for all"/USING(true)). En Postgres las
-- policies permisivas se combinan con OR, así que esa permitía ver todas las
-- filas aunque agregáramos policies scoped. El DROP por nombre del fix anterior
-- no la tocó (nombre distinto).
--
-- Fix robusto: eliminar TODAS las policies de solicitudes_epp (con RAISE NOTICE
-- para dejar registro de lo que había) y recrear SOLO las scoped por obra→org.
-- ============================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT policyname, permissive, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'solicitudes_epp'
  LOOP
    RAISE NOTICE 'policy previa: % | permissive=% | cmd=% | qual=% | check=%',
      r.policyname, r.permissive, r.cmd, r.qual, r.with_check;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.solicitudes_epp', r.policyname);
  END LOOP;
END $$;

ALTER TABLE solicitudes_epp ENABLE ROW LEVEL SECURITY;

CREATE POLICY "solicitudes_epp_select_org" ON solicitudes_epp FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id())
  );

CREATE POLICY "solicitudes_epp_insert_org" ON solicitudes_epp FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id())
  );

CREATE POLICY "solicitudes_epp_update_org" ON solicitudes_epp FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = solicitudes_epp.obra_id AND org_id = get_user_org_id())
  );

CREATE POLICY "solicitudes_epp_no_delete" ON solicitudes_epp FOR DELETE USING (false);
