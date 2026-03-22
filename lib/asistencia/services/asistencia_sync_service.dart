import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'asistencia_hive_service.dart';
import 'asistencia_upload_service.dart';

class AsistenciaSyncService {
  AsistenciaSyncService._();
  static final instance = AsistenciaSyncService._();

  Timer? _timer;
  bool _syncing = false;
  bool _estabaOnline = false;
  VoidCallback? _onStatusChange;

  bool get isOnline => _estabaOnline;

  void start({VoidCallback? onStatusChange}) {
    _onStatusChange = onStatusChange;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
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
      debugPrint('[AsistenciaSync] Estado → ${online ? "ONLINE" : "OFFLINE"}');
      _onStatusChange?.call();
    }

    if (!online || _syncing) return;

    final pendientes = AsistenciaHiveService.listarPendientes();
    if (pendientes.isEmpty) return;

    debugPrint('[AsistenciaSync] ${pendientes.length} pendiente(s), sincronizando...');
    await _syncAll();
  }

  Future<void> _syncAll() async {
    _syncing = true;
    try {
      final pendientes = AsistenciaHiveService.listarPendientes();
      for (final a in pendientes) {
        try {
          if (a.intentos >= 3) {
            await AsistenciaHiveService.actualizarStatus(a.id, 'fallida');
            continue;
          }
          await AsistenciaHiveService.actualizarStatus(a.id, 'subiendo');
          final bytes = await File(a.fotoLocalPath).readAsBytes();
          final fotoPath =
              await AsistenciaUploadService.subirFoto(a.id, a.rut, bytes);
          await AsistenciaUploadService.insertarRegistro(
              a: a, fotoPath: fotoPath);
          await AsistenciaHiveService.marcarEnviada(a.id);
          // Borra la foto local inmediatamente para no llenar la memoria
          try {
            await File(a.fotoLocalPath).delete();
          } catch (_) {}
          debugPrint('[AsistenciaSync] ✓ Enviada: ${a.rut}');
        } catch (e) {
          await AsistenciaHiveService.incrementarIntento(a.id, e.toString());
          debugPrint('[AsistenciaSync] Error sync ${a.rut}: $e');
        }
      }
    } finally {
      _syncing = false;
    }
  }

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
}
