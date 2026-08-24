-- ============================================================
-- SUSPENSIÓN Portal de Fiscalización DT (REVERSIBLE)
--
-- Cierra el hallazgo de seguridad CRITICAL del advisor de Supabase:
--   "Security Definer View: public.v_asistencias_dt"
-- detectado en la auditoría manual de seguridad (RLS + manejo de
-- service_role key) del 2026-08-22.
--
-- ── Riesgo que cierra ──────────────────────────────────────
-- Las RPCs dt_consulta_asistencias / dt_contar_asistencias son
-- SECURITY DEFINER y estaban expuestas a cualquier usuario
-- autenticado, sin verificar que el llamador fuera un inspector DT.
-- Filtraban solo por el RUT de empresa recibido como parámetro, así
-- que un supervisor de la Empresa A podía consultar las asistencias
-- de la Empresa B pasando su RUT → fuga cross-org
-- (OWASP A01 — Broken Access Control).
--
-- ── Decisión ───────────────────────────────────────────────
-- El módulo de asistencia / portal DT NO está en el foco actual
-- (el producto se enfoca hoy solo en la entrega de EPP). Se DESACTIVA
-- sin borrar nada, para eliminar el riesgo hoy y reactivarlo bien
-- cuando se levante el portal.
--
-- Esta migración NO elimina la vista ni las funciones, y NO toca
-- ningún objeto (vistas, RLS, triggers) del módulo EPP.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Cortar el ÚNICO camino de acceso: revocar EXECUTE.
--    En Postgres las funciones conceden EXECUTE a PUBLIC por
--    defecto, así que revocamos de PUBLIC, anon y authenticated
--    para garantizar que ningún rol pueda invocarlas.
--    Las funciones siguen existiendo; quedan inaccesibles.
-- ─────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.dt_consulta_asistencias(TEXT, DATE, DATE, INT, INT)
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.dt_contar_asistencias(TEXT, DATE, DATE)
  FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2. Apagar el advisor CRITICAL: con security_invoker la vista deja
--    de ejecutarse con los privilegios del owner (definer) y pasa a
--    respetar el RLS del invocador. La vista NO se elimina.
-- ─────────────────────────────────────────────────────────────
ALTER VIEW public.v_asistencias_dt SET (security_invoker = true);

-- ============================================================
-- CÓMO REACTIVAR (cuando se levante de nuevo el portal DT)
--
-- NO basta con volver a hacer GRANT: eso reabre exactamente el
-- mismo agujero. Antes hay que agregar un guard de autorización
-- para que SOLO inspectores DT autorizados puedan consultar
-- cualquier empresa por RUT.
--
-- a) Allowlist de inspectores (cuentas Auth cross-org, sin org):
--
--    CREATE TABLE IF NOT EXISTS dt_inspectores (
--      user_id    UUID PRIMARY KEY REFERENCES auth.users(id),
--      nombre     TEXT,
--      activo     BOOLEAN NOT NULL DEFAULT true,
--      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
--    );
--    ALTER TABLE dt_inspectores ENABLE ROW LEVEL SECURITY;  -- sin políticas: nadie lo lee desde el cliente
--
-- b) Agregar al INICIO de AMBAS RPCs (CREATE OR REPLACE) el guard:
--
--    IF NOT EXISTS (
--      SELECT 1 FROM dt_inspectores
--      WHERE user_id = auth.uid() AND activo = true
--    ) THEN
--      RAISE EXCEPTION 'No autorizado: acceso exclusivo para inspectores DT';
--    END IF;
--
-- c) Recién entonces reconceder EXECUTE:
--
--    GRANT EXECUTE ON FUNCTION public.dt_consulta_asistencias(TEXT,DATE,DATE,INT,INT) TO authenticated;
--    GRANT EXECUTE ON FUNCTION public.dt_contar_asistencias(TEXT,DATE,DATE)          TO authenticated;
--
-- d) Dar de alta cada inspector con su UUID de auth.users:
--    INSERT INTO dt_inspectores (user_id, nombre) VALUES ('<uuid>', 'Nombre inspector');
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- VERIFICACIÓN (ejecutar en SQL Editor tras aplicar):
-- ─────────────────────────────────────────────────────────────
/*
-- La vista ya usa security_invoker (debe devolver 'true'):
SELECT c.relname, c.reloptions
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'v_asistencias_dt';

-- Nadie tiene EXECUTE sobre las RPCs (debe devolver 0 filas para anon/authenticated):
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_name IN ('dt_consulta_asistencias','dt_contar_asistencias')
  AND grantee IN ('anon','authenticated','PUBLIC');
*/
