-- ============================================================
-- Fase 4 buckets privados: privar 'evidencias' y 'fotos-rostro'.
--
-- ⚠️ ORDEN DE APLICACIÓN: aplicar SOLO después de que el dashboard
--    con las lecturas por signed URL (Fase 1) esté desplegado en
--    gh-pages. Una versión vieja del dashboard/app que lea la URL
--    pública directa dejaría de cargar imágenes.
--
-- Como la app aún no se entrega, no hay instalaciones en terreno que
-- romper; el único consumidor vivo es el dashboard (web).
--
-- Reversible: UPDATE storage.buckets SET public = true WHERE ...
-- El bucket 'asistencias-fotos' ya era privado (no se toca).
-- ============================================================
UPDATE storage.buckets
   SET public = false
 WHERE id IN ('evidencias', 'fotos-rostro');

-- VERIFICACIÓN:
--   SELECT id, public FROM storage.buckets
--   WHERE id IN ('evidencias','fotos-rostro','asistencias-fotos');
--   → evidencias=false, fotos-rostro=false
