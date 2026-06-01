-- ============================================================
-- TrazApp — Prevención de stock negativo
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- Trigger que bloquea un movimiento de SALIDA si deja
-- el stock de esa bodega+EPP en negativo.
-- Actúa como guardia de último recurso en caso de
-- race condition o acceso directo a la API.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_prevent_stock_negativo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stock_actual INTEGER;
BEGIN
  -- Solo aplica a movimientos de SALIDA
  IF NEW.tipo <> 'SALIDA' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(SUM(
    CASE WHEN tipo = 'ENTRADA' THEN cantidad ELSE -cantidad END
  ), 0)
  INTO v_stock_actual
  FROM stock_movimientos
  WHERE bodega_id = NEW.bodega_id
    AND epp_id    = NEW.epp_id;

  IF (v_stock_actual - NEW.cantidad) < 0 THEN
    RAISE EXCEPTION
      'Stock insuficiente: bodega=% epp=% disponible=% solicitado=%',
      NEW.bodega_id, NEW.epp_id, v_stock_actual, NEW.cantidad;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_stock_negativo ON stock_movimientos;
CREATE TRIGGER trg_prevent_stock_negativo
  BEFORE INSERT ON stock_movimientos
  FOR EACH ROW
  EXECUTE FUNCTION fn_prevent_stock_negativo();

-- ── Verificación ─────────────────────────────────────────
/*
-- Ver stock actual por bodega y EPP:
SELECT
  b.nombre        AS bodega,
  c.nombre        AS epp,
  SUM(CASE WHEN sm.tipo = 'ENTRADA' THEN sm.cantidad ELSE -sm.cantidad END) AS stock
FROM stock_movimientos sm
JOIN bodegas      b ON b.bodega_id = sm.bodega_id
JOIN catalogo_epp c ON c.epp_id    = sm.epp_id
GROUP BY b.nombre, c.nombre
ORDER BY b.nombre, c.nombre;
*/
