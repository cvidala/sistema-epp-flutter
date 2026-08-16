---
slug: dt-compliance-hardening
created: "2026-08-14"
status: in-progress
---

# DT Compliance Hardening — Módulo Asistencia

## Goal
Cerrar 5 brechas críticas del módulo de asistencia para cumplimiento Res. Exenta N°38 de la DT.

## Tasks

- [ ] T1: supabase/migrations/20260814000000_dt_hardening_asistencias.sql — org_id + obra_id + trigger inmutabilidad + RLS por org
- [ ] T2: supabase/migrations/20260814000001_fix_errores_kiosko_anon.sql — RPC registrar_error_marcacion() accesible por anon
- [ ] T3: supabase/migrations/20260814000002_portal_dt_inspector.sql — vista v_asistencias_dt + RPC dt_consulta_asistencias()
- [ ] T4: lib/asistencia/services/asistencia_upload_service.dart — agregar org_id y obra_id a insertarRegistro() y subirOnline()
- [ ] T5: lib/asistencia/screens/rut_input_screen.dart — pasar orgId, reemplazar insert directo a errores por RPC
