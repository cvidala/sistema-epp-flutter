---
type: quick-summary
slug: fix-offline-entrega-snapshot-evaluacion
status: complete
completed: 2026-08-27
---

# Summary — Fix snapshot de evaluación en entregas offline

## Qué se hizo

Migración `supabase/migrations/20260827000000_offline_entrega_snapshot_evaluacion.sql`:

1. **`insert_entrega_offline_v1`** (CREATE OR REPLACE, misma firma que la versión
   vigente `20260824000000`): tras insertar la entrega + `stock_movimientos`
   SALIDA, guarda el snapshot de cumplimiento con
   `evaluar_entrega_v2(obra, trab, '[]')`. Bloque best-effort: un fallo del
   evaluador no aborta la entrega. Trae el flujo offline a paridad con el online.
2. **Backfill puntual**: recalcula `evaluacion` solo para la última entrega de
   cada (trabajador, obra) con `evaluacion NULL`, para limpiar las alertas ya
   colgadas sin corromper snapshots históricos.

## Por qué

Las entregas offline guardaban `evaluacion = NULL`; el dashboard descartaba esas
filas (`.not('evaluacion','is',null)`) y mostraba el snapshot anterior a la
entrega, marcando el EPP como pendiente/faltante aunque ya se había entregado y
descontado del stock.

## Alcance

- Solo la migración SQL. No se tocó dashboard, app Flutter,
  `insert_entrega_online_v1` ni el flujo de stock.

## Verificación

- Estructura SQL validada (balance de `$$`, cuerpo copiado verbatim de la
  migración desplegada + bloque nuevo).
- Pendiente: aplicar a prod con `supabase db push` (lo hace el orquestador tras
  revisar) y reconfirmar en dashboard que la alerta del caso de prueba se limpia.
