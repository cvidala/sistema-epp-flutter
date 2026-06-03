-- Trigger que calcula datos_completos automáticamente en INSERT/UPDATE.
-- Elimina la necesidad de setearlo manualmente desde el dashboard o la app móvil.
--
-- Campos requeridos (mínimo operacional para EPP):
--   nombre, apellido, rut → identidad
--   cargo, fecha_ingreso, tipo_contrato → datos laborales
--
-- La foto (foto_rostro_url) NO es requisito aquí — es requisito del kiosko de
-- asistencia y se muestra como indicador separado en el dashboard.

CREATE OR REPLACE FUNCTION public.fn_auto_datos_completos()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.datos_completos := (
    NEW.nombre          IS NOT NULL AND trim(NEW.nombre)          != '' AND
    NEW.apellido        IS NOT NULL AND trim(NEW.apellido)        != '' AND
    NEW.rut             IS NOT NULL AND trim(NEW.rut)             != '' AND
    NEW.cargo           IS NOT NULL AND trim(NEW.cargo)           != '' AND
    NEW.fecha_ingreso   IS NOT NULL AND
    NEW.tipo_contrato   IS NOT NULL AND trim(NEW.tipo_contrato)   != ''
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_datos_completos ON trabajadores;
CREATE TRIGGER trg_auto_datos_completos
  BEFORE INSERT OR UPDATE ON trabajadores
  FOR EACH ROW
  EXECUTE FUNCTION fn_auto_datos_completos();

-- Recalcular todos los registros existentes — el trigger BEFORE UPDATE recalcula datos_completos
UPDATE trabajadores SET datos_completos = datos_completos;
