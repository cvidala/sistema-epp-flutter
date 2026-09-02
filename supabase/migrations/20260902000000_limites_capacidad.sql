-- ============================================================
-- Capacidad / límites de plan (2º eje del plan, además de config_modulos).
--
-- MIRA envía por empresa un objeto `limites` (snapshot, igual patrón que
-- config_modulos) con topes de capacidad. TrazApp los guarda en
-- organizaciones.limites y BLOQUEA DE FORMA DURA la creación al llegar al tope.
--
-- Forma de organizaciones.limites (jsonb, nullable):
--   { "max_trabajadores": 100, "max_usuarios": 5, "max_obras": 6 }
--   - entero  = tope
--   - llave ausente o valor null, o limites null = SIN TOPE (fail-open)
--
-- Conteo de "activos" (lo que consume cupo):
--   - trabajadores: estado = 'ACTIVO'
--   - perfiles (usuarios): activo = true
--   - obras (centros): estado = 'ACTIVA'
--
-- Los topes son DATO por empresa (editables sin tocar código): MIRA los setea
-- por tramo y puede overridearlos por empresa re-aprovisionando; también se
-- pueden editar directo en organizaciones.limites.
-- ============================================================

-- 1) Columna de límites (nullable → orgs existentes quedan sin tope).
ALTER TABLE public.organizaciones
  ADD COLUMN IF NOT EXISTS limites jsonb;

-- 2) Helper: lee un tope entero desde organizaciones.limites (o NULL = sin tope).
CREATE OR REPLACE FUNCTION public.org_limite(p_org_id uuid, p_key text)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULLIF(limites->>p_key, '')::int
  FROM organizaciones
  WHERE org_id = p_org_id;
$$;

-- ─────────────────────────────────────────────────────────────
-- 3) Guard TRABAJADORES (estado = 'ACTIVO')
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_limite_trabajadores()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_limite int;
  v_count int;
BEGIN
  -- Solo consume cupo si el registro queda ACTIVO.
  IF NEW.estado IS DISTINCT FROM 'ACTIVO' THEN RETURN NEW; END IF;
  -- En UPDATE, si ya estaba ACTIVO, el cupo no cambia.
  IF TG_OP = 'UPDATE' AND OLD.estado = 'ACTIVO' THEN RETURN NEW; END IF;

  v_org := COALESCE(NEW.org_id, get_user_org_id());
  IF v_org IS NULL THEN RETURN NEW; END IF; -- sin org resoluble → no se puede enforcar

  v_limite := org_limite(v_org, 'max_trabajadores');
  IF v_limite IS NULL THEN RETURN NEW; END IF; -- sin tope (fail-open)

  SELECT count(*) INTO v_count
  FROM trabajadores
  WHERE org_id = v_org AND estado = 'ACTIVO'
    AND trabajador_id <> NEW.trabajador_id;

  IF v_count >= v_limite THEN
    RAISE EXCEPTION 'Alcanzaste el límite de trabajadores de tu plan (%). Contacta a tu proveedor para ampliarlo.', v_limite
      USING ERRCODE = 'check_violation', HINT = 'LIMITE_TRABAJADORES';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_limite_trabajadores ON public.trabajadores;
CREATE TRIGGER trg_enforce_limite_trabajadores
  BEFORE INSERT OR UPDATE ON public.trabajadores
  FOR EACH ROW EXECUTE FUNCTION public.enforce_limite_trabajadores();

-- ─────────────────────────────────────────────────────────────
-- 4) Guard USUARIOS / perfiles (activo = true)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_limite_usuarios()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_limite int;
  v_count int;
BEGIN
  IF NEW.activo IS DISTINCT FROM true THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.activo = true THEN RETURN NEW; END IF;

  v_org := COALESCE(NEW.org_id, get_user_org_id());
  IF v_org IS NULL THEN RETURN NEW; END IF;

  v_limite := org_limite(v_org, 'max_usuarios');
  IF v_limite IS NULL THEN RETURN NEW; END IF;

  SELECT count(*) INTO v_count
  FROM perfiles
  WHERE org_id = v_org AND activo = true
    AND user_id <> NEW.user_id;

  IF v_count >= v_limite THEN
    RAISE EXCEPTION 'Alcanzaste el límite de usuarios de tu plan (%). Contacta a tu proveedor para ampliarlo.', v_limite
      USING ERRCODE = 'check_violation', HINT = 'LIMITE_USUARIOS';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_limite_usuarios ON public.perfiles;
CREATE TRIGGER trg_enforce_limite_usuarios
  BEFORE INSERT OR UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_limite_usuarios();

-- ─────────────────────────────────────────────────────────────
-- 5) Guard OBRAS / centros (estado = 'ACTIVA')
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_limite_obras()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_limite int;
  v_count int;
BEGIN
  IF NEW.estado IS DISTINCT FROM 'ACTIVA' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.estado = 'ACTIVA' THEN RETURN NEW; END IF;

  v_org := COALESCE(NEW.org_id, get_user_org_id());
  IF v_org IS NULL THEN RETURN NEW; END IF;

  v_limite := org_limite(v_org, 'max_obras');
  IF v_limite IS NULL THEN RETURN NEW; END IF;

  SELECT count(*) INTO v_count
  FROM obras
  WHERE org_id = v_org AND estado = 'ACTIVA'
    AND obra_id <> NEW.obra_id;

  IF v_count >= v_limite THEN
    RAISE EXCEPTION 'Alcanzaste el límite de centros de trabajo de tu plan (%). Contacta a tu proveedor para ampliarlo.', v_limite
      USING ERRCODE = 'check_violation', HINT = 'LIMITE_OBRAS';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enforce_limite_obras ON public.obras;
CREATE TRIGGER trg_enforce_limite_obras
  BEFORE INSERT OR UPDATE ON public.obras
  FOR EACH ROW EXECUTE FUNCTION public.enforce_limite_obras();
