---
type: quick-summary
slug: ui-banner-offline-y-nubes-cache
status: complete
completed: 2026-08-28
---

# Summary — Ajustes UI: banner offline + nubes de caché

## Fix #1 — Banner "Modo OFFLINE" pegado (workers_page.dart)

El banner se muestra con `offlineMode || !isOnline`. Al reconectar, `isOnline`
se actualizaba pero `offlineMode` quedaba en `true` (solo se reseteaba en una
recarga completa), así que el banner quedaba pegado tras la sincronización auto.

- `onStatusChange`: al volver online, ahora dispara `_loadWorkersSilent()`.
- `_loadWorkersSilent`: en éxito (datos vinieron de la red) setea
  `offlineMode = false` → el banner desaparece solo al recuperar señal.

## Fix #2 — Nubes de caché con frescura + fecha (obras_page.dart)

Antes: ícono verde (descargada) / gris (no), sin antigüedad.
Ahora, botón compacto con borde por estado:
- **Gris** `cloud_download_outlined` + "Descargar" → nunca descargada.
- **Verde** `cloud_done` + "hace X" → descargada hace < 8 h (fresca).
- **Ámbar** `cloud_off` + "hace X" → descargada pero desactualizada (≥ 8 h).

Helpers: `_cacheTtl` (8 h), `_haceCuanto(DateTime)`, `_botonCache(o)`. La
antigüedad se muestra bajo el ícono. Al tocar, re-descarga y actualiza estado.

Nota: la degradación es por **tiempo** (TTL), no por detección de cambios de
stock en el servidor (evita una consulta por obra en la lista; se dejó a
criterio y se optó por lo liviano).

## Verificación

`flutter analyze --no-fatal-infos` sobre ambos archivos: sin issues.
