import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Configuración centralizada de Sentry — proyecto `trazapp-app` (org MIRA).
/// El mismo proyecto cubre ambos entry points (EPP y asistencia).
///
/// Privacidad (no viajan datos personales de trabajadores):
///  - `sendDefaultPii = false` → sin IP ni usuario automático, sin cuerpos de request.
///  - `beforeBreadcrumb` descarta las migas HTTP, que son el vector donde podría
///    filtrarse una URL de Supabase con RUT en un filtro (`?rut=eq...`).
///  - Complemento recomendado: una regla de data-scrubbing server-side en Sentry
///    para el patrón de RUT (defensa en profundidad).
class SentryConfig {
  SentryConfig._();

  // DSN del proyecto trazapp-app. No es secreto: viaja embebido en el cliente.
  static const String _dsn =
      'https://f204de66060d2f8d55e6361eb5eae8f3@o4512007442333696.ingest.us.sentry.io/4512007550992384';

  /// Inicializa Sentry y arranca la app. Solo activo en **release**:
  /// en debug el DSN queda vacío → SDK deshabilitado (sin ruido de desarrollo).
  static Future<void> initAndRun({
    required String flavor,
    required Widget Function() app,
  }) async {
    await SentryFlutter.init(
      (options) {
        options.dsn = kReleaseMode ? _dsn : '';
        options.environment = kReleaseMode ? 'production' : 'debug';
        options.release = 'trazapp-$flavor';
        options.tracesSampleRate = 0.0; // foco en errores, no performance (cuida cuota)
        options.sendDefaultPii = false;
        // Descartar migas HTTP: evita que una URL de Supabase con datos
        // sensibles quede registrada como breadcrumb.
        options.beforeBreadcrumb = (crumb, hint) {
          if (crumb?.category == 'http' || crumb?.type == 'http') return null;
          return crumb;
        };
      },
      appRunner: () {
        Sentry.configureScope((s) => s.setTag('flavor', flavor));
        app();
      },
    );
  }

  /// Etiqueta el scope tras el login con identificadores de empresa/rol.
  /// No es PII de personas: `orgId` es el id del tenant y `empresa` su razón social.
  static void setUsuario({
    required String orgId,
    required String rol,
    String empresa = '',
  }) {
    Sentry.configureScope((s) {
      s.setTag('organization_id', orgId);
      s.setTag('rol', rol);
      if (empresa.isNotEmpty) s.setTag('empresa', empresa);
    });
  }

  /// Limpia las etiquetas al cerrar sesión.
  static void clearUsuario() {
    Sentry.configureScope((s) {
      s.removeTag('organization_id');
      s.removeTag('rol');
      s.removeTag('empresa');
    });
  }
}
