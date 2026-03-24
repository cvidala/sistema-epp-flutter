-- ============================================================
-- TrazApp — Validación manual de asistencia con PIN
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- ── 0. EXTENSIÓN PGCRYPTO (para bcrypt) ─────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── 1. COLUMNAS EN ASISTENCIAS ───────────────────────────────
ALTER TABLE asistencias
  ADD COLUMN IF NOT EXISTS validacion_manual  BOOLEAN,
  ADD COLUMN IF NOT EXISTS validado_por       TEXT,
  ADD COLUMN IF NOT EXISTS validado_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS validacion_motivo  TEXT;

-- ── 2. COLUMNA PIN EN ORGANIZACIONES ────────────────────────
ALTER TABLE organizaciones
  ADD COLUMN IF NOT EXISTS pin_validacion_hash TEXT;

-- ── 3. RPC: VALIDAR ASISTENCIA ───────────────────────────────
-- Verifica el PIN server-side y registra la validación con el
-- nombre del usuario autenticado (no viene del cliente).
CREATE OR REPLACE FUNCTION public.validar_asistencia_manual(
  p_asistencia_id UUID,
  p_pin           TEXT,
  p_motivo        TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash  TEXT;
  v_nombre TEXT;
BEGIN
  -- Nombre del usuario autenticado (no viene del cliente)
  SELECT nombre INTO v_nombre
  FROM usuarios
  WHERE user_id = auth.uid();

  IF v_nombre IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Usuario no identificado');
  END IF;

  -- Hash del PIN de la organización del usuario
  SELECT o.pin_validacion_hash INTO v_hash
  FROM organizaciones o
  JOIN usuarios u ON u.org_id = o.org_id
  WHERE u.user_id = auth.uid();

  IF v_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PIN de validación no configurado. Configúralo en Administración → Usuarios.');
  END IF;

  -- Verificación bcrypt
  IF crypt(p_pin, v_hash) != v_hash THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PIN incorrecto');
  END IF;

  -- Motivo requerido
  IF trim(p_motivo) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'El motivo es obligatorio');
  END IF;

  -- Actualizar registro
  UPDATE asistencias SET
    validacion_manual  = true,
    validado_por       = v_nombre,
    validado_at        = now(),
    validacion_motivo  = trim(p_motivo)
  WHERE id = p_asistencia_id;

  RETURN jsonb_build_object('ok', true, 'validado_por', v_nombre);
END;
$$;

GRANT EXECUTE ON FUNCTION public.validar_asistencia_manual(UUID, TEXT, TEXT) TO authenticated;

-- ── 4. RPC: CONFIGURAR PIN (solo ADMIN) ──────────────────────
CREATE OR REPLACE FUNCTION public.configurar_pin_validacion(
  p_pin_nuevo  TEXT,
  p_pin_actual TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol        TEXT;
  v_hash_actual TEXT;
  v_org_id     UUID;
BEGIN
  -- Solo administradores
  SELECT rol, org_id INTO v_rol, v_org_id
  FROM usuarios WHERE user_id = auth.uid();

  IF v_rol != 'ADMIN' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Solo los administradores pueden configurar el PIN');
  END IF;

  -- Validar formato: 4–8 dígitos
  IF p_pin_nuevo !~ '^\d{4,8}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'El PIN debe tener entre 4 y 8 dígitos numéricos');
  END IF;

  -- Si ya existe PIN, verificar el actual antes de cambiar
  SELECT pin_validacion_hash INTO v_hash_actual
  FROM organizaciones WHERE org_id = v_org_id;

  IF v_hash_actual IS NOT NULL THEN
    IF p_pin_actual IS NULL OR crypt(p_pin_actual, v_hash_actual) != v_hash_actual THEN
      RETURN jsonb_build_object('ok', false, 'error', 'PIN actual incorrecto');
    END IF;
  END IF;

  -- Guardar nuevo PIN hasheado con bcrypt (factor 10)
  UPDATE organizaciones
  SET pin_validacion_hash = crypt(p_pin_nuevo, gen_salt('bf', 10))
  WHERE org_id = v_org_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.configurar_pin_validacion(TEXT, TEXT) TO authenticated;

-- ── 5. VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT column_name FROM information_schema.columns
WHERE table_name = 'asistencias'
  AND column_name LIKE 'valid%';

SELECT pin_validacion_hash IS NOT NULL AS pin_configurado FROM organizaciones;
*/
