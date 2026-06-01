import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:epp_app/evidence_service.dart';

/// Reimplementación inline de la lógica de _canonicalJson de SyncService.
/// No se importa SyncService para mantener sus internos privados.
String _canonicalJson(Map<String, dynamic> m) {
  final keys = m.keys.toList()..sort();
  final out = <String, dynamic>{};
  for (final k in keys) {
    out[k] = m[k];
  }
  return jsonEncode(out);
}

void main() {
  group('Hash chain — UTL-01', () {
    const payload1 = {
      'device_id': 'device-test',
      'local_event_id': 'evt-001',
      'obra_id': 'obra-001',
    };
    const payload2 = {
      'device_id': 'device-test',
      'local_event_id': 'evt-002',
      'obra_id': 'obra-001',
    };

    test('canonicalJson ordena claves alfabéticamente', () {
      final result = _canonicalJson({'z': 1, 'a': 2});
      expect(result, equals('{"a":2,"z":1}'));
    });

    test('hash de primera entrega es determinístico', () {
      final h1a = EvidenceService.hashString('|${_canonicalJson(payload1)}');
      final h1b = EvidenceService.hashString('|${_canonicalJson(payload1)}');
      expect(h1a, isNotEmpty);
      expect(h1a, equals(h1b));
    });

    test('hash chain: hash2 usa hash1 como prev_hash', () {
      final h1 = EvidenceService.hashString('|${_canonicalJson(payload1)}');
      final h2 = EvidenceService.hashString('$h1|${_canonicalJson(payload2)}');
      expect(h2, isNot(equals(h1)));
    });

    test('prev_hash incorrecto produce hash diferente', () {
      final h1 = EvidenceService.hashString('|${_canonicalJson(payload1)}');
      final actualH2 = EvidenceService.hashString('$h1|${_canonicalJson(payload2)}');
      final wrongH2 = EvidenceService.hashString('hash-incorrecto|${_canonicalJson(payload2)}');
      expect(wrongH2, isNot(equals(actualH2)));
    });
  });
}
