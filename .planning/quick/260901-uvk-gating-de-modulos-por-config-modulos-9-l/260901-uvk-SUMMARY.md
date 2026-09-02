---
quick_id: 260901-uvk
slug: gating-de-modulos-por-config-modulos-9-l
status: complete
completed: 2026-09-02
---

# Summary — Gating de módulos por config_modulos (9 llaves)

## Qué se hizo

TrazApp gatea pestañas/secciones por `organizaciones.config_modulos` (snapshot,
offline-safe). La consulta viva (SubscriptionService) queda intacta como kill-switch
global. Sin `MIRA_API_KEY` en builds, sin proxy. Fail-open en todo.

### Tarea 1 — Edge Function `provision-organizacion` (`supabase/functions/provision-organizacion/index.ts`)
- Default de `config_modulos` migrado de 4 llaves (con remap a `asistencia`) a las 9
  canónicas. El body se guarda **tal cual** llega, sin renombrar ni filtrar.
- Re-aprovisionamiento (org existente por RUT): ahora hace `UPDATE` de **solo**
  `config_modulos` (no pisa razon_social/activo). Antes quedaba congelado.
- Respuesta incluye `accion: created|updated`.
- Comentario de cabecera actualizado.

### Tarea 2 — Dashboard (`dashboard/index.html`)
- `data-modulo="<llave>"` en 12 nav-items (gating independiente por llave).
- `aplicarGatingModulos()` AWAITED: recorre `[data-modulo]`, oculta solo lo que viene
  `=== false` (fail-open), y oculta un wrapper `.sidebar-modulo` solo si todos sus
  ítems quedaron ocultos. Reemplaza el IIFE fire-and-forget que gateaba 4 wrappers.
- `esVisible()` + `primeraPaginaVisible()` + fallback de navegación: si la pestaña
  objetivo (o resumen por defecto) quedó oculta, cae a la primera visible.
- `firma_digital` NO se cablea (firma del trabajador siempre activa).

### Tarea 3 — App móvil (`lib/services/auth_service.dart`)
- Solo documentación: nota del contrato de 9 llaves; la app móvil consume solo
  `gestion_epp`. Sin cambio funcional.

## Mapa final llave → sección
gestion_epp→entregas/reglas · stock_bodega→stock/alertas · solicitudes_epp→solicitudes ·
marcaje_asistencia→asistencia · reportes_dt→reportes · dashboard→resumen ·
prevencion→sección Prevención · contratos→sección Documentación · firma_digital→reservada.
Siempre visibles: Trabajadores, Centros, Usuarios, Auditoría, Mantenimiento.

## Verificación
- `node --check` de los scripts inline del dashboard: OK (sin errores de sintaxis).
- Conteo `data-modulo` = 12, helpers definidos 1 c/u, 0 referencias al gating viejo.
- `flutter analyze` de auth_service.dart: sin issues.
- deno check local omitido (deno no instalado); lo valida el job CI `deno-test`.

## Pendiente (fuera de commits de código)
- **Re-desplegar la Edge Function a prod**: `supabase functions deploy
  provision-organizacion --no-verify-jwt` (acción de prod).
- El dashboard se publica a gh-pages al mergear a main (deploy.yml).

## Commits
- feat(provision): guardar config_modulos 9 llaves as-is + upsert en org existente
- feat(dashboard): gating de secciones por config_modulos (9 llaves, por ítem)
- docs(auth): documentar contrato canónico de 9 llaves config_modulos
