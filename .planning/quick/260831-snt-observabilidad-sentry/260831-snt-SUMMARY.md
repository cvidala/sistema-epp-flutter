---
type: quick-summary
slug: observabilidad-sentry
status: complete
completed: 2026-08-31
---

# Summary — Observabilidad con Sentry (Fase 1 auditoría)

Monitoreo de errores centralizado bajo la org **MIRA Developer** en Sentry.
Dos proyectos: `trazapp-app` (Flutter) y `trazapp-dashboard` (web).

## App Flutter (`lib/services/sentry_config.dart` + entry points)
- Nuevo `SentryConfig` centraliza init, DSN (`trazapp-app`), scrubbing y tags.
- `main.dart` (flavor `epp`) y `main_asistencia.dart` (flavor `asistencia`)
  arrancan vía `SentryConfig.initAndRun(...)`.
- Solo **release** (en debug el DSN queda vacío → SDK deshabilitado).
- `tracesSampleRate = 0` (foco en errores, cuida la cuota gratis).
- `auth_service`: tras login setea tags `organization_id`/`rol`/`empresa`
  (sin PII de personas); los limpia en `limpiar()`.

## Dashboard (`dashboard/index.html`)
- Loader script de Sentry (`trazapp-dashboard`) + init vía `sentryOnLoad`.
- **No** monitorea la preview local (guard por `localhost`/`file://`).
- Tags `organization_id`/`rol`/`empresa` tras cargar el perfil.

## Privacidad (PII)
- `sendDefaultPii = false` (sin IP/usuario/cuerpos de request).
- Se **descartan las migas HTTP** (fetch/xhr en web; category/type `http` en
  Flutter) — vector donde podría filtrarse una URL de Supabase con RUT.
- **Pendiente (config en Sentry, no código):** agregar regla de data-scrubbing
  server-side para el patrón de RUT (defensa en profundidad).

## Dependencia
- `sentry_flutter` **^9.28.0**. Se subió desde 8.14.2 porque esa versión
  pineaba `languageVersion = "1.6"` en su build.gradle y el proyecto usa
  Kotlin 2.2.20 (que ya no soporta 1.6) → fallaba `compileReleaseKotlin`.

## Verificación
- `flutter analyze` limpio; `flutter build apk --release --flavor epp` OK.
- **Pendiente end-to-end:** instalar en dispositivo, disparar un error de
  prueba y confirmar que llega a Sentry **sin PII** en el evento.
