-- Fix RLS: trabajador_obras, obra_epp_reglas, entregas_epp

ALTER TABLE trabajador_obras ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE pol record; BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='trabajador_obras'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON trabajador_obras', pol.policyname); END LOOP;
END $$;

CREATE POLICY "trabajador_obras_select_org"
  ON trabajador_obras FOR SELECT TO authenticated
  USING (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));

CREATE POLICY "trabajador_obras_write_org"
  ON trabajador_obras FOR ALL TO authenticated
  USING (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()))
  WITH CHECK (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));

ALTER TABLE obra_epp_reglas ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE pol record; BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='obra_epp_reglas'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON obra_epp_reglas', pol.policyname); END LOOP;
END $$;

CREATE POLICY "obra_epp_reglas_select_org"
  ON obra_epp_reglas FOR SELECT TO authenticated
  USING (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));

CREATE POLICY "obra_epp_reglas_write_org"
  ON obra_epp_reglas FOR ALL TO authenticated
  USING (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()))
  WITH CHECK (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));

ALTER TABLE entregas_epp ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE pol record; BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='entregas_epp'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON entregas_epp', pol.policyname); END LOOP;
END $$;

CREATE POLICY "entregas_epp_select_org"
  ON entregas_epp FOR SELECT TO authenticated
  USING (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));

CREATE POLICY "entregas_epp_insert_org"
  ON entregas_epp FOR INSERT TO authenticated
  WITH CHECK (obra_id IN (SELECT obra_id FROM obras WHERE org_id = get_user_org_id()));
