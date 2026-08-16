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
            upsert: true,
          ),
        );
    return path;
  }

  /// Inserta el registro en la tabla asistencias (para sync offline).
  static Future<void> insertarRegistro({
    required AsistenciaPendiente a,
    required String fotoPath,
    required String orgId,
    String? obraId,
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
      'org_id':              orgId,
      'obra_id':             obraId,
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
    required String orgId,
    String? obraId,
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
      'org_id':              orgId,
      'obra_id':             obraId,
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

  /// Registra una marcación fallida vía RPC (accesible por anon).
  /// Reemplaza el insert directo a asistencias_errores que fallaba silenciosamente
  /// porque la política INSERT usaba auth.uid() = NULL para el kiosko anon.
  static Future<void> registrarErrorMarcacion({
    required String orgId,
    required String? rut,
    required String codigoError,
    required String mensajeError,
    required Map<String, dynamic>? forensics,
  }) async {
    try {
      await _s.rpc('registrar_error_marcacion', params: {
        'p_org_id':        orgId,
        'p_rut':           rut,
        'p_codigo':        codigoError,
        'p_mensaje':       mensajeError,
        'p_gps_lat':       forensics?['gps_lat'],
        'p_gps_lng':       forensics?['gps_lng'],
        'p_device_model':  forensics?['device_model'],
      });
    } catch (_) {
      // No crítico: el error de marcación es evidencia secundaria
    }
  }
}
