import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Estado de la suscripción retornado por MIRA DEVELOPER.
class EstadoSuscripcion {
  final bool active;
  final String planNombre;
  final String estado;
  final Map<String, bool> modulos;

  const EstadoSuscripcion({
    required this.active,
    this.planNombre = '',
    this.estado = '',
    required this.modulos,
  });
}

/// Servicio singleton que verifica la suscripción de la organización
/// contra la API de MIRA DEVELOPER (JSV).
///
/// Uso:
///   await SubscriptionService.instance.checkSubscription(rut);
///   if (!SubscriptionService.instance.active) { ... }
///   if (SubscriptionService.instance.moduloHabilitado('marcaje_asistencia')) { ... }
///
/// Módulos disponibles: marcaje_asistencia, firma_digital, contratos, reportes_dt
class SubscriptionService {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  // Configurar con: flutter run --dart-define=MIRA_API_KEY=tu_clave
  static const String _apiKey = String.fromEnvironment(
    'MIRA_API_KEY',
    defaultValue: '',
  );
  static const String _endpoint =
      'https://js-vsytem.vercel.app/api/v1/subscriptions/check';

  bool _active = true;
  String _planNombre = '';
  String _estado = '';
  Map<String, bool> _modulos = {};

  /// true si la suscripción está activa. Default true hasta que se verifique.
  bool get active => _active;

  /// Nombre del plan (ej. "Beta full"). Vacío si no hay suscripción activa.
  String get planNombre => _planNombre;

  /// Estado de la suscripción (ej. "activa"). Vacío si no hay suscripción activa.
  String get estado => _estado;

  /// Mapa de feature flags retornado por MIRA.
  Map<String, bool> get modulos => Map.unmodifiable(_modulos);

  /// Retorna true si el módulo está habilitado en la suscripción.
  /// Módulos válidos: marcaje_asistencia, firma_digital, contratos, reportes_dt
  bool moduloHabilitado(String key) => _modulos[key] ?? false;

  /// Consulta el estado de la suscripción de [rutEmpresa] en MIRA.
  /// MIRA normaliza el RUT internamente — enviar en cualquier formato.
  ///
  /// En caso de error de red o respuesta inesperada, permite el acceso
  /// para no bloquear al usuario por fallas del servicio externo.
  Future<void> checkSubscription(String rutEmpresa) async {
    if (_apiKey.isEmpty) {
      debugPrint('[SubscriptionService] MIRA_API_KEY no configurada — acceso permitido por defecto');
      return;
    }

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'empresaRut': rutEmpresa,
      'producto': 'trazapp',
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          'x-api-key': _apiKey,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      // 401 = API key incorrecta — no bloquear, tratar como error de red
      if (response.statusCode == 401) {
        debugPrint('[SubscriptionService] 401 — MIRA_API_KEY inválida, acceso permitido');
        return;
      }

      // 400/404 = parámetros incorrectos — no confundir con "sin suscripción"
      if (response.statusCode == 400 || response.statusCode == 404) {
        debugPrint('[SubscriptionService] HTTP ${response.statusCode} — parámetros incorrectos, acceso permitido');
        return;
      }

      if (response.statusCode != 200) {
        debugPrint('[SubscriptionService] HTTP ${response.statusCode} — acceso permitido');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _active = (json['active'] as bool?) ?? false;

      if (!_active) {
        // Suscripción inactiva — { "active": false, "reason": "..." }
        // No hay campo suscripcion ni modulos en este caso
        final reason = json['reason'] as String? ?? 'sin motivo';
        debugPrint('[SubscriptionService] Suscripción inactiva: $reason');
        _planNombre = '';
        _estado = '';
        _modulos = {};
        return;
      }

      // Suscripción activa — leer suscripcion.modulos (no raíz)
      final suscripcion = json['suscripcion'] as Map<String, dynamic>?;
      if (suscripcion != null) {
        _planNombre = (suscripcion['planNombre'] as String?) ?? '';
        _estado = (suscripcion['estado'] as String?) ?? '';

        final rawModulos = suscripcion['modulos'];
        if (rawModulos is Map) {
          _modulos = {
            for (final e in rawModulos.entries)
              if (e.value is bool) e.key as String: e.value as bool,
          };
        }
      }

      debugPrint('[SubscriptionService] active=$_active plan=$_planNombre modulos=$_modulos');
    } catch (e) {
      // Error de red u otro: no bloquear al usuario
      debugPrint('[SubscriptionService] Error al verificar: $e — acceso permitido');
    }
  }

  /// Limpia el estado (llamar al hacer logout).
  void limpiar() {
    _active = true;
    _planNombre = '';
    _estado = '';
    _modulos = {};
  }
}
