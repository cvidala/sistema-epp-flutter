import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../evidence_service.dart';
import 'offline_queue_service.dart';

class SyncService {
  SyncService({
    required this.supabase,
    required this.deviceId,
    this.onSyncComplete, // ✅ callback para refrescar UI al terminar
  });

  final SupabaseClient supabase;
  final String deviceId;
  final VoidCallback? onSyncComplete;

  /// Sincroniza todas las entregas pendientes.
  /// Retorna un resumen: {enviadas, errores, pendientes}
  Future<Map<String, int>> syncOnce() async {
    final pendings = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .toList();

    int enviadas = 0;
    int errores = 0;

    debugPrint('[SyncService] Pendientes a sincronizar: ${pendings.length}');

    for (final e in pendings) {
      try {
        e.status = 'UPLOADING';
        e.attempts += 1;
        await OfflineQueueService.update(e);

        // ── 1) Subir evidencia a Storage ──────────────────────────
        final Uint8List bytes =
            await EvidenceService.readEvidenceOffline(e.evidenciaLocalPath);

        final remotePath = 'epp/offline_${e.localEventId}.jpg';
        await supabase.storage.from('evidencias').uploadBinary(
              remotePath,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        e.evidenciaRemotePath = remotePath;

        final evidenciaUrl =
            supabase.storage.from('evidencias').getPublicUrl(remotePath);

        debugPrint('[SyncService] Evidencia subida: $remotePath');

        // ── 2) Intentar RPC insert_entrega_offline_v1 ─────────────
        //    Si no existe en Supabase, caemos al fallback directo.
        bool insertOk = false;

        try {
          // Calcular prev_hash + hash encadenado (D4)
          String? prevHash;
          try {
            final prevResp = await supabase.rpc('get_prev_hash', params: {
              'p_scope': e.scope,
              'p_obra_id': e.obraId,
              'p_trabajador_id': e.trabajadorId,
            }).timeout(const Duration(seconds: 10));
            prevHash = _parsePrevHash(prevResp);
          } catch (hashErr) {
            debugPrint('[SyncService] get_prev_hash falló (no crítico): $hashErr');
            prevHash = null;
          }

          final payload = <String, dynamic>{
            'device_id': deviceId,
            'local_event_id': e.localEventId,
            'scope': e.scope,
            'obra_id': e.obraId,
            'trabajador_id': e.trabajadorId,
            'bodega_id': e.bodegaId,
            'items': _canonicalItems(e.items),
            'evidencia_hash': e.evidenciaHash,
            'created_at_client': e.createdAtClientIso,
            'evidencia_path': remotePath,
          };

          final canon = _canonicalJson(payload);
          final toHash = '${prevHash ?? ''}|$canon';
          final eventHash = EvidenceService.hashString(toHash);
          e.prevHash = prevHash;
          e.hash = eventHash;
          await OfflineQueueService.update(e);

          final ins = await supabase
              .rpc('insert_entrega_offline_v1', params: {
                'p_device_id': deviceId,
                'p_local_event_id': e.localEventId,
                'p_scope': e.scope,
                'p_obra_id': e.obraId,
                'p_trabajador_id': e.trabajadorId,
                'p_bodega_id': e.bodegaId,
                'p_items': e.items,
                'p_evidencia_path': remotePath,
                'p_evidencia_hash': e.evidenciaHash,
                'p_prev_hash': prevHash,
                'p_hash': eventHash,
                'p_created_at_client': e.createdAtClientIso,
              })
              .timeout(const Duration(seconds: 15));

          debugPrint('[SyncService] RPC insert_entrega_offline_v1 resp: $ins');
          insertOk = _parseOk(ins);

          if (!insertOk) {
            debugPrint('[SyncService] RPC retornó ok=false, usando fallback directo');
          }
        } catch (rpcErr) {
          debugPrint('[SyncService] RPC insert_entrega_offline_v1 no disponible o error: $rpcErr');
          debugPrint('[SyncService] Usando fallback: insert directo en entregas_epp');
        }

        // ── 3) Fallback: insert directo si RPC falló o no existe ──
        if (!insertOk) {
          final userId = supabase.auth.currentUser?.id;
          final eventId = 'EPP-SYNC-${e.localEventId}';

          await supabase.from('entregas_epp').insert({
            'event_id': eventId,
            'trabajador_id': e.trabajadorId,
            'obra_id': e.obraId,
            'bodega_id': e.bodegaId,
            'items': e.items,
            'entregado_por': userId,
            'sync_status': 'ENVIADO',
            'evidencia_foto_url': evidenciaUrl,
            'evidencia_hash': e.evidenciaHash,
            'evaluacion': null,
            'declaracion_text': null,
            'validacion_tipo': 'OFFLINE_SYNC',
            'created_at': e.createdAtClientIso,
          });

          debugPrint('[SyncService] Insert directo OK para: $eventId');

          // ── 4) Descontar stock (SALIDA) por cada item ──────────
          for (final it in e.items) {
            await supabase.from('stock_movimientos').insert({
              'bodega_id': e.bodegaId,
              'epp_id': it['epp_id'],
              'tipo': 'SALIDA',
              'cantidad': it['cantidad'],
              'referencia_event_id': eventId,
              'motivo': 'Entrega EPP (sync offline)',
              'created_by': userId,
            });
          }

          insertOk = true;
        }

        // ── 5) Marcar como SENT ───────────────────────────────────
        if (insertOk) {
          await OfflineQueueService.markSent(e.localEventId);
          enviadas++;
          debugPrint('[SyncService] ✅ ${e.localEventId} → SENT');
        }
      } catch (ex) {
        e.status = 'ERROR';
        e.lastError = ex.toString();
        await OfflineQueueService.update(e);
        errores++;
        debugPrint('[SyncService] ❌ Error en ${e.localEventId}: $ex');
      }
    }

    final pendientesRestantes = OfflineQueueService.listPending()
        .where((e) => e.status != 'SENT')
        .length;

    debugPrint(
        '[SyncService] Sync completo — enviadas: $enviadas, errores: $errores, pendientes: $pendientesRestantes');

    // ✅ Notificar UI para que recargue historial
    onSyncComplete?.call();

    return {
      'enviadas': enviadas,
      'errores': errores,
      'pendientes': pendientesRestantes,
    };
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  bool _parseOk(dynamic ins) {
    if (ins is Map) return ins['ok'] == true;
    if (ins is List && ins.isNotEmpty && ins.first is Map) {
      return (ins.first as Map)['ok'] == true;
    }
    // ✅ Si la RPC no retorna {ok: true} explícito pero tampoco lanzó excepción,
    // asumimos que fue exitosa solo si ins no es null
    return false;
  }

  String? _parsePrevHash(dynamic prevResp) {
    if (prevResp is List && prevResp.isNotEmpty && prevResp.first is Map) {
      final v = (prevResp.first as Map)['last_hash'];
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }
    if (prevResp is Map) {
      final s = prevResp['last_hash']?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }
    return null;
  }

  List<Map<String, dynamic>> _canonicalItems(
      List<Map<String, dynamic>> items) {
    final list = items.map((x) => Map<String, dynamic>.from(x)).toList();
    list.sort((a, b) =>
        a['epp_id'].toString().compareTo(b['epp_id'].toString()));
    return list;
  }

  String _canonicalJson(Map<String, dynamic> m) {
    final keys = m.keys.toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k] = m[k];
    }
    return out.toString();
  }
}