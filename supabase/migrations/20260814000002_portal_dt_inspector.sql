-- Portal de Fiscalización DT
-- Vista sanitizada + RPC paginada para inspectores de la Dirección del Trabajo.
-- No expone foto_path directamente; las URLs firmadas se generan en la Edge Function.

-- ── 1. Vista sanitizada v_asistencias_dt ─────────────────────────────────────
CREATE OR REPLACE VIEW v_asistencias_dt AS
SELECT
  a.id,
  a.org_id,
  o.razon_social          AS empresa_nombre,
  o.rut_empresa           AS empresa_rut,
  ob.nombre               AS obra_nombre,
  a.rut                   AS trabajador_rut,
  a.trabajador_nombre,
  a.tipo,
  a.validacion_tipo,
  a.fallback_motivo,
  a.captured_at,
  a.gps_lat,
  a.gps_lng,
  a.gps_accuracy_m,
  a.evidencia_hash,
  a.device_model,
  -- foto_path se usa en la Edge Function para generar URL firmada de 15 min
  a.foto_path             AS foto_path_storage
FROM asistencias a
LEFT JOIN organizaciones o ON o.org_id = a.org_id
LEFT JOIN obras ob         ON ob.id    = a.obra_id;

-- ── 2. RPC paginada para inspectores ─────────────────────────────────────────
-- Filtra por RUT de empresa + rango de fechas.
-- Máximo 500 registros por página para evitar dumps masivos.
CREATE OR REPLACE FUNCTION public.dt_consulta_asistencias(
  p_rut_empresa  TEXT,
  p_fecha_desde  DATE,
  p_fecha_hasta  DATE,
  p_pagina       INT DEFAULT 0,
  p_por_pagina   INT DEFAULT 100
) RETURNS SETOF v_asistencias_dt
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM v_asistencias_dt
  WHERE empresa_rut = p_rut_empresa
    AND captured_at::date BETWEEN p_fecha_desde AND p_fecha_hasta
  ORDER BY captured_at DESC
  LIMIT  LEAST(p_por_pagina, 500)
  OFFSET p_pagina * LEAST(p_por_pagina, 500);
$$;

-- Solo usuarios autenticados (inspectores con token JWT válido, no anon)
GRANT EXECUTE ON FUNCTION public.dt_consulta_asistencias(
  TEXT, DATE, DATE, INT, INT
) TO authenticated;

-- ── 3. RPC de conteo (para paginación en el portal) ──────────────────────────
CREATE OR REPLACE FUNCTION public.dt_contar_asistencias(
  p_rut_empresa TEXT,
  p_fecha_desde DATE,
  p_fecha_hasta DATE
) RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)
  FROM v_asistencias_dt
  WHERE empresa_rut = p_rut_empresa
    AND captured_at::date BETWEEN p_fecha_desde AND p_fecha_hasta;
$$;

GRANT EXECUTE ON FUNCTION public.dt_contar_asistencias(TEXT, DATE, DATE) TO authenticated;
