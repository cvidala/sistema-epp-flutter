-- RPC para validar PIN desde el kiosko de asistencia (sin sesión de usuario).
-- El kiosko usa la clave anon — esta función verifica el PIN bcrypt de la
-- organización sin exponer el hash al cliente.
--
-- Seguridad: SECURITY DEFINER con search_path restringido.
-- No retorna el hash en ningún caso.

CREATE OR REPLACE FUNCTION public.validar_pin_kiosko(
  p_org_id UUID,
  p_pin    TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_hash TEXT;
BEGIN
  SELECT pin_validacion_hash INTO v_hash
  FROM organizaciones
  WHERE org_id = p_org_id;

  IF v_hash IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN crypt(p_pin, v_hash) = v_hash;
END;
$$;

-- Accesible por el rol anon (kiosko usa clave anon)
GRANT EXECUTE ON FUNCTION public.validar_pin_kiosko(UUID, TEXT) TO anon, authenticated;
