// ignore_for_file: avoid_print

@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'helpers/test_client.dart';
import 'helpers/test_data.dart';

// IDs de referencia
const _kObraId = '7becbb3a-dbe6-4b0b-856d-8751e266735d';
const _kAdminUserId = 'ad1b770a-bf3e-4bff-9ac2-5e140b46a430';

void main() {
  late String realBodegaId;
  late String realEppId;
  late String realTrabajadorId;
  late String realAdminUserId;

  setUpAll(() async {
    final svc = serviceClient();

    // Obtener IDs reales para los tests
    final bodegaResp =
        await svc.from('bodegas').select('bodega_id').limit(1).single();
    realBodegaId = bodegaResp['bodega_id'] as String;

    final eppResp =
        await svc.from('catalogo_epp').select('epp_id').limit(1).single();
    realEppId = eppResp['epp_id'] as String;

    final trabResp =
        await svc.from('trabajadores').select('trabajador_id').limit(1).single();
    realTrabajadorId = trabResp['trabajador_id'] as String;

    // Usar el admin de test como created_by en stock_movimientos
    realAdminUserId = _kAdminUserId;

    svc.dispose();
  });

  tearDownAll(() async {
    await TestDataHelper.tearDownTestData();
  });

  // ────────────────────────────────────────────────────────────
  // TRG-01: trg_prevent_stock_negativo bloquea SALIDA con stock=0
  // ────────────────────────────────────────────────────────────
  group('TRG-01: trg_prevent_stock_negativo blocks SALIDA with no stock', () {
    test(
      'SALIDA of 1 unit with zero prior stock raises Stock insuficiente',
      () async {
        // Buscar una combinación (bodega, epp) donde el stock neto sea 0.
        // Se calcula sumando ENTRADAs y restando SALIDAs.
        // Si ninguna combinación tiene stock=0, intentamos crear una nueva con
        // una bodega y EPP que sabemos no tienen historial o buscamos la que
        // tenga balance = 0.
        final svc = serviceClient();

        // Calcular stock actual por (bodega_id, epp_id)
        final movimientos = await svc
            .from('stock_movimientos')
            .select('bodega_id, epp_id, tipo, cantidad');

        // Agrupar por (bodega, epp) y calcular stock neto
        final stockMap = <String, int>{};
        for (final mov in movimientos) {
          final key = '${mov['bodega_id']}|${mov['epp_id']}';
          final cantidad = (mov['cantidad'] as num).toInt();
          final delta = mov['tipo'] == 'ENTRADA' ? cantidad : -cantidad;
          stockMap[key] = (stockMap[key] ?? 0) + delta;
        }

        // Buscar combo con stock = 0
        String? testBodegaId;
        String? testEppId;
        for (final entry in stockMap.entries) {
          if (entry.value == 0) {
            final parts = entry.key.split('|');
            testBodegaId = parts[0];
            testEppId = parts[1];
            break;
          }
        }

        // Si no hay combo con stock=0, usar una combinación completamente nueva
        // que no tiene historial (stock implícito = 0)
        if (testBodegaId == null) {
          // Buscar epp_id que no aparezca en stock_movimientos para la bodega real
          final eppsUsados = movimientos
              .where((m) => m['bodega_id'] == realBodegaId)
              .map((m) => m['epp_id'] as String)
              .toSet();

          final allEpps = await svc.from('catalogo_epp').select('epp_id');
          final eppSinHistorial = allEpps
              .map((e) => e['epp_id'] as String)
              .where((id) => !eppsUsados.contains(id))
              .toList();

          if (eppSinHistorial.isEmpty) {
            svc.dispose();
            markTestSkipped(
              'TRG-01: No se encontró combinación (bodega,epp) con stock=0. '
              'Todos los EPPs tienen movimientos con stock > 0. '
              'Test no es verificable con los datos actuales.',
            );
            return;
          }

          testBodegaId = realBodegaId;
          testEppId = eppSinHistorial.first;
        }

        svc.dispose();

        // Intentar SALIDA con stock=0 — debe fallar con "Stock insuficiente"
        final svc2 = serviceClient();
        Object? caughtError;
        try {
          await svc2.from('stock_movimientos').insert({
            'bodega_id': testBodegaId,
            'epp_id': testEppId,
            'tipo': 'SALIDA',
            'cantidad': 1,
            'created_by': realAdminUserId,
          });
        } catch (e) {
          caughtError = e;
        } finally {
          svc2.dispose();
        }

        expect(caughtError, isA<PostgrestException>(),
            reason: 'TRG-01: SALIDA con stock=0 debe lanzar PostgrestException');

        final ex = caughtError as PostgrestException;
        expect(ex.message, contains('Stock insuficiente'),
            reason: 'TRG-01: El mensaje debe contener "Stock insuficiente"');
      },
    );
  });

  // ────────────────────────────────────────────────────────────
  // TRG-02: trg_prevent_stock_negativo permite SALIDA con stock suficiente
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-02: trg_prevent_stock_negativo allows SALIDA with sufficient stock',
    () {
      // IDs dinámicos — se asignan en setUpAll del grupo
      late String trg02BodegaId;
      late String trg02EppId;

      setUpAll(() async {
        // Buscar o crear una combinación limpia para TRG-02.
        // Preferimos un EPP sin historial para evitar interferencia con otros tests.
        final svc = serviceClient();

        final movimientos = await svc
            .from('stock_movimientos')
            .select('bodega_id, epp_id');
        final usedCombos = movimientos
            .map((m) => '${m['bodega_id']}|${m['epp_id']}')
            .toSet();

        final allEpps =
            await svc.from('catalogo_epp').select('epp_id');
        final bodega = realBodegaId;

        // Buscar EPP sin historial en esta bodega
        final eppSinHistorial = allEpps
            .map((e) => e['epp_id'] as String)
            .where((id) => !usedCombos.contains('$bodega|$id'))
            .toList();

        if (eppSinHistorial.isEmpty) {
          // Todos tienen historial — usar realEppId pero con balance compensado
          // El test manejará el estado inicial
          trg02BodegaId = bodega;
          trg02EppId = realEppId;
        } else {
          trg02BodegaId = bodega;
          trg02EppId = eppSinHistorial.first;
        }

        svc.dispose();
      });

      test('SALIDA succeeds after ENTRADA of equal or greater quantity',
          () async {
        final svc = serviceClient();

        // Paso 1: ENTRADA de 10 unidades para garantizar stock suficiente
        // (stock actual irrelevante — 10 ENTRADA siempre permite SALIDA de 5)
        await svc.from('stock_movimientos').insert({
          'bodega_id': trg02BodegaId,
          'epp_id': trg02EppId,
          'tipo': 'ENTRADA',
          'cantidad': 10,
          'created_by': realAdminUserId,
          'motivo': '${kTestPrefix}trg02_entrada',
        });

        // Paso 2: SALIDA de 5 unidades — debe tener éxito (stock = 10)
        Object? saliErrorr;
        try {
          await svc.from('stock_movimientos').insert({
            'bodega_id': trg02BodegaId,
            'epp_id': trg02EppId,
            'tipo': 'SALIDA',
            'cantidad': 5,
            'created_by': realAdminUserId,
            'motivo': '${kTestPrefix}trg02_salida',
          });
        } catch (e) {
          saliErrorr = e;
        }

        expect(saliErrorr, isNull,
            reason:
                'TRG-02: SALIDA con stock suficiente NO debe lanzar excepción. '
                'Error encontrado: $saliErrorr');

        // Paso 3: Compensar — insertar SALIDA de 5 más para restaurar balance
        // El stock queda en: stockActual + 10 - 5 - 5 = stockActual
        // Esto hace el test idempotente
        try {
          await svc.from('stock_movimientos').insert({
            'bodega_id': trg02BodegaId,
            'epp_id': trg02EppId,
            'tipo': 'SALIDA',
            'cantidad': 5,
            'created_by': realAdminUserId,
            'motivo': '${kTestPrefix}trg02_compensacion',
          });
        } catch (e) {
          print('[TRG-02] Warning: compensating SALIDA failed: $e');
        }

        svc.dispose();
      });
    },
  );

  // ────────────────────────────────────────────────────────────
  // TRG-03: trg_entregas_epp_immutable bloquea UPDATE de items
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-03: trg_entregas_epp_immutable blocks UPDATE of items field',
    () {
      late String insertedEventId;

      setUp(() async {
        // Insertar una entrega de test para luego intentar actualizarla
        insertedEventId = TestDataHelper.testId('trg03');
        final svc = serviceClient();
        await svc.from('entregas_epp').insert({
          'event_id': insertedEventId,
          'trabajador_id': realTrabajadorId,
          'obra_id': _kObraId,
          'bodega_id': realBodegaId,
          'items': [],
          'entregado_por': realAdminUserId,
          'local_event_id': const Uuid().v4(),
        });
        svc.dispose();
      });

      // No tearDown para entregas — el trigger BEFORE DELETE bloquea incluso service_role.
      // Las filas de test con event_id 'test_qa_*' son permanentes pero inofensivas.

      test(
        'UPDATE of items field throws PostgrestException containing "Campo inmutable"',
        () async {
          final svc = serviceClient();
          Object? caughtError;
          try {
            await svc
                .from('entregas_epp')
                .update({'items': '[{"epp_id":"test"}]'})
                .eq('event_id', insertedEventId);
          } catch (e) {
            caughtError = e;
          } finally {
            svc.dispose();
          }

          expect(caughtError, isA<PostgrestException>(),
              reason: 'TRG-03: UPDATE de items debe lanzar PostgrestException');

          final ex = caughtError as PostgrestException;
          expect(ex.message, contains('Campo inmutable'),
              reason: 'TRG-03: El mensaje debe contener "Campo inmutable"');
        },
      );
    },
  );

  // ────────────────────────────────────────────────────────────
  // TRG-04: trg_audit_entregas_epp escribe a audit_log en INSERT
  // ────────────────────────────────────────────────────────────
  group(
    'TRG-04: trg_audit_entregas_epp writes to audit_log on INSERT',
    () {
      late String insertedEventId;

      setUp(() async {
        insertedEventId = TestDataHelper.testId('trg04');
        final svc = serviceClient();
        await svc.from('entregas_epp').insert({
          'event_id': insertedEventId,
          'trabajador_id': realTrabajadorId,
          'obra_id': _kObraId,
          'bodega_id': realBodegaId,
          'items': [],
          'entregado_por': realAdminUserId,
          'local_event_id': const Uuid().v4(),
        });
        svc.dispose();
      });

      test(
        'INSERT into entregas_epp creates audit_log row with tabla=entregas_epp',
        () async {
          // La función fn_audit_log usa row_to_json(NEW)->>'id' para registro_id.
          // Como entregas_epp no tiene columna 'id' (PK es event_id),
          // registro_id será NULL. Buscamos el log por event_id en datos_nuevos.
          final svc = serviceClient();
          final auditRows = await svc
              .from('audit_log')
              .select('id, tabla, operacion, registro_id, datos_nuevos')
              .eq('tabla', 'entregas_epp')
              .eq('operacion', 'INSERT')
              .like('datos_nuevos->>event_id', insertedEventId);

          svc.dispose();

          expect(auditRows, isNotEmpty,
              reason:
                  'TRG-04: audit_log debe tener al menos 1 fila para el INSERT '
                  'en entregas_epp con event_id=$insertedEventId');

          // Verificar estructura del registro de auditoría
          final auditRow = auditRows.first;
          expect(auditRow['tabla'], equals('entregas_epp'));
          expect(auditRow['operacion'], equals('INSERT'));
        },
      );
    },
  );
}
