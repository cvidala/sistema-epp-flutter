import 'test_client.dart';

/// Helpers de seed y limpieza para tests de integración Supabase.
///
/// Usa service_role (bypasa RLS) para limpiar datos en tablas
/// que tienen políticas USING(false) en DELETE.
class TestDataHelper {
  TestDataHelper._();

  /// Genera un local_event_id único con el prefijo centinela para un tag dado.
  ///
  /// Ejemplo: testId('rls03') → 'test_qa_rls03_1748000000000'
  static String testId(String tag) =>
      '$kTestPrefix${tag}_${DateTime.now().millisecondsSinceEpoch}';

  /// Elimina todas las filas de test de las tablas críticas.
  ///
  /// Limpia filas donde local_event_id LIKE 'test_qa_%' en:
  /// - entregas_epp
  /// - stock_movimientos (si columna existe)
  ///
  /// Limpia filas en asistencias donde rut LIKE 'TEST_QA_%'.
  ///
  /// Usa service_role para bypasear las políticas no-delete.
  /// Los errores se imprimen pero no re-lanzan (tearDown no debe fallar
  /// el test suite por errores de limpieza).
  static Future<void> tearDownTestData() async {
    final svc = serviceClient();
    try {
      // Limpiar entregas_epp con local_event_id centinela
      await svc
          .from('entregas_epp')
          .delete()
          .like('local_event_id', '$kTestPrefix%');
    } catch (e) {
      // ignore: avoid_print
      print('[TestDataHelper] Error limpiando entregas_epp: $e');
    }

    try {
      // Limpiar asistencias de test (identificadas por rut centinela)
      await svc
          .from('asistencias')
          .delete()
          .like('rut', 'TEST_QA_%');
    } catch (e) {
      // ignore: avoid_print
      print('[TestDataHelper] Error limpiando asistencias: $e');
    }

    try {
      // Limpiar stock_movimientos con local_event_id centinela si la columna existe
      // La tabla puede no tener local_event_id — envolvemos en try/catch adicional
      await svc
          .from('stock_movimientos')
          .delete()
          .like('local_event_id', '$kTestPrefix%');
    } catch (_) {
      // Columna puede no existir — silenciar
    }

    svc.dispose();
  }
}
