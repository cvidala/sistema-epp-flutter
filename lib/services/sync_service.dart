import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../evidence_service.dart';
import 'offline_queue_service.dart';

class SyncService {
  SyncService({
    required this.supabase,
    required this.deviceId,
    this.onSyncComplete,
  });

  final SupabaseClient supabase;
  final String deviceId;
  final VoidCallback? onSyncComplete;

  /// Sincroniza todas las entregas pendientes respetando backoff.
  /// Retorna {enviadas, errores, pendientes, fallidas}
  Future<Map<String, int>> syncOnce() async {
    // listPending() ya filtra por backoff y estado — no resetear masivamente
    final pendings = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .toList();

    int enviadas = 0;
    int errores  = 0;

    debugPrint('[SyncService] Pendientes a sincronizar: ${pendings.length}');

    for (final e in pendings) {
      try {
        e.status = 'UPLOADING';
        e.attempts += 1;
        await OfflineQueueService.update(e);

        // ── 0) Verificar duplicado ─────────────────────────────────────────
        try {
          final existing = await supabase
              .from('entregas_epp')
              .select('event_id, sync_status')
              .or('event_id.eq.EPP-SYNC-${e.localEventId},local_event_id.eq.${e.localEventId}')
              .maybeSingle()
              .timeout(const Duration(seconds: 8));

          if (existing != null) {
            debugPrint('[SyncService] Ya existe: ${existing['event_id']} — SENT');
            await OfflineQueueService.markSent(e.localEventId);
            enviadas++;
            continue;
          }
        } catch (checkErr) {
          debugPrint('[SyncService] Check duplicado falló (no crítico): $checkErr');
        }

        // ── 1) Subir evidencia a Storage ──────────────────────────────────
        final Uint8List evidenciaBytes =
            await EvidenceService.readEvidenceOffline(e.evidenciaLocalPath);

        final remotePath = 'epp/offline_${e.localEventId}.jpg';
        await supabase.storage.from('evidencias').uploadBinary(
              remotePath,
              evidenciaBytes,
              fileOptions: const FileOptions(upsert: true),
            );
        e.evidenciaRemotePath = remotePath;
        debugPrint('[SyncService] Evidencia subida: $remotePath');

        // ── 2) Subir firma a Storage (si existe) ──────────────────────────
        String? firmaRemotePath;
        String? firmaHash;
        if (e.firmaLocalPath != null) {
          final firmaBytes =
              await EvidenceService.readEvidenceOffline(e.firmaLocalPath!);

          firmaRemotePath = 'epp/offline_${e.localEventId}_firma.png';
          await supabase.storage.from('evidencias').uploadBinary(
                firmaRemotePath,
                firmaBytes,
                fileOptions: const FileOptions(upsert: true),
              );
          debugPrint('[SyncService] Firma subida: $firmaRemotePath');

          // Calcular hash de la firma (para integridad encadenada)
          firmaHash = e.firmaHash ?? EvidenceService.hashBytes(firmaBytes);
          e.firmaHash = firmaHash;
          await OfflineQueueService.update(e);
        }

        // ── 3) get_prev_hash para encadenamiento ──────────────────────────
        String? prevHash;
        try {
          final prevResp = await supabase.rpc('get_prev_hash', params: {
            'p_scope': e.scope,
            'p_obra_id': e.obraId,
            'p_trabajador_id': e.trabajadorId,
          }).timeout(const Duration(seconds: 10));
          prevHash = _parsePrevHash(prevResp);
          debugPrint('[SyncService] prev_hash: $prevHash');
        } catch (hashErr) {
          debugPrint('[SyncService] get_prev_hash falló (no crítico): $hashErr');
          prevHash = null;
        }

        // ── 4) Calcular hash encadenado ────────────────────────────────────
        // IMPORTANTE: firma_hash incluido → cualquier alteración rompe la cadena
        final payload = <String, dynamic>{
          'device_id':         deviceId,
          'local_event_id':    e.localEventId,
          'scope':             e.scope,
          'obra_id':           e.obraId,
          'trabajador_id':     e.trabajadorId,
          'bodega_id':         e.bodegaId,
          'items':             _canonicalItems(e.items),
          'evidencia_hash':    e.evidenciaHash,
          'created_at_client': e.createdAtClientIso,
          'evidencia_path':    remotePath,
          if (firmaHash != null)    'firma_hash':  firmaHash,
          if (firmaRemotePath != null) 'firma_path': firmaRemotePath,
          if (e.forensics != null) 'forensics_gps_lat': e.forensics!['gps_lat'],
          if (e.forensics != null) 'forensics_gps_lng': e.forensics!['gps_lng'],
        };
        final canon    = _canonicalJson(payload);
        final toHash   = '${prevHash ?? ''}|$canon';
        final eventHash = EvidenceService.hashString(toHash);
        e.prevHash = prevHash;
        e.hash     = eventHash;
        await OfflineQueueService.update(e);

        // ── 5) RPC atómico ────────────────────────────────────────────────
        bool insertOk      = false;
        bool rpcDisponible = true;

        try {
          final ins = await supabase.rpc('insert_entrega_offline_v1', params: {
            'p_device_id':        deviceId,
            'p_local_event_id':   e.localEventId,
            'p_scope':            e.scope,
            'p_obra_id':          e.obraId,
            'p_trabajador_id':    e.trabajadorId,
            'p_bodega_id':        e.bodegaId,
            'p_items':            e.items,
            'p_evidencia_path':   remotePath,
            'p_evidencia_hash':   e.evidenciaHash,
            'p_prev_hash':        prevHash,
            'p_hash':             eventHash,
            'p_created_at_client': e.createdAtClientIso,
            'p_firma_path':       firmaRemotePath,
            'p_firma_hash':       firmaHash,
            'p_forensics':        e.forensics,
          }).timeout(const Duration(seconds: 20));

          debugPrint('[SyncService] RPC resp: $ins');
          insertOk = _parseOk(ins);

          if (!insertOk) {
            final errMsg = _parseError(ins);
            debugPrint('[SyncService] RPC error de negocio: $errMsg');
            await _handleError(e, 'RPC error: $errMsg');
            errores++;
            continue;
          }
        } on PostgrestException catch (pgErr) {
          if (pgErr.code == 'PGRST202' ||
              pgErr.message.contains('Could not find') ||
              pgErr.message.contains('function')) {
            debugPrint('[SyncService] RPC no existe, usando fallback directo');
            rpcDisponible = false;
          } else {
            rethrow;
          }
        }

        // ── 6) Fallback directo (si RPC no existe) ────────────────────────
        if (!rpcDisponible) {
          debugPrint('[SyncService] Fallback: insert directo (no atómico)');
          final userId  = supabase.auth.currentUser?.id;
          final eventId = 'EPP-SYNC-${e.localEventId}';
          final evidenciaUrl = supabase.storage
              .from('evidencias')
              .getPublicUrl(remotePath);
          final firmaUrl = firmaRemotePath != null
              ? supabase.storage.from('evidencias').getPublicUrl(firmaRemotePath)
              : null;

          await supabase.from('entregas_epp').insert({
            'event_id':          eventId,
            'trabajador_id':     e.trabajadorId,
            'obra_id':           e.obraId,
            'bodega_id':         e.bodegaId,
            'items':             e.items,
            'entregado_por':     userId,
            'sync_status':       'ENVIADO',
            'evidencia_foto_url': evidenciaUrl,
            'evidencia_hash':    e.evidenciaHash,
            'firma_url':         firmaUrl,
            'firma_hash':        firmaHash,
            'forensics':         e.forensics,
            'validacion_tipo':   'OFFLINE_SYNC',
            'created_at':        e.createdAtClientIso,
          });

          for (final it in e.items) {
            await supabase.from('stock_movimientos').insert({
              'bodega_id':           e.bodegaId,
              'epp_id':              it['epp_id'],
              'tipo':                'SALIDA',
              'cantidad':            it['cantidad'],
              'referencia_event_id': eventId,
              'motivo':              'Entrega EPP (sync offline)',
              'created_by':         userId,
            });
          }

          debugPrint('[SyncService] Fallback OK: $eventId');
          insertOk = true;
        }

        // ── 7) Marcar SENT ────────────────────────────────────────────────
        if (insertOk) {
          await OfflineQueueService.markSent(e.localEventId);
          enviadas++;
          debugPrint('[SyncService] ✅ ${e.localEventId} → SENT');
        }
      } catch (ex) {
        await _handleError(e, ex.toString());
        errores++;
        debugPrint('[SyncService] ❌ Error en ${e.localEventId}: $ex');
      }
    }

    final pendientesRestantes = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .length;

    debugPrint(
        '[SyncService] Sync completo — '
        'enviadas: $enviadas, errores: $errores, pendientes: $pendientesRestantes');

    onSyncComplete?.call();

    return {
      'enviadas':   enviadas,
      'errores':    errores,
      'pendientes': pendientesRestantes,
    };
  }

  // ─────────────────────────────────────────────
  // BACKOFF EXPONENCIAL
  // ─────────────────────────────────────────────

  /// Registra un error con backoff. Si supera maxAttempts → FAILED permanente.
  Future<void> _handleError(OfflineEntrega e, String error) async {
    if (e.attempts >= e.maxAttempts) {
      await OfflineQueueService.markFailed(e.localEventId,
          'Máximo de intentos alcanzado (${ e.maxAttempts}). Último: $error');
      debugPrint('[SyncService] ⛔ ${e.localEventId} → FAILED permanente');
      return;
    }
    e.status    = 'ERROR';
    e.lastError = error;
    // Backoff: min(2^(attempts-1), 60) minutos
    final delayMin = min(pow(2, e.attempts - 1).toInt(), 60);
    e.nextRetryAt =
        DateTime.now().add(Duration(minutes: delayMin)).toIso8601String();
    await OfflineQueueService.update(e);
    debugPrint('[SyncService] ⏳ ${e.localEventId} → retry en ${delayMin}min');
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  bool _parseOk(dynamic ins) {
    if (ins is Map) return ins['ok'] == true;
    if (ins is List && ins.isNotEmpty && ins.first is Map) {
      return (ins.first as Map)['ok'] == true;
    }
    return false;
  }

  String _parseError(dynamic ins) {
    if (ins is Map) return (ins['error'] ?? 'error desconocido').toString();
    if (ins is List && ins.isNotEmpty && ins.first is Map) {
      return ((ins.first as Map)['error'] ?? 'error desconocido').toString();
    }
    return ins.toString();
  }

  String? _parsePrevHash(dynamic prevResp) {
    if (prevResp is Map) {
      final s = prevResp['last_hash']?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }
    if (prevResp is List && prevResp.isNotEmpty && prevResp.first is Map) {
      final v = (prevResp.first as Map)['last_hash'];
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }
    return null;
  }

  List<Map<String, dynamic>> _canonicalItems(
      List<Map<String, dynamic>> items) {
    final list = items.map((x) => Map<String, dynamic>.from(x)).toList();
    list.sort(
        (a, b) => a['epp_id'].toString().compareTo(b['epp_id'].toString()));
    return list;
  }

  String _canonicalJson(Map<String, dynamic> m) {
    final keys = m.keys.toList()..sort();
    final out  = <String, dynamic>{};
    for (final k in keys) {
      out[k] = m[k];
    }
    return jsonEncode(out);
  }
}
