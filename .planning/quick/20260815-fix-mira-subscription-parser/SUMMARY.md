---
slug: fix-mira-subscription-parser
status: complete
completed: "2026-08-15"
---

# Fix MIRA Subscription Parser — Summary

## Completado

- T1 ✅ Leer modulos desde `json['suscripcion']['modulos']`
- T2 ✅ Omitir modulos si `active == false`
- T3 ✅ 401 → key inválida, no bloquea acceso
- T4 ✅ 400/404 → parámetros incorrectos, no bloquea acceso
- T5 ✅ Exponer `planNombre` y `estado` desde suscripcion
- T6 ✅ `flutter analyze` sin errores
- T7 ✅ Commit atómico (e75b85e)

## Cambios

- `lib/services/subscription_service.dart` — parseo corregido al schema real de MIRA
