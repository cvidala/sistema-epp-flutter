-- ============================================================
-- TrazApp — Logs de Auditoría
-- Registra automáticamente quién hizo qué y cuándo en las
-- tablas críticas del sistema.
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 1. TABLA audit_log ────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tabla            TEXT        NOT NULL,
  operacion        TEXT        NOT NULL,   -- 'INSERT' | 'UPDATE' | 'DELETE'
  registro_id      TEXT,                   -- id del registro afectado
  usuario_id       UUID,                   -- auth.uid() (NULL si es anon/kiosko)
  usuario_nombre   TEXT,                   -- nombre desde perfiles
  org_id           UUID,                   -- para filtrar por empresa
  datos_anteriores JSONB,                  -- valores OLD (UPDATE / DELETE)
  datos_nuevos     JSONB,                  -- valores NEW (INSERT / UPDATE)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_tabla      ON audit_log(tabla);
CREATE INDEX IF NOT EXISTS idx_audit_registro   ON audit_log(registro_id);
CREATE INDEX IF NOT EXISTS idx_audit_usuario    ON audit_log(usuario_id);
CREATE INDEX IF NOT EXISTS idx_audit_org        ON audit_log(org_id);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_log(created_at DESC);

-- ── 2. RLS: solo lectura para autenticados, escritura solo vía trigger
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_select"    ON audit_log;
DROP POLICY IF EXISTS "audit_no_insert" ON audit_log;
DROP POLICY IF EXISTS "audit_no_update" ON audit_log;
DROP POLICY IF EXISTS "audit_no_delete" ON audit_log;

CREATE POLICY "audit_select"
  ON audit_log FOR SELECT TO authenticated
  USING (true);

-- Bloquear escritura directa desde clientes
CREATE POLICY "audit_no_insert" ON audit_log FOR INSERT     WITH CHECK (false);
CREATE POLICY "audit_no_update" ON audit_log FOR UPDATE     USING (false);
CREATE POLICY "audit_no_delete" ON audit_log FOR DELETE     USING (false);

-- ── 3. FUNCIÓN TRIGGER ───────────────────────────────────
-- SECURITY DEFINER para poder insertar en audit_log
-- aunque el RLS bloquee inserts directos.
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
  -- Campos que nunca deben quedar en el log (sensibles o muy grandes)
  v_excluir        TEXT[] := ARRAY[
    'pin_validacion_hash',
    'foto_path',
    'foto_bytes',
    'firma_svg'
  ];
BEGIN
  -- Usuario autenticado (NULL si viene del kiosko con clave anon)
  v_usuario_id := auth.uid();

  IF v_usuario_id IS NOT NULL THEN
    SELECT nombre, org_id
      INTO v_usuario_nombre, v_org_id
      FROM perfiles
     WHERE user_id = v_usuario_id;
  END IF;

  -- ID del registro afectado
  v_registro_id := CASE TG_OP
    WHEN 'DELETE' THEN (row_to_json(OLD) ->> 'id')
    ELSE                (row_to_json(NEW) ->> 'id')
  END;

  -- Construir JSONB sin campos sensibles
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_datos_ant := row_to_json(OLD)::jsonb - v_excluir;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_datos_nue := row_to_json(NEW)::jsonb - v_excluir;
  END IF;

  -- Filtro de ruido: en UPDATE ignorar si solo cambió sync_status
  -- (ocurre constantemente durante la sincronización offline→online)
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

-- ── 4. TRIGGERS EN TABLAS CLAVE ──────────────────────────

-- entregas_epp: INSERT (nueva entrega) + UPDATE (cambios de estado/sync)
DROP TRIGGER IF EXISTS trg_audit_entregas_epp ON entregas_epp;
CREATE TRIGGER trg_audit_entregas_epp
  AFTER INSERT OR UPDATE OR DELETE ON entregas_epp
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- trabajadores: altas, bajas (estado=INACTIVO), modificaciones
DROP TRIGGER IF EXISTS trg_audit_trabajadores ON trabajadores;
CREATE TRIGGER trg_audit_trabajadores
  AFTER INSERT OR UPDATE OR DELETE ON trabajadores
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- asistencias: solo UPDATE (validación manual, credibilidad)
-- INSERT masivo desde kiosko anon no se audita para evitar ruido
DROP TRIGGER IF EXISTS trg_audit_asistencias ON asistencias;
CREATE TRIGGER trg_audit_asistencias
  AFTER UPDATE ON asistencias
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- solicitudes_epp: apertura y cambios de estado
DROP TRIGGER IF EXISTS trg_audit_solicitudes_epp ON solicitudes_epp;
CREATE TRIGGER trg_audit_solicitudes_epp
  AFTER INSERT OR UPDATE ON solicitudes_epp
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- organizaciones: cambios de configuración (PIN, módulos, nombre)
DROP TRIGGER IF EXISTS trg_audit_organizaciones ON organizaciones;
CREATE TRIGGER trg_audit_organizaciones
  AFTER UPDATE ON organizaciones
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- obras: altas y modificaciones de centros de costo
DROP TRIGGER IF EXISTS trg_audit_obras ON obras;
CREATE TRIGGER trg_audit_obras
  AFTER INSERT OR UPDATE ON obras
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- stock_movimientos: cualquier movimiento de inventario
DROP TRIGGER IF EXISTS trg_audit_stock ON stock_movimientos;
CREATE TRIGGER trg_audit_stock
  AFTER INSERT ON stock_movimientos
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- ── 5. VERIFICACIÓN ─────────────────────────────────────
/*
-- Ver últimos 20 eventos de auditoría:
SELECT
  created_at,
  tabla,
  operacion,
  usuario_nombre,
  registro_id,
  datos_nuevos
FROM audit_log
ORDER BY created_at DESC
LIMIT 20;

-- Ver quién cambió el estado de una solicitud:
SELECT created_at, usuario_nombre, datos_anteriores->>'estado', datos_nuevos->>'estado'
FROM audit_log
WHERE tabla = 'solicitudes_epp' AND operacion = 'UPDATE'
ORDER BY created_at DESC;

-- Ver actividad de un usuario específico:
SELECT created_at, tabla, operacion, registro_id
FROM audit_log
WHERE usuario_nombre = 'Carlos Vidal'
ORDER BY created_at DESC;
*/
