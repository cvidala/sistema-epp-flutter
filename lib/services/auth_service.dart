import 'package:supabase_flutter/supabase_flutter.dart';

import 'sentry_config.dart';

/// Configuración de módulos habilitados para la organización.
/// Las claves siguen el contrato unificado MIRA/JSV.
///
/// Contrato canónico = 9 llaves booleanas en organizaciones.config_modulos:
/// gestion_epp, marcaje_asistencia, stock_bodega, solicitudes_epp, firma_digital,
/// reportes_dt, dashboard, prevencion, contratos. El gating fino (por sección)
/// vive en el dashboard web; la app móvil hoy solo consume `gestion_epp` (gatea el
/// botón "Entregar EPP"). Se lee del snapshot (offline-safe), no de la consulta viva.
class ConfigModulos {
  final bool gestionEpp;    // key MIRA: gestion_epp
  final bool asistencia;
  final bool prevencion;
  final bool dashboard;     // key MIRA: dashboard

  const ConfigModulos({
    this.gestionEpp  = true,
    this.asistencia  = false,
    this.prevencion  = false,
    this.dashboard   = true,
  });

  factory ConfigModulos.fromJson(Map<String, dynamic> json) {
    return ConfigModulos(
      // fallback a claves legacy ('epp', 'reportes') para datos Supabase existentes
      gestionEpp:  ((json['gestion_epp'] ?? json['epp'])      ?? true)  as bool,
      asistencia:  (json['asistencia']                         ?? false) as bool,
      prevencion:  (json['prevencion']                         ?? false) as bool,
      dashboard:   ((json['dashboard']   ?? json['reportes'])  ?? true)  as bool,
    );
  }

  /// Configuración por defecto — todos los módulos base habilitados
  factory ConfigModulos.defaults() => const ConfigModulos(
    gestionEpp: true, asistencia: false, prevencion: false, dashboard: true,
  );

  Map<String, dynamic> toJson() => {
    'gestion_epp': gestionEpp,
    'asistencia':  asistencia,
    'prevencion':  prevencion,
    'dashboard':   dashboard,
  };

  @override
  String toString() => 'ConfigModulos(gestion_epp:$gestionEpp, asistencia:$asistencia, '
      'prevencion:$prevencion, dashboard:$dashboard)';
}

/// Perfil del usuario autenticado.
/// Se carga una vez al hacer login y se cachea en memoria.
class PerfilUsuario {
  final String userId;
  final String nombre;
  final String rol; // 'ADMIN' | 'SUPERVISOR' | 'READONLY'
  final String orgId;
  final String rutEmpresa; // RUT de la organización — usado para verificar suscripción MIRA
  final String razonSocial; // Nombre legal de la empresa
  final ConfigModulos modulos;

  const PerfilUsuario({
    required this.userId,
    required this.nombre,
    required this.rol,
    required this.orgId,
    required this.rutEmpresa,
    this.razonSocial = '',
    ConfigModulos? modulos,
  }) : modulos = modulos ?? const ConfigModulos();

  bool get isAdmin      => rol == 'ADMIN';
  bool get isSupervisor => rol == 'SUPERVISOR';
  bool get isReadonly   => rol == 'READONLY';

  /// Puede entregar EPP y manejar stock
  bool get canWrite => rol == 'ADMIN' || rol == 'SUPERVISOR';

  /// Puede crear/editar centros de trabajo, usuarios y reglas
  bool get canManageSystem => rol == 'ADMIN';

  /// Shortcuts de módulos — claves unificadas con contrato MIRA/JSV
  bool get moduloGestionEpp  => modulos.gestionEpp;
  bool get moduloAsistencia  => modulos.asistencia;
  bool get moduloPrevencion  => modulos.prevencion;
  bool get moduloDashboard   => modulos.dashboard;

  @override
  String toString() => 'PerfilUsuario($nombre, $rol, org:$orgId)';
}

/// Servicio singleton que carga y cachea el perfil del usuario actual.
///
/// Uso:
///   await AuthService.instance.cargarPerfil();
///   final perfil = AuthService.instance.perfil;
///   if (perfil?.canWrite == true) { ... }
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  PerfilUsuario? _perfil;

  /// Perfil cargado. Null si no hay sesión o aún no se cargó.
  PerfilUsuario? get perfil => _perfil;

  /// Carga el perfil desde Supabase y lo cachea en memoria.
  /// Lanza [PerfilNoEncontradoException] si el usuario no tiene perfil.
  Future<PerfilUsuario> cargarPerfil() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _perfil = null;
      throw const PerfilNoEncontradoException(
          'No hay usuario autenticado.');
    }

    // Cargamos perfil + config_modulos + rut + razon_social de la organización
    final data = await supabase
        .from('perfiles')
        .select('nombre, rol, org_id, organizaciones(config_modulos, rut, razon_social)')
        .eq('user_id', userId)
        .eq('activo', true)
        .maybeSingle();

    if (data == null) {
      _perfil = null;
      throw const PerfilNoEncontradoException(
          'Tu usuario no tiene perfil asignado. Contacta al administrador.');
    }

    // Parsear config_modulos y rut desde la org relacionada
    ConfigModulos modulos = ConfigModulos.defaults();
    String rutEmpresa = '';
    String razonSocial = '';
    final orgData = data['organizaciones'];
    if (orgData is Map) {
      if (orgData['config_modulos'] is Map) {
        modulos = ConfigModulos.fromJson(
          Map<String, dynamic>.from(orgData['config_modulos'] as Map),
        );
      }
      rutEmpresa  = (orgData['rut']          as String?) ?? '';
      razonSocial = (orgData['razon_social'] as String?) ?? '';
    }

    _perfil = PerfilUsuario(
      userId:      userId,
      nombre:      data['nombre'] as String,
      rol:         data['rol']    as String,
      orgId:       data['org_id'] as String,
      rutEmpresa:  rutEmpresa,
      razonSocial: razonSocial,
      modulos:     modulos,
    );

    // Etiquetar Sentry con empresa/rol (sin PII de personas) para filtrar
    // errores por cliente. No-op si Sentry está deshabilitado (debug).
    SentryConfig.setUsuario(
      orgId: _perfil!.orgId,
      rol: _perfil!.rol,
      empresa: _perfil!.razonSocial,
    );

    return _perfil!;
  }

  /// Carga las obras a las que tiene acceso el usuario.
  /// - ADMIN: todas las obras
  /// - SUPERVISOR/READONLY: solo obras en obra_usuarios
  Future<List<Map<String, dynamic>>> cargarObras() async {
    final supabase = Supabase.instance.client;

    // El RLS en la tabla 'obras' ya filtra automáticamente
    // según can_access_obra(). Solo hacemos el SELECT.
    final data = await supabase
        .from('obras')
        .select()
        .order('created_at')
        .timeout(const Duration(seconds: 12));

    return List<Map<String, dynamic>>.from(data);
  }

  /// Verifica si el usuario actual puede escribir en una obra específica.
  /// Usa obra_usuarios si no es ADMIN.
  Future<bool> canWriteObra(String obraId) async {
    if (_perfil == null) return false;
    if (_perfil!.isAdmin) return true;
    if (_perfil!.isReadonly) return false;

    // SUPERVISOR: verificar membresía en obra_usuarios
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final result = await supabase
        .from('obra_usuarios')
        .select('rol_obra')
        .eq('obra_id', obraId)
        .eq('user_id', userId)
        .maybeSingle();

    return result != null && result['rol_obra'] == 'SUPERVISOR';
  }

  /// Limpia el perfil cacheado (llamar al hacer logout).
  /// Carga el perfil desde datos cacheados localmente (uso offline).
  void cargarPerfilDesdeCache(Map<String, dynamic> data) {
    ConfigModulos modulos = ConfigModulos.defaults();
    if (data['config_modulos'] is Map) {
      modulos = ConfigModulos.fromJson(
        Map<String, dynamic>.from(data['config_modulos'] as Map),
      );
    }
    _perfil = PerfilUsuario(
      userId:     data['user_id']     ?? '',
      nombre:     data['nombre']      ?? 'Usuario',
      rol:        data['rol']         ?? 'READONLY',
      orgId:      data['org_id']      ?? '',
      rutEmpresa: data['rut_empresa'] ?? '',
      modulos:    modulos,
    );
  }

  void limpiar() {
    _perfil = null;
    SentryConfig.clearUsuario();
  }
}

class PerfilNoEncontradoException implements Exception {
  final String message;
  const PerfilNoEncontradoException(this.message);

  @override
  String toString() => 'PerfilNoEncontradoException: $message';
}