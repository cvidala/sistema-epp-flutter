---
quick_id: 260822-dyl
slug: suspender-modulo-portal-fiscalizacion-dt
date: 2026-08-22
status: complete
commit: 422be7f
branch: fix/suspender-portal-dt-security
---

# Quick Task 260822-dyl — Summary

## Qué se hizo

Se desactivó (sin borrar) el módulo Portal de Fiscalización DT para
cerrar el hallazgo **CRITICAL** del advisor de Supabase
("Security Definer View: public.v_asistencias_dt").

Migración creada: `supabase/migrations/20260822000000_suspender_portal_dt_inspector.sql`

Contenido:
- `REVOKE EXECUTE` de `dt_consulta_asistencias(TEXT,DATE,DATE,INT,INT)` y
  `dt_contar_asistencias(TEXT,DATE,DATE)` desde `PUBLIC`, `anon` y
  `authenticated`. Se incluyó `PUBLIC` porque Postgres concede EXECUTE a
  PUBLIC por defecto — revocar solo de `authenticated` no habría bastado.
- `ALTER VIEW public.v_asistencias_dt SET (security_invoker = true)`.
- Comentarios con el procedimiento de reactivación (allowlist
  `dt_inspectores` + guard `auth.uid()` en ambas RPCs + re-GRANT).

## Qué NO se tocó

- No se eliminó la vista `v_asistencias_dt` ni las funciones RPC.
- No se modificó ningún objeto del módulo EPP (vistas, RLS, triggers).

## Riesgo cerrado

Fuga cross-org (OWASP A01 — Broken Access Control): las RPCs SECURITY
DEFINER estaban invocables por cualquier usuario autenticado y filtraban
solo por el RUT recibido, permitiendo que un supervisor de una empresa
consultara asistencias de otra.

## Pendiente (aplicación)

La migración está en el repo pero **debe aplicarse a la base**. Como el
proyecto Supabase se opera manualmente (SQL Editor / CLI), aplicar con
`supabase db push` o pegando el SQL en el editor. Luego verificar en
**Dashboard → Advisors → Security** que el CRITICAL desaparece.

## Reactivación futura

Ver el bloque "CÓMO REACTIVAR" al final del archivo de migración. No
reconceder GRANT sin agregar antes el guard de allowlist de inspectores.

## Commits

- `422be7f` — fix(security): suspender Portal DT para cerrar CRITICAL de v_asistencias_dt
