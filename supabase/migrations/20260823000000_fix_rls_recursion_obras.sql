-- ============================================================
-- Fix RLS: recursión infinita en la política de `obras` (42P17)
--
-- Síntoma: cualquier consulta authenticated a `obras` o
--   `trabajadores` devuelve
--   "infinite recursion detected in policy for relation obras".
--
-- Causa (introducida en 20260821000000):
--   - obras_select_org         consulta obra_usuarios (bajo RLS)
--   - obra_usuarios_select_org consulta obras          (bajo RLS)
--   → referencia mutua → Postgres entra en recursión al planificar.
--   Rompía la carga online de obras/trabajadores en la app
--   (mitigado solo por la caché offline).
--
-- Fix: cortar el ciclo con funciones SECURITY DEFINER que leen las
--   tablas SIN disparar RLS, y reescribir obras_select_org para
--   usarlas en vez de consultar obra_usuarios bajo RLS. Es el
--   patrón recomendado por Supabase para evitar recursión en RLS.
--
-- No cambia la semántica de acceso (ADMIN ve toda su org; el resto
-- solo sus obras asignadas). No toca el módulo EPP ni el aislamiento
-- por organización.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Helpers SECURITY DEFINER (bypasan RLS → cortan la recursión)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.user_is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM perfiles
    WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true
  );
$$;

CREATE OR REPLACE FUNCTION public.user_obra_ids()
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT obra_id FROM obra_usuarios WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.user_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_obra_ids() TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2. Reescribir obras_select_org SIN referenciar obra_usuarios bajo
--    RLS (usa las funciones definer). Esto rompe el ciclo:
--    obra_usuarios → obras → user_obra_ids() [definer, sin RLS] → fin.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "obras_select_org" ON obras;

CREATE POLICY "obras_select_org" ON obras FOR SELECT TO authenticated
  USING (
    org_id = get_user_org_id()
    AND (
      user_is_admin()
      OR obra_id IN (SELECT user_obra_ids())
    )
  );

-- ─────────────────────────────────────────────────────────────
-- VERIFICACIÓN (SQL Editor, como un usuario authenticated):
--   SELECT * FROM obras;          -- ya NO debe lanzar 42P17
--   SELECT * FROM trabajadores;   -- ya NO debe lanzar 42P17
-- ─────────────────────────────────────────────────────────────
