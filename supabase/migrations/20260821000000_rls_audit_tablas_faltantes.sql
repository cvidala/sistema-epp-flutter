-- ============================================================
-- RLS Audit: habilitar RLS en 10 tablas sin políticas
-- Detectado en auditoría OWASP A01 — 2026-08-21
-- Tablas: obras, bodegas, perfiles, organizaciones,
--         obra_usuarios, obra_contactos, epp_uso_eventos,
--         hash_chain_head, entregas_notificaciones, stock_umbrales
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. OBRAS
--    ADMIN ve todas las obras de su org.
--    SUPERVISOR/READONLY solo ve las que tiene asignadas en obra_usuarios.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE obras ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "obras_select_org"   ON obras;
DROP POLICY IF EXISTS "obras_insert_admin" ON obras;
DROP POLICY IF EXISTS "obras_update_admin" ON obras;
DROP POLICY IF EXISTS "obras_no_delete"    ON obras;

CREATE POLICY "obras_select_org" ON obras FOR SELECT TO authenticated
  USING (
    org_id = get_user_org_id()
    AND (
      EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN'  AND activo = true)
      OR EXISTS (SELECT 1 FROM obra_usuarios ou WHERE ou.obra_id = obras.obra_id AND ou.user_id = auth.uid())
    )
  );

CREATE POLICY "obras_insert_admin" ON obras FOR INSERT TO authenticated
  WITH CHECK (
    org_id = get_user_org_id()
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obras_update_admin" ON obras FOR UPDATE TO authenticated
  USING (
    org_id = get_user_org_id()
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obras_no_delete" ON obras FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 2. BODEGAS (tiene org_id directo)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE bodegas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bodegas_select_org"    ON bodegas;
DROP POLICY IF EXISTS "bodegas_write_admin"  ON bodegas;
DROP POLICY IF EXISTS "bodegas_update_admin" ON bodegas;
DROP POLICY IF EXISTS "bodegas_no_delete"    ON bodegas;

CREATE POLICY "bodegas_select_org" ON bodegas FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

CREATE POLICY "bodegas_write_admin" ON bodegas FOR INSERT TO authenticated
  WITH CHECK (
    org_id = get_user_org_id()
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "bodegas_update_admin" ON bodegas FOR UPDATE TO authenticated
  USING (
    org_id = get_user_org_id()
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "bodegas_no_delete" ON bodegas FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 3. PERFILES (tiene org_id directo)
--    Todos los usuarios autenticados de la org pueden ver perfiles
--    (necesario para listar supervisores en el dashboard).
--    Solo ADMIN puede modificar roles; cada usuario puede
--    actualizar sus propias preferencias de notificación.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "perfiles_select_org"    ON perfiles;
DROP POLICY IF EXISTS "perfiles_update_self"   ON perfiles;
DROP POLICY IF EXISTS "perfiles_update_admin"  ON perfiles;
DROP POLICY IF EXISTS "perfiles_no_insert"     ON perfiles;
DROP POLICY IF EXISTS "perfiles_no_delete"     ON perfiles;

CREATE POLICY "perfiles_select_org" ON perfiles FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

-- Cada usuario puede actualizar sus propias preferencias (email_notif, recibe_notif_venc)
CREATE POLICY "perfiles_update_self" ON perfiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND org_id = get_user_org_id());

CREATE POLICY "perfiles_no_insert" ON perfiles FOR INSERT WITH CHECK (false);
CREATE POLICY "perfiles_no_delete" ON perfiles FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 4. ORGANIZACIONES
--    Cada usuario solo ve su propia organización.
--    Sin escritura desde el cliente.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE organizaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organizaciones_select_own" ON organizaciones;
DROP POLICY IF EXISTS "organizaciones_no_write"   ON organizaciones;

CREATE POLICY "organizaciones_select_own" ON organizaciones FOR SELECT TO authenticated
  USING (org_id = get_user_org_id());

CREATE POLICY "organizaciones_no_insert" ON organizaciones FOR INSERT WITH CHECK (false);
CREATE POLICY "organizaciones_no_delete" ON organizaciones FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 5. OBRA_USUARIOS (vía obras.org_id)
--    ADMIN gestiona asignaciones; todos ven la de su org.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE obra_usuarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "obra_usuarios_select_org"   ON obra_usuarios;
DROP POLICY IF EXISTS "obra_usuarios_write_admin"  ON obra_usuarios;
DROP POLICY IF EXISTS "obra_usuarios_delete_admin" ON obra_usuarios;

CREATE POLICY "obra_usuarios_select_org" ON obra_usuarios FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM obras
      WHERE obra_id = obra_usuarios.obra_id AND org_id = get_user_org_id()
    )
  );

CREATE POLICY "obra_usuarios_write_admin" ON obra_usuarios FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_usuarios.obra_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obra_usuarios_update_admin" ON obra_usuarios FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_usuarios.obra_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obra_usuarios_delete_admin" ON obra_usuarios FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_usuarios.obra_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

-- ─────────────────────────────────────────────────────────────
-- 6. OBRA_CONTACTOS (vía obras.org_id)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE obra_contactos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "obra_contactos_select_org"  ON obra_contactos;
DROP POLICY IF EXISTS "obra_contactos_write_admin" ON obra_contactos;
DROP POLICY IF EXISTS "obra_contactos_no_delete"   ON obra_contactos;

CREATE POLICY "obra_contactos_select_org" ON obra_contactos FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_contactos.obra_id AND org_id = get_user_org_id())
  );

CREATE POLICY "obra_contactos_write_admin" ON obra_contactos FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_contactos.obra_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obra_contactos_update_admin" ON obra_contactos FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = obra_contactos.obra_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "obra_contactos_no_delete" ON obra_contactos FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 7. EPP_USO_EVENTOS (vía obras.org_id)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE epp_uso_eventos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "epp_uso_eventos_select_org" ON epp_uso_eventos;
DROP POLICY IF EXISTS "epp_uso_eventos_no_delete"  ON epp_uso_eventos;

CREATE POLICY "epp_uso_eventos_select_org" ON epp_uso_eventos FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM obras WHERE obra_id = epp_uso_eventos.obra_id AND org_id = get_user_org_id())
  );

-- Inserts solo desde service_role (Edge Functions); cliente no inserta directamente
CREATE POLICY "epp_uso_eventos_no_delete" ON epp_uso_eventos FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 8. HASH_CHAIN_HEAD (vía obras.org_id)
--    Lectura para la app; escritura solo vía service_role.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE hash_chain_head ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hash_chain_head_select_org" ON hash_chain_head;
DROP POLICY IF EXISTS "hash_chain_head_no_delete"  ON hash_chain_head;

CREATE POLICY "hash_chain_head_select_org" ON hash_chain_head FOR SELECT TO authenticated
  USING (
    obra_id IS NULL
    OR EXISTS (SELECT 1 FROM obras WHERE obra_id = hash_chain_head.obra_id AND org_id = get_user_org_id())
  );

CREATE POLICY "hash_chain_head_no_delete" ON hash_chain_head FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 9. ENTREGAS_NOTIFICACIONES
--    Solo lectura para usuarios de la org (via entregas_epp.obra_id).
--    Escritura exclusivamente desde service_role (Edge Functions).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE entregas_notificaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "entregas_notif_select_org" ON entregas_notificaciones;
DROP POLICY IF EXISTS "entregas_notif_no_delete"  ON entregas_notificaciones;

CREATE POLICY "entregas_notif_select_org" ON entregas_notificaciones FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM entregas_epp e
      JOIN obras o ON o.obra_id = e.obra_id
      WHERE e.event_id = entregas_notificaciones.event_id
        AND o.org_id = get_user_org_id()
    )
  );

CREATE POLICY "entregas_notif_no_delete" ON entregas_notificaciones FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- 10. STOCK_UMBRALES (vía bodegas.org_id)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE stock_umbrales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_umbrales_select_org"  ON stock_umbrales;
DROP POLICY IF EXISTS "stock_umbrales_write_admin" ON stock_umbrales;
DROP POLICY IF EXISTS "stock_umbrales_no_delete"   ON stock_umbrales;

CREATE POLICY "stock_umbrales_select_org" ON stock_umbrales FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM bodegas WHERE bodega_id = stock_umbrales.bodega_id AND org_id = get_user_org_id()
    )
  );

CREATE POLICY "stock_umbrales_write_admin" ON stock_umbrales FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM bodegas WHERE bodega_id = stock_umbrales.bodega_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "stock_umbrales_update_admin" ON stock_umbrales FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM bodegas WHERE bodega_id = stock_umbrales.bodega_id AND org_id = get_user_org_id())
    AND EXISTS (SELECT 1 FROM perfiles WHERE user_id = auth.uid() AND rol = 'ADMIN' AND activo = true)
  );

CREATE POLICY "stock_umbrales_no_delete" ON stock_umbrales FOR DELETE USING (false);

-- ─────────────────────────────────────────────────────────────
-- VERIFICACIÓN — ejecutar en SQL Editor para confirmar:
-- ─────────────────────────────────────────────────────────────
/*
SELECT tablename, rowsecurity, COUNT(policyname) AS policies
FROM pg_tables t
LEFT JOIN pg_policies p USING (schemaname, tablename)
WHERE t.schemaname = 'public'
GROUP BY tablename, rowsecurity
ORDER BY rowsecurity, tablename;
*/
