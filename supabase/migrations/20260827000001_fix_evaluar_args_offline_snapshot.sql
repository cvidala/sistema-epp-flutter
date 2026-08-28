-- ============================================================
-- Fix del fix: la migración 20260827000000 llamaba a evaluar_entrega_v2 con
-- argumentos POSICIONALES asumiendo el orden (obra, trabajador, items). El
-- orden/nombres reales son (p_items, p_obra_id, p_trabajador_id), por lo que la
-- llamada fallaba por tipos y el bloque best-effort la tragaba en silencio →
-- el snapshot quedaba NULL y el backfill no hacía nada.
--
-- Esta migración vuelve a definir insert_entrega_offline_v1 y el backfill
-- usando NOTACIÓN CON NOMBRES (a prueba de orden). Idéntica en todo lo demás.
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
  INSERT INTO entregas_epp (
    event_id, trabajador_id, obra_id, bodega_id, items,
    entregado_por, sync_status, evidencia_foto_url, evidencia_hash,
    firma_url, firma_hash, forensics, validacion_tipo, device_id,
    local_event_id, prev_hash, hash_chain_scope, hash_integridad, created_at_client
  ) VALUES (
    v_event_id, p_trabajador_id, p_obra_id, p_bodega_id, p_items,
    v_user_id, 'ENVIADO', p_evidencia_path, p_evidencia_hash,
    p_firma_path, p_firma_hash, p_forensics, 'OFFLINE_SYNC', p_device_id,
    v_local_uuid, p_prev_hash, p_scope, p_hash,
    CASE WHEN p_created_at_client IS NOT NULL
         THEN p_created_at_client::TIMESTAMPTZ ELSE NULL END
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

  -- Snapshot de cumplimiento (best-effort). Notación con nombres: la firma real
  -- es evaluar_entrega_v2(p_items, p_obra_id, p_trabajador_id).
  BEGIN
    UPDATE entregas_epp
       SET evaluacion = public.evaluar_entrega_v2(
             p_obra_id       => p_obra_id,
             p_trabajador_id => p_trabajador_id,
             p_items         => '[]'::jsonb)
     WHERE event_id = v_event_id;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'event_id', v_event_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$$;

-- Backfill puntual (con notación con nombres): recalcula evaluacion solo para la
-- última entrega de cada (trabajador, obra) que hoy tenga evaluacion NULL.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (trabajador_id, obra_id) event_id, obra_id, trabajador_id
      FROM entregas_epp
     WHERE trabajador_id IS NOT NULL AND obra_id IS NOT NULL
     ORDER BY trabajador_id, obra_id, created_at DESC
  LOOP
    BEGIN
      UPDATE entregas_epp
         SET evaluacion = public.evaluar_entrega_v2(
               p_obra_id       => r.obra_id,
               p_trabajador_id => r.trabajador_id,
               p_items         => '[]'::jsonb)
       WHERE event_id = r.event_id AND evaluacion IS NULL;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;
