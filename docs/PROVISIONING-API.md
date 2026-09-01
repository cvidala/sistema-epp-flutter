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
  "config_modulos": { "gestion_epp": true, "asistencia": false, "prevencion": false, "dashboard": true },
  "admin": { "email": "admin@empresa.cl", "nombre": "Nombre Admin" },
  "plan": "piloto"
}
```

| Campo | Req | Nota |
|-------|-----|------|
| `rut` | ✔ | Llave de idempotencia. **Debe coincidir** con el RUT de la suscripción en MIRA. |
| `razon_social` | ✔ | Se guarda en `razon_social` y `nombre_empresa`. |
| `config_modulos` | – | Claves del contrato unificado MIRA/JSV. Default: EPP + dashboard. |
| `admin.email` | ✔ | Email del usuario ADMIN. |
| `admin.nombre` | ✔ | Nombre del ADMIN. |
| `plan` | – | Informativo. |

## Respuestas

**200 — OK**
```json
{
  "ok": true,
  "org_id": "<uuid>",
  "admin_user_id": "<uuid>",
  "dedup": false,
  "credenciales": { "email": "admin@empresa.cl", "password_temporal": "…", "modo": "password_temporal" }
}
```
- `dedup: true` → la organización ya existía (no se duplicó).
- `credenciales.modo`:
  - `password_temporal` → usuario admin recién creado; MIRA entrega la contraseña temporal al cliente (debe cambiarla al ingresar).
  - `existente` → el admin ya existía en Auth; no se devuelve contraseña.

> **Futuro:** cuando Supabase tenga SMTP configurado, migrar a *invite email*
> (el admin define su propia contraseña por enlace) en vez de contraseña temporal.

**Errores** — `{ "ok": false, "error": "...", "code": "..." }`
| HTTP | code | Caso |
|------|------|------|
| 401 | AUTH | Secreto ausente o inválido |
| 400 | BAD_REQUEST / VALIDATION | JSON inválido o faltan campos |
| 409 | ADMIN_LOOKUP | El admin existe en Auth pero no se pudo resolver |
| 500 | — | Error interno (detalle en `detail`) |

## Idempotencia

- **Organización:** por `rut`. Reintentar con el mismo RUT devuelve la existente (`dedup:true`).
- **Perfil admin:** `upsert` por `user_id` (no duplica).

## Ejemplo (curl, lo que hará MIRA)

```bash
curl -X POST https://ppltpmmtdnprgauwnytf.supabase.co/functions/v1/provision-organizacion \
  -H 'Content-Type: application/json' \
  -H 'x-trazapp-provision-key: <SECRETO>' \
  -d '{
    "rut": "76.123.456-7",
    "razon_social": "Constructora Demo SpA",
    "config_modulos": {"gestion_epp": true, "asistencia": false, "prevencion": false, "dashboard": true},
    "admin": {"email": "admin@empresa.cl", "nombre": "Nombre Admin"}
  }'
```

## Qué hace la función (resumen)

1. Valida el secreto.
2. Busca org por `rut`; si no existe, la crea (`activo=true`, `config_modulos`).
3. Crea el usuario ADMIN en Auth (Admin API, `email_confirm=true`, contraseña temporal).
4. `upsert` del perfil `ADMIN` ligado a la org.
5. Devuelve `org_id`, `admin_user_id` y las credenciales.

Después: el admin entra al dashboard y da de alta centros, catálogo/reglas EPP,
stock, supervisores y trabajadores (todo self-service). Ver `docs/ONBOARDING.md`.
