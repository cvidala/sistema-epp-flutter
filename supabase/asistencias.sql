-- ============================================================
-- TrazApp — Módulo 2: Asistencia Diaria
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. TABLA ASISTENCIAS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS asistencias (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  local_event_id  UUID UNIQUE,                    -- idempotencia (generado en cliente)
  rut             TEXT NOT NULL,
  foto_path       TEXT,                           -- ruta en Storage bucket 'asistencias-fotos'
  gps_lat         DOUBLE PRECISION,
  gps_lng         DOUBLE PRECISION,
  gps_accuracy_m  DOUBLE PRECISION,
  device_model    TEXT,
  sync_status     TEXT NOT NULL DEFAULT 'online', -- 'online' | 'synced'
  captured_at     TIMESTAMPTZ,                    -- timestamp del dispositivo cliente
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_asistencias_rut        ON asistencias(rut);
CREATE INDEX IF NOT EXISTS idx_asistencias_created_at ON asistencias(created_at DESC);

-- ── 2. ROW LEVEL SECURITY ───────────────────────────────────
ALTER TABLE asistencias ENABLE ROW LEVEL SECURITY;

-- Anon puede insertar (el kiosko usa anon key)
DROP POLICY IF EXISTS "insert_anon_asistencias" ON asistencias;
CREATE POLICY "insert_anon_asistencias"
  ON asistencias FOR INSERT TO anon
  WITH CHECK (true);

-- Autenticados pueden leer todo (dashboard)
DROP POLICY IF EXISTS "select_auth_asistencias" ON asistencias;
CREATE POLICY "select_auth_asistencias"
  ON asistencias FOR SELECT TO authenticated
  USING (true);

-- Nadie puede eliminar
DROP POLICY IF EXISTS "no_delete_asistencias" ON asistencias;
CREATE POLICY "no_delete_asistencias"
  ON asistencias FOR DELETE
  USING (false);

-- ── 3. STORAGE BUCKET ───────────────────────────────────────
-- Crear en Supabase Dashboard: Storage → New bucket
-- Nombre: asistencias-fotos
-- Tipo: privado
--
-- Luego agregar estas políticas en Storage → Policies:

-- INSERT (anon puede subir fotos desde el kiosko)
-- DROP POLICY IF EXISTS "asistencias_insert" ON storage.objects;
-- CREATE POLICY "asistencias_insert"
--   ON storage.objects FOR INSERT TO anon
--   WITH CHECK (bucket_id = 'asistencias-fotos');

-- SELECT (solo autenticados pueden ver las fotos)
-- DROP POLICY IF EXISTS "asistencias_select" ON storage.objects;
-- CREATE POLICY "asistencias_select"
--   ON storage.objects FOR SELECT TO authenticated
--   USING (bucket_id = 'asistencias-fotos');

-- ── 4. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'asistencias'
ORDER BY cmd;
*/
