-- Fix 3 problemas detectados en CI:
--
-- 1. vw_cumplimiento_trabajador y vw_usos_desde_ultima_entrega eliminadas
--    accidentalmente con CASCADE. Las recrea con security_invoker=true.
--
-- 2. RLS-02: política trabajadores_select_org solo filtraba por org_id,
--    pero SUPERVISOR debe ver solo trabajadores de sus obras (obra_usuarios).
--    Se restaura la restricción por obra para roles no-ADMIN.

-- ── 1. vw_usos_desde_ultima_entrega ──────────────────────────
-- Acumula usos de EPP registrados DESPUÉS de la última entrega de ese item.
CREATE VIEW public.vw_usos_desde_ultima_entrega
  WITH (security_invoker = true) AS
SELECT
    u.trabajador_id,
    u.obra_id,
    u.epp_id,
    COALESCE(SUM(u.usos_registrados), 0) AS usos_acumulados
FROM public.epp_uso_eventos u
JOIN public.vw_ultima_entrega_epp ue
  ON  ue.trabajador_id = u.trabajador_id
  AND ue.obra_id       = u.obra_id
  AND ue.epp_id        = u.epp_id
WHERE u.fecha_uso > ue.fecha_ultima_entrega
GROUP BY u.trabajador_id, u.obra_id, u.epp_id;

GRANT SELECT ON public.vw_usos_desde_ultima_entrega TO authenticated;

-- ── 2. vw_cumplimiento_trabajador ────────────────────────────
-- Vista principal de cumplimiento: cruza reglas EPP de cada obra
-- con los trabajadores asignados y su última entrega de cada item.
CREATE VIEW public.vw_cumplimiento_trabajador
  WITH (security_invoker = true) AS
SELECT
    oer.obra_id,
    to2.trabajador_id,
    oer.epp_id,
    oer.obligatorio,
    oer.modo_control,
    oer.vence_por,
    oer.vida_util_dias,
    oer.vida_util_uso,
    oer.warning_dias_antes,
    oer.warning_uso_antes,
    ue.fecha_ultima_entrega,
    COALESCE(ud.usos_acumulados, 0) AS usos_acumulados,

    -- Estado del EPP para este trabajador
    CASE
        WHEN ue.fecha_ultima_entrega IS NULL
            THEN 'FALTA'
        WHEN oer.vence_por = 'FECHA'
             AND oer.vida_util_dias IS NOT NULL
             AND (ue.fecha_ultima_entrega + (oer.vida_util_dias || ' days')::interval) < now()
            THEN 'VENCIDO'
        WHEN oer.vence_por = 'FECHA'
             AND oer.vida_util_dias IS NOT NULL
             AND (ue.fecha_ultima_entrega + ((oer.vida_util_dias - oer.warning_dias_antes) || ' days')::interval) < now()
            THEN 'POR_VENCER'
        WHEN oer.vence_por = 'USO'
             AND oer.vida_util_uso IS NOT NULL
             AND COALESCE(ud.usos_acumulados, 0) >= oer.vida_util_uso
            THEN 'VENCIDO'
        WHEN oer.vence_por = 'USO'
             AND oer.vida_util_uso IS NOT NULL
             AND COALESCE(ud.usos_acumulados, 0) >= (oer.vida_util_uso - oer.warning_uso_antes)
            THEN 'POR_VENCER'
        ELSE 'OK'
    END AS estado,

    CASE
        WHEN oer.vence_por = 'FECHA' AND oer.vida_util_dias IS NOT NULL AND ue.fecha_ultima_entrega IS NOT NULL
            THEN (ue.fecha_ultima_entrega + (oer.vida_util_dias || ' days')::interval)::date
        ELSE NULL
    END AS vence_el,

    CASE
        WHEN oer.vence_por = 'FECHA' AND oer.vida_util_dias IS NOT NULL AND ue.fecha_ultima_entrega IS NOT NULL
            THEN (EXTRACT(EPOCH FROM
                    (ue.fecha_ultima_entrega + (oer.vida_util_dias || ' days')::interval) - now()
                 ) / 86400)::int
        ELSE NULL
    END AS dias_restantes,

    CASE
        WHEN oer.vence_por = 'USO' AND oer.vida_util_uso IS NOT NULL
            THEN GREATEST(0, oer.vida_util_uso - COALESCE(ud.usos_acumulados, 0))
        ELSE NULL
    END AS usos_restantes

FROM public.obra_epp_reglas oer
JOIN public.trabajador_obras to2
  ON  to2.obra_id = oer.obra_id
  AND to2.activo  = true
LEFT JOIN public.vw_ultima_entrega_epp ue
  ON  ue.trabajador_id = to2.trabajador_id
  AND ue.obra_id       = oer.obra_id
  AND ue.epp_id        = oer.epp_id
LEFT JOIN public.vw_usos_desde_ultima_entrega ud
  ON  ud.trabajador_id = to2.trabajador_id
  AND ud.obra_id       = oer.obra_id
  AND ud.epp_id        = oer.epp_id
WHERE oer.activo = true;

GRANT SELECT ON public.vw_cumplimiento_trabajador TO authenticated;

-- ── 3. Corregir RLS de trabajadores para SUPERVISOR ──────────
-- La política anterior (solo org_id) permite a SUPERVISOR ver
-- trabajadores de obras a las que no pertenece.
-- ADMIN ve todos de la org; SUPERVISOR/READONLY solo los de sus obras.
DROP POLICY IF EXISTS "trabajadores_select_org" ON trabajadores;
DROP POLICY IF EXISTS "trabajadores_write_org"  ON trabajadores;

CREATE POLICY "trabajadores_select_org"
  ON trabajadores FOR SELECT TO authenticated
  USING (
    org_id = get_user_org_id()
    AND (
      -- ADMIN ve todos los trabajadores de la org
      (SELECT rol FROM perfiles
       WHERE user_id = auth.uid() AND activo = true LIMIT 1) = 'ADMIN'
      OR
      -- SUPERVISOR y READONLY solo ven trabajadores de sus obras
      trabajador_id IN (
        SELECT to2.trabajador_id
        FROM trabajador_obras to2
        JOIN obra_usuarios ou ON ou.obra_id = to2.obra_id
        WHERE ou.user_id = auth.uid()
      )
    )
  );

CREATE POLICY "trabajadores_write_org"
  ON trabajadores FOR ALL TO authenticated
  USING (org_id = get_user_org_id())
  WITH CHECK (org_id = get_user_org_id());
