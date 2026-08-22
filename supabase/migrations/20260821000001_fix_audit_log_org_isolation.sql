-- ============================================================
-- Fix A09: Auditoría estructurada
-- 1. Corregir política audit_select (filtra por org_id)
-- 2. Agregar triggers en tablas críticas faltantes
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. FIX POLÍTICA: audit_select usaba USING (true) → cross-org
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "audit_select" ON audit_log;

CREATE POLICY "audit_select" ON audit_log FOR SELECT TO authenticated
  USING (
    -- ADMIN ve logs de su org; otros roles también (solo su org)
    org_id = get_user_org_id()
    AND EXISTS (
      SELECT 1 FROM perfiles
      WHERE user_id = auth.uid()
        AND rol = 'ADMIN'
        AND activo = true
    )
  );

-- ─────────────────────────────────────────────────────────────
-- 2. TRIGGER: perfiles (cambios de rol, desactivaciones)
--    Evento más crítico: un ADMIN que sube a otro a ADMIN.
-- ─────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_perfiles ON perfiles;
CREATE TRIGGER trg_audit_perfiles
  AFTER UPDATE ON perfiles
  FOR EACH ROW
  WHEN (
    OLD.rol      IS DISTINCT FROM NEW.rol      OR
    OLD.activo   IS DISTINCT FROM NEW.activo
  )
  EXECUTE FUNCTION fn_audit_log();

-- ─────────────────────────────────────────────────────────────
-- 3. TRIGGER: obra_usuarios (asignación/remoción de supervisores)
-- ─────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_obra_usuarios ON obra_usuarios;
CREATE TRIGGER trg_audit_obra_usuarios
  AFTER INSERT OR DELETE ON obra_usuarios
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- ─────────────────────────────────────────────────────────────
-- 4. TRIGGER: catalogo_epp (cambios al catálogo de EPP)
-- ─────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_catalogo_epp ON catalogo_epp;
CREATE TRIGGER trg_audit_catalogo_epp
  AFTER INSERT OR UPDATE OR DELETE ON catalogo_epp
  FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

-- ─────────────────────────────────────────────────────────────
-- 5. FUNCIÓN RPC: registrar eventos de sesión desde el cliente
--    (login, logout, acceso denegado) — la app llama esta RPC
--    porque Supabase Auth no expone sus logs al cliente.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_session_event(
  p_evento  TEXT,   -- 'LOGIN' | 'LOGOUT' | 'ACCESS_DENIED'
  p_detalle JSONB   -- contexto adicional (página, recurso, etc.)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre TEXT;
  v_org_id UUID;
BEGIN
  SELECT nombre, org_id
    INTO v_nombre, v_org_id
    FROM perfiles
   WHERE user_id = auth.uid() AND activo = true
   LIMIT 1;

  INSERT INTO audit_log (
    tabla, operacion, registro_id,
    usuario_id, usuario_nombre, org_id,
    datos_nuevos
  ) VALUES (
    'session',
    p_evento,
    auth.uid()::text,
    auth.uid(),
    v_nombre,
    v_org_id,
    p_detalle
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_session_event TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- VERIFICACIÓN
-- ─────────────────────────────────────────────────────────────
/*
-- Ver logs de sesión:
SELECT created_at, usuario_nombre, operacion, datos_nuevos
FROM audit_log WHERE tabla = 'session' ORDER BY created_at DESC LIMIT 20;

-- Ver cambios de rol:
SELECT created_at, usuario_nombre,
       datos_anteriores->>'rol' AS rol_antes,
       datos_nuevos->>'rol'     AS rol_despues
FROM audit_log WHERE tabla = 'perfiles' ORDER BY created_at DESC;
*/
