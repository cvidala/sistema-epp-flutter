// E2E-04: Kiosko de asistencia — AsistenciaApp pumps RutInputScreen.
//
// Run with:
//   export $(cat .env.test | xargs) && flutter test integration_test/kiosko_test.dart -d macos --tags e2e --reporter expanded
//
// NOTE: This test does NOT tap the rut_submit button. Tapping would trigger
// _marcar() → CameraCaptureScreen → ForensicService.capture() (GPS),
// all of which throw MissingPluginException on macOS. The test stops at
// the state where RUT is entered and the button is present and enabled.

@Tags(['e2e'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:epp_app/main_asistencia.dart' show AsistenciaApp;
import 'package:epp_app/asistencia/screens/rut_input_screen.dart';

import 'helpers/test_setup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    debugPrint('[E2ETest] E2E-04 setUpAll — initializing Asistencia services');
    await initServicesAsistencia();
  });

  tearDownAll(() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  });

  group('E2E-04: Kiosko asistencia', () {
    testWidgets(
      'AsistenciaApp carga RutInputScreen al iniciar',
      (tester) async {
        debugPrint('[E2ETest] E2E-04a: pumping AsistenciaApp');

        await tester.pumpWidget(const AsistenciaApp());
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(
          find.byType(RutInputScreen),
          findsOneWidget,
          reason: 'RutInputScreen debe ser la pantalla inicial de AsistenciaApp',
        );

        debugPrint('[E2ETest] E2E-04a: PASS — RutInputScreen found');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    testWidgets(
      'RUT válido activa botón Marcar Asistencia (rut_submit enabled)',
      (tester) async {
        debugPrint('[E2ETest] E2E-04b: entering RUT and checking submit button');

        await tester.pumpWidget(const AsistenciaApp());
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Ingresar un RUT que pase _validarFormato (estructura válida)
        // '12345678-9' tiene formato correcto: cuerpo 1-8 dígitos + DV dígito o K
        await tester.enterText(
          find.byKey(const ValueKey('rut_field')),
          '12345678-9',
        );
        await tester.pump(const Duration(milliseconds: 300));

        // El botón Marcar Asistencia debe estar habilitado (onPressed != null)
        // cuando _cargando es false (estado inicial) y hay texto en el campo
        final btn = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('rut_submit')),
        );
        expect(
          btn.onPressed,
          isNotNull,
          reason:
              'El botón rut_submit debe estar habilitado (onPressed != null) '
              'cuando _cargando es false',
        );

        // NOTA: No tocamos el botón — _marcar() navegaría a CameraCaptureScreen
        // que lanza MissingPluginException en macOS (sin cámara física).

        debugPrint('[E2ETest] E2E-04b: PASS — rut_submit button enabled');
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
