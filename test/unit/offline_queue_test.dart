import 'package:flutter_test/flutter_test.dart';
import 'package:epp_app/services/offline_queue_service.dart';

OfflineEntrega _entrega({
  String status = 'PENDING',
  int attempts = 0,
  int maxAttempts = 5,
  String? nextRetryAt,
}) =>
    OfflineEntrega(
      localEventId: 'evt-test-001',
      createdAtClientIso: '2026-06-01T10:00:00.000Z',
      scope: 'EPP',
      obraId: 'obra-001',
      trabajadorId: 'trab-001',
      bodegaId: 'bodega-001',
      items: [{'epp_id': 'epp-001', 'cantidad': 2}],
      evidenciaLocalPath: '/tmp/foto.jpg',
      evidenciaHash: 'abc123',
      status: status,
      attempts: attempts,
      maxAttempts: maxAttempts,
      nextRetryAt: nextRetryAt,
    );

void main() {
  group('OfflineEntrega — isFailed', () {
    test('status FAILED → isFailed=true', () {
      expect(_entrega(status: 'FAILED').isFailed, isTrue);
    });

    test('status PENDING → isFailed=false', () {
      expect(_entrega(status: 'PENDING').isFailed, isFalse);
    });

    test('status SENT → isFailed=false', () {
      expect(_entrega(status: 'SENT').isFailed, isFalse);
    });

    test('status ERROR → isFailed=false', () {
      expect(_entrega(status: 'ERROR').isFailed, isFalse);
    });
  });

  group('OfflineEntrega — isPermanentlyFailed', () {
    test('status FAILED → isPermanentlyFailed=true', () {
      expect(_entrega(status: 'FAILED').isPermanentlyFailed, isTrue);
    });

    test('attempts == maxAttempts → isPermanentlyFailed=true', () {
      expect(_entrega(attempts: 5, maxAttempts: 5).isPermanentlyFailed, isTrue);
    });

    test('attempts > maxAttempts → isPermanentlyFailed=true', () {
      expect(_entrega(attempts: 6, maxAttempts: 5).isPermanentlyFailed, isTrue);
    });

    test('attempts < maxAttempts y status PENDING → isPermanentlyFailed=false', () {
      expect(_entrega(attempts: 2, maxAttempts: 5).isPermanentlyFailed, isFalse);
    });
  });

  group('OfflineEntrega — serialización round-trip', () {
    test('toMap/fromMap conserva todos los campos', () {
      final original = _entrega(status: 'ERROR', attempts: 3, nextRetryAt: '2026-06-01T11:00:00.000Z');
      final restored = OfflineEntrega.fromMap(original.toMap());

      expect(restored.localEventId, equals(original.localEventId));
      expect(restored.status, equals(original.status));
      expect(restored.attempts, equals(original.attempts));
      expect(restored.nextRetryAt, equals(original.nextRetryAt));
      expect(restored.obraId, equals(original.obraId));
      expect(restored.items, equals(original.items));
    });

    test('items se preserva como lista de mapas', () {
      final e = _entrega();
      final r = OfflineEntrega.fromMap(e.toMap());
      expect(r.items, isA<List>());
      expect(r.items.first['epp_id'], equals('epp-001'));
      expect(r.items.first['cantidad'], equals(2));
    });
  });
}
