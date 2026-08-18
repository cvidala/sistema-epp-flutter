-- Fix RLS: aislar trabajadores y catalogo_epp por org_id
-- Detectado: demo@trazapp.cl veía trabajadores y EPP de todas las organizaciones.

CREATE OR REPLACE FUNCTION public.get_user_org_id()
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT org_id FROM perfiles
  WHERE user_id = auth.uid() AND activo = true
  LIMIT 1;
$$;

ALTER TABLE trabajadores ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'trabajadores'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON trabajadores', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "trabajadores_select_org"
  ON trabajadores FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

CREATE POLICY "trabajadores_write_org"
  ON trabajadores FOR ALL TO authenticated
  USING (org_id = get_user_org_id())
  WITH CHECK (org_id = get_user_org_id());

ALTER TABLE catalogo_epp ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'catalogo_epp'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON catalogo_epp', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "catalogo_epp_select_org"
  ON catalogo_epp FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

CREATE POLICY "catalogo_epp_write_org"
  ON catalogo_epp FOR ALL TO authenticated
  USING (org_id = get_user_org_id())
  WITH CHECK (org_id = get_user_org_id());
