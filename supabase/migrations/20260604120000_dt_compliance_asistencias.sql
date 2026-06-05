-- Cumplimiento ORD. N°1140/27 Dirección del Trabajo
--
-- C-2: Datos del empleador en cada marcación (§3.3)
-- A-1: Registro de marcaciones fallidas con código de error (§1)
-- A-2: Nombre completo del trabajador en cada marcación (§1)

-- ── organizaciones: agregar datos del empleador ──────────────────────────────
ALTER TABLE organizaciones
  ADD COLUMN IF NOT EXISTS rut_empresa        TEXT,
  ADD COLUMN IF NOT EXISTS razon_social       TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_calle    TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_numero   TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_piso     TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_oficina  TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_comuna   TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_ciudad   TEXT,
  ADD COLUMN IF NOT EXISTS domicilio_region   TEXT;

-- ── asistencias: agregar campos requeridos por la DT ─────────────────────────
ALTER TABLE asistencias
  -- A-2: nombre completo del trabajador al momento de la marcación
  ADD COLUMN IF NOT EXISTS trabajador_nombre  TEXT,

  -- C-2: snapshot del empleador al momento de la marcación
  ADD COLUMN IF NOT EXISTS empleador_rut      TEXT,
  ADD COLUMN IF NOT EXISTS empleador_nombre   TEXT,
  ADD COLUMN IF NOT EXISTS empleador_domicilio TEXT,  -- formato legible: "Calle N° X, Comuna, Ciudad, Región"

  -- A-1: tipo de validación y datos de fallback
  ADD COLUMN IF NOT EXISTS validacion_tipo    TEXT DEFAULT 'BIOMETRICA',
  ADD COLUMN IF NOT EXISTS fallback_motivo    TEXT,   -- 'face_timeout' | 'face_rejected' | 'manual'
  ADD COLUMN IF NOT EXISTS evidencia_hash     TEXT;   -- SHA-256 foto (§1 checksum)

-- ── asistencias_errores: registro de marcaciones fallidas (§1) ───────────────
-- La ordenanza exige almacenar alertas de operaciones fallidas con
-- día, hora, lugar y código de error.
CREATE TABLE IF NOT EXISTS asistencias_errores (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID        REFERENCES organizaciones(org_id),
  rut             TEXT,
  codigo_error    TEXT        NOT NULL,   -- 'FACE_NO_DETECTED' | 'FACE_TIMEOUT' | 'GPS_FAILED' | 'NETWORK_ERROR' | etc.
  mensaje_error   TEXT,
  gps_lat         DOUBLE PRECISION,
  gps_lng         DOUBLE PRECISION,
  device_model    TEXT,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  notificado      BOOLEAN     DEFAULT FALSE  -- si se envió comprobante de error al trabajador
);

ALTER TABLE asistencias_errores ENABLE ROW LEVEL SECURITY;

-- Solo autenticados de la misma org pueden ver sus errores
CREATE POLICY "org_errors_select" ON asistencias_errores
  FOR SELECT USING (
    org_id = (SELECT org_id FROM perfiles WHERE user_id = auth.uid())
  );

CREATE POLICY "org_errors_insert" ON asistencias_errores
  FOR INSERT WITH CHECK (
    org_id = (SELECT org_id FROM perfiles WHERE user_id = auth.uid())
  );

-- Índices para reportes de fiscalización
CREATE INDEX IF NOT EXISTS idx_asistencias_errores_org_fecha
  ON asistencias_errores(org_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_asistencias_trabajador_fecha
  ON asistencias(rut, captured_at DESC);
