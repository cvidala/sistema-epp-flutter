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
> (acceso permitido) — ver §5.

---

## 3. Lado TrazApp / Supabase (datos operativos)

> ⚠️ El esquema base vive en la BD (no en migraciones). **Confirmar los nombres
> exactos de columnas contra la BD antes de ejecutar** cada INSERT. Las
> plantillas siguientes usan los campos conocidos por el código de la app.

### 3.1 Organización
```sql
insert into organizaciones (rut, razon_social, config_modulos)
values ('76.123.456-7', 'Constructora Demo SpA',
        '{"gestion_epp": true, "asistencia": false, "prevencion": false, "dashboard": true}'::jsonb)
returning org_id;   -- guardar este org_id para los pasos siguientes
```
> El `config_modulos` sigue el contrato unificado MIRA/JSV.
> El `rut` debe ser **idéntico** al de MIRA.

### 3.2 Usuario ADMIN
1. **Supabase Auth** → crear usuario (email + contraseña temporal) — vía Dashboard
   (Authentication → Add user) o Admin API. Anotar su `user_id` (UUID).
2. **Perfil**:
```sql
insert into perfiles (user_id, nombre, rol, org_id, activo)
values ('<auth_user_id>', 'Nombre Admin', 'ADMIN', '<org_id>', true);
```

### 3.3 Obras (centros de trabajo)
```sql
insert into obras (nombre, direccion, estado, org_id)  -- verificar si obras lleva org_id o hereda por RLS
values ('Edificio Las Acacias', 'Av. Ejemplo 123', 'ACTIVA', '<org_id>')
returning obra_id;
```

### 3.4 Bodegas
```sql
insert into bodegas (nombre, obra_id)   -- obra_id null = bodega central de la org
values ('Bodega Las Acacias', '<obra_id>')
returning bodega_id;
```

### 3.5 Catálogo EPP
```sql
insert into catalogo_epp (codigo, nombre, activo /*, es_critico, vence_por, ... */)
values
 ('CASCO',   'Casco de seguridad',   true),
 ('CHALECO', 'Chaleco reflectante',  true),
 ('BOTAS',   'Botas de seguridad',   true),
 ('GUANTES', 'Guantes de nitrilo',   true),
 ('LENTES',  'Lentes de seguridad',  true);
-- Confirmar columnas de criticidad/vencimiento contra la BD (es_critico, vence_por FECHA/USO/AMBOS, etc.)
```

### 3.6 Stock inicial
```sql
insert into stock_movimientos (bodega_id, epp_id, tipo, cantidad, motivo, created_by)
values ('<bodega_id>', '<epp_id>', 'ENTRADA', 100, 'Carga inicial onboarding', '<admin_user_id>');
```

### 3.7 Supervisores
- Crear cada usuario en Auth + fila en `perfiles` (rol `SUPERVISOR`, mismo `org_id`).
- Asignar obras:
```sql
insert into obra_usuarios (obra_id, user_id /*, puede_escribir */)
values ('<obra_id>', '<supervisor_user_id>');
```

### 3.8 Trabajadores (opcional; puede cargarlos el cliente desde la app)
- `trabajadores` (rut, nombre, apellido, estado ACTIVO, org_id) + `trabajador_obras`
  (obra_id, trabajador_id, cargo, activo).

---

## 4. Verificación (smoke test)

- [ ] Login del **admin** en la app → ve sus obras.
- [ ] Login de un **supervisor** → ve solo sus obras asignadas (RLS).
- [ ] Entrega de EPP de prueba (foto + firma) → se registra y **descuenta stock**.
- [ ] La entrega aparece en el **dashboard** con el semáforo correcto.
- [ ] **Aislamiento:** el usuario NO ve datos de otra organización.
- [ ] Errores/health visibles en **Sentry** (`trazapp-app` / `trazapp-dashboard`).

---

## 5. App y distribución

- Compilar el APK **desde `main`** (trae todos los fixes + Sentry):
  `flutter build apk --release --flavor epp -t lib/main.dart`
  (firma: keystore en `~/.trazapp/`).
- **Suscripción:** decidir si se activa la verificación MIRA en el build
  (`--dart-define=MIRA_API_KEY=<clave>`). Para marcha blanca puede quedar
  *fail-open* (sin la key) para no bloquear al cliente por fallas del servicio.
- Distribuir el APK a los dispositivos del cliente (sideload / internal testing).

---

## 6. Checklist final

- [ ] Empresa creada en **MIRA** con plan/módulos activos.
- [ ] `organizaciones` en Supabase con el **mismo RUT**.
- [ ] Admin + supervisores creados (Auth + `perfiles` + `obra_usuarios`).
- [ ] Obras, bodegas, catálogo EPP y stock inicial cargados.
- [ ] Smoke test OK (entrega + descuento + dashboard + aislamiento).
- [ ] APK distribuido.
- [ ] (Cliente de pago) Supabase Pro + backups activos.
