-- RPC atómica para entregas online: une entregas_epp + stock_movimientos
-- en una sola transacción. Elimina la ventana de inconsistencia donde
-- entregas_epp se insertaba pero stock_movimientos podía fallar.
--
-- Diferencias con insert_entrega_offline_v1:
--   - Recibe URLs directas (ya subidas) en lugar de paths
--   - Incluye evaluacion JSONB y declaracion_text
--   - No hace hash chaining (flujo online ya autenticado en tiempo real)

CREATE OR REPLACE FUNCTION public.insert_entrega_online_v1(
  p_event_id          TEXT,
  p_obra_id           UUID,
  p_trabajador_id     UUID,
  p_bodega_id         UUID,
  p_items             JSONB,
  p_entregado_por     UUID,
  p_evidencia_url     TEXT,
  p_evidencia_hash    TEXT,
  p_firma_url         TEXT,
  p_evaluacion        JSONB    DEFAULT NULL,
  p_declaracion_text  TEXT     DEFAULT NULL,
  p_forensics         JSONB    DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
BEGIN
  -- Dedup: si ya existe este event_id, retornar ok silencioso
  IF EXISTS (SELECT 1 FROM entregas_epp WHERE event_id = p_event_id) THEN
    RETURN jsonb_build_object('ok', true, 'dedup', true, 'event_id', p_event_id);
  END IF;

  -- INSERT principal
  INSERT INTO entregas_epp (
    event_id, trabajador_id, obra_id, bodega_id, items,
    entregado_por, sync_status, evidencia_foto_url, evidencia_hash,
    firma_url, evaluacion, declaracion_text, forensics, validacion_tipo
  ) VALUES (
    p_event_id, p_trabajador_id, p_obra_id, p_bodega_id, p_items,
    p_entregado_por, 'ENVIADO', p_evidencia_url, p_evidencia_hash,
    p_firma_url, p_evaluacion, p_declaracion_text, p_forensics, 'FIRMA_DIGITAL'
  );

  -- Stock movimientos por cada ítem (misma transacción)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO stock_movimientos (
      bodega_id, epp_id, tipo, cantidad, referencia_event_id, motivo, created_by
    ) VALUES (
      p_bodega_id,
      (v_item->>'epp_id')::UUID,
      'SALIDA',
      (v_item->>'cantidad')::INTEGER,
      p_event_id,
      'Entrega EPP',
      p_entregado_por
    );
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'event_id', p_event_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_entrega_online_v1(
  TEXT, UUID, UUID, UUID, JSONB, UUID, TEXT, TEXT, TEXT, JSONB, TEXT, JSONB
) TO authenticated;
