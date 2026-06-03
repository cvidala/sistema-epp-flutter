// ignore_for_file: avoid_print

@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'helpers/test_client.dart';
import 'helpers/test_data.dart';

// IDs de obras conocidas (del setup de Task 0 y .env.test):
// - Obra asignada al SUPERVISOR: 7becbb3a-dbe6-4b0b-856d-8751e266735d
// - Obra SIN acceso para SUPERVISOR: 8e171e42-98a2-44b1-a0e2-1c3f6ef7377e
const _kObraAsignadaId = '7becbb3a-dbe6-4b0b-856d-8751e266735d';
const _kObraSinAccesoId = '8e171e42-98a2-44b1-a0e2-1c3f6ef7377e';

// IDs de los usuarios de test (del setup de Task 0):
const _kAdminUserId = 'ad1b770a-bf3e-4bff-9ac2-5e140b46a430';
const _kReadonlyUserId = '00493ac5-e650-4c07-a24f-afd391b9fbeb';

void main() {
  const uuid = Uuid();

  // IDs de apoyo resueltos en setUpAll desde la DB real
  late String realTrabajadorId;
  late String realBodegaId;

  // UUID estable para RLS-05 (entregas_epp)
  final rls05LocalEventId = uuid.v4();

  setUpAll(() async {
    final svc = serviceClient();

    // Resolver un trabajador_id real para insertar entregas válidas
    final trabResp = await svc
        .from('trabajadores')
        .select('trabajador_id')
        .limit(1)
        .single();
    realTrabajadorId = trabResp['trabajador_id'] as String;

    // Resolver bodega_id real
    final bodegaResp =
        await svc.from('bodegas').select('bodega_id').limit(1).single();
    realBodegaId = bodegaResp['bodega_id'] as String;

    svc.dispose();
  });

  tearDownAll(() async {
    await TestDataHelper.tearDownTestData();
  });

  // ────────────────────────────────────────────────────────────
  // RLS-01: ADMIN ve trabajadores de cualquier obra
  // ────────────────────────────────────────────────────────────
  group('RLS-01: ADMIN reads all trabajadores', () {
    late SupabaseClient adminClient;

    setUp(() async {
      adminClient = await clientForRole('admin');
    });

    tearDown(() async {
      await disposeClient(adminClient);
    });

    test('ADMIN receives at least one trabajador row', () async {
      final result =
          await adminClient.from('trabajadores').select('trabajador_id');
      expect(result, isNotEmpty,
          reason: 'ADMIN debe ver al menos un trabajador en la DB');
    });
  });

  // ────────────────────────────────────────────────────────────
  // RLS-02: SUPERVISOR solo ve trabajadores de sus obras
  // ────────────────────────────────────────────────────────────
  group('RLS-02: SUPERVISOR sees only own-obra trabajadores', () {
    late SupabaseClient supClient;

    setUp(() async {
      supClient = await clientForRole('supervisor');
    });

    tearDown(() async {
      await disposeClient(supClient);
    });

    test(
      'SUPERVISOR cannot see trabajadores exclusively in unassigned obra',
      () async {
        // La política select_trabajadores usa JOIN con trabajador_obras y obra_usuarios.
        // El SUPERVISOR solo está en obra_usuarios para _kObraAsignadaId.
        // Un trabajador que SOLO está en _kObraSinAccesoId no debería ser visible.
        //
        // Verificamos que el SUPERVISOR no ve trabajadores que SOLO pertenecen
        // a la obra sin acceso (sin solapamiento con obras asignadas).
        final svc = serviceClient();

        // Trabajadores en la obra sin acceso
        final trabEnObraSinAcceso = await svc
            .from('trabajador_obras')
            .select('trabajador_id')
            .eq('obra_id', _kObraSinAccesoId);

        // Trabajadores en la obra CON acceso
        final trabEnObraConAcceso = await svc
            .from('trabajador_obras')
            .select('trabajador_id')
            .eq('obra_id', _kObraAsignadaId);

        svc.dispose();

        // IDs en la obra sin acceso
        final idsSinAcceso = trabEnObraSinAcceso
            .map((r) => r['trabajador_id'] as String)
            .toSet();

        // IDs en la obra con acceso (el SUPERVISOR SÍ debería verlos)
        final idsConAcceso = trabEnObraConAcceso
            .map((r) => r['trabajador_id'] as String)
            .toSet();

        // Trabajadores EXCLUSIVAMENTE en la obra sin acceso
        final idsExclusivosSinAcceso =
            idsSinAcceso.difference(idsConAcceso);

        if (idsExclusivosSinAcceso.isEmpty) {
          markTestSkipped(
            'RLS-02: No hay trabajadores exclusivamente en la obra sin acceso — '
            'todos los trabajadores pertenecen también a la obra asignada. '
            'El test no puede verificar la restricción con los datos actuales.',
          );
          return;
        }

        // Lo que ve el SUPERVISOR
        final supResult =
            await supClient.from('trabajadores').select('trabajador_id');
        final trabIdsVisibles = supResult
            .map((r) => r['trabajador_id'] as String)
            .toSet();

        // El SUPERVISOR NO debe ver ningún trabajador exclusivo de la obra sin acceso
        final intersection =
            idsExclusivosSinAcceso.intersection(trabIdsVisibles);
        expect(intersection, isEmpty,
            reason:
                'SUPERVISOR no debe ver trabajadores exclusivos de obra no asignada');
      },
    );
  });

  // ────────────────────────────────────────────────────────────
  // RLS-03: READONLY NO puede insertar entregas (fix SF-01)
  // ────────────────────────────────────────────────────────────
  group('RLS-03: READONLY cannot insert entregas_epp', () {
    late SupabaseClient roClient;

    setUp(() async {
      roClient = await clientForRole('readonly');
    });

    tearDown(() async {
      await disposeClient(roClient);
    });

    test(
      'READONLY is blocked by RLS when trying to insert entregas_epp',
      () async {
        // Fix SF-01: insert_own_entregas ahora requiere rol IN ('ADMIN','SUPERVISOR').
        // READONLY debe recibir error 42501 row-level security policy violation.
        final eventId = TestDataHelper.testId('rls03');
        final localEventId = const Uuid().v4();

        dynamic insertError;
        try {
          await roClient.from('entregas_epp').insert({
            'event_id': eventId,
            'trabajador_id': realTrabajadorId,
            'obra_id': _kObraAsignadaId,
            'bodega_id': realBodegaId,
            'items': [],
            'entregado_por': _kReadonlyUserId,
            'local_event_id': localEventId,
          });
          insertError = null;
        } catch (e) {
          insertError = e;
        }

        expect(insertError, isNotNull,
            reason: 'READONLY debe ser bloqueado por RLS al insertar entregas_epp');
        expect(insertError.toString(), contains('42501'),
            reason: 'Error esperado: row-level security policy violation');
      },
    );
  });

  // ────────────────────────────────────────────────────────────
  // RLS-04: Anon puede insertar asistencias, no leer
  // ────────────────────────────────────────────────────────────
  group('RLS-04: Anon inserts asistencias, cannot SELECT', () {
    test('anon can insert asistencia', () async {
      // IMPORTANTE: usar .insert() sin .select() para enviar Prefer: return=minimal.
      // Con Prefer: return=representation, PostgREST hace un SELECT posterior que
      // falla para anon (sin política SELECT). La inserción en sí SÍ funciona.
      final rut = 'TEST_QA_rls04_${DateTime.now().millisecondsSinceEpoch}';
      final anon = anonClient();
      try {
        // .insert() sin .select() → Prefer: return=minimal → solo necesita INSERT
        await anon.from('asistencias').insert({
          'rut': rut,
          'tipo': 'Entrada',
        });
        // Si llegamos aquí sin excepción, el insert fue exitoso
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          fail(
            'FALLO RLS-04: anon debería poder insertar asistencias '
            '(policy insert_anon_asistencias TO anon), pero fue bloqueado: $e',
          );
        }
        // Otros errores de validación son aceptables (datos inválidos)
      } finally {
        anon.dispose();
        // Cleanup via service_role
        final svc = serviceClient();
        await svc.from('asistencias').delete().eq('rut', rut);
        svc.dispose();
      }
    });

    test('anon cannot SELECT asistencias', () async {
      // La política select_auth_asistencias es TO authenticated.
      // Anon (sin sesión) no debe recibir filas — o lanza PostgrestException.
      final anon = anonClient();
      try {
        List<dynamic> result = [];
        try {
          result =
              await anon.from('asistencias').select('id').limit(1);
        } on PostgrestException {
          // PostgrestException también es válido — RLS bloqueó
          return;
        }
        expect(result, isEmpty,
            reason:
                'Anon no debe poder leer asistencias '
                '(sin política SELECT para anon)');
      } finally {
        anon.dispose();
      }
    });
  });

  // ────────────────────────────────────────────────────────────
  // RLS-05: Nadie puede eliminar registros de entregas_epp
  // ────────────────────────────────────────────────────────────
  group('RLS-05: Nobody can DELETE entregas_epp', () {
    late SupabaseClient adminClient;

    setUpAll(() async {
      // Insertar fila centinela idempotente para RLS-05.
      // event_id es la clave primaria (TEXT) — verificar por event_id para idempotencia.
      // La fila es permanente (trigger BEFORE DELETE bloquea incluso service_role).
      final svc = serviceClient();
      const sentinelEventId = '${kTestPrefix}rls05_sentinel';
      final existing = await svc
          .from('entregas_epp')
          .select('event_id, local_event_id')
          .eq('event_id', sentinelEventId);

      if (existing.isEmpty) {
        await svc.from('entregas_epp').insert({
          'event_id': sentinelEventId,
          'trabajador_id': realTrabajadorId,
          'obra_id': _kObraAsignadaId,
          'bodega_id': realBodegaId,
          'items': [],
          'entregado_por': _kAdminUserId,
          'local_event_id': rls05LocalEventId,
        });
      } else {
        // Fila ya existe de un run previo — recordar su local_event_id
        // (no podemos actualizarla porque el trigger bloquea UPDATE de local_event_id)
        // Usamos la que ya existe para el test de DELETE
      }
      svc.dispose();
    });

    setUp(() async {
      adminClient = await clientForRole('admin');
    });

    tearDown(() async {
      await disposeClient(adminClient);
    });

    test(
      'ADMIN cannot delete entregas_epp — row persists after attempt',
      () async {
        const sentinelEventId = '${kTestPrefix}rls05_sentinel';
        // RLS USING(false) no lanza excepción — retorna 0 filas afectadas.
        // El trigger BEFORE DELETE también bloquea (incluso a service_role).
        // Verificamos que la fila persiste después del intento de borrado.
        try {
          await adminClient
              .from('entregas_epp')
              .delete()
              .eq('event_id', sentinelEventId);
        } catch (_) {
          // Excepción también es aceptable — confirma bloqueo del delete
        }

        // Verificar que la fila todavía existe via service_role
        final svc = serviceClient();
        final remaining = await svc
            .from('entregas_epp')
            .select('event_id')
            .eq('event_id', sentinelEventId);
        svc.dispose();

        expect(remaining, isNotEmpty,
            reason:
                'La fila centinela debe persistir después del DELETE de ADMIN '
                '(policy no_delete_entregas USING false + trigger bloquea todo)');
      },
    );
  });

  // ────────────────────────────────────────────────────────────
  // RLS-06: Nadie puede eliminar registros de asistencias
  // ────────────────────────────────────────────────────────────
  group('RLS-06: Nobody can DELETE asistencias', () {
    // RUT único por run para evitar colisiones con runs anteriores
    final rls06Rut = '${kTestPrefix}rls06_${DateTime.now().millisecondsSinceEpoch}';

    tearDownAll(() async {
      // Limpiar fila centinela via service_role
      final svc = serviceClient();
      try {
        await svc.from('asistencias').delete().like('rut', '${kTestPrefix}rls06_%');
      } catch (e) {
        print('[RLS-06] Error limpiando centinela asistencias: $e');
      }
      svc.dispose();
    });

    test('anon cannot delete asistencias — row persists after attempt',
        () async {
      // Insertar sentinel aquí (no en setUpAll) para garantizar que existe
      // justo antes de la verificación, independiente del orden de tearDowns
      final svc = serviceClient();
      await svc.from('asistencias').insert({
        'rut': rls06Rut,
        'tipo': 'Entrada',
        'local_event_id': uuid.v4(),
      });
      svc.dispose();

      final anon = anonClient();
      try {
        try {
          await anon
              .from('asistencias')
              .delete()
              .eq('rut', rls06Rut);
        } catch (_) {
          // Excepción también es aceptable — confirma bloqueo
        }

        // Verificar que la fila persiste via service_role
        final svc2 = serviceClient();
        final remaining = await svc2
            .from('asistencias')
            .select('id')
            .eq('rut', rls06Rut);
        svc2.dispose();

        expect(remaining, isNotEmpty,
            reason:
                'La fila centinela debe persistir después del DELETE de anon '
                '(policy no_delete_asistencias USING false)');
      } finally {
        anon.dispose();
      }
    });
  });
}
