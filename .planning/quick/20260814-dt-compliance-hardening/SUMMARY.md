---
slug: dt-compliance-hardening
status: complete
completed: "2026-08-14"
---

# DT Compliance Hardening — Summary

## Completado

- T1 ✅ supabase/migrations/20260814000000_dt_hardening_asistencias.sql
- T2 ✅ supabase/migrations/20260814000001_fix_errores_kiosko_anon.sql
- T3 ✅ supabase/migrations/20260814000002_portal_dt_inspector.sql
- T4 ✅ lib/asistencia/services/asistencia_upload_service.dart
- T5 ✅ lib/asistencia/services/asistencia_sync_service.dart
- T5 ✅ lib/asistencia/models/asistencia_pendiente.dart
- T5 ✅ lib/asistencia/screens/rut_input_screen.dart
- T6 ✅ portal-dt/index.html — portal web completo para inspectores DT

## Commits
- 16d5590 feat(dt): harden asistencias module for Res. Exenta N°38 compliance
- (portal commit pendiente)

## Pendiente (manual)
- Ejecutar las 3 migraciones SQL en Supabase SQL Editor
- Crear usuario inspector en Supabase Auth con email del fiscalizador DT
- Desplegar portal-dt/index.html (Supabase Storage, Vercel, o GitHub Pages)
