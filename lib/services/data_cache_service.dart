import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_cache_service.dart';

/// Descarga y guarda en caché local todo lo necesario para operar offline.
/// Se llama después del login exitoso y cada vez que se detecta conexión.
class DataCacheService {
  static final _client = Supabase.instance.client;

  /// Sincronización completa: perfil + obras + trabajadores + catálogo + bodegas.
  /// Silenciosa — no lanza excepciones, solo loguea errores.
  static Future<void> sincronizarTodo() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // 1) Perfil + config_modulos de la org
      final perfilRes = await _client
          .from('perfiles')
          .select('user_id, nombre, rol, org_id, activo, organizaciones(config_modulos)')
          .eq('user_id', userId)
          .single();
      final perfilMap = Map<String, dynamic>.from(perfilRes);
      final orgData = perfilMap['organizaciones'];
      if (orgData is Map && orgData['config_modulos'] != null) {
        perfilMap['config_modulos'] = orgData['config_modulos'];
      }
      perfilMap.remove('organizaciones');
      await OfflineCacheService.guardarPerfil(perfilMap);

      // 2) Obras accesibles (RLS filtra automáticamente)
      final obrasRes = await _client
          .from('obras')
          .select('obra_id, nombre, direccion, estado')
          .order('nombre');
      final obras = List<Map<String, dynamic>>.from(
          obrasRes.map((e) => Map<String, dynamic>.from(e)));
      await OfflineCacheService.guardarObras(obras);

      // 3) Trabajadores por cada obra
      for (final obra in obras) {
        final obraId = obra['obra_id'] as String;
        try {
          final trabRes = await _client
              .from('trabajador_obras')
              .select('cargo, trabajadores!inner(trabajador_id, nombre, rut, estado)')
              .eq('obra_id', obraId)
              .eq('activo', true);
          final trabajadores = List<Map<String, dynamic>>.from(
            trabRes.map((e) {
              final t = Map<String, dynamic>.from(e['trabajadores']);
              t['cargo'] = e['cargo'];
              return t;
            }),
          );
          await OfflineCacheService.guardarTrabajadores(obraId, trabajadores);
        } catch (_) {
          // Si falla una obra, continuar con las demás
        }
      }

      // 4) Catálogo EPP completo
      final catRes = await _client
          .from('catalogo_epp')
          .select('epp_id, nombre, codigo, categoria, vida_util_dias, activo')
          .eq('activo', true)
          .order('nombre');
      await OfflineCacheService.guardarCatalogo(
          List<Map<String, dynamic>>.from(
              catRes.map((e) => Map<String, dynamic>.from(e))));

      // 5) Bodegas accesibles
      final bodRes = await _client
          .from('bodegas')
          .select('bodega_id, nombre, obra_id')
          .order('nombre');
      await OfflineCacheService.guardarBodegas(
          List<Map<String, dynamic>>.from(
              bodRes.map((e) => Map<String, dynamic>.from(e))));

      // Marcar timestamp de última sync exitosa
      await OfflineCacheService.marcarSync();

      print('[SyncService] ✅ Sincronización completa: '
          '${obras.length} obras, ${catRes.length} EPPs');
    } catch (e) {
      // Sync fallida — no interrumpir el flujo de la app
      print('[SyncService] ⚠️ Error en sincronización: $e');
    }
  }

  /// Sync rápida solo del catálogo y bodegas (más liviana, para refrescos frecuentes)
  static Future<void> sincronizarCatalogo() async {
    try {
      final catRes = await _client
          .from('catalogo_epp')
          .select('epp_id, nombre, codigo, categoria, vida_util_dias, activo')
          .eq('activo', true)
          .order('nombre');
      await OfflineCacheService.guardarCatalogo(
          List<Map<String, dynamic>>.from(
              catRes.map((e) => Map<String, dynamic>.from(e))));

      final bodRes = await _client
          .from('bodegas')
          .select('bodega_id, nombre, obra_id')
          .order('nombre');
      await OfflineCacheService.guardarBodegas(
          List<Map<String, dynamic>>.from(
              bodRes.map((e) => Map<String, dynamic>.from(e))));

      await OfflineCacheService.marcarSync();
    } catch (e) {
      print('[SyncService] ⚠️ Error sync catálogo: $e');
    }
  }
}