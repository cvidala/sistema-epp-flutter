import 'test_client.dart';

/// Helpers de seed y limpieza para tests de integración Supabase.
///
/// Usa service_role (bypasa RLS) para limpiar datos en tablas
/// que tienen políticas USING(false) en DELETE.
///
/// NOTA: entregas_epp tiene un trigger BEFORE DELETE que bloquea
/// toda eliminación, incluso con service_role. Las filas de test en
/// esa tabla son permanentes — se usan event_id únicos con prefijo
/// centinela para evitar colisiones entre runs.
class TestDataHelper {
  TestDataHelper._();

  /// Genera un event_id de texto único con el prefijo centinela para un tag dado.
  ///
  /// Ejemplo: testId('rls03') → 'test_qa_rls03_1748000000000'
  static String testId(String tag) =>
      '$kTestPrefix${tag}_${DateTime.now().millisecondsSinceEpoch}';

  /// Genera un local_event_id UUID determinístico y único usando timestamp.
  ///
  /// Retorna siempre un UUID v4 aleatorio único para este run.
  static String testUuid() {
    // UUID v4 pseudo-aleatorio usando el timestamp actual
    final ts = DateTime.now().microsecondsSinceEpoch;
    final hex = ts.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-${hex.substring(0, 12)}';
  }

  /// Elimina todas las filas de test de las tablas críticas.
  ///
  /// - asistencias: elimina filas donde rut LIKE 'TEST_QA_%' (service_role bypasa RLS)
  /// - entregas_epp: NO se puede eliminar (trigger BEFORE DELETE bloquea incluso
  ///   a service_role). Los tests usan event_id únicos con prefijo 'test_qa_' —
  ///   estas filas permanecen en la DB pero no interfieren con datos reales.
  ///
  /// Los errores se imprimen pero no re-lanzan (tearDown no debe fallar
  /// el test suite por errores de limpieza).
  static Future<void> tearDownTestData() async {
    final svc = serviceClient();

    try {
      // Limpiar asistencias de test (identificadas por rut centinela)
      // service_role bypasa la política USING(false) en asistencias
      await svc
          .from('asistencias')
          .delete()
          .like('rut', 'TEST_QA_%');
    } catch (e) {
      // ignore: avoid_print
      print('[TestDataHelper] Error limpiando asistencias: $e');
    }

    // entregas_epp: el trigger BEFORE DELETE bloquea incluso a service_role.
    // No intentar eliminar — las filas de test son permanentes pero inofensivas.
    // Se identifican por event_id comenzando con 'test_qa_'.

    svc.dispose();
  }
}
