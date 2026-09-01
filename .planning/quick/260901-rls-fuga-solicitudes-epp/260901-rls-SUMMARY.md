---
type: quick-summary
slug: rls-fuga-solicitudes-epp
status: complete
completed: 2026-09-01
---

# Summary — CRÍTICO: fuga cross-org en solicitudes_epp

## Causa raíz
`solicitudes_epp` tenía RLS habilitado pero con **policies PERMISIVAS `USING(true)`**
(template Supabase "allow all authenticated": `select_auth_solicitudes_epp`
qual=true, + `insert_auth_/update_auth_` con check=true). Como las policies
permisivas se combinan con OR, cualquier usuario autenticado veía las solicitudes
de **todas las organizaciones**. El dashboard no filtra por org (confía en RLS)
→ el admin de una empresa nueva veía solicitudes de otra.

## Fix (2 migraciones, aplicadas a prod)
- `20260901000000_rls_solicitudes_epp.sql`: primer intento (agregó policies
  scoped, pero OR con las `true` → sin efecto).
- `20260901000001_rls_solicitudes_epp_fix.sql`: **dropea TODAS** las policies de
  la tabla (con RAISE NOTICE para registro) y recrea SOLO las scoped por
  obra→org: `EXISTS (SELECT 1 FROM obras WHERE obra_id = solicitudes_epp.obra_id
  AND org_id = get_user_org_id())` para SELECT/INSERT/UPDATE, DELETE=false.

## Verificación (funcional, como usuarios reales de otra org)
- Pre-fix: supervisor veía solicitud de obra ajena (org 32d49995 ≠ su org).
- Post-fix: ADMIN ve solo la solicitud de SU org (1 de 2 totales); anon ve 0;
  el foreign desaparece. Dashboard (admin) sigue viendo lo suyo.

## Auditoría de aislamiento (todas las tablas de negocio)
Probado funcionalmente como supervisor de otra org (columna org_id/obra_id):
- **Única fuga: `solicitudes_epp`** (corregida).
- Scoped OK: obras, bodegas, perfiles, organizaciones, trabajadores,
  catalogo_epp, entregas_epp, stock_movimientos (bodegas propias),
  trabajador_obras, obra_epp_reglas, obra_usuarios, obra_contactos, asistencias,
  audit_log, stock_umbrales, epp_uso_eventos, hash_chain_head (0/1 org-obra).

## Nota / gotcha
Tablas nuevas en Supabase pueden nacer con el template permisivo `USING(true)`.
Al crear una tabla de negocio, SIEMPRE reemplazar por policy scoped por org.
