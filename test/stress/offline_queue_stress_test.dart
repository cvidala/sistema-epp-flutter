@Tags(['stress'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:epp_app/services/offline_queue_service.dart';

OfflineEntrega _entrega({
  String localEventId = 'evt-test-001',
  String createdAt = '2026-06-01T10:00:00.000Z',
  String status = 'PENDING',
  int attempts = 0,
  int maxAttempts = 5,
  String? nextRetryAt,
}) =>
    OfflineEntrega(
      localEventId: localEventId,
      createdAtClientIso: createdAt,
      scope: 'EPP',
      obraId: 'obra-001',
      trabajadorId: 'trab-001',
      bodegaId: 'bodega-001',
      items: [
        {'epp_id': 'epp-001', 'cantidad': 2}
      ],
      evidenciaLocalPath: '/tmp/foto.jpg',
      evidenciaHash: 'abc123',
      status: status,
      attempts: attempts,
      maxAttempts: maxAttempts,
      nextRetryAt: nextRetryAt,
    );

void main() {
  group('STR-01 — volumen 200 items', () {
    setUp(() async {
      await setUpTestHive();
      await OfflineQueueService.init();
    });

    tearDown(() async {
      await tearDownTestHive();
    });

    test(
        'encolar 200 entregas devuelve exactamente 200 registros sin duplicados',
        () async {
      final base = DateTime.utc(2026, 6, 1, 10, 0, 0);

      for (var i = 0; i < 200; i++) {
        final ts = base.add(Duration(seconds: i)).toIso8601String();
        await OfflineQueueService.enqueue(
          _entrega(localEventId: 'evt-$i', createdAt: ts),
        );
      }

      final all = OfflineQueueService.listAll();
      expect(all.length, equals(200));

      final ids = all.map((e) => e.localEventId).toSet();
      expect(ids.length, equals(200));
    });
  });

  group('STR-02 — concurrencia 20 enqueues', () {
    setUp(() async {
      await setUpTestHive();
      await OfflineQueueService.init();
    });

    tearDown(() async {
      await tearDownTestHive();
    });

    test(
        '20 enqueues simultáneos via Future.wait resultan en 20 registros sin duplicados',
        () async {
      final base = DateTime.utc(2026, 6, 1, 10, 0, 0);

      await Future.wait(
        List.generate(20, (i) {
          final ts = base.add(Duration(seconds: i)).toIso8601String();
          return OfflineQueueService.enqueue(
            _entrega(localEventId: 'evt-conc-$i', createdAt: ts),
          );
        }),
      );

      final all = OfflineQueueService.listAll();
      expect(all.length, equals(20));

      final ids = all.map((e) => e.localEventId).toSet();
      expect(ids.length, equals(20));
    });
  });

  group('STR-03 — filtro backoff bajo carga', () {
    setUp(() async {
      await setUpTestHive();
      await OfflineQueueService.init();
    });

    tearDown(() async {
      await tearDownTestHive();
    });

    test(
        'con 50 items (30 PENDING + 15 ERROR-future + 5 ERROR-past), '
        'listPending devuelve 35 en orden cronológico',
        () async {
      final base = DateTime.utc(2026, 6, 1, 8, 0, 0);
      final futureRetry =
          DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      final pastRetry =
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

      // 30 PENDING — segundos 0..29
      for (var i = 0; i < 30; i++) {
        final ts = base.add(Duration(seconds: i)).toIso8601String();
        await OfflineQueueService.enqueue(
          _entrega(
            localEventId: 'evt-pending-$i',
            createdAt: ts,
            status: 'PENDING',
          ),
        );
      }

      // 15 ERROR-future — segundos 30..44 (excluidos por backoff)
      for (var i = 0; i < 15; i++) {
        final ts = base.add(Duration(seconds: 30 + i)).toIso8601String();
        await OfflineQueueService.enqueue(
          _entrega(
            localEventId: 'evt-err-future-$i',
            createdAt: ts,
            status: 'ERROR',
            nextRetryAt: futureRetry,
          ),
        );
      }

      // 5 ERROR-past — segundos 45..49 (incluidos)
      for (var i = 0; i < 5; i++) {
        final ts = base.add(Duration(seconds: 45 + i)).toIso8601String();
        await OfflineQueueService.enqueue(
          _entrega(
            localEventId: 'evt-err-past-$i',
            createdAt: ts,
            status: 'ERROR',
            nextRetryAt: pastRetry,
          ),
        );
      }

      final pending = OfflineQueueService.listPending();

      // Exactamente 35 (30 PENDING + 5 ERROR-past)
      expect(pending.length, equals(35));

      // Ningún ERROR-future debe aparecer
      expect(
        pending.where((e) => e.localEventId.startsWith('evt-err-future')).isEmpty,
        isTrue,
      );

      // Verificar orden cronológico ascendente
      final sorted = [...pending]
        ..sort((a, b) => a.createdAtClientIso.compareTo(b.createdAtClientIso));
      expect(
        pending.map((e) => e.localEventId).toList(),
        equals(sorted.map((e) => e.localEventId).toList()),
      );
    });
  });
}
