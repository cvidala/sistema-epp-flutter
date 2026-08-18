---
slug: fix-mira-subscription-parser
status: in-progress
created: "2026-08-15"
---

# Fix: parseo de respuesta MIRA en SubscriptionService

## Goal
Corregir `lib/services/subscription_service.dart` para que parsee el schema real
de la API de MIRA DEVELOPER en lugar del schema incorrecto que tenía.

## Tasks

- [ ] T1: Leer modulos desde `json['suscripcion']['modulos']` (no desde raíz)
- [ ] T2: Omitir lectura de modulos si `active == false`
- [ ] T3: Manejar 401 como error de key (loguear, no bloquear)
- [ ] T4: Manejar 400/404 como parámetros incorrectos (loguear, no bloquear)
- [ ] T5: Exponer `planNombre` y `estado` desde `suscripcion`
- [ ] T6: Verificar `flutter analyze` pasa sin errores
- [ ] T7: Commit atómico

## Schema real MIRA

```json
{
  "active": true,
  "empresa": { "id": "...", "nombre": "...", "rut": "..." },
  "suscripcion": {
    "estado": "activa",
    "planNombre": "Beta full",
    "modulos": {
      "marcaje_asistencia": true,
      "firma_digital": true,
      "contratos": true,
      "reportes_dt": true
    }
  }
}
```

Inactivo: `{ "active": false, "reason": "..." }` — sin `suscripcion`.

## Claves válidas de módulo
`marcaje_asistencia`, `firma_digital`, `contratos`, `reportes_dt`
