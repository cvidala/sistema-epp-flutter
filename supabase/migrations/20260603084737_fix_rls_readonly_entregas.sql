-- ============================================================
-- Fix SF-01: READONLY puede insertar en entregas_epp
-- La política insert_own_entregas no tenía restricción de rol.
-- Solo ADMIN y SUPERVISOR deben poder registrar entregas.
-- ============================================================
DROP POLICY IF EXISTS "insert_own_entregas" ON entregas_epp;
CREATE POLICY "insert_own_entregas"
  ON entregas_epp FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND entregado_por = auth.uid()
    AND EXISTS (
      SELECT 1 FROM perfiles p
      WHERE p.user_id = auth.uid()
        AND p.rol IN ('ADMIN', 'SUPERVISOR')
    )
  );
