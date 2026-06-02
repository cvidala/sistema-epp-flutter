import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:epp_app/config/supabase_config.dart';
import 'package:epp_app/services/cache_service.dart';
import 'package:epp_app/services/device_id_service.dart';
import 'package:epp_app/services/offline_cache_service.dart';
import 'package:epp_app/services/offline_queue_service.dart';
import 'package:epp_app/asistencia/services/asistencia_hive_service.dart';

/// Prefijo centinela para todos los datos de test E2E.
/// Filas con local_event_id que empieza con este valor son identificables
/// en la DB como generadas por los E2E tests.
const String kE2ePrefix = 'test_e2e_';

/// Flag de inicialización para EPP services — evita doble-init en un mismo proceso.
bool _eppInitialized = false;

/// Flag de inicialización para Asistencia services.
bool _asistenciaInitialized = false;

/// Inicializa todos los servicios necesarios para los tests de la app EPP.
///
/// Guards:
/// - Static bool para evitar doble-init en el mismo proceso (ej. múltiples grupos de test)
/// - Hive.isBoxOpen() para evitar re-abrir cajas ya abiertas
/// - try/catch en Supabase.initialize() para absorber 'already initialized'
Future<void> initServicesEpp() async {
  if (_eppInitialized) {
    debugPrint('[E2ESetup] EPP services already initialized — skipping');
    return;
  }

  debugPrint('[E2ESetup] Initializing EPP services...');

  await Hive.initFlutter();

  // Guard: solo inicializar OfflineQueueService si la caja no está abierta
  if (!Hive.isBoxOpen('outbox_entregas')) {
    await OfflineQueueService.init();
  }

  await CacheService.init();
  await DeviceIdService.init();

  // Guard: OfflineCacheService puede lanzar si ya está inicializado
  try {
    await OfflineCacheService.init();
  } catch (_) {
    // ya inicializado — ignorar
  }

  // Guard: Supabase.initialize puede lanzar si ya fue llamado
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    // Already initialized in a previous test group — safe to continue
  }

  _eppInitialized = true;
  debugPrint('[E2ESetup] EPP services initialized');
}

/// Inicializa todos los servicios necesarios para los tests del kiosko de asistencia.
Future<void> initServicesAsistencia() async {
  if (_asistenciaInitialized) {
    debugPrint('[E2ESetup] Asistencia services already initialized — skipping');
    return;
  }

  debugPrint('[E2ESetup] Initializing Asistencia services...');

  await Hive.initFlutter();

  // Guard: solo inicializar AsistenciaHiveService si la caja no está abierta
  if (!Hive.isBoxOpen('asistencias_pendientes')) {
    await AsistenciaHiveService.init();
  }

  // Guard: Supabase.initialize puede lanzar si ya fue llamado
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    // Already initialized — safe to continue
  }

  _asistenciaInitialized = true;
  debugPrint('[E2ESetup] Asistencia services initialized');
}

/// Escribe un archivo de evidencia de prueba (100 bytes cero) en [path].
///
/// Usado por E2E-02 y E2E-03 para proveer un archivo real que
/// EvidenceService.readEvidenceOffline() pueda leer.
Future<void> writeFixtureEvidence(String path) async {
  final file = File(path);
  final dir = file.parent;
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  await file.writeAsBytes(List.filled(100, 0));
  debugPrint('[E2ESetup] Fixture evidence written to $path');
}
