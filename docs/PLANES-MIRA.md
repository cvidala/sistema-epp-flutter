# Composición de planes de TrazApp (MIRA)

Guía para el compositor de planes de TrazApp en MIRA. Define cómo se arman los
planes a partir de **módulos** y **submódulos**, y cómo se entregan a TrazApp.

> **Contrato relacionado:** `docs/PROVISIONING-API.md` (endpoint de aprovisionamiento).

---

## Cómo gatea TrazApp

MIRA es la fuente de verdad de empresas, planes y pagos. TrazApp (producto
`trazapp`) **gatea sus pestañas/secciones a partir de `config_modulos`**, un
snapshot booleano que MIRA envía al aprovisionar (push, server-to-server).
TrazApp **no** consulta el plan en vivo para gatear — la consulta viva solo actúa
de kill-switch global (activo/inactivo). Por eso, **cada plan se materializa como
un objeto `config_modulos` de 9 llaves** que se manda en el alta y en cada cambio
de plan.

El gating es **fail-open**: una llave ausente / `config_modulos` nulo / sin datos
→ NO oculta. Por eso hay que **enviar siempre las 9 llaves con booleano explícito**.

---

## Modelo: 4 módulos, 9 submódulos (llaves)

Un plan es un conjunto de **módulos completos**. Cada módulo agrupa submódulos
(llaves booleanas). **Regla de oro: no cruzar submódulos entre módulos.** Si un
módulo entra al plan, TODAS sus llaves van en `true`; si no entra, TODAS en `false`.

| Módulo | Estado hoy | Llaves (submódulos) | Qué enciende en el dashboard |
|---|---|---|---|
| **1 · Entrega EPP** | ✅ funcional | `gestion_epp`, `stock_bodega`, `solicitudes_epp`, `firma_digital`, `reportes_dt` | Entregas, Reglas, Stock, Alertas, Solicitudes, Reportes, bloque EPP del Resumen |
| **2 · Asistencia** | ✅ funcional | `marcaje_asistencia` | Asistencia Diaria (y bloque de Asistencia del Resumen — en construcción) |
| **3 · Documentación** | ⏳ próximamente | `contratos` | Contratos, Docs. Siniestro (placeholders) |
| **4 · Charlas / Prevención** | ⏳ próximamente | `prevencion` | Charlas/PTS, Asistente IA (placeholders) |
| **Transversal (base)** | ✅ | `dashboard` | Resumen General (home; su contenido se compone por módulo) |

**Las 9 llaves canónicas** (enviar SIEMPRE las 9, sin renombrar ni omitir):

```
gestion_epp, stock_bodega, solicitudes_epp, firma_digital, reportes_dt,
marcaje_asistencia, contratos, prevencion, dashboard
```

---

## Reglas de composición

1. **Módulo atómico**: nunca actives una llave suelta de un módulo sin el resto de
   ese módulo. En particular, `stock_bodega`, `solicitudes_epp` y `reportes_dt`
   **nunca** van sin `gestion_epp`.
2. **`dashboard` = siempre `true`** (home transversal; su contenido se compone solo
   según los módulos contratados).
3. **`firma_digital` = `true` solo si el módulo EPP está** en el plan (es la firma
   del trabajador al recibir EPP; no se vende suelta). Sin EPP → `false`.
4. **Módulos 3 y 4 (`contratos`, `prevencion`) son placeholders** ("🔒 Próximamente"):
   no se venden como activos por ahora. Solo van en `true` en el plan "Full".

### Lógica del compositor (pseudocódigo)

```js
// La selección del plan = qué MÓDULOS incluye (no llaves sueltas).
const config_modulos = {
  // Módulo Entrega EPP
  gestion_epp:        hasEPP,
  stock_bodega:       hasEPP,
  solicitudes_epp:    hasEPP,
  firma_digital:      hasEPP,
  reportes_dt:        hasEPP,
  // Módulo Asistencia
  marcaje_asistencia: hasAsistencia,
  // Módulo Documentación (próximamente)
  contratos:          hasDocumentacion,
  // Módulo Charlas (próximamente)
  prevencion:         hasCharlas,
  // Transversal
  dashboard:          true,
};
```

---

## Catálogo de planes y su `config_modulos` exacto

```jsonc
// Plan "EPP"
{ "gestion_epp": true, "stock_bodega": true, "solicitudes_epp": true, "firma_digital": true, "reportes_dt": true,
  "marcaje_asistencia": false, "contratos": false, "prevencion": false, "dashboard": true }

// Plan "Asistencia"
{ "gestion_epp": false, "stock_bodega": false, "solicitudes_epp": false, "firma_digital": false, "reportes_dt": false,
  "marcaje_asistencia": true, "contratos": false, "prevencion": false, "dashboard": true }

// Plan "EPP + Asistencia"
{ "gestion_epp": true, "stock_bodega": true, "solicitudes_epp": true, "firma_digital": true, "reportes_dt": true,
  "marcaje_asistencia": true, "contratos": false, "prevencion": false, "dashboard": true }

// Plan "Full"  (contratos / prevencion = incluidos, "próximamente")
{ "gestion_epp": true, "stock_bodega": true, "solicitudes_epp": true, "firma_digital": true, "reportes_dt": true,
  "marcaje_asistencia": true, "contratos": true, "prevencion": true, "dashboard": true }
```

> Un plan "Asistencia solo" hoy no muestra bloque en el Resumen (el bloque de
> Asistencia está en construcción — Fase 2); mientras tanto el Resumen muestra un
> empty-state. EPP / EPP+Asistencia / Full ven el Resumen EPP normal.

---

## Capacidad (2º eje del plan): `limites`

Además de los módulos, cada plan tiene una **capacidad** = topes de cantidad, que
se cobra por tramos (el costo real escala con el nº de trabajadores → storage de
fotos). Se envía como objeto `limites` junto al `config_modulos`:

```json
"limites": { "max_trabajadores": 100, "max_usuarios": 5, "max_obras": 6 }
```

- Entero = tope · `null` o llave ausente (o `limites` completo ausente) = **sin tope**.
- TrazApp **bloquea de forma dura en el servidor** la creación al llegar al tope
  (trigger en BD, a prueba de bypass), con un mensaje claro al admin. Cuenta:
  trabajadores `estado=ACTIVO`, usuarios (perfiles) `activo=true`, obras `estado=ACTIVA`.
  Dar de baja libera cupo.
- Los topes son **dato por empresa, editables sin tocar código**: MIRA los rellena
  por tramo y puede **overridearlos por empresa** re-aprovisionando (o editando
  `organizaciones.limites`). Así se sube/baja el tope de un cliente puntual sin
  cambiar de tramo ni desplegar.

### Tramos sugeridos (los números y precios los define MIRA)

| Tramo | max_trabajadores | max_usuarios | max_obras |
|---|---|---|---|
| **S** | 50 | 3 | 3 |
| **M** | 100 | 5 | 6 |
| **L** | 200 | 8 | 12 |
| **XL** | 350 | 12 | 25 |
| **Enterprise** | `null` | `null` | `null` |

El tramo **rellena** `limites`, pero MIRA debe permitir **editar los 3 números por
empresa** (override manual desde el superadmin), defaulteando desde el tramo.

**Precio final = módulos (qué) × tramo de capacidad (cuánto).**

## Cómo entregar el plan a TrazApp

**Alta nueva** y **cambio de plan** usan el mismo endpoint (idempotente por `rut`):

```
POST https://ppltpmmtdnprgauwnytf.supabase.co/functions/v1/provision-organizacion
Header: x-trazapp-provision-key: <TRAZAPP_PROVISION_KEY>
```

```json
{
  "rut": "76.123.456-7",
  "razon_social": "Constructora Demo SpA",
  "admin": { "email": "admin@empresa.cl", "nombre": "Nombre Admin" },
  "config_modulos": { "...las 9 llaves del plan elegido..." },
  "limites": { "max_trabajadores": 100, "max_usuarios": 5, "max_obras": 6 }
}
```

- **Empresa nueva** → `accion: "created"`: crea org + admin, devuelve
  `credenciales.password_temporal` (entregar al cliente).
- **Cambio de plan** (mismo `rut`) → `accion: "updated"`: actualiza **solo**
  `config_modulos`. **No toca credenciales** (`password_temporal: null`). Es el
  mecanismo para propagar un cambio de plan; se refleja en TrazApp en el próximo
  ingreso/refresco del dashboard.

El `rut` DEBE coincidir con el RUT de la suscripción en MIRA (llave de idempotencia).
Ver el contrato completo en `docs/PROVISIONING-API.md`.
