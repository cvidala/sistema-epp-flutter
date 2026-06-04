import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/asistencia_pendiente.dart';

class AsistenciaUploadService {
  static SupabaseClient get _s => Supabase.instance.client;
  static const _bucket = 'asistencias-fotos';

  /// Sube la foto al bucket y retorna el path remoto.
  static Future<String> subirFoto(
      String id, String rut, Uint8List bytes) async {
    final path = '${rut.replaceAll('.', '').replaceAll('-', '')}/$id.jpg';
    await _s.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true, // reintento seguro si el upload anterior quedó parcial
          ),
        );
    return path;
  }

  /// Inserta el registro en la tabla asistencias (para sync offline).
  static Future<void> insertarRegistro({
    required AsistenciaPendiente a,
    required String fotoPath,
  }) async {
    await _s.from('asistencias').insert({
      'local_event_id':      a.id,
      'rut':                 a.rut,
      'tipo':                a.tipo,
      'foto_path':           fotoPath,
      'gps_lat':             a.gpsLat,
      'gps_lng':             a.gpsLng,
      'gps_accuracy_m':      a.gpsAccuracy,
      'device_model':        a.deviceModel,
      'captured_at':         a.capturedAt,
      'sync_status':         'synced',
      // Campos DT — ORD. N°1140/27
      'trabajador_nombre':   a.trabajadorNombre,
      'empleador_rut':       a.empleadorRut,
      'empleador_nombre':    a.empleadorNombre,
      'empleador_domicilio': a.empleadorDomicilio,
      'validacion_tipo':     a.validacionTipo,
      'fallback_motivo':     a.fallbackMotivo,
      'evidencia_hash':      a.fotoHash,
    });
  }

  /// Upload completo en tiempo real (flujo online).
  static Future<void> subirOnline({
    required String localEventId,
    required String rut,
    required Uint8List fotoBytes,
    required String fotoHash,
    required Map<String, dynamic>? forensics,
    required String tipo,
    // Campos DT
    String? trabajadorNombre,
    String? empleadorRut,
    String? empleadorNombre,
    String? empleadorDomicilio,
    String validacionTipo = 'BIOMETRICA',
    String? fallbackMotivo,
  }) async {
    final path = await subirFoto(localEventId, rut, fotoBytes);
    await _s.from('asistencias').insert({
      'local_event_id':      localEventId,
      'rut':                 rut,
      'tipo':                tipo,
      'foto_path':           path,
      'gps_lat':             forensics?['gps_lat'],
      'gps_lng':             forensics?['gps_lng'],
      'gps_accuracy_m':      forensics?['gps_accuracy_m'],
      'device_model':        forensics?['device_model'],
      'captured_at':         forensics?['captured_at'] ??
                             DateTime.now().toUtc().toIso8601String(),
      'sync_status':         'online',
      // Campos DT — ORD. N°1140/27
      'trabajador_nombre':   trabajadorNombre,
      'empleador_rut':       empleadorRut,
      'empleador_nombre':    empleadorNombre,
      'empleador_domicilio': empleadorDomicilio,
      'validacion_tipo':     validacionTipo,
      'fallback_motivo':     fallbackMotivo,
      'evidencia_hash':      fotoHash,
    });
  }

  /// Registra una marcación fallida en asistencias_errores (§1 ORD. 1140/27).
  static Future<void> registrarErrorMarcacion({
    required String orgId,
    required String? rut,
    required String codigoError,
    required String mensajeError,
    required Map<String, dynamic>? forensics,
  }) async {
    try {
      await _s.from('asistencias_errores').insert({
        'org_id':       orgId,
        'rut':          rut,
        'codigo_error': codigoError,
        'mensaje_error': mensajeError,
        'gps_lat':      forensics?['gps_lat'],
        'gps_lng':      forensics?['gps_lng'],
        'device_model': forensics?['device_model'],
        'occurred_at':  DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // No crítico: el error de marcación es evidencia, pero no bloquea el flujo
    }
  }
}
