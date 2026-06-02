// ignore_for_file: avoid_print

@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_client.dart';

// La RPC evaluar_entrega_v2 retorna:
// {
//   "accion": "WARNING" | "BLOQUEO" | "OK",
//   "errors": [...],
//   "warnings": [...],
//   "pendientes_criticos": [...],
//   "pendientes_no_criticos": [...]
// }
// Nota: el campo es "accion", NO "estado" (diferencia con la documentación del plan).
// Verificado contra la DB real 2026-06-02.

// Trabajadores de referencia:
// - Con entregas: 09e5ffb5-3da9-46a7-81c3-ec8df2b36a03 (en obra 7becbb3a)
// - Sin entregas: 0bcb4909-7e50-44fa-94de-e10b5a2e0e41
const _kObraId = '7becbb3a-dbe6-4b0b-856d-8751e266735d';
const _kTrabajadorConEntregas = '09e5ffb5-3da9-46a7-81c3-ec8df2b36a03';
const _kTrabajadorSinEntregas = '0bcb4909-7e50-44fa-94de-e10b5a2e0e41';

void main() {
  late String realEppId;

  setUpAll(() async {
    final svc = serviceClient();
    final eppResp =
        await svc.from('catalogo_epp').select('epp_id').limit(1).single();
    realEppId = eppResp['epp_id'] as String;
    svc.dispose();
  });

  // ────────────────────────────────────────────────────────────
  // TRG-05: evaluar_entrega_v2 para trabajador CON entregas previas
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-05: evaluar_entrega_v2 returns valid response for trabajador with EPP',
    () {
      test(
        'RPC completes without error and returns a Map with "accion" key',
        () async {
          final svc = serviceClient();

          // Verificar que el trabajador con entregas existe en la DB
          final entrResp = await svc
              .from('entregas_epp')
              .select('trabajador_id')
              .eq('trabajador_id', _kTrabajadorConEntregas)
              .limit(1);

          if (entrResp.isEmpty) {
            svc.dispose();
            markTestSkipped(
              'TRG-05: El trabajador $_kTrabajadorConEntregas no tiene '
              'entregas en la DB — test no es verificable.',
            );
            return;
          }

          // Llamar evaluar_entrega_v2 con lista vacía de items requeridos
          // → la función evalúa si el trabajador está al día con su EPP
          final response = await svc.rpc('evaluar_entrega_v2', params: {
            'p_trabajador_id': _kTrabajadorConEntregas,
            'p_obra_id': _kObraId,
            'p_items': [],
          });

          svc.dispose();

          expect(response, isA<Map>(),
              reason: 'TRG-05: evaluar_entrega_v2 debe retornar un Map');
          expect(response, contains('accion'),
              reason:
                  'TRG-05: La respuesta debe contener la clave "accion". '
                  'Respuesta recibida: $response');

          // accion puede ser "OK", "WARNING" o "BLOQUEO" — cualquiera es válido
          final accion = response['accion'] as String;
          expect(['OK', 'WARNING', 'BLOQUEO'], contains(accion),
              reason:
                  'TRG-05: accion debe ser OK, WARNING o BLOQUEO. '
                  'Recibido: $accion');
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────
  // TRG-06: evaluar_entrega_v2 retorna BLOQUEO para trabajador sin EPP
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-06: evaluar_entrega_v2 returns BLOQUEO for trabajador without EPP',
    () {
      test(
        'RPC returns accion=BLOQUEO when CRITICO EPP item is missing',
        () async {
          final svc = serviceClient();

          // Verificar que el trabajador sin entregas realmente no tiene entregas
          final entrResp = await svc
              .from('entregas_epp')
              .select('trabajador_id')
              .eq('trabajador_id', _kTrabajadorSinEntregas)
              .limit(1);

          final String trabId;
          if (entrResp.isNotEmpty) {
            // El trabajador ya tiene entregas — buscar uno sin entregas
            final allTrab = await svc
                .from('trabajadores')
                .select('trabajador_id');
            final trabConEntregas = (await svc
                    .from('entregas_epp')
                    .select('trabajador_id'))
                .map((e) => e['trabajador_id'] as String)
                .toSet();

            final trabSinEntregas = allTrab
                .map((t) => t['trabajador_id'] as String)
                .where((id) => !trabConEntregas.contains(id))
                .toList();

            if (trabSinEntregas.isEmpty) {
              svc.dispose();
              markTestSkipped(
                'TRG-06: No se encontró trabajador sin entregas en la DB. '
                'Test no es verificable con los datos actuales.',
              );
              return;
            }
            trabId = trabSinEntregas.first;
          } else {
            trabId = _kTrabajadorSinEntregas;
          }

          // Llamar con un item CRITICO que el trabajador no tiene
          // → la función debe retornar accion=BLOQUEO
          final response = await svc.rpc('evaluar_entrega_v2', params: {
            'p_trabajador_id': trabId,
            'p_obra_id': _kObraId,
            'p_items': [
              {
                'epp_id': realEppId,
                'cantidad': 1,
                'criticidad': 'CRITICO',
              }
            ],
          });

          svc.dispose();

          expect(response, isA<Map>(),
              reason: 'TRG-06: evaluar_entrega_v2 debe retornar un Map');
          expect(response, contains('accion'),
              reason:
                  'TRG-06: La respuesta debe contener la clave "accion". '
                  'Respuesta recibida: $response');

          final accion = response['accion'] as String;
          expect(accion, equals('BLOQUEO'),
              reason:
                  'TRG-06: Para trabajador sin EPP y item CRITICO faltante, '
                  'accion debe ser BLOQUEO (no $accion)');
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────
  // TRG-07: get_vencimientos_proximos retorna una lista
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-07: get_vencimientos_proximos returns a List via service_role',
    () {
      test(
        'RPC returns a List (empty is acceptable — no upcoming vencimientos)',
        () async {
          // Nota (RESEARCH.md Pitfall 7): get_vencimientos_proximos tiene
          // GRANT EXECUTE ... TO service_role. Usar serviceClient().
          final svc = serviceClient();

          final response =
              await svc.rpc('get_vencimientos_proximos');

          svc.dispose();

          expect(response, isA<List>(),
              reason:
                  'TRG-07: get_vencimientos_proximos debe retornar una Lista. '
                  'El tipo recibido fue: ${response.runtimeType}');
          // length >= 0 es aceptable — puede no haber vencimientos próximos
        },
      );
    },
  );
}
