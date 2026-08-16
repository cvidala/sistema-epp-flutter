import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Estado de la suscripción retornado por MIRA DEVELOPER.
class EstadoSuscripcion {
  final bool active;
  final Map<String, bool> modulos;

  const EstadoSuscripcion({required this.active, required this.modulos});
}

/// Servicio singleton que verifica la suscripción de la organización
/// contra la API de MIRA DEVELOPER (JSV).
///
/// Uso:
///   await SubscriptionService.instance.checkSubscription(rut);
///   if (!SubscriptionService.instance.active) { ... }
///   if (SubscriptionService.instance.moduloHabilitado('marcaje_asistencia')) { ... }
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
  Map<String, bool> _modulos = {};

  /// true si la suscripción está activa. Default true hasta que se verifique.
  bool get active => _active;

  /// Mapa de feature flags retornado por MIRA. Ej: {'marcaje_asistencia': true}
  Map<String, bool> get modulos => Map.unmodifiable(_modulos);

  /// Retorna true si el módulo está habilitado en la suscripción.
  /// Devuelve false si no existe la clave.
  bool moduloHabilitado(String key) => _modulos[key] ?? false;

  /// Consulta el estado de la suscripción de [rutEmpresa] en MIRA.
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
      'producto':   'trazapp',
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          'x-api-key':     _apiKey,
          'Content-Type':  'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[SubscriptionService] HTTP ${response.statusCode} — acceso permitido');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      _active = (json['active'] as bool?) ?? false;

      final rawModulos = json['modulos'];
      if (rawModulos is Map) {
        _modulos = {
          for (final e in rawModulos.entries)
            if (e.value is bool) e.key as String: e.value as bool,
        };
      }

      debugPrint('[SubscriptionService] active=$_active modulos=$_modulos');
    } catch (e) {
      // Error de red u otro: no bloquear al usuario
      debugPrint('[SubscriptionService] Error al verificar: $e — acceso permitido');
    }
  }

  /// Limpia el estado (llamar al hacer logout).
  void limpiar() {
    _active = true;
    _modulos = {};
  }
}
