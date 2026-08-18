-- Aplica security_invoker a las views restantes sin DROP (evita perder dependencias).
-- En PostgreSQL 15+ ALTER VIEW SET soporta esta opción.

ALTER VIEW public.vw_ultima_entrega_epp      SET (security_invoker = true);
ALTER VIEW public.vw_entrega_items           SET (security_invoker = true);
ALTER VIEW public.vw_stock_semaforo          SET (security_invoker = true);
ALTER VIEW public.vw_trabajadores_por_obra   SET (security_invoker = true);

GRANT SELECT ON public.vw_ultima_entrega_epp    TO authenticated;
GRANT SELECT ON public.vw_entrega_items          TO authenticated;
GRANT SELECT ON public.vw_stock_semaforo         TO authenticated;
GRANT SELECT ON public.vw_trabajadores_por_obra  TO authenticated;
