---
type: quick-summary
slug: runbook-onboarding-empresa
status: complete
completed: 2026-09-01
---

# Summary — Runbook de onboarding de empresa

Se creó `docs/ONBOARDING.md`: proceso canónico end-to-end para dar de alta una
empresa cliente en TrazApp (módulo EPP), como preparación de la marcha blanca.

Cubre las dos capas y su orden:
- **Pre-onboarding infra** (Supabase Pro + backups).
- **Datos a recopilar** del cliente.
- **Lado MIRA** (suscripción/plan/módulos por RUT).
- **Lado Supabase** (organización, admin, obras, bodegas, catálogo EPP, stock,
  supervisores, trabajadores) con plantillas SQL marcadas para verificar
  columnas contra la BD (el esquema base vive en la BD, no en migraciones).
- **Verificación** (smoke test: entrega + descuento + dashboard + aislamiento RLS + Sentry).
- **App/distribución** (APK desde `main`, decisión MIRA_API_KEY fail-open).
- **Checklist final**.

Solo documentación; no toca código ni esquema. La ejecución para el piloto se
hará siguiendo este runbook, confirmando el esquema real al momento de los INSERT.
