import 'package:flutter_test/flutter_test.dart';
import 'package:epp_app/services/forensic_service.dart';

void main() {
  group('ForensicService.hasValidGps', () {
    test('retorna true cuando lat y lng están presentes', () {
      expect(
        ForensicService.hasValidGps({'gps_lat': -38.7359, 'gps_lng': -72.5904}),
        isTrue,
      );
    });

    test('retorna false cuando el mapa es null', () {
      expect(ForensicService.hasValidGps(null), isFalse);
    });

    test('retorna false cuando gps_lat es null', () {
      expect(
        ForensicService.hasValidGps({'gps_lat': null, 'gps_lng': -72.5904}),
        isFalse,
      );
    });

    test('retorna false cuando gps_lng es null', () {
      expect(
        ForensicService.hasValidGps({'gps_lat': -38.7359, 'gps_lng': null}),
        isFalse,
      );
    });

    test('retorna false cuando el mapa está vacío', () {
      expect(ForensicService.hasValidGps({}), isFalse);
    });

    test('retorna false con clave gps_error pero sin coordenadas', () {
      expect(
        ForensicService.hasValidGps({'gps_error': 'permission_denied'}),
        isFalse,
      );
    });
  });
}
