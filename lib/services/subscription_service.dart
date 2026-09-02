import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kill-switch de suscripción: decide si la empresa puede ENTRAR a TrazApp.
///
/// No embebe ninguna API key en la app. Llama a la Edge Function proxy
/// `subscription-check` (que guarda la SUBSCRIPTIONS_API_KEY server-side) con el
/// JWT del usuario. El proxy consulta a MIRA/JSV por el RUT de la empresa.
///
/// Uso:
///   await SubscriptionService.instance.checkSubscription(rutEmpresa);
///   if (!SubscriptionService.instance.active) { ...bloquear... }
///
/// FAIL-OPEN: solo bloquea ante `active:false` EXPLÍCITO del upstream. Cualquier
/// error (red, timeout, sin key, RUT no resoluble) => se permite el acceso, para
/// no dejar fuera a un cliente que paga por una falla del servicio.
///
/// Alcance: SOLO entrar/no entrar. El gating de módulos es aparte (config_modulos).
class SubscriptionService {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  bool _active = true;
  String _planNombre = '';
  String _estado = '';

  /// true si la suscripción está activa. Default true hasta que un `active:false`
  /// explícito lo baje (fail-open).
  bool get active => _active;
  String get planNombre => _planNombre;
  String get estado => _estado;

  /// Consulta el estado de la suscripción de [rutEmpresa] vía el proxy.
  /// Nunca lanza: ante cualquier error deja `active = true` (fail-open).
  Future<void> checkSubscription(String rutEmpresa) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'subscription-check',
        body: {'empresaRut': rutEmpresa},
      );
      final data = res.data;
      if (data is Map && data['active'] == false) {
        // Único caso de bloqueo: active:false explícito.
        _active = false;
        _planNombre = '';
        _estado = (data['estado'] as String?) ?? '';
        debugPrint('[SubscriptionService] Suscripción INACTIVA → bloquear acceso');
        return;
      }
      // ok:true active:true, o failopen (ok:false sin active) → permitir.
      _active = true;
      if (data is Map) {
        _planNombre = (data['planNombre'] as String?) ?? '';
        _estado = (data['estado'] as String?) ?? '';
      }
      debugPrint('[SubscriptionService] active=$_active plan=$_planNombre');
    } catch (e) {
      // Red / función caída / etc. → fail-open (no bloquear).
      _active = true;
      debugPrint('[SubscriptionService] Error al verificar: $e — acceso permitido (fail-open)');
    }
  }

  /// Limpia el estado (llamar al hacer logout).
  void limpiar() {
    _active = true;
    _planNombre = '';
    _estado = '';
  }
}
