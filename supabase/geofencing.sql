-- ============================================================
-- TrazApp — Geofencing: ubicación por centro de costo
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- Coordenadas GPS del centro de costo y radio de validación
ALTER TABLE obras
  ADD COLUMN IF NOT EXISTS gps_lat    DOUBLE PRECISION;

ALTER TABLE obras
  ADD COLUMN IF NOT EXISTS gps_lng    DOUBLE PRECISION;

ALTER TABLE obras
  ADD COLUMN IF NOT EXISTS geo_radio_m INTEGER DEFAULT 300;  -- metros

-- ── VERIFICACIÓN ─────────────────────────────────────────
/*
SELECT obra_id, nombre, gps_lat, gps_lng, geo_radio_m
FROM obras ORDER BY nombre;
*/
