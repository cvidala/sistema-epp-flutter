-- Fix: asistencias_errores INSERT desde kiosko anon
--
-- Bug: la política INSERT usaba auth.uid() pero el kiosko opera con clave anon
-- (uid = NULL), haciendo que todos los inserts de errores fallaran silenciosamente.
-- Solución: RPC SECURITY DEFINER accesible por anon, sin política INSERT directa.

-- ── 1. Eliminar política INSERT directa (rota para anon) ─────────────────────
DROP POLICY IF EXISTS "org_errors_insert" ON asistencias_errores;

-- ── 2. RPC para registro de errores desde kiosko ─────────────────────────────
CREATE OR REPLACE FUNCTION public.registrar_error_marcacion(
  p_org_id       UUID,
  p_rut          TEXT,
  p_codigo       TEXT,
  p_mensaje      TEXT,
  p_gps_lat      DOUBLE PRECISION DEFAULT NULL,
  p_gps_lng      DOUBLE PRECISION DEFAULT NULL,
  p_device_model TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO asistencias_errores (
    org_id, rut, codigo_error, mensaje_error,
    gps_lat, gps_lng, device_model, occurred_at
  ) VALUES (
    p_org_id, p_rut, p_codigo, p_mensaje,
    p_gps_lat, p_gps_lng, p_device_model, now()
  );
END;
$$;

-- Accesible por anon (kiosko) y authenticated (dashboard)
GRANT EXECUTE ON FUNCTION public.registrar_error_marcacion(
  UUID, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT
) TO anon, authenticated;
