-- ============================================================
-- TrazApp — Security Hardening SQL
-- Ejecutar en Supabase SQL Editor (como service_role / postgres)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. COLUMNAS NUEVAS en entregas_epp
--    (si no existen; safe a ejecutar varias veces)
-- ────────────────────────────────────────────────────────────
ALTER TABLE entregas_epp
  ADD COLUMN IF NOT EXISTS firma_hash    TEXT,
  ADD COLUMN IF NOT EXISTS forensics     JSONB,
  ADD COLUMN IF NOT EXISTS local_event_id TEXT;

-- Índice para búsqueda de duplicados en sync
CREATE UNIQUE INDEX IF NOT EXISTS idx_entregas_local_event_id
  ON entregas_epp (local_event_id)
  WHERE local_event_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- 2. TRIGGER DE INMUTABILIDAD en entregas_epp
--    Una vez insertado, los campos de integridad NO pueden
--    modificarse. Solo sync_status, evidencia_foto_url y
--    firma_url pueden actualizarse (ej: durante sync offline).
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION prevent_entrega_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Campos absolutamente inmutables
  IF OLD.event_id          IS DISTINCT FROM NEW.event_id          THEN
    RAISE EXCEPTION 'Campo inmutable: event_id';
  END IF;
  IF OLD.trabajador_id     IS DISTINCT FROM NEW.trabajador_id     THEN
    RAISE EXCEPTION 'Campo inmutable: trabajador_id';
  END IF;
  IF OLD.obra_id           IS DISTINCT FROM NEW.obra_id           THEN
    RAISE EXCEPTION 'Campo inmutable: obra_id';
  END IF;
  IF OLD.bodega_id         IS DISTINCT FROM NEW.bodega_id         THEN
    RAISE EXCEPTION 'Campo inmutable: bodega_id';
  END IF;
  IF OLD.items             IS DISTINCT FROM NEW.items             THEN
    RAISE EXCEPTION 'Campo inmutable: items';
  END IF;
  IF OLD.evidencia_hash    IS DISTINCT FROM NEW.evidencia_hash    THEN
    RAISE EXCEPTION 'Campo inmutable: evidencia_hash';
  END IF;
  IF OLD.firma_hash        IS DISTINCT FROM NEW.firma_hash        THEN
    RAISE EXCEPTION 'Campo inmutable: firma_hash';
  END IF;
  IF OLD.hash              IS DISTINCT FROM NEW.hash              THEN
    RAISE EXCEPTION 'Campo inmutable: hash';
  END IF;
  IF OLD.prev_hash         IS DISTINCT FROM NEW.prev_hash         THEN
    RAISE EXCEPTION 'Campo inmutable: prev_hash';
  END IF;
  IF OLD.created_at        IS DISTINCT FROM NEW.created_at        THEN
    RAISE EXCEPTION 'Campo inmutable: created_at';
  END IF;
  IF OLD.local_event_id    IS DISTINCT FROM NEW.local_event_id    THEN
    RAISE EXCEPTION 'Campo inmutable: local_event_id';
  END IF;
  IF OLD.entregado_por     IS DISTINCT FROM NEW.entregado_por     THEN
    RAISE EXCEPTION 'Campo inmutable: entregado_por';
  END IF;
  IF OLD.forensics         IS DISTINCT FROM NEW.forensics         THEN
    RAISE EXCEPTION 'Campo inmutable: forensics';
  END IF;

  -- Campos permitidos en UPDATE: sync_status, evidencia_foto_url, firma_url
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_entregas_epp_immutable ON entregas_epp;
CREATE TRIGGER trg_entregas_epp_immutable
  BEFORE UPDATE ON entregas_epp
  FOR EACH ROW
  EXECUTE FUNCTION prevent_entrega_mutation();

-- ────────────────────────────────────────────────────────────
-- 3. ROW LEVEL SECURITY — entregas_epp
-- ────────────────────────────────────────────────────────────
ALTER TABLE entregas_epp ENABLE ROW LEVEL SECURITY;

-- SELECT: solo usuarios con acceso a la obra
-- (usa la función can_access_obra que ya debería existir en el proyecto)
DROP POLICY IF EXISTS "select_own_entregas" ON entregas_epp;
CREATE POLICY "select_own_entregas"
  ON entregas_epp FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      -- Admin ve todo
      EXISTS (
        SELECT 1 FROM usuarios u
        WHERE u.user_id = auth.uid()
          AND u.rol = 'ADMIN'
      )
      OR
      -- Supervisor/usuario: solo obras a las que tiene acceso
      EXISTS (
        SELECT 1 FROM obra_usuarios ou
        WHERE ou.user_id  = auth.uid()
          AND ou.obra_id  = entregas_epp.obra_id
      )
      OR
      -- El propio entregador siempre ve sus registros
      entregado_por = auth.uid()
    )
  );

-- INSERT: solo si eres el entregador declarado
DROP POLICY IF EXISTS "insert_own_entregas" ON entregas_epp;
CREATE POLICY "insert_own_entregas"
  ON entregas_epp FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND entregado_por = auth.uid()
  );

-- UPDATE: muy restringido — solo sync_status / URLs de evidencia
-- Los campos de integridad están protegidos por el trigger
DROP POLICY IF EXISTS "update_sync_status" ON entregas_epp;
CREATE POLICY "update_sync_status"
  ON entregas_epp FOR UPDATE
  USING (
    auth.uid() IS NOT NULL
    AND (
      entregado_por = auth.uid()
      OR EXISTS (
        SELECT 1 FROM usuarios u
        WHERE u.user_id = auth.uid() AND u.rol = 'ADMIN'
      )
    )
  );

-- DELETE: NADIE puede eliminar
DROP POLICY IF EXISTS "no_delete_entregas" ON entregas_epp;
CREATE POLICY "no_delete_entregas"
  ON entregas_epp FOR DELETE
  USING (false);

-- ────────────────────────────────────────────────────────────
-- 4. ROW LEVEL SECURITY — stock_movimientos
-- ────────────────────────────────────────────────────────────
ALTER TABLE stock_movimientos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_stock_movimientos" ON stock_movimientos;
CREATE POLICY "select_stock_movimientos"
  ON stock_movimientos FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM bodegas b
      WHERE b.bodega_id = stock_movimientos.bodega_id
        AND (
          b.obra_id IS NULL  -- bodega global: todos ven
          OR EXISTS (
            SELECT 1 FROM obra_usuarios ou
            WHERE ou.user_id = auth.uid() AND ou.obra_id = b.obra_id
          )
          OR EXISTS (
            SELECT 1 FROM usuarios u
            WHERE u.user_id = auth.uid() AND u.rol = 'ADMIN'
          )
        )
    )
  );

-- Solo insertar como sí mismo
DROP POLICY IF EXISTS "insert_stock_movimientos" ON stock_movimientos;
CREATE POLICY "insert_stock_movimientos"
  ON stock_movimientos FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND created_by = auth.uid()
  );

-- Nadie puede eliminar movimientos de stock
DROP POLICY IF EXISTS "no_delete_stock_movimientos" ON stock_movimientos;
CREATE POLICY "no_delete_stock_movimientos"
  ON stock_movimientos FOR DELETE
  USING (false);

-- ────────────────────────────────────────────────────────────
-- 5. ROW LEVEL SECURITY — trabajadores
-- ────────────────────────────────────────────────────────────
ALTER TABLE trabajadores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_trabajadores" ON trabajadores;
CREATE POLICY "select_trabajadores"
  ON trabajadores FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM usuarios u WHERE u.user_id = auth.uid() AND u.rol = 'ADMIN')
      OR EXISTS (
        SELECT 1 FROM trabajador_obras tob
        JOIN obra_usuarios ou ON ou.obra_id = tob.obra_id
        WHERE tob.trabajador_id = trabajadores.trabajador_id
          AND ou.user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "insert_trabajadores" ON trabajadores;
CREATE POLICY "insert_trabajadores"
  ON trabajadores FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.user_id = auth.uid() AND u.rol IN ('ADMIN', 'SUPERVISOR')
    )
  );

-- No DELETE de trabajadores (desactivar con estado='INACTIVO')
DROP POLICY IF EXISTS "no_delete_trabajadores" ON trabajadores;
CREATE POLICY "no_delete_trabajadores"
  ON trabajadores FOR DELETE
  USING (false);

-- ────────────────────────────────────────────────────────────
-- 6. STORAGE — bucket evidencias
--    Prevenir sobreescritura de evidencias ya subidas
--    (complementa FileOptions(upsert: false) del cliente)
-- ────────────────────────────────────────────────────────────

-- Ver objetos propios del bucket
DROP POLICY IF EXISTS "evidencias_select" ON storage.objects;
CREATE POLICY "evidencias_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'evidencias'
    AND auth.uid() IS NOT NULL
  );

-- Solo subir, sin sobreescribir (el cliente ya usa upsert:false online)
DROP POLICY IF EXISTS "evidencias_insert" ON storage.objects;
CREATE POLICY "evidencias_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'evidencias'
    AND auth.uid() IS NOT NULL
  );

-- No eliminar evidencias desde el cliente
DROP POLICY IF EXISTS "evidencias_no_delete" ON storage.objects;
CREATE POLICY "evidencias_no_delete"
  ON storage.objects FOR DELETE
  USING (false);

-- ────────────────────────────────────────────────────────────
-- 7. VERIFICACIÓN — consulta de auditoría
--    Ejecutar para verificar que las políticas quedaron bien:
-- ────────────────────────────────────────────────────────────
/*
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('entregas_epp', 'stock_movimientos', 'trabajadores')
ORDER BY tablename, cmd;
*/

-- Ver trigger:
/*
SELECT trigger_name, event_manipulation, event_object_table
FROM information_schema.triggers
WHERE event_object_table = 'entregas_epp';
*/
