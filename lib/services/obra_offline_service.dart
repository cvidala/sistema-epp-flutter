import 'package:supabase_flutter/supabase_flutter.dart';
import 'cache_service.dart';
import 'stock_calculator.dart';

/// Descarga proactiva de todos los datos de una obra para uso sin conexión.
///
/// Guarda en las MISMAS claves de [CacheService] que leen las pantallas
/// cuando no hay señal (workers_page: 'trabajadores_activos';
/// new_delivery_page: 'bodegas', 'catalogo_epp', 'stock'), de modo que en
/// faena aparezcan todos los trabajadores y se pueda entregar a cualquiera
/// sin depender de haber abierto cada pantalla antes.
class ObraOfflineService {
  static SupabaseClient get _c => Supabase.instance.client;
  static const _timeout = Duration(seconds: 20);

  /// Descarga y cachea trabajadores + bodegas + catálogo + stock de la obra.
  /// Devuelve conteos. Lanza excepción si falla (para mostrar el error).
  static Future<Map<String, int>> descargarObra(String obraId) async {
    // 1) Trabajadores (misma query que workers_page._loadWorkers)
    final trabRaw = await _c
        .from('trabajador_obras')
        .select(
            'cargo, trabajadores!inner(trabajador_id, nombre, apellido, rut, estado, datos_completos)')
        .eq('obra_id', obraId)
        .eq('activo', true)
        .eq('trabajadores.estado', 'ACTIVO')
        .order('trabajadores(nombre)')
        .timeout(_timeout);
    final trabajadores = (trabRaw as List).map((row) {
      final t = Map<String, dynamic>.from(row['trabajadores'] as Map);
      if (row['cargo'] != null) t['cargo'] = row['cargo'];
      return t;
    }).toList();
    await CacheService.setJson('trabajadores_activos', trabajadores,
        obraId: obraId);

    // 2) Bodegas (misma query que new_delivery_page._loadInit)
    final bod = await _c
        .from('bodegas')
        .select()
        .or('obra_id.eq.$obraId,obra_id.is.null')
        .order('created_at')
        .timeout(_timeout);
    await CacheService.setJson('bodegas', bod, obraId: obraId);

    // 3) Catálogo EPP
    final cat = await _c
        .from('catalogo_epp')
        .select()
        .eq('activo', true)
        .order('nombre')
        .timeout(_timeout);
    await CacheService.setJson('catalogo_epp', cat, obraId: obraId);

    // 4) Stock por cada bodega → mapa {bodegaId: {epp_id: cantidad}}
    final Map<String, Map<String, int>> stockPorBodega = {};
    for (final b in (bod as List)) {
      final bId = b['bodega_id'] as String;
      try {
        final rows = await _c
            .from('stock_movimientos')
            .select('epp_id, tipo, cantidad')
            .eq('bodega_id', bId)
            .timeout(_timeout);
        stockPorBodega[bId] = StockCalculator.computeStock(
          (rows as List).cast<Map<String, dynamic>>(),
        );
      } catch (_) {
        // Una bodega que falle no aborta el resto de la descarga.
      }
    }
    await CacheService.setJson('stock', stockPorBodega, obraId: obraId);

    // 5) Timestamp de la descarga
    await CacheService.setJson(
        'descarga_ts', DateTime.now().toIso8601String(),
        obraId: obraId);

    return {
      'trabajadores': trabajadores.length,
      'bodegas': (bod).length,
      'catalogo': (cat as List).length,
    };
  }

  /// Momento de la última descarga offline de la obra, o null si nunca.
  static DateTime? ultimaDescarga(String obraId) {
    final raw = CacheService.getJson('descarga_ts', obraId: obraId);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
