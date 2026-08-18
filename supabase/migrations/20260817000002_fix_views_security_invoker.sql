-- Aplica security_invoker a las views via DROP+recreate (con CASCADE).
-- NOTA: Esta migración elimina vw_cumplimiento_trabajador y vw_usos_desde_ultima_entrega
-- que dependen de las views base. Ambas se restauran en 20260818000000.

DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_cumplimiento_trabajador';
  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_cumplimiento_trabajador CASCADE;
    EXECUTE format('CREATE VIEW public.vw_cumplimiento_trabajador WITH (security_invoker = true) AS %s', v_def);
    GRANT SELECT ON public.vw_cumplimiento_trabajador TO authenticated;
  END IF;
END $$;

DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_stock_semaforo';
  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_stock_semaforo CASCADE;
    EXECUTE format('CREATE VIEW public.vw_stock_semaforo WITH (security_invoker = true) AS %s', v_def);
    GRANT SELECT ON public.vw_stock_semaforo TO authenticated;
  END IF;
END $$;

DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_ultima_entrega_epp';
  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_ultima_entrega_epp CASCADE;
    EXECUTE format('CREATE VIEW public.vw_ultima_entrega_epp WITH (security_invoker = true) AS %s', v_def);
    GRANT SELECT ON public.vw_ultima_entrega_epp TO authenticated;
  END IF;
END $$;

DO $$
DECLARE v_def text;
BEGIN
  SELECT definition INTO v_def FROM pg_views
  WHERE schemaname = 'public' AND viewname = 'vw_trabajadores_por_obra';
  IF v_def IS NOT NULL THEN
    DROP VIEW IF EXISTS public.vw_trabajadores_por_obra CASCADE;
    EXECUTE format('CREATE VIEW public.vw_trabajadores_por_obra WITH (security_invoker = true) AS %s', v_def);
    GRANT SELECT ON public.vw_trabajadores_por_obra TO authenticated;
  END IF;
END $$;
