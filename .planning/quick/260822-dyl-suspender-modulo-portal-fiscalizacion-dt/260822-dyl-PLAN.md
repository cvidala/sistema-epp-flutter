---
quick_id: 260822-dyl
slug: suspender-modulo-portal-fiscalizacion-dt
date: 2026-08-22
mode: quick
---

# Quick Task 260822-dyl: Suspender módulo Portal de Fiscalización DT

## Descripción

Cerrar el hallazgo de seguridad **CRITICAL** del advisor de Supabase
("Security Definer View: public.v_asistencias_dt") desactivando —sin
borrar— el módulo del Portal de Fiscalización DT. El producto se enfoca
hoy solo en la entrega de EPP; el portal DT se reactivará más adelante
con una autorización correcta.

## Contexto

Surge de una auditoría manual de seguridad (RLS + manejo de la
service_role key). Las RPCs `dt_consulta_asistencias` /
`dt_contar_asistencias` son SECURITY DEFINER y estaban invocables por
cualquier usuario autenticado, filtrando solo por el RUT recibido como
parámetro → un supervisor de una empresa podía leer asistencias de otra
empresa (fuga cross-org, OWASP A01).

## Tareas

1. **Crear migración SQL** `supabase/migrations/20260822000000_suspender_portal_dt_inspector.sql`
   - `REVOKE EXECUTE` de ambas RPCs desde `PUBLIC`, `anon`, `authenticated`
     (PUBLIC incluido porque Postgres concede EXECUTE a PUBLIC por defecto).
   - `ALTER VIEW public.v_asistencias_dt SET (security_invoker = true)` para
     apagar el advisor CRITICAL.
   - Comentarios que documentan que es reversible y el procedimiento de
     reactivación (allowlist `dt_inspectores` + guard `auth.uid()` + re-GRANT).
   - **No** eliminar vista ni funciones. **No** tocar objetos del módulo EPP.

## Restricciones

- Cambio reversible, no destructivo.
- No modificar vistas, RLS ni triggers del módulo EPP.
- Migración idempotente en lo posible; la aplica el dueño (service_role/postgres).

## Verificación

- La vista `v_asistencias_dt` reporta `security_invoker=true` en `pg_class.reloptions`.
- `anon`/`authenticated`/`PUBLIC` ya no tienen EXECUTE sobre las RPCs
  (`information_schema.role_routine_grants`).
- Advisor de Supabase (Security) deja de mostrar el CRITICAL.
