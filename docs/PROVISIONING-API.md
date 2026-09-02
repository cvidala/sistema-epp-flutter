# API de aprovisionamiento — MIRA → TrazApp

Contrato de la Edge Function que **MIRA** llama (server-to-server) al dar de alta
una empresa en `/superadmin`. Crea en TrazApp la **organización** + el **usuario
ADMIN**. El resto del setup (obras, catálogo EPP, stock, supervisores,
trabajadores) lo hace el admin **self-service** en el dashboard.

> Diseño acordado: **push** (MIRA llama a TrazApp) · **opción A** (MIRA aprovisiona
> solo org + admin; el admin gestiona a sus supervisores en el dashboard).

---

## Endpoint

```
POST https://ppltpmmtdnprgauwnytf.supabase.co/functions/v1/provision-organizacion
```

## Autenticación

Secreto compartido en header (no requiere JWT de usuario — la función se despliega
con `--no-verify-jwt`):

```
x-trazapp-provision-key: <TRAZAPP_PROVISION_KEY>
```

El secreto lo custodia TrazApp (guardado como secret de Supabase) y se entrega a
MIRA por canal seguro. Si se compromete, se regenera de ambos lados.

## Request (JSON)

```json
{
  "rut": "76.123.456-7",
  "razon_social": "Constructora Demo SpA",
  "config_modulos": {
    "gestion_epp": true, "stock_bodega": true, "solicitudes_epp": true,
    "firma_digital": true, "reportes_dt": true, "dashboard": true,
    "marcaje_asistencia": false, "contratos": false, "prevencion": false
  },
  "admin": { "email": "admin@empresa.cl", "nombre": "Nombre Admin" },
  "plan": "piloto"
}
```

| Campo | Req | Nota |
|-------|-----|------|
| `rut` | ✔ | Llave de idempotencia. **Debe coincidir** con el RUT de la suscripción en MIRA. |
| `razon_social` | ✔ | Se guarda en `razon_social` y `nombre_empresa`. |
| `config_modulos` | – | **Contrato canónico de 9 llaves booleanas** (ver `docs/PLANES-MIRA.md`): `gestion_epp, stock_bodega, solicitudes_epp, firma_digital, reportes_dt, marcaje_asistencia, contratos, prevencion, dashboard`. Se guarda **tal cual** (sin renombrar ni filtrar). Enviar siempre las 9. Default si se omite: plan EPP + asistencia off. |
| `admin.email` | ✔ | Email del usuario ADMIN. |
| `admin.nombre` | ✔ | Nombre del ADMIN. |
| `plan` | – | Informativo. |

## Respuestas

**200 — OK (alta nueva)**
```json
{
  "ok": true,
  "org_id": "<uuid>",
  "admin_user_id": "<uuid>",
  "dedup": false,
  "accion": "created",
  "credenciales": { "email": "admin@empresa.cl", "password_temporal": "…", "modo": "password_temporal" }
}
```

**200 — OK (re-aprovisionamiento / cambio de plan)**
```json
{
  "ok": true,
  "org_id": "<uuid>",
  "admin_user_id": "<uuid>",
  "dedup": true,
  "accion": "updated",
  "credenciales": { "email": "admin@empresa.cl", "password_temporal": null, "modo": "sin_cambios" }
}
```
- `accion`:
  - `created` → org nueva: se creó org + admin y se devuelve `password_temporal`.
  - `updated` → la org **ya existía** (mismo `rut`): se **sincroniza solo `config_modulos`** y se retorna de inmediato, **sin tocar Auth ni el perfil**. Un cambio de plan **nunca** cambia credenciales (`password_temporal: null`, `modo: "sin_cambios"`).
- `dedup: true` ⇔ `accion: "updated"`.
- `credenciales.modo`:
  - `password_temporal` → admin recién creado; MIRA entrega la contraseña temporal al cliente (debe cambiarla al ingresar).
  - `existente` → en alta nueva, el admin ya existía en Auth; no se devuelve contraseña.
  - `sin_cambios` → re-aprovisionamiento; no se tocaron credenciales.

> **Futuro:** cuando Supabase tenga SMTP configurado, migrar a *invite email*
> (el admin define su propia contraseña por enlace) en vez de contraseña temporal.

**Errores** — `{ "ok": false, "error": "...", "code": "..." }`
| HTTP | code | Caso |
|------|------|------|
| 401 | AUTH | Secreto ausente o inválido |
| 400 | BAD_REQUEST / VALIDATION | JSON inválido o faltan campos |
| 409 | ADMIN_LOOKUP | El admin existe en Auth pero no se pudo resolver |
| 500 | — | Error interno (detalle en `detail`) |

## Idempotencia y cambio de plan

- **Organización:** por `rut`. Reintentar con el mismo RUT no la duplica.
- **Cambio de plan:** re-llamar al endpoint con el mismo `rut` y un `config_modulos` distinto → `accion:"updated"` actualiza **solo** `config_modulos`. Es el mecanismo oficial para propagar un cambio de plan de MIRA a TrazApp (se refleja en el próximo ingreso/refresco del dashboard). No se tocan credenciales ni otros campos de la organización.
- **Perfil admin:** en alta nueva, `upsert` por `user_id` (no duplica). En re-aprovisionamiento no se toca.

## Ejemplo (curl, lo que hará MIRA)

```bash
curl -X POST https://ppltpmmtdnprgauwnytf.supabase.co/functions/v1/provision-organizacion \
  -H 'Content-Type: application/json' \
  -H 'x-trazapp-provision-key: <SECRETO>' \
  -d '{
    "rut": "76.123.456-7",
    "razon_social": "Constructora Demo SpA",
    "config_modulos": {"gestion_epp": true, "stock_bodega": true, "solicitudes_epp": true, "firma_digital": true, "reportes_dt": true, "dashboard": true, "marcaje_asistencia": false, "contratos": false, "prevencion": false},
    "admin": {"email": "admin@empresa.cl", "nombre": "Nombre Admin"}
  }'
```

## Qué hace la función (resumen)

1. Valida el secreto.
2. Busca org por `rut`.
   - **No existe** (`created`): la crea (`activo=true`, `config_modulos`), crea el usuario ADMIN en Auth (Admin API, `email_confirm=true`, contraseña temporal) y hace `upsert` del perfil `ADMIN`. Devuelve `org_id`, `admin_user_id` y las credenciales.
   - **Ya existe** (`updated`): actualiza **solo** `config_modulos` y retorna de inmediato, **sin tocar Auth ni el perfil**. `password_temporal: null`.

Después (solo en alta nueva): el admin entra al dashboard y da de alta centros,
catálogo/reglas EPP, stock, supervisores y trabajadores (todo self-service). Ver
`docs/ONBOARDING.md`. La composición de planes (módulos/submódulos) está en
`docs/PLANES-MIRA.md`.
