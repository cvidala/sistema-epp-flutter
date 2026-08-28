-- ============================================================
-- Fix definitivo del snapshot de evaluación en entregas offline.
--
-- Descubrimiento: entregas_epp tiene un trigger de inmutabilidad/auditoría que
-- hace FALLAR cualquier UPDATE (error "record old has no field hash"). Por eso
-- el enfoque anterior (insertar y luego UPDATE evaluacion) nunca funcionó — el
-- bloque best-effort tragaba el error del trigger y el snapshot quedaba NULL.
-- El flujo online no lo sufre porque inserta la evaluacion en el mismo INSERT.
--
-- Solución: replicar el patrón del online — calcular evaluar_entrega_v2 ANTES
-- del INSERT (pasando los items realmente entregados, para que refleje el
-- estado POST-entrega, idéntico al online) e incluir el resultado en el propio
-- INSERT. Cero UPDATE sobre entregas_epp.
--
-- Notación con nombres (firma real: p_items, p_obra_id, p_trabajador_id).
-- Best-effort: si evaluar_entrega_v2 fallara, evaluacion queda NULL y la
-- entrega igual se registra.
-- ============================================================
CREATE OR REPLACE FUNCTION public.insert_entrega_offline_v1(
  p_device_id          TEXT,
  p_local_event_id     TEXT,
  p_scope              TEXT,
  p_obra_id            UUID,
  p_trabajador_id      UUID,
  p_bodega_id          UUID,
  p_items              JSONB,
  p_evidencia_path     TEXT,
  p_evidencia_hash     TEXT,
  p_prev_hash          TEXT        DEFAULT NULL,
  p_hash               TEXT        DEFAULT NULL,
  p_created_at_client  TEXT        DEFAULT NULL,
  p_firma_path         TEXT        DEFAULT NULL,
  p_firma_hash         TEXT        DEFAULT NULL,
  p_forensics          JSONB       DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id      TEXT;
  v_user_id       UUID;
  v_local_uuid    UUID;
  v_item          JSONB;
  v_eval          JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  v_event_id := 'EPP-SYNC-' || p_local_event_id;
  IF EXISTS (SELECT 1 FROM entregas_epp WHERE event_id = v_event_id) THEN
    RETURN jsonb_build_object('ok', true, 'dedup', true, 'event_id', v_event_id);
  END IF;
  BEGIN
    v_local_uuid := p_local_event_id::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    v_local_uuid := NULL;
  END;

  -- Snapshot de cumplimiento calculado ANTES del INSERT (best-effort). Se pasan
  -- los items entregados para que el resultado refleje el estado POST-entrega,
  -- igual que insert_entrega_online_v1. Si falla, queda NULL sin abortar.
  BEGIN
    v_eval := public.evaluar_entrega_v2(
                p_obra_id       => p_obra_id,
                p_trabajador_id => p_trabajador_id,
                p_items         => p_items);
  EXCEPTION WHEN OTHERS THEN
    v_eval := NULL;
  END;

  INSERT INTO entregas_epp (
    event_id, trabajador_id, obra_id, bodega_id, items,
    entregado_por, sync_status, evidencia_foto_url, evidencia_hash,
    firma_url, firma_hash, forensics, validacion_tipo, device_id,
    local_event_id, prev_hash, hash_chain_scope, hash_integridad, created_at_client,
    evaluacion
  ) VALUES (
    v_event_id, p_trabajador_id, p_obra_id, p_bodega_id, p_items,
    v_user_id, 'ENVIADO', p_evidencia_path, p_evidencia_hash,
    p_firma_path, p_firma_hash, p_forensics, 'OFFLINE_SYNC', p_device_id,
    v_local_uuid, p_prev_hash, p_scope, p_hash,
    CASE WHEN p_created_at_client IS NOT NULL
         THEN p_created_at_client::TIMESTAMPTZ ELSE NULL END,
    v_eval
  );
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO stock_movimientos (
      bodega_id, epp_id, tipo, cantidad, referencia_event_id, motivo, created_by
    ) VALUES (
      p_bodega_id, (v_item->>'epp_id')::UUID, 'SALIDA',
      (v_item->>'cantidad')::INTEGER, v_event_id,
      'Entrega EPP (sync offline)', v_user_id
    );
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$$;
