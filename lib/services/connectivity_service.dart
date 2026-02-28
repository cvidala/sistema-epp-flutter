import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_service.dart';
import 'device_id_service.dart';
import 'offline_queue_service.dart';

/// Monitorea la conectividad sondeando Supabase cada N segundos.
/// Cuando detecta transición offline → online, dispara sync automático.
///
/// Uso:
///   ConnectivityService.instance.start(onSyncComplete: () { ... });
///   ConnectivityService.instance.stop();
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  Timer? _timer;
  bool _estabaOnline = false; // estado previo conocido
  bool _syncing = false;      // evita solapamiento de syncs

  VoidCallback? _onSyncComplete;
  VoidCallback? _onStatusChange; // para actualizar UI con estado online/offline

  bool get isOnline => _estabaOnline;

  /// Inicia el monitoreo.
  /// [intervalSeconds] — cada cuánto sondea (default: 10s).
  /// [onSyncComplete] — se llama cuando termina un sync automático.
  /// [onStatusChange] — se llama cuando cambia el estado online/offline.
  void start({
    int intervalSeconds = 10,
    VoidCallback? onSyncComplete,
    VoidCallback? onStatusChange,
  }) {
    _onSyncComplete = onSyncComplete;
    _onStatusChange = onStatusChange;

    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _check();
    });

    // Primer chequeo inmediato
    _check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    final online = await _testConnectivity();

    final cambio = online != _estabaOnline;
    _estabaOnline = online;

    if (cambio) {
      debugPrint('[Connectivity] Estado cambió → ${online ? "ONLINE" : "OFFLINE"}');
      _onStatusChange?.call();
    }

    // Solo disparar sync si:
    // 1) Ahora está online
    // 2) Hubo cambio (venía de offline) O hay pendientes sin intentar
    // 3) No hay sync en curso
    if (online && !_syncing) {
      final pendientes = OfflineQueueService.listPending()
          .where((e) => e.status != 'SENT')
          .toList();

      if (pendientes.isEmpty) return;

      // Si hubo cambio de offline→online, sync inmediato
      // Si ya estaba online pero hay pendientes con error, reintentar
      final hayParaReintentar = pendientes.any(
        (e) => e.status == 'PENDING' || e.status == 'ERROR',
      );

      if (!hayParaReintentar) return;

      debugPrint(
          '[Connectivity] ${pendientes.length} pendiente(s) detectado(s), iniciando sync automático...');
      await _runSync();
    }
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    _syncing = true;

    try {
      final supabase = Supabase.instance.client;
      final deviceId = DeviceIdService.deviceId;

      final sync = SyncService(
        supabase: supabase,
        deviceId: deviceId,
        onSyncComplete: _onSyncComplete,
      );

      final resultado = await sync.syncOnce();
      debugPrint(
          '[Connectivity] Sync automático completado — '
          'enviadas: ${resultado['enviadas']}, '
          'errores: ${resultado['errores']}, '
          'pendientes: ${resultado['pendientes']}');
    } catch (e) {
      debugPrint('[Connectivity] Error en sync automático: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Prueba si hay conexión real intentando llegar a Supabase.
  /// Más confiable que `connectivity_plus` porque valida el backend real.
  Future<bool> _testConnectivity() async {
    try {
      await Supabase.instance.client
          .from('obras')
          .select('obra_id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fuerza un sync manual inmediato (para el botón 🔄).
  /// Retorna el resumen {enviadas, errores, pendientes}.
  Future<Map<String, int>> syncManual() async {
    final supabase = Supabase.instance.client;
    final deviceId = DeviceIdService.deviceId;

    final sync = SyncService(
      supabase: supabase,
      deviceId: deviceId,
      onSyncComplete: _onSyncComplete,
    );

    return await sync.syncOnce();
  }
}