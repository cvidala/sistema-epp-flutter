-- ============================================================
-- TrazApp — Módulo: Solicitudes EPP a Bodega
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. TABLA SOLICITUDES_EPP ─────────────────────────────────
CREATE TABLE IF NOT EXISTS solicitudes_epp (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id         UUID NOT NULL REFERENCES obras(obra_id) ON DELETE CASCADE,
  trabajador_id   UUID REFERENCES trabajadores(trabajador_id) ON DELETE SET NULL,
  trabajador_rut  TEXT,
  trabajador_nombre TEXT,
  supervisor_id   UUID REFERENCES trabajadores(trabajador_id) ON DELETE SET NULL,
  supervisor_nombre TEXT,
  items           JSONB NOT NULL DEFAULT '[]',  -- [{epp_id, nombre, cantidad}]
  observacion     TEXT,
  estado          TEXT NOT NULL DEFAULT 'pendiente',  -- 'pendiente' | 'atendida' | 'rechazada'
  atendida_por    TEXT,
  atendida_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_solicitudes_epp_obra_id    ON solicitudes_epp(obra_id);
CREATE INDEX IF NOT EXISTS idx_solicitudes_epp_estado     ON solicitudes_epp(estado);
CREATE INDEX IF NOT EXISTS idx_solicitudes_epp_created_at ON solicitudes_epp(created_at DESC);

-- ── 2. ROW LEVEL SECURITY ───────────────────────────────────
ALTER TABLE solicitudes_epp ENABLE ROW LEVEL SECURITY;

-- Autenticados pueden insertar (supervisor desde la app)
DROP POLICY IF EXISTS "insert_auth_solicitudes_epp" ON solicitudes_epp;
CREATE POLICY "insert_auth_solicitudes_epp"
  ON solicitudes_epp FOR INSERT TO authenticated
  WITH CHECK (true);

-- Autenticados pueden leer todo (dashboard + app)
DROP POLICY IF EXISTS "select_auth_solicitudes_epp" ON solicitudes_epp;
CREATE POLICY "select_auth_solicitudes_epp"
  ON solicitudes_epp FOR SELECT TO authenticated
  USING (true);

-- Autenticados pueden actualizar (para marcar como atendida/rechazada)
DROP POLICY IF EXISTS "update_auth_solicitudes_epp" ON solicitudes_epp;
CREATE POLICY "update_auth_solicitudes_epp"
  ON solicitudes_epp FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (true);

-- Nadie puede eliminar
DROP POLICY IF EXISTS "no_delete_solicitudes_epp" ON solicitudes_epp;
CREATE POLICY "no_delete_solicitudes_epp"
  ON solicitudes_epp FOR DELETE
  USING (false);

-- ── 3. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'solicitudes_epp'
ORDER BY cmd;
*/
