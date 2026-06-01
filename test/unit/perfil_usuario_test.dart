import 'package:flutter_test/flutter_test.dart';
import 'package:epp_app/services/auth_service.dart';

PerfilUsuario _perfil(String rol, {ConfigModulos? modulos}) => PerfilUsuario(
      userId: 'uid-test',
      nombre: 'Test User',
      rol: rol,
      orgId: 'org-test',
      modulos: modulos,
    );

void main() {
  group('PerfilUsuario — roles', () {
    test('ADMIN: isAdmin=true, isSupervisor=false, isReadonly=false', () {
      final p = _perfil('ADMIN');
      expect(p.isAdmin, isTrue);
      expect(p.isSupervisor, isFalse);
      expect(p.isReadonly, isFalse);
    });

    test('SUPERVISOR: isAdmin=false, isSupervisor=true, isReadonly=false', () {
      final p = _perfil('SUPERVISOR');
      expect(p.isAdmin, isFalse);
      expect(p.isSupervisor, isTrue);
      expect(p.isReadonly, isFalse);
    });

    test('READONLY: isAdmin=false, isSupervisor=false, isReadonly=true', () {
      final p = _perfil('READONLY');
      expect(p.isAdmin, isFalse);
      expect(p.isSupervisor, isFalse);
      expect(p.isReadonly, isTrue);
    });
  });

  group('PerfilUsuario — canWrite', () {
    test('ADMIN puede escribir', () => expect(_perfil('ADMIN').canWrite, isTrue));
    test('SUPERVISOR puede escribir', () => expect(_perfil('SUPERVISOR').canWrite, isTrue));
    test('READONLY no puede escribir', () => expect(_perfil('READONLY').canWrite, isFalse));
  });

  group('PerfilUsuario — canManageSystem', () {
    test('ADMIN puede administrar el sistema', () => expect(_perfil('ADMIN').canManageSystem, isTrue));
    test('SUPERVISOR no puede administrar el sistema', () => expect(_perfil('SUPERVISOR').canManageSystem, isFalse));
    test('READONLY no puede administrar el sistema', () => expect(_perfil('READONLY').canManageSystem, isFalse));
  });

  group('ConfigModulos — defaults', () {
    test('defaults: epp=true, asistencia=false, prevencion=false, reportes=true', () {
      final m = ConfigModulos.defaults();
      expect(m.epp, isTrue);
      expect(m.asistencia, isFalse);
      expect(m.prevencion, isFalse);
      expect(m.reportes, isTrue);
    });

    test('fromJson respeta valores del JSON', () {
      final m = ConfigModulos.fromJson({
        'epp': false,
        'asistencia': true,
        'prevencion': true,
        'reportes': false,
      });
      expect(m.epp, isFalse);
      expect(m.asistencia, isTrue);
      expect(m.prevencion, isTrue);
      expect(m.reportes, isFalse);
    });

    test('fromJson con JSON vacío usa defaults', () {
      final m = ConfigModulos.fromJson({});
      expect(m.epp, isTrue);
      expect(m.asistencia, isFalse);
    });

    test('toJson round-trip conserva valores', () {
      final original = ConfigModulos(epp: true, asistencia: true, prevencion: false, reportes: true);
      final restored = ConfigModulos.fromJson(original.toJson());
      expect(restored.epp, equals(original.epp));
      expect(restored.asistencia, equals(original.asistencia));
      expect(restored.prevencion, equals(original.prevencion));
      expect(restored.reportes, equals(original.reportes));
    });
  });

  group('PerfilUsuario — módulos', () {
    test('moduloEpp expone el valor del módulo EPP', () {
      final p = _perfil('ADMIN', modulos: const ConfigModulos(epp: false));
      expect(p.moduloEpp, isFalse);
    });

    test('moduloAsistencia expone el valor del módulo asistencia', () {
      final p = _perfil('ADMIN', modulos: const ConfigModulos(asistencia: true));
      expect(p.moduloAsistencia, isTrue);
    });
  });

  group('AuthService — cargarPerfilDesdeCache', () {
    test('carga perfil desde datos cacheados con rol correcto', () {
      AuthService.instance.cargarPerfilDesdeCache({
        'user_id': 'uid-abc',
        'nombre': 'Carlos Vidal',
        'rol': 'ADMIN',
        'org_id': 'org-xyz',
      });
      final p = AuthService.instance.perfil;
      expect(p, isNotNull);
      expect(p!.nombre, equals('Carlos Vidal'));
      expect(p.isAdmin, isTrue);
      expect(p.orgId, equals('org-xyz'));
    });

    test('limpiar() borra el perfil cacheado', () {
      AuthService.instance.cargarPerfilDesdeCache({'user_id': 'x', 'nombre': 'X', 'rol': 'ADMIN', 'org_id': 'o'});
      AuthService.instance.limpiar();
      expect(AuthService.instance.perfil, isNull);
    });

    test('datos faltantes en caché usan valores por defecto seguros', () {
      AuthService.instance.cargarPerfilDesdeCache({});
      final p = AuthService.instance.perfil!;
      expect(p.rol, equals('READONLY'));
      expect(p.canWrite, isFalse);
    });
  });
}
