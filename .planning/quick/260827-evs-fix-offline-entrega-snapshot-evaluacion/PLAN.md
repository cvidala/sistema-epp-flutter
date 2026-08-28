---
type: quick
slug: fix-offline-entrega-snapshot-evaluacion
status: in-progress
created: 2026-08-27
---

# Fix: snapshot de evaluación en entregas offline

## Problema

Tras sincronizar una entrega hecha offline, el dashboard sigue marcando el EPP
como pendiente/faltante aunque la entrega quedó registrada y el stock se
descontó correctamente.

## Causa raíz

Las entregas offline (`validacion_tipo='OFFLINE_SYNC'`) se insertan con
`entregas_epp.evaluacion = NULL` (offline se omite el semáforo). El dashboard
(`loadAlertas` ~2125 y `loadPageAlertas` ~3018 en `dashboard/index.html`) filtra
`.not('evaluacion','is',null)` y toma el snapshot más reciente por
(trabajador, obra); al descartar la entrega offline usa el snapshot **anterior**
a la entrega, que aún lista el EPP como FALTA.

La sincronización atómica (`insert_entrega_offline_v1`) ya inserta entrega +
`stock_movimientos` SALIDA correctamente — eso NO se toca.

## Solución (una migración SQL)

`supabase/migrations/20260827000000_offline_entrega_snapshot_evaluacion.sql`

- **(A)** `CREATE OR REPLACE insert_entrega_offline_v1`: misma firma/lógica que
  `20260824000000` (guarda PATHS), + bloque best-effort que tras insertar la
  entrega + SALIDA hace
  `UPDATE entregas_epp SET evaluacion = evaluar_entrega_v2(obra, trab, '[]')`.
  Si `evaluar_entrega_v2` fallara, la entrega igual queda registrada.
- **(B)** Backfill puntual: recalcula `evaluacion` solo para la última entrega
  de cada (trabajador, obra) que hoy tenga `evaluacion NULL` → limpia alertas
  colgadas sin corromper el histórico.

No se cambia el dashboard ni la app Flutter. No se toca
`insert_entrega_online_v1` ni el flujo de stock.

## Aplicación

El orquestador aplica con `supabase db push` tras revisar el archivo (no se
aplica automáticamente dentro del flujo).

## Verificación

- Migración es SQL válido (estructura consistente con migraciones existentes).
- Best-effort: ningún fallo de `evaluar_entrega_v2` aborta la entrega ni el backfill.
