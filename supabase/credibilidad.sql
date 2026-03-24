-- ============================================================
-- TrazApp — Módulo: Credibilidad facial (face-api.js en browser)
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. COLUMNAS EN ASISTENCIAS ───────────────────────────────
ALTER TABLE asistencias
  ADD COLUMN IF NOT EXISTS credibilidad_score   INTEGER,   -- 0–100
  ADD COLUMN IF NOT EXISTS credibilidad_status  TEXT;      -- 'alta'|'media'|'baja'|'sin_foto'|'sin_rostro'|'error'

-- ── 2. RLS: autenticados pueden actualizar credibilidad ──────
-- El dashboard (usuario autenticado) escribe los scores desde el browser.
DROP POLICY IF EXISTS "update_credibilidad_auth" ON asistencias;
CREATE POLICY "update_credibilidad_auth"
  ON asistencias FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (true);

-- ── 3. RPC: obtener foto de perfil por RUT (normalizado) ─────
CREATE OR REPLACE FUNCTION public.get_foto_perfil_por_rut(p_rut text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT foto_rostro_url FROM trabajadores
  WHERE upper(replace(replace(replace(rut,'.',''),'-',''),' ','')) =
        upper(replace(replace(replace(p_rut,'.',''),'-',''),' ',''))
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_foto_perfil_por_rut(text) TO authenticated;

-- ── 4. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'asistencias'
  AND column_name IN ('credibilidad_score','credibilidad_status');

SELECT policyname, cmd FROM pg_policies WHERE tablename = 'asistencias';
*/
