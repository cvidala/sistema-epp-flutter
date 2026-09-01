---
type: quick-summary
slug: provision-organizacion
status: complete
completed: 2026-09-01
---

# Summary — API de aprovisionamiento MIRA→TrazApp

Se construyó el **flujo real** de alta de empresa (sin SQL manual), decisión
del usuario: **push** + **opción A** (MIRA aprovisiona org + admin; el admin
gestiona supervisores en el dashboard).

## Qué se hizo
- **Edge Function `supabase/functions/provision-organizacion/index.ts`**: crea
  `organizaciones` + usuario ADMIN (Auth Admin API, contraseña temporal) +
  `perfiles` (upsert). Idempotente por RUT. Auth por secreto compartido
  (`x-trazapp-provision-key` vs secret `TRAZAPP_PROVISION_KEY`). Desplegada a
  prod con `--no-verify-jwt`.
- **Secreto** generado (openssl 32 bytes) y guardado como secret de Supabase.
- **`docs/PROVISIONING-API.md`**: contrato para que MIRA implemente el llamador.
- **`docs/ONBOARDING.md`**: reescrito — §3 ahora usa la función de
  aprovisionamiento y §4 documenta que el resto (obras, catálogo/reglas EPP,
  stock, supervisores, trabajadores) es **self-service** en el dashboard/app.

## Verificación
- Deploy OK. Compuertas probadas (no mutan datos): sin secreto → 401, secreto
  malo → 401, secreto OK + faltan campos → 400.
- Happy-path (crear org+admin) se prueba dogfoodeando el piloto real.

## Pendiente
- MIRA implementa la llamada a la función (le pasamos el secreto + el contrato).
- Futuro: migrar de contraseña temporal a *invite email* cuando haya SMTP.
- Endurecer/mover a Edge Function el alta de usuarios del dashboard (bug de
  re-login con contraseña vacía) — siguiente iteración.
