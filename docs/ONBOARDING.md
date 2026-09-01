# Onboarding de una empresa cliente — TrazApp

Runbook para dar de alta una empresa nueva en TrazApp (módulo EPP). Cubre las
**dos capas** del sistema y el orden correcto para no dejar cabos sueltos.

> **Arquitectura en una frase:** MIRA (js-vsystem) es la fuente de verdad de la
> **suscripción/plan**; TrazApp/Supabase guarda los **datos operativos** (org,
> usuarios, obras, bodegas, catálogo EPP, entregas). El **RUT de la empresa** es
> la llave que une ambos sistemas.

---

## 0. Pre-onboarding (infra) — una sola vez, antes del primer cliente real

- [ ] Supabase **FREE → Pro** (fiabilidad + retención).
- [ ] Activar **backups** (Point-in-Time Recovery / daily backups).
- [ ] Confirmar que RLS está activo y verificado (aislamiento por `org_id`).
- [ ] Sentry operativo (proyectos `trazapp-app` + `trazapp-dashboard`) con la
      regla de scrubbing de RUT a nivel **organización**.

> Para una **marcha blanca** sin datos productivos aún, el paso Pro/backups es
> recomendable pero puede diferirse; para un cliente **de pago**, es obligatorio
> y va primero.

---

## 1. Datos a recopilar del cliente (antes de empezar)

| Dato | Ejemplo | Para |
|------|---------|------|
| RUT empresa | `76.123.456-7` | Llave MIRA ↔ Supabase |
| Razón social | `Constructora Demo SpA` | Org en ambos sistemas |
| Plan / módulos | EPP + Dashboard | MIRA (suscripción) |
| Obras / centros de trabajo | "Edificio Las Acacias", "Ruta 5 Km 42" | `obras` |
| Bodegas | 1 por obra o central | `bodegas` |
| Catálogo EPP | casco, chaleco, botas, guantes, lentes… (+ críticos y vencimientos) | `catalogo_epp` |
| Stock inicial | cantidades por EPP/bodega | `stock_movimientos` (ENTRADA) |
| Usuario ADMIN | email + nombre | `perfiles` + Auth |
| Supervisores (~10) | email + nombre + obras asignadas | `perfiles` + `obra_usuarios` |
| Trabajadores (~60) | RUT + nombre + obra | `trabajadores` + `trabajador_obras` (puede cargarlos el cliente) |

---

## 2. Lado MIRA (suscripción) — lo hace MIRA / `/superadmin`

1. Crear la empresa con **RUT + razón social**.
2. Asignar **plan** y **módulos** del producto `trazapp` (para EPP: gestión EPP + dashboard).
3. Dejar la suscripción en estado **activa**.

> TrazApp consulta esto en tiempo real:
> `GET https://js-vsytem.vercel.app/api/v1/subscriptions/check?empresaRut=<RUT>&producto=trazapp`
> Devuelve `active`, `planNombre`, `estado`, `modulos`.
> Si `MIRA_API_KEY` no está seteada en el build, el chequeo es **fail-open**
> (acceso permitido) — ver §6.

---

## 3. Lado TrazApp (organización + admin) — vía API de aprovisionamiento

> **Nada de SQL manual.** La organización y el usuario ADMIN se crean llamando a
> la Edge Function `provision-organizacion` (la llama MIRA al dar de alta la
> empresa). Contrato completo en [`PROVISIONING-API.md`](PROVISIONING-API.md).

```
POST /functions/v1/provision-organizacion
Header: x-trazapp-provision-key: <secreto>
Body: { rut, razon_social, config_modulos, admin: { email, nombre } }
→ crea organización + usuario ADMIN (idempotente por RUT) y devuelve credenciales.
```

Resultado: el admin recibe email + contraseña temporal (debe cambiarla al ingresar).

## 4. Setup operativo — self-service (dashboard/app, sin SQL)

Con el admin ya creado, **todo lo demás se hace desde la UI** (así lo hará el
cliente en el día a día — no hay carga manual):

| Qué | Dónde |
|-----|-------|
| Centros de trabajo (obras) | Dashboard → **Centros de trabajo** / app → crear obra |
| Catálogo y reglas de EPP (críticos, vencimientos) | Dashboard → **Reglas EPP** |
| Bodegas y **stock** inicial | Dashboard/app → **Stock EPP** (ingreso de stock) |
| **Supervisores** | Dashboard → **Usuarios** (crea usuario + rol SUPERVISOR en la org) |
| Asignar supervisores a obras | Dashboard → **Centros de trabajo** |
| **Trabajadores** | Dashboard → **Trabajadores** (o los carga el supervisor en la app) |

> Todas estas tablas están aisladas por `org_id` vía RLS, así que cada admin
> solo ve/gestiona lo suyo.

---

## 5. Verificación (smoke test)

- [ ] Login del **admin** en la app → ve sus obras.
- [ ] Login de un **supervisor** → ve solo sus obras asignadas (RLS).
- [ ] Entrega de EPP de prueba (foto + firma) → se registra y **descuenta stock**.
- [ ] La entrega aparece en el **dashboard** con el semáforo correcto.
- [ ] **Aislamiento:** el usuario NO ve datos de otra organización.
- [ ] Errores/health visibles en **Sentry** (`trazapp-app` / `trazapp-dashboard`).

---

## 6. App y distribución

- Compilar el APK **desde `main`** (trae todos los fixes + Sentry):
  `flutter build apk --release --flavor epp -t lib/main.dart`
  (firma: keystore en `~/.trazapp/`).
- **Suscripción:** decidir si se activa la verificación MIRA en el build
  (`--dart-define=MIRA_API_KEY=<clave>`). Para marcha blanca puede quedar
  *fail-open* (sin la key) para no bloquear al cliente por fallas del servicio.
- Distribuir el APK a los dispositivos del cliente (sideload / internal testing).

---

## 7. Checklist final

- [ ] Empresa creada en **MIRA** con plan/módulos activos.
- [ ] `organizaciones` en Supabase con el **mismo RUT**.
- [ ] Admin + supervisores creados (Auth + `perfiles` + `obra_usuarios`).
- [ ] Obras, bodegas, catálogo EPP y stock inicial cargados.
- [ ] Smoke test OK (entrega + descuento + dashboard + aislamiento).
- [ ] APK distribuido.
- [ ] (Cliente de pago) Supabase Pro + backups activos.
