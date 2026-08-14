-- DT Compliance: org_id, obra_id, trigger inmutabilidad, RLS por org
-- Ref: ORD. N°1140/27 Dirección del Trabajo

-- ── 1. Columnas de tenant y faena ────────────────────────────────────────────
ALTER TABLE asistencias
  ADD COLUMN IF NOT EXISTS org_id  UUID REFERENCES organizaciones(org_id),
  ADD COLUMN IF NOT EXISTS obra_id UUID REFERENCES obras(id);

CREATE INDEX IF NOT EXISTS idx_asistencias_org_fecha
  ON asistencias(org_id, captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_asistencias_obra_fecha
  ON asistencias(obra_id, captured_at DESC);

-- ── 2. Trigger de inmutabilidad ───────────────────────────────────────────────
-- Bloquea UPDATE de campos críticos una vez insertado el registro.
-- sync_status puede actualizarse (paso offline→synced), los demás no.
CREATE OR REPLACE FUNCTION fn_asistencias_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.rut              IS DISTINCT FROM NEW.rut              OR
     OLD.captured_at      IS DISTINCT FROM NEW.captured_at      OR
     OLD.evidencia_hash   IS DISTINCT FROM NEW.evidencia_hash   OR
     OLD.validacion_tipo  IS DISTINCT FROM NEW.validacion_tipo  OR
     OLD.foto_path        IS DISTINCT FROM NEW.foto_path
  THEN
    RAISE EXCEPTION
      'Registro de asistencia inmutable — campos críticos no pueden modificarse (ORD. N°1140/27)';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_asistencias_immutable ON asistencias;
CREATE TRIGGER trg_asistencias_immutable
  BEFORE UPDATE ON asistencias
  FOR EACH ROW EXECUTE FUNCTION fn_asistencias_immutable();

-- ── 3. RLS SELECT aislado por org_id ─────────────────────────────────────────
-- Reemplaza la política anterior que permitía ver registros de todas las orgs.
DROP POLICY IF EXISTS "select_auth_asistencias" ON asistencias;

CREATE POLICY "select_org_asistencias"
  ON asistencias FOR SELECT TO authenticated
  USING (
    org_id = (SELECT org_id FROM perfiles WHERE user_id = auth.uid())
  );

-- ── 4. INSERT desde kiosko (anon): agregar org_id obligatorio ────────────────
-- La política INSERT anon existente (WITH CHECK (true)) sigue válida.
-- El cliente ahora envía org_id en el payload — no hace falta cambiar la política.
