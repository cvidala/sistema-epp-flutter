import 'package:flutter_test/flutter_test.dart';
import 'package:epp_app/services/stock_calculator.dart';

void main() {
  group('StockCalculator.computeStock — UTL-02', () {
    test('lista vacía retorna mapa vacío', () {
      expect(StockCalculator.computeStock([]), equals({}));
    });

    test('una ENTRADA retorna stock positivo', () {
      final stock = StockCalculator.computeStock([
        {'epp_id': 'casco-001', 'tipo': 'ENTRADA', 'cantidad': 10},
      ]);
      expect(stock['casco-001'], equals(10));
    });

    test('ENTRADA y SALIDA retorna la diferencia (10 - 3 = 7)', () {
      final stock = StockCalculator.computeStock([
        {'epp_id': 'casco-001', 'tipo': 'ENTRADA', 'cantidad': 10},
        {'epp_id': 'casco-001', 'tipo': 'SALIDA', 'cantidad': 3},
      ]);
      expect(stock['casco-001'], equals(7));
    });

    test('dos epp_id distintos se acumulan independientemente', () {
      final stock = StockCalculator.computeStock([
        {'epp_id': 'casco-001', 'tipo': 'ENTRADA', 'cantidad': 10},
        {'epp_id': 'guantes-01', 'tipo': 'ENTRADA', 'cantidad': 5},
        {'epp_id': 'casco-001', 'tipo': 'SALIDA', 'cantidad': 3},
      ]);
      expect(stock['casco-001'], equals(7));
      expect(stock['guantes-01'], equals(5));
    });
  });

  group('StockCalculator.validateCart — UTL-03', () {
    test('cantidad > disponible retorna el epp_id fallido', () {
      expect(
        StockCalculator.validateCart({'casco-001': 3}, {'casco-001': 2}),
        equals('casco-001'),
      );
    });

    test('cantidad == disponible retorna null (stock exacto es válido)', () {
      expect(
        StockCalculator.validateCart({'casco-001': 2}, {'casco-001': 2}),
        isNull,
      );
    });

    test('cantidad < disponible retorna null (stock suficiente)', () {
      expect(
        StockCalculator.validateCart({'casco-001': 1}, {'casco-001': 5}),
        isNull,
      );
    });

    test('epp_id ausente del mapa de stock usa 0 como disponible y retorna ese epp_id', () {
      expect(
        StockCalculator.validateCart({'unknown-epp': 1}, {}),
        equals('unknown-epp'),
      );
    });
  });
}
