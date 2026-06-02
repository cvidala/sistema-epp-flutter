// E2E-05: Dashboard stock verificado via DB query.
//
// This test queries stock_movimientos for SALIDA rows with referencia_event_id
// starting with 'EPP-SYNC-test_e2e_', verifying that at least one delivery
// from E2E-02/E2E-03 has been synced and created a stock movement record.
//
// Run with:
//   export $(cat .env.test | xargs) && flutter test integration_test/dashboard_test.dart -d macos --tags e2e --reporter expanded
//
// NOTE: This test depends on E2E-02 or E2E-03 having run first to seed
// stock_movimientos with SALIDA rows.

@Tags(['e2e'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Relative path to serviceClient from Phase 2 infrastructure
import '../test/integration/supabase/helpers/test_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // No service init needed — this test uses serviceClient() directly
  // which reads SUPABASE_SERVICE_ROLE_KEY from Platform.environment

  group('E2E-05: Dashboard stock verificado via DB', () {
    test(
      'stock_movimientos contiene SALIDA de entrega test_e2e_ después de sync',
      () async {
        debugPrint(
            '[E2ETest] E2E-05: querying stock_movimientos for test_e2e_ SALIDA rows');

        // serviceClient() lanza StateError si SUPABASE_SERVICE_ROLE_KEY no está definida
        final svc = serviceClient();

        final rows = await svc
            .from('stock_movimientos')
            .select('tipo, referencia_event_id')
            .eq('tipo', 'SALIDA')
            .like('referencia_event_id', 'EPP-SYNC-test_e2e_%');

        svc.dispose();

        debugPrint('[E2ETest] E2E-05: found ${rows.length} SALIDA row(s)');

        expect(
          rows,
          isNotEmpty,
          reason:
              'No se encontraron filas SALIDA con referencia_event_id EPP-SYNC-test_e2e_*. '
              'Los tests E2E-02 o E2E-03 deben ejecutarse primero para sembrar stock_movimientos.',
        );

        debugPrint('[E2ETest] E2E-05: PASS — SALIDA row(s) found in stock_movimientos');
      },
    );
  });
}
