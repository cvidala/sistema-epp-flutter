-- ============================================================
-- TrazApp — Módulo Mantenimiento de Trabajadores
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. COLUMNAS BÁSICAS (Mantenimiento v1) ──────────────────
ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS datos_completos BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS foto_rostro_url TEXT;

-- ── 2. DATOS PERSONALES ─────────────────────────────────────
ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS apellido TEXT;              -- apellido(s) separado del nombre

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS fecha_nacimiento DATE;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS direccion TEXT;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS telefono TEXT;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS email TEXT;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS nacionalidad TEXT DEFAULT 'Chilena';

-- ── 3. DATOS LABORALES ───────────────────────────────────────
ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS cargo TEXT;                        -- cargo base (independiente de la obra)

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS fecha_ingreso DATE;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS tipo_contrato TEXT;                -- Indefinido | Plazo Fijo | Obra o Faena | Honorarios

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS afp TEXT;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS sistema_salud TEXT;                -- Fonasa | Isapre + nombre

-- ── 4. CONTACTO DE EMERGENCIA ────────────────────────────────
ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS emergencia_nombre TEXT;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS emergencia_telefono TEXT;

-- ── 5. STORAGE BUCKET: fotos-rostro ─────────────────────────
-- Crear en Supabase Dashboard: Storage → New bucket
-- Nombre: fotos-rostro  |  Tipo: PUBLIC
--
-- Políticas Storage → Policies → FOTOS-ROSTRO → New policy:
--   INSERT: authenticated  |  WITH CHECK: bucket_id = 'fotos-rostro'
--   UPDATE: authenticated  |  USING:      bucket_id = 'fotos-rostro'

-- ── 6. RLS: permitir DELETE de trabajadores ──────────────────
DROP POLICY IF EXISTS "delete_auth_trabajadores" ON trabajadores;
CREATE POLICY "delete_auth_trabajadores"
  ON trabajadores FOR DELETE TO authenticated
  USING (true);

-- ── 7. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'trabajadores'
ORDER BY ordinal_position;
*/
