-- ============================================================
-- TrazApp — Notificaciones de vencimiento EPP
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. COLUMNAS EN catalogo_epp ──────────────────────────
-- Días de anticipación para notificar por tipo de EPP.
-- Configurable porque hay materiales más críticos que otros.
ALTER TABLE catalogo_epp
  ADD COLUMN IF NOT EXISTS notif_dias_1 INTEGER DEFAULT 30,  -- primera alerta (ej: 30 días antes)
  ADD COLUMN IF NOT EXISTS notif_dias_2 INTEGER DEFAULT 7;   -- segunda alerta (ej: 7 días antes)

-- ── 2. COLUMNAS EN perfiles ───────────────────────────────
-- Preferencias de notificación por usuario.
ALTER TABLE perfiles
  ADD COLUMN IF NOT EXISTS email_notif      TEXT,             -- email para notifs (puede ser distinto al de login)
  ADD COLUMN IF NOT EXISTS recibe_notif_venc BOOLEAN DEFAULT false;

-- ── 3. RPC: get_vencimientos_proximos ────────────────────
-- Retorna los EPP que vencen exactamente en notif_dias_1 o notif_dias_2 días.
-- La edge function llama esta RPC con la service role key (bypass RLS).
CREATE OR REPLACE FUNCTION public.get_vencimientos_proximos()
RETURNS TABLE (
  org_id           UUID,
  trabajador_nombre TEXT,
  trabajador_rut    TEXT,
  obra_nombre       TEXT,
  epp_nombre        TEXT,
  epp_codigo        TEXT,
  dias_restantes    INTEGER,
  fecha_vencimiento DATE,
  nivel_alerta      TEXT    -- 'CRITICO' (alerta 2) | 'AVISO' (alerta 1)
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH raw_items AS (
    -- Desanidar el JSONB de items de cada entrega
    SELECT
      e.event_id,
      e.trabajador_id,
      e.obra_id,
      e.entregado_por,
      e.created_at,
      (item->>'epp_id')::uuid AS epp_id
    FROM entregas_epp e,
         jsonb_array_elements(e.items) AS item
    WHERE e.items IS NOT NULL
  ),
  ultima_entrega AS (
    -- Para cada trabajador+EPP, solo la entrega más reciente
    SELECT DISTINCT ON (trabajador_id, epp_id)
      event_id, trabajador_id, obra_id, entregado_por, created_at, epp_id
    FROM raw_items
    ORDER BY trabajador_id, epp_id, created_at DESC
  ),
  vencimientos AS (
    SELECT
      p.org_id,
      t.nombre                                                    AS trabajador_nombre,
      t.rut                                                       AS trabajador_rut,
      o.nombre                                                    AS obra_nombre,
      c.nombre                                                    AS epp_nombre,
      c.codigo                                                    AS epp_codigo,
      c.notif_dias_1,
      c.notif_dias_2,
      (ue.created_at::date + (c.vida_util_dias || ' days')::interval)::date AS fecha_vencimiento,
      ((ue.created_at::date + (c.vida_util_dias || ' days')::interval)::date
        - current_date)::integer                                  AS dias_restantes
    FROM ultima_entrega ue
    JOIN catalogo_epp  c ON c.epp_id        = ue.epp_id
    JOIN trabajadores  t ON t.trabajador_id = ue.trabajador_id
    JOIN obras         o ON o.obra_id       = ue.obra_id
    JOIN perfiles      p ON p.user_id       = ue.entregado_por
    WHERE c.vida_util_dias IS NOT NULL
      AND c.notif_dias_1   IS NOT NULL
  )
  SELECT
    org_id,
    trabajador_nombre,
    trabajador_rut,
    obra_nombre,
    epp_nombre,
    epp_codigo,
    dias_restantes,
    fecha_vencimiento,
    CASE
      WHEN dias_restantes = notif_dias_2 THEN 'CRITICO'
      WHEN dias_restantes = notif_dias_1 THEN 'AVISO'
    END AS nivel_alerta
  FROM vencimientos
  WHERE dias_restantes = notif_dias_1
     OR dias_restantes = notif_dias_2
  ORDER BY org_id, dias_restantes;
$$;

GRANT EXECUTE ON FUNCTION public.get_vencimientos_proximos() TO service_role;

-- ── 4. CRON: llamar la edge function diariamente a las 8:00 AM UTC
-- Requiere tener habilitadas las extensiones pg_cron y pg_net.
-- Reemplaza [PROJECT_ID] con tu Project ID de Supabase (Settings → General)
-- y [SERVICE_ROLE_KEY] con tu service role key (Settings → API).
/*
SELECT cron.schedule(
  'notif-vencimiento-diario',
  '0 8 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://[PROJECT_ID].supabase.co/functions/v1/notif-vencimiento',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer [SERVICE_ROLE_KEY]"}'::jsonb,
      body    := '{}'::jsonb
    );
  $$
);

-- Para verificar que quedó agendado:
SELECT jobid, jobname, schedule, active FROM cron.job;

-- Para eliminar si necesitas recrearlo:
SELECT cron.unschedule('notif-vencimiento-diario');
*/

-- ── 5. VERIFICACIÓN ─────────────────────────────────────
/*
-- Ver próximos vencimientos manualmente:
SELECT * FROM get_vencimientos_proximos();

-- Ver quién recibe notificaciones:
SELECT nombre, rol, email_notif, recibe_notif_venc
FROM perfiles
WHERE recibe_notif_venc = true;

-- Ver configuración de notificaciones por EPP:
SELECT nombre, codigo, vida_util_dias, notif_dias_1, notif_dias_2
FROM catalogo_epp
ORDER BY nombre;
*/
