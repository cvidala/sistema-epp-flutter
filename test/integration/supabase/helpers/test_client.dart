import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:epp_app/config/supabase_config.dart';

/// Prefijo centinela para todos los datos de test.
/// Filas con local_event_id que empieza con este valor se limpian en tearDown.
const String kTestPrefix = 'test_qa_';

/// Credenciales de los usuarios de test (leídas desde Platform.environment como fallback).
/// Las contraseñas son de bajo valor (entorno de pruebas, sin datos reales).
const _kTestCredentials = {
  'admin': (
    email: 'test_admin@trazapp.cl',
    password: 'TestAdmin2026!',
  ),
  'supervisor': (
    email: 'test_supervisor@trazapp.cl',
    password: 'TestSuper2026!',
  ),
  'readonly': (
    email: 'test_readonly@trazapp.cl',
    password: 'TestRead2026!',
  ),
};

/// Retorna un [SupabaseClient] autenticado para el rol indicado.
///
/// [role] debe ser 'admin', 'supervisor' o 'readonly'.
/// Crea una instancia separada (no el singleton) para evitar contaminación
/// de sesión entre tests.
Future<SupabaseClient> clientForRole(String role) async {
  final creds = _kTestCredentials[role];
  if (creds == null) {
    throw ArgumentError(
      'Rol desconocido: "$role". Usar uno de: admin, supervisor, readonly.',
    );
  }

  // Leer credenciales desde env si están disponibles (CI), sino usar defaults
  final email =
      Platform.environment['TEST_${role.toUpperCase()}_EMAIL'] ?? creds.email;
  final password =
      Platform.environment['TEST_${role.toUpperCase()}_PASSWORD'] ??
          creds.password;

  final client = SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
  );

  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

/// Retorna un [SupabaseClient] con service_role key (bypasa todo RLS).
///
/// La clave se carga EXCLUSIVAMENTE desde [Platform.environment].
/// Lanza [StateError] si la variable de entorno no está definida.
SupabaseClient serviceClient() {
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    throw StateError(
      'SUPABASE_SERVICE_ROLE_KEY no está definida en el entorno. '
      'Ejecutar: export \$(cat .env.test | xargs) antes de correr los tests.',
    );
  }
  return SupabaseClient(SupabaseConfig.url, serviceRoleKey);
}

/// Retorna un [SupabaseClient] anónimo (sin sign-in).
/// Simula el comportamiento del kiosko de asistencia.
SupabaseClient anonClient() {
  return SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
}

/// Cierra la sesión y libera recursos del cliente.
/// Llamar en tearDown de cada test group.
Future<void> disposeClient(SupabaseClient client) async {
  try {
    await client.auth.signOut();
  } catch (_) {
    // Ignorar errores al cerrar sesión (cliente puede ya estar cerrado)
  }
  client.dispose();
}
