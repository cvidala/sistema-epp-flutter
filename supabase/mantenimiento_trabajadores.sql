-- ============================================================
-- TrazApp — Módulo Mantenimiento de Trabajadores
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. NUEVAS COLUMNAS EN trabajadores ──────────────────────
ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS datos_completos BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE trabajadores
  ADD COLUMN IF NOT EXISTS foto_rostro_url TEXT;

-- Marcar como incompletos los trabajadores que ya no tienen foto
-- (opcional — solo si quieres clasificar los existentes)
-- UPDATE trabajadores SET datos_completos = FALSE WHERE foto_rostro_url IS NULL;

-- ── 2. STORAGE BUCKET: fotos-rostro ─────────────────────────
-- Crear en Supabase Dashboard: Storage → New bucket
-- Nombre: fotos-rostro
-- Tipo: PUBLIC (para que la URL pública funcione en el dashboard)
--
-- Luego agregar estas políticas en Storage → Policies:

-- INSERT: solo autenticados pueden subir
-- CREATE POLICY "fotos_rostro_insert"
--   ON storage.objects FOR INSERT TO authenticated
--   WITH CHECK (bucket_id = 'fotos-rostro');

-- UPDATE (upsert): solo autenticados
-- CREATE POLICY "fotos_rostro_update"
--   ON storage.objects FOR UPDATE TO authenticated
--   USING (bucket_id = 'fotos-rostro');

-- SELECT: público (o solo autenticados si prefieres privado)
-- CREATE POLICY "fotos_rostro_select"
--   ON storage.objects FOR SELECT TO public
--   USING (bucket_id = 'fotos-rostro');

-- ── 3. RLS PARA DELETE EN trabajadores ──────────────────────
-- Permitir que admins puedan eliminar trabajadores desde el dashboard
DROP POLICY IF EXISTS "delete_auth_trabajadores" ON trabajadores;
CREATE POLICY "delete_auth_trabajadores"
  ON trabajadores FOR DELETE TO authenticated
  USING (true);

-- ── 4. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'trabajadores'
  AND column_name IN ('datos_completos', 'foto_rostro_url');
*/
