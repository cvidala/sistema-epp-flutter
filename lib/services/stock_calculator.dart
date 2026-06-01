/// Servicio puro de cálculo de stock disponible y validación de carrito.
///
/// Métodos estáticos sin estado — sin dependencias externas ni efectos secundarios.
class StockCalculator {
  /// Calcula el stock disponible por EPP a partir de movimientos de bodega.
  ///
  /// Recibe una lista de filas con {epp_id, tipo: 'ENTRADA'|'SALIDA', cantidad}.
  /// Retorna un mapa epp_id → stock disponible (puede ser negativo si hay inconsistencias).
  static Map<String, int> computeStock(List<Map<String, dynamic>> rows) {
    final mapa = <String, int>{};
    for (final r in rows) {
      final id = r['epp_id'] as String;
      final tipo = r['tipo'] as String;
      final qty = (r['cantidad'] as num).toInt();
      mapa[id] = (mapa[id] ?? 0) + (tipo == 'ENTRADA' ? qty : -qty);
    }
    return mapa;
  }

  /// Valida que el carrito no supere el stock disponible.
  ///
  /// Retorna el epp_id del primer ítem con stock insuficiente, o null si todo es válido.
  static String? validateCart(
    Map<String, int> carrito,
    Map<String, int> stockDisponible,
  ) {
    for (final entry in carrito.entries) {
      final disponible = stockDisponible[entry.key] ?? 0;
      if (entry.value > disponible) return entry.key;
    }
    return null;
  }
}
