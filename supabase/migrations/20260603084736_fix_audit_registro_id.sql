-- ============================================================
-- Fix: fn_audit_log — REGISTRO ID siempre NULL
-- El trigger usaba row_to_json(NEW) ->> 'id' pero las tablas
-- críticas usan PKs con nombres distintos a 'id'.
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_audit_log()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_id     UUID;
  v_usuario_nombre TEXT;
  v_org_id         UUID;
  v_registro_id    TEXT;
  v_datos_ant      JSONB;
  v_datos_nue      JSONB;
  v_excluir        TEXT[] := ARRAY[
    'pin_validacion_hash',
    'foto_path',
    'foto_bytes',
    'firma_svg'
  ];
  v_row            JSONB;
BEGIN
  v_usuario_id := auth.uid();

  IF v_usuario_id IS NOT NULL THEN
    SELECT nombre, org_id
      INTO v_usuario_nombre, v_org_id
      FROM perfiles
     WHERE user_id = v_usuario_id;
  END IF;

  -- Resolver el ID del registro según la PK real de cada tabla
  v_row := CASE TG_OP WHEN 'DELETE' THEN row_to_json(OLD)::jsonb
                      ELSE              row_to_json(NEW)::jsonb END;

  v_registro_id := CASE TG_TABLE_NAME
    WHEN 'entregas_epp'       THEN v_row ->> 'event_id'
    WHEN 'trabajadores'       THEN v_row ->> 'trabajador_id'
    WHEN 'obras'              THEN v_row ->> 'obra_id'
    WHEN 'asistencias'        THEN v_row ->> 'id'
    WHEN 'solicitudes_epp'    THEN v_row ->> 'id'
    WHEN 'stock_movimientos'  THEN v_row ->> 'mov_id'
    WHEN 'organizaciones'     THEN v_row ->> 'org_id'
    ELSE                           v_row ->> 'id'   -- fallback genérico
  END;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_datos_ant := row_to_json(OLD)::jsonb - v_excluir;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_datos_nue := row_to_json(NEW)::jsonb - v_excluir;
  END IF;

  -- Filtro de ruido: UPDATE que solo cambia sync_status
  IF TG_OP = 'UPDATE' THEN
    IF (v_datos_ant - 'sync_status'::text) = (v_datos_nue - 'sync_status'::text) THEN
      RETURN NEW;
    END IF;
  END IF;

  INSERT INTO audit_log (
    tabla, operacion, registro_id,
    usuario_id, usuario_nombre, org_id,
    datos_anteriores, datos_nuevos
  ) VALUES (
    TG_TABLE_NAME, TG_OP, v_registro_id,
    v_usuario_id, v_usuario_nombre, v_org_id,
    v_datos_ant, v_datos_nue
  );

  RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
