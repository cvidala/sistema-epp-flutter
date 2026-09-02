---
quick_id: 260901-uvk
slug: gating-de-modulos-por-config-modulos-9-l
description: Gating de módulos por config_modulos (contrato de 9 llaves canónicas) en Edge Function y dashboard
date: 2026-09-02
mode: quick
---

# Quick Task 260901-uvk — Gating de módulos por config_modulos (9 llaves)

## Objetivo

TrazApp gatea las pestañas/secciones por `organizaciones.config_modulos` (snapshot,
offline-safe). MIRA es la fuente de verdad y envía las 9 llaves canónicas booleanas.
La consulta viva (SubscriptionService) **NO se toca** — queda solo como kill-switch
global. NO se compila `MIRA_API_KEY` ni se crea proxy. **Fail-open en todo**: llave
ausente / config_modulos nulo / sin datos → NO ocultar.

Llaves canónicas: `gestion_epp, marcaje_asistencia, stock_bodega, solicitudes_epp,
firma_digital, reportes_dt, dashboard, prevencion, contratos`.

## Mapa final llave → sección (gating independiente)

| Llave | Dashboard (nav-item / sección) | App móvil |
|---|---|---|
| gestion_epp | entregas, reglas | botón "Entregar EPP" (ya funciona) |
| stock_bodega | stock, alertas | — |
| solicitudes_epp | solicitudes | — |
| marcaje_asistencia | asistencia | (binario aparte) |
| reportes_dt | reportes | — |
| dashboard | resumen (solo Resumen General) | — |
| prevencion | sección Prevención (2 coming-soon) | — |
| contratos | sección Documentación (2 coming-soon) | — |
| firma_digital | RESERVADA (no cablear) | firma del trabajador siempre activa |

Siempre visibles (no gatear): Trabajadores, Centros, Usuarios, Auditoría, Mantenimiento.

## Tareas

### Tarea 1 — Edge Function `provision-organizacion`
- **files:** supabase/functions/provision-organizacion/index.ts
- **action:** (a) Guardar `config_modulos` tal cual llega en el body (9 llaves as-is);
  reemplazar el default de 4 llaves con remap a `asistencia` por el default de 9 llaves
  canónicas. (b) En org existente (dedup por RUT) hacer UPDATE de `config_modulos` con lo
  recibido (no clobber de otros campos); devolver `accion: created|updated`.
- **verify:** `deno check` del archivo; DRY_RUN deno test si aplica.
- **done:** el body persiste las 9 llaves; re-aprovisionar actualiza config_modulos.

### Tarea 2 — Dashboard `dashboard/index.html`
- **files:** dashboard/index.html
- **action:** (a) `data-modulo="<llave>"` en cada nav-item gateable según el mapa.
  (b) Reemplazar el IIFE de gating por una función AWAITED que recorre `[data-modulo]`
  y aplica `display=(m[key]===false)?'none':''` (fail-open), oculta wrappers
  `.sidebar-modulo` vacíos, y devuelve `m`. (c) Helper `primeraPaginaVisible()` +
  fallback de navegación cuando la pestaña destino quedó oculta.
- **verify:** `open dashboard/index.html` parsea sin error de sintaxis JS.
- **done:** cada llave gatea su sección de forma independiente, fail-open, sin dejar al
  admin sin pestaña activa.

### Tarea 3 — App móvil (nota)
- **files:** lib/services/auth_service.dart
- **action:** comentario notando que el contrato canónico son 9 llaves y la app móvil
  solo consume `gestion_epp`. Sin cambio funcional.
- **verify:** `flutter analyze --no-fatal-infos` limpio.
- **done:** documentado; app intacta.

## No romper
Badges (solicitudesBadge, alertBadge), adminSection (gateado por rol ADMIN), lazy-load
en navTo, la firma del trabajador. Sin cambios de esquema, sin tocar RLS.
