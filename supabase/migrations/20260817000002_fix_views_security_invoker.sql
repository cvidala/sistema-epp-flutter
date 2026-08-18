-- Fix: views que bypassan RLS porque corren como el owner (postgres).
-- En PostgreSQL 15+, security_invoker=true hace que la view respete
-- el RLS del usuario llamante.

-- ── vw_cumplimiento_trabajador ────────────────────────────────
DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def
  FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_cumplimiento_trabajador';

  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_cumplimiento_trabajador CASCADE;
    EXECUTE format(
      'CREATE VIEW public.vw_cumplimiento_trabajador WITH (security_invoker = true) AS %s',
      v_def
    );
    GRANT SELECT ON public.vw_cumplimiento_trabajador TO authenticated;
  END IF;
END $$;

-- ── vw_stock_semaforo (si existe) ─────────────────────────────
DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def
  FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_stock_semaforo';

  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_stock_semaforo CASCADE;
    EXECUTE format(
      'CREATE VIEW public.vw_stock_semaforo WITH (security_invoker = true) AS %s',
      v_def
    );
    GRANT SELECT ON public.vw_stock_semaforo TO authenticated;
  END IF;
END $$;

-- ── vw_ultima_entrega_epp (si existe) ────────────────────────
DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def
  FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_ultima_entrega_epp';

  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_ultima_entrega_epp CASCADE;
    EXECUTE format(
      'CREATE VIEW public.vw_ultima_entrega_epp WITH (security_invoker = true) AS %s',
      v_def
    );
    GRANT SELECT ON public.vw_ultima_entrega_epp TO authenticated;
  END IF;
END $$;

-- ── vw_trabajadores_por_obra (si existe) ─────────────────────
DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def
  FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_trabajadores_por_obra';

  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_trabajadores_por_obra CASCADE;
    EXECUTE format(
      'CREATE VIEW public.vw_trabajadores_por_obra WITH (security_invoker = true) AS %s',
      v_def
    );
    GRANT SELECT ON public.vw_trabajadores_por_obra TO authenticated;
  END IF;
END $$;

-- ── vw_usos_desde_ultima_entrega (si existe) ─────────────────
DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def
  FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_usos_desde_ultima_entrega';

  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_usos_desde_ultima_entrega CASCADE;
    EXECUTE format(
      'CREATE VIEW public.vw_usos_desde_ultima_entrega WITH (security_invoker = true) AS %s',
      v_def
    );
    GRANT SELECT ON public.vw_usos_desde_ultima_entrega TO authenticated;
  END IF;
END $$;
