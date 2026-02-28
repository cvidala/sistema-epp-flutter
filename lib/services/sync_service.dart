import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../evidence_service.dart';
import 'offline_queue_service.dart';

class SyncService {
  SyncService({
    required this.supabase,
    required this.deviceId,
  });

  final SupabaseClient supabase;
  final String deviceId;

  /// Sincroniza una pasada: evidencia -> prev_hash -> hash encadenado (D4) -> RPC insert
  Future<void> syncOnce() async {
    final pendings = OfflineQueueService.listPending();

    for (final e in pendings) {
      if (e.status == 'SENT') continue;

      try {
        e.status = 'UPLOADING';
        e.attempts += 1;
        await OfflineQueueService.update(e);

        // 1) Obtener prev_hash real del servidor
        final prevResp = await supabase.rpc('get_prev_hash', params: {
          'p_scope': e.scope,
          'p_obra_id': e.obraId,
          'p_trabajador_id': e.scope == 'obra_trabajador' ? e.trabajadorId : null,
        });

        String? prevHash = _parsePrevHash(prevResp);
        e.prevHash = prevHash;

        // 2) Leer evidencia desde disco local
        final Uint8List bytes = await EvidenceService.readEvidenceOffline(e.evidenciaLocalPath);

        // 3) Subir evidencia a Storage (path determinístico por device/localEventId)
        final remotePath = 'offline/$deviceId/${e.localEventId}.jpg';
        await supabase.storage.from('evidencias').uploadBinary(
              remotePath,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        e.evidenciaRemotePath = remotePath;

        // 4) D4: Calcular hash encadenado
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
          'evidencia_path': e.evidenciaRemotePath,
        };

        final canon = _canonicalJson(payload);
        final toHash = '${prevHash ?? ''}|$canon';
        final eventHash = EvidenceService.hashString(toHash);
        e.hash = eventHash;

        await OfflineQueueService.update(e);

        // 5) Insert atómico en servidor
        final ins = await supabase.rpc('insert_entrega_offline_v1', params: {
          'p_device_id': deviceId,
          'p_local_event_id': e.localEventId,
          'p_scope': e.scope,
          'p_obra_id': e.obraId,
          'p_trabajador_id': e.trabajadorId,
          'p_bodega_id': e.bodegaId,
          'p_items': e.items,
          'p_evidencia_path': e.evidenciaRemotePath,
          'p_evidencia_hash': e.evidenciaHash,
          'p_prev_hash': e.prevHash,
          'p_hash': e.hash,
          'p_created_at_client': e.createdAtClientIso,
        });

        final ok = _parseOk(ins);
        if (!ok) {
          e.status = 'ERROR';
          e.lastError = ins.toString();
          await OfflineQueueService.update(e);
          continue;
        }

        await OfflineQueueService.markSent(e.localEventId);
      } catch (ex) {
        e.status = 'ERROR';
        e.lastError = ex.toString();
        await OfflineQueueService.update(e);
      }
    }
  }

  bool _parseOk(dynamic ins) {
    if (ins is Map) return ins['ok'] == true;
    if (ins is List && ins.isNotEmpty && ins.first is Map) return (ins.first as Map)['ok'] == true;
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

  // Ordena items por epp_id para hash estable
  List<Map<String, dynamic>> _canonicalItems(List<Map<String, dynamic>> items) {
    final list = items.map((x) => Map<String, dynamic>.from(x)).toList();
    list.sort((a, b) => a['epp_id'].toString().compareTo(b['epp_id'].toString()));
    return list;
  }

  String _canonicalJson(Map<String, dynamic> m) {
    final keys = m.keys.toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k] = m[k];
    }
    return out.toString(); // suficiente para MVP (si quieres, lo hacemos jsonEncode ordenado)
  }
}
