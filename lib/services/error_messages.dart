/// Traduce excepciones/errores a mensajes amigables para el usuario final.
///
/// Nunca se debe mostrar el `toString()` de una excepción ni un mensaje
/// técnico en la UI. Usar `friendlyError(e)` en los `catch` que alimentan
/// un texto visible.
String friendlyError(Object? e) {
  final raw = (e == null ? '' : e.toString()).toLowerCase();

  bool has(List<String> keys) => keys.any(raw.contains);

  // Errores de red / conectividad (lo más común en terreno).
  if (has([
    'socketexception',
    'clientexception',
    'connection reset',
    'connection closed',
    'connection refused',
    'connection terminated',
    'failed host lookup',
    'network is unreachable',
    'timeout',
    'timeoutexception',
    'authretryablefetch',
    'handshake',
    'xmlhttprequest',
  ])) {
    return 'Error de red. Revisa tu conexión e inténtalo nuevamente.';
  }

  // Credenciales inválidas.
  if (has(['invalid login credentials', 'invalid_credentials', 'invalid grant'])) {
    return 'Correo o contraseña incorrectos.';
  }

  // Correo no confirmado.
  if (has(['email not confirmed'])) {
    return 'Debes confirmar tu correo antes de ingresar.';
  }

  // Permisos / RLS / sesión.
  if (has([
    'row-level security',
    'permission denied',
    '42501',
    'not authorized',
    'jwt',
  ])) {
    return 'No tienes permiso para realizar esta acción.';
  }

  // Genérico: nunca exponer el detalle técnico.
  return 'Ocurrió un error. Inténtalo nuevamente.';
}
