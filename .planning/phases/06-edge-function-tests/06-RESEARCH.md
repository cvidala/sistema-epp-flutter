# Phase 6: Edge Function Tests - Research

**Investigado:** 2026-06-14
**Dominio:** Deno unit tests para Supabase Edge Functions (TypeScript / Deno runtime)
**Confianza:** HIGH

---

## Resumen

`notif-vencimiento/index.ts` es una Edge Function de Deno que corre via `Deno.serve`. Actualmente NO exporta ninguna función pura — `buildEmailHtml` y `formatFecha` son funciones de módulo no exportadas. El refactor requiere: (1) exportar `buildEmailHtml`, `formatFecha` y los tipos `Vencimiento`/`Destinatario`; (2) agregar la guardia `DRY_RUN` al inicio del handler; (3) crear `supabase/functions/tests/notif-vencimiento-test.ts` con tests Deno que stubean `globalThis.fetch` y no necesitan Supabase real. La lógica de negocio (agrupación por org, filtrado de críticos/avisos, construcción del asunto) puede extraerse en una función pura adicional `buildNotifPayload()` o testearse importando directamente las funciones ya existentes.

El único cambio de toolchain del equipo es agregar un job Deno separado en `.github/workflows/test.yml` usando `denoland/setup-deno@v2`. Este job NO necesita Flutter, no necesita secrets de Supabase ni de Resend, y corre `deno test supabase/functions/tests/ --allow-env --allow-net=false` (o simplemente `--allow-all` con fetch stubbeado).

**Recomendación principal:** Refactorizar `index.ts` con exports mínimos (guardia DRY_RUN + exportar funciones puras), crear `supabase/functions/tests/notif-vencimiento-test.ts`, agregar job Deno en CI. No se necesitan packages externos — todo corre con `jsr:@std/assert` y `jsr:@std/testing/mock` del ecosistema estándar de Deno.

---

<phase_requirements>
## Phase Requirements

| ID | Descripcion | Soporte en esta investigacion |
|----|-------------|-------------------------------|
| EFN-01 | `notif-vencimiento/index.ts` tiene guardia `DRY_RUN` que bloquea envio de emails en test | Patron DRY_RUN documentado — `Deno.env.get('DRY_RUN')` al inicio del handler |
| EFN-02 | Logica de agrupacion/filtrado extraida en funcion pura testeable sin Supabase ni Resend | `buildEmailHtml` ya existe como funcion no-exportada; requiere `export`; logica de negocio interna al handler puede extraerse como `buildNotifPayload()` |
| EFN-03 | Tests Deno verifican que `buildEmailHtml()` genera HTML correcto | Patron verificado: importar funcion pura, llamar con datos de fixture, `assertStringIncludes` sobre el HTML |
| EFN-04 | Tests Deno stubean `globalThis.fetch` para capturar payload Resend sin enviar emails reales | Patron verificado: `spy(async (url, init) => ...)` + `globalThis.fetch = mockFetch` + `assertSpyCalls` + `fetchStub.calls[0].args` |
| EFN-05 | CI ejecuta `deno test supabase/functions/tests/` en job separado con `denoland/setup-deno@v2` | Configuracion YAML verificada — job independiente, sin Flutter setup |

</phase_requirements>

---

## Mapa de Responsabilidades Arquitecturales

| Capacidad | Tier Primario | Tier Secundario | Razon |
|-----------|--------------|-----------------|-------|
| Guardia DRY_RUN | Edge Function (Deno) | — | La guardia vive en el handler que decide si enviar o no |
| `buildEmailHtml()` pura | Edge Function (Deno) | — | Funcion de presentacion sin I/O; candidata a export |
| `buildNotifPayload()` pura (opcional) | Edge Function (Deno) | — | Logica de agrupacion por org sin Supabase |
| Stub de `globalThis.fetch` | Test layer (Deno) | — | Intercepta la llamada HTTP a Resend en memoria |
| Job CI Deno | GitHub Actions | — | Job separado del job Flutter; no comparte setup |
| Tests unitarios Deno | `supabase/functions/tests/` | — | Convencion oficial Supabase para tests de funciones |

---

## Stack Estandar

### Core

| Libreria | Version | Proposito | Por que es estandar |
|---------|---------|-----------|---------------------|
| `jsr:@std/assert` | `@1` (latest v1.x) | Assertions: `assertEquals`, `assertStringIncludes`, `assertExists` | Stdlib oficial de Deno — sin deps externas [VERIFIED: docs.deno.com] |
| `jsr:@std/testing/mock` | `@1` (latest v1.x) | `spy`, `stub`, `assertSpyCalls`, `returnsNext` para stubear fetch | Stdlib oficial de Deno [VERIFIED: docs.deno.com] |
| `denoland/setup-deno@v2` | `v2.0.4` (latest tag) | GitHub Action para instalar Deno en CI | Action oficial del equipo de Deno [VERIFIED: github.com/denoland/setup-deno] |

### Supporting

| Libreria | Version | Proposito | Cuando usar |
|---------|---------|-----------|-------------|
| `deno-version: v2.x` | canal stable | Especificacion de version en setup-deno | Fija el canal sin anclar a patch version [VERIFIED: docs.deno.com/runtime/reference/continuous_integration] |

### Alternativas Descartadas

| En lugar de | Se podria usar | Tradeoff |
|------------|---------------|----------|
| `jsr:@std/testing/mock` | `globalThis.fetch = async () => ...` manual | Mock manual funciona pero no provee `assertSpyCalls` ni restauracion automatica |
| Job Deno separado | Step adicional en el job Flutter | Job separado es lo requerido por EFN-05 y es mas limpio — sin Flutter overhead |

### Instalacion

```bash
# No hay instalacion npm. Deno resuelve jsr: y npm: al momento de correr deno test.
# Verificar que Deno este disponible en CI:
# denoland/setup-deno@v2 con deno-version: v2.x
```

---

## Auditoria de Legitimidad de Paquetes

Esta fase NO instala packages npm. Las dependencias son del ecosistema Deno y se resuelven via especificadores `jsr:` y `npm:` en tiempo de ejecucion. No aplica slopcheck (herramienta npm).

| Modulo | Registro | Edad | Uso | Repo | Verificacion | Disposicion |
|--------|----------|------|-----|------|-------------|-------------|
| `jsr:@std/assert@1` | JSR | >2 anos | Assertions | github.com/denoland/std | Stdlib oficial Deno | Aprobado |
| `jsr:@std/testing/mock@1` | JSR | >2 anos | Mocking/spies | github.com/denoland/std | Stdlib oficial Deno | Aprobado |
| `denoland/setup-deno@v2` | GitHub Actions | >2 anos | CI Action | github.com/denoland/setup-deno | Action oficial Deno team | Aprobado |

**Paquetes eliminados por slopcheck [SLOP]:** ninguno (slopcheck no aplica a modulos Deno/JSR)
**Paquetes marcados [SUS]:** ninguno

---

## Patrones de Arquitectura

### Diagrama de Arquitectura del Sistema

```
Test runner (deno test)
        |
        v
notif-vencimiento-test.ts
        |
        |-- import "../notif-vencimiento/index.ts"  (pure exports only)
        |         |
        |         +--> buildEmailHtml(todos, criticos, avisos) --> string HTML
        |         +--> formatFecha(iso) --> string
        |         +--> Vencimiento interface (type-only)
        |
        |-- globalThis.fetch = spy(mockFetch)  ← stub antes de llamar al handler
        |
        |-- [test buildEmailHtml]: llama funcion pura con fixture, assert HTML
        |-- [test DRY_RUN]: Deno.env.set('DRY_RUN','1'), invoca handler,
        |   assert fetch NO fue llamado
        |-- [test payload Resend]: invoca handler con fetch stubbeado,
        |   captura calls[0].args, assert URL + body JSON
        |
        v
Resultados sin red, sin Supabase, sin emails reales
```

### Estructura de Proyecto Recomendada

```
supabase/
├── functions/
│   ├── notif-vencimiento/
│   │   └── index.ts          # refactorizado: DRY_RUN guard + exports
│   └── tests/
│       ├── deno.json         # imports para jsr:@std/* (opcional pero recomendado)
│       └── notif-vencimiento-test.ts
```

> Nota: `deno.json` dentro de `tests/` es opcional si se usan especificadores `jsr:` directamente en los imports del test file. Supabase recomienda el directorio `functions/tests/` con naming `[function-name]-test.ts`. [CITED: supabase.com/docs/guides/functions/unit-test]

### Patron 1: Guardia DRY_RUN (EFN-01)

**Que hace:** Lee `Deno.env.get('DRY_RUN')` al inicio del handler. Si esta presente, retorna inmediatamente sin llamar a Supabase ni a Resend.

**Cuando usar:** Siempre que CI ejecute los tests — la variable de entorno `DRY_RUN=1` debe estar setteada en el step de CI del job Deno.

```typescript
// Source: patron de diseno, verificado contra EFN-01 success criteria
Deno.serve(async () => {
  // ── DRY_RUN guard (test safety) ─────────────────────
  if (Deno.env.get('DRY_RUN')) {
    return new Response('DRY_RUN: no emails sent.', { status: 200 });
  }

  try {
    // ... logica normal
  } catch (e) {
    return new Response(`Error: ${e.message}`, { status: 500 });
  }
});
```

**Alternativa si el test necesita ejercer la logica completa:** No setear `DRY_RUN` y stubbear `globalThis.fetch` directamente (Patron 3). DRY_RUN es para el caso en que NO queremos ejecutar nada del handler.

### Patron 2: Exportar funciones puras (EFN-02, EFN-03)

**Que hace:** Agrega `export` a `buildEmailHtml` y `formatFecha` en `index.ts`. Los tests los importan directamente con ruta relativa.

```typescript
// supabase/functions/notif-vencimiento/index.ts
export interface Vencimiento { ... }  // export del tipo tambien

// export de funcion pura (sin Supabase, sin fetch)
export function buildEmailHtml(
  todos: Vencimiento[],
  criticos: Vencimiento[],
  avisos: Vencimiento[]
): string { ... }

export function formatFecha(iso: string): string { ... }
```

```typescript
// supabase/functions/tests/notif-vencimiento-test.ts
// Source: patron verificado en docs.deno.com/runtime/fundamentals/testing
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { buildEmailHtml, type Vencimiento } from '../notif-vencimiento/index.ts';

const fixture: Vencimiento = {
  org_id: 'org-1',
  trabajador_nombre: 'Juan Perez',
  trabajador_rut: '12.345.678-9',
  obra_nombre: 'Obra Norte',
  epp_nombre: 'Casco',
  epp_codigo: 'CASC-001',
  dias_restantes: 3,
  fecha_vencimiento: '2026-06-17',
  nivel_alerta: 'CRITICO',
};

Deno.test('buildEmailHtml incluye nombre del trabajador', () => {
  const html = buildEmailHtml([fixture], [fixture], []);
  assertStringIncludes(html, 'Juan Perez');
  assertStringIncludes(html, '3 dias');
  assertStringIncludes(html, 'Casco');
});
```

### Patron 3: Stub de globalThis.fetch para capturar payload Resend (EFN-04)

**Que hace:** Reemplaza `globalThis.fetch` con un spy que captura URL, headers y body antes de que lleguen a la red. Permite verificar que el payload enviado a Resend es correcto sin enviar emails reales.

**Fuente verificada:** [docs.deno.com/examples/web_testing_tutorial](https://docs.deno.com/examples/web_testing_tutorial/) — ejemplo completo de spy sobre fetch global.

```typescript
// Source: docs.deno.com/examples/web_testing_tutorial (VERIFIED)
import { assertSpyCalls, spy } from 'jsr:@std/testing/mock@1';
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';

Deno.test('handler envia payload correcto a Resend', async () => {
  let capturedUrl = '';
  let capturedBody: Record<string, unknown> = {};

  const originalFetch = globalThis.fetch;

  const mockFetch = spy(async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    capturedUrl = input.toString();
    capturedBody = JSON.parse(init?.body as string ?? '{}');
    return new Response(JSON.stringify({ id: 'email-123' }), { status: 200 });
  });

  globalThis.fetch = mockFetch;

  try {
    // Preparar Deno.env con mocks
    Deno.env.set('SUPABASE_URL', 'https://mock.supabase.co');
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'mock-key');
    Deno.env.set('RESEND_API_KEY', 'mock-resend-key');

    // Llamar a la funcion que construye y envia el email
    // (la logica extraida que llama a fetch)
    await sendEmailForOrg(destinatariosFixture, itemsFixture);

    assertSpyCalls(mockFetch, 1);
    assertEquals(capturedUrl, 'https://api.resend.com/emails');
    assertStringIncludes(capturedBody.html as string, 'Juan Perez');
    assertEquals(capturedBody.to, ['admin@empresa.com']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
```

> **Nota critica:** El handler actual `Deno.serve(async () => {...})` llama a Supabase ANTES de llamar a Resend (fetch). Para testear el payload Resend sin Supabase real, la logica de envio de email debe extraerse en una funcion separada testeable (`sendEmailForOrg` o similar), o bien se deben stubbear AMBOS: la llamada a `createClient` (via mock del modulo esm.sh) Y `globalThis.fetch`. La opcion mas simple es extraer la logica de envio en una funcion pura adicional que reciba destinatarios e items como argumentos, ya que eso elimina la dependencia de Supabase del test.

### Patron 4: Job Deno en GitHub Actions (EFN-05)

**Que hace:** Agrega un job `deno-test` paralelo al job `test` existente en `.github/workflows/test.yml`. El job NO tiene dependencia `needs:` del job Flutter — corren en paralelo.

```yaml
# Source: docs.deno.com/runtime/reference/continuous_integration (VERIFIED)
# Agregar a .github/workflows/test.yml despues del job test: existente

  deno-test:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Deno
        uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x

      - name: Edge Function Tests
        run: deno test supabase/functions/tests/ --allow-env --allow-read
        env:
          DRY_RUN: "1"
```

> **Nota sobre permisos Deno:** `--allow-env` es necesario porque `buildEmailHtml` usa `new Date()` y porque la guardia DRY_RUN lee `Deno.env`. `--allow-read` puede necesitarse si Deno resuelve imports locales. `--allow-net=false` es opcional — al stubbear fetch el test no hace llamadas de red reales, pero setear explicitamente la restriccion es una capa de seguridad adicional.

### Anti-Patrones a Evitar

- **Testear contra Supabase real desde el job Deno:** Requeriria secrets y perderia el valor de tests unitarios puros. Los tests de integracion completa contra Supabase estan diferidos a v3.
- **Importar `https://esm.sh/@supabase/supabase-js@2` en el test file:** Deno descargara el modulo aunque no lo uses. El test de `buildEmailHtml` no debe importar supabase-js.
- **Usar `import_map.json` (legacy):** Supabase lo soporta pero lo marca como legado. Preferir `deno.json` o especificadores `jsr:` directos en el test file.
- **Agregar el job Deno como step dentro del job Flutter:** EFN-05 requiere job separado. Un step adicional seria mas fragil (falla de Deno rompe el job entero de Flutter).
- **Olvidar restaurar `globalThis.fetch`:** Siempre en bloque `try/finally` o usando `using` keyword de Deno.

---

## No Construir a Mano

| Problema | No construyas | Usa en cambio | Por que |
|----------|--------------|---------------|---------|
| Verificar que fetch fue llamado N veces | Contador manual con closure | `assertSpyCalls(spy, N)` de `@std/testing/mock` | Maneja cleanup, acceso a args, assertion clara |
| Restaurar fetch despues del test | `try/finally` manual tedioso | `using fetchStub = stub(...)` (auto-restore) o `try/finally` explicito | Sin `using`, un test que falla puede dejar fetch stubbeado para tests posteriores |
| Parsear HTML generado | Regex sobre string HTML | `assertStringIncludes` + assertions de presencia | HTML inline con template literals no necesita parser para verificar contenido |
| Mock de Deno.env.get | Reescribir la funcion para recibir env como parametro | `Deno.env.set('KEY', 'value')` antes del test (Deno permite set en tests) | Mas simple; restaurar despues con `Deno.env.delete('KEY')` |

**Insight clave:** Las funciones puras de TypeScript en Deno no necesitan ningun framework de mocking si sus dependencias externas (Supabase, Resend) estan fuera de ellas. El 80% del valor de testing viene de exportar `buildEmailHtml` y testearla directamente.

---

## Pitfalls Comunes

### Pitfall 1: Top-level module execution al importar index.ts

**Que falla:** Al hacer `import { buildEmailHtml } from '../notif-vencimiento/index.ts'`, Deno ejecuta todo el modulo incluyendo `Deno.serve(...)`. Esto puede causar que el servidor HTTP se inicie o que las constantes con `Deno.env.get('SUPABASE_URL')!` fallen con `undefined!` (null assertion sobre undefined).

**Por que ocurre:** `Deno.serve` y las constantes con `!` son top-level — se ejecutan cuando el modulo se importa, no solo cuando se llama la funcion.

**Como evitar:** Dos estrategias:
1. **Mover constantes dentro del handler:** `const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';` dentro de `Deno.serve(async () => {...})`, no en el top-level. Asi la importacion del modulo no falla aunque las env vars no esten.
2. **Guard de entry point:** `if (import.meta.main) { Deno.serve(...) }` — el handler solo corre cuando el archivo es el entry point, no cuando es importado.

**Senal de alerta:** Error `TypeError: Cannot read property of undefined` o `null!` al ejecutar `deno test`.

**Recomendacion para este proyecto:** Usar `if (import.meta.main) { Deno.serve(...) }` porque es el patron mas limpio y no requiere reestructurar las constantes. Las funciones puras pueden quedar como exports de nivel de modulo.

### Pitfall 2: import.meta.url vs rutas relativas en deno test

**Que falla:** `deno test supabase/functions/tests/` desde la raiz del repo resuelve rutas relativas desde el directorio de trabajo, pero si el test file usa `new URL('../notif-vencimiento/', import.meta.url)` puede fallar si el CWD no es el esperado.

**Como evitar:** Usar solo imports de modulo estandar (`import X from '../notif-vencimiento/index.ts'`) — estos se resuelven relativo al archivo fuente, no al CWD. [CITED: docs.deno.com/runtime/fundamentals/testing]

### Pitfall 3: Olvido del DRY_RUN en CI antes de stubbear fetch

**Que falla:** Si el test ejercita la ruta completa del handler (con Supabase + fetch) sin DRY_RUN y sin stubbear fetch correctamente, Deno intentara conectar a `https://api.resend.com` en CI y fallara por timeout o por key invalida.

**Como evitar:** El job Deno en CI siempre debe tener `env: DRY_RUN: "1"`. Ademas, `--allow-net=false` como flag de `deno test` bloquea conexiones de red a nivel de runtime.

### Pitfall 4: Conflicto de permisos Deno

**Que falla:** `deno test` sin flags de permisos lanzara errores `PermissionDenied` si el codigo intenta leer env vars o hacer network.

**Como evitar:** Usar `--allow-env --allow-read` minimo. Si se desea maxima permisividad (y el stub de fetch es la unica proteccion de red): `--allow-all`. Para CI se recomienda `--allow-env --allow-read` (mas restrictivo es mejor).

### Pitfall 5: deno.json en `tests/` no es necesario pero si recomendado

**Que falla:** Sin `deno.json`, Deno 2.x puede mostrar warnings sobre imports sin lock file o puede tardar mas al resolver `jsr:` por primera vez.

**Como evitar:** Crear `supabase/functions/tests/deno.json` minimo:

```json
{
  "imports": {
    "@std/assert": "jsr:@std/assert@1",
    "@std/testing": "jsr:@std/testing@1"
  }
}
```

Esto permite usar `import { assertEquals } from '@std/assert'` en el test file (mas limpio). [CITED: supabase.com/docs/guides/functions/unit-test]

---

## Ejemplos de Codigo

### Estructura completa del archivo de test

```typescript
// supabase/functions/tests/notif-vencimiento-test.ts
// Source: patron oficial Supabase (supabase.com/docs/guides/functions/unit-test)
// + patron fetch spy (docs.deno.com/examples/web_testing_tutorial)

import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { assertSpyCalls, spy } from 'jsr:@std/testing/mock@1';
import {
  buildEmailHtml,
  formatFecha,
  type Vencimiento,
} from '../notif-vencimiento/index.ts';

// ── Fixtures ────────────────────────────────────────────────
const critico: Vencimiento = {
  org_id: 'org-1',
  trabajador_nombre: 'Juan Perez',
  trabajador_rut: '12.345.678-9',
  obra_nombre: 'Obra Norte',
  epp_nombre: 'Casco de Seguridad',
  epp_codigo: 'CASC-001',
  dias_restantes: 3,
  fecha_vencimiento: '2026-06-17',
  nivel_alerta: 'CRITICO',
};

const aviso: Vencimiento = {
  ...critico,
  epp_nombre: 'Chaleco Reflectante',
  epp_codigo: 'CHALV-002',
  dias_restantes: 20,
  fecha_vencimiento: '2026-07-04',
  nivel_alerta: 'AVISO',
};

// ── EFN-03: Tests de buildEmailHtml ────────────────────────
Deno.test('buildEmailHtml - incluye datos del trabajador critico', () => {
  const html = buildEmailHtml([critico], [critico], []);
  assertStringIncludes(html, 'Juan Perez');
  assertStringIncludes(html, '12.345.678-9');
  assertStringIncludes(html, 'Casco de Seguridad');
  assertStringIncludes(html, '3 d');  // "3 dias" en la tabla
});

Deno.test('buildEmailHtml - incluye seccion aviso cuando hay avisos', () => {
  const html = buildEmailHtml([aviso], [], [aviso]);
  assertStringIncludes(html, 'Chaleco Reflectante');
  assertStringIncludes(html, '20 d');
});

Deno.test('buildEmailHtml - no incluye seccion criticos cuando lista vacia', () => {
  const html = buildEmailHtml([aviso], [], [aviso]);
  // La seccion de criticos no debe aparecer
  assertEquals(html.includes('Vencimiento critico'), false);
});

// ── EFN-04: Test de payload Resend via fetch stub ───────────
// Requiere funcion exportada que llame a fetch (ver Pitfall 1)
// Ejemplo con funcion hipotetica sendResendEmail():
Deno.test('sendResendEmail - payload correcto a Resend API', async () => {
  const originalFetch = globalThis.fetch;

  let capturedUrl = '';
  let capturedBody: Record<string, unknown> = {};

  const mockFetch = spy(async (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    capturedUrl = input.toString();
    capturedBody = JSON.parse(init?.body as string ?? '{}');
    return new Response(JSON.stringify({ id: 'test-email-id' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  });

  globalThis.fetch = mockFetch;

  try {
    // Llamar a la funcion que encapsula el envio a Resend
    // (importada desde index.ts como export)
    const html = buildEmailHtml([critico], [critico], []);
    await sendResendEmail(
      ['admin@empresa.cl'],
      '🔴 1 EPP vence en 3 dias — TrazApp',
      html,
      'mock-resend-key',
    );

    assertSpyCalls(mockFetch, 1);
    assertEquals(capturedUrl, 'https://api.resend.com/emails');
    assertEquals(capturedBody.to, ['admin@empresa.cl']);
    assertStringIncludes(capturedBody.subject as string, 'TrazApp');
    assertStringIncludes(capturedBody.html as string, 'Juan Perez');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
```

### YAML del job Deno en CI

```yaml
# Source: docs.deno.com/runtime/reference/continuous_integration (VERIFIED)
# Agregar en .github/workflows/test.yml, al mismo nivel que el job 'test':

  deno-test:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Deno
        uses: denoland/setup-deno@v2
        with:
          deno-version: v2.x

      - name: Edge Function Tests (EFN-05)
        run: deno test supabase/functions/tests/ --allow-env --allow-read
        env:
          DRY_RUN: "1"
```

### Refactor minimo de index.ts (entry point guard + exports)

```typescript
// supabase/functions/notif-vencimiento/index.ts — cambios minimos
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Las constantes con ! quedan arriba solo para el handler (no se ejecutan al importar)
// Si se usa import.meta.main, las constantes dentro del bloque son seguras.

// ── Tipos exportados ──────────────────────────────────────
export interface Vencimiento { ... }
export interface Destinatario { ... }

// ── Funciones puras exportadas ────────────────────────────
export function buildEmailHtml(
  todos: Vencimiento[],
  criticos: Vencimiento[],
  avisos: Vencimiento[]
): string { ... }

export function formatFecha(iso: string): string { ... }

// ── Funcion de envio exportada (para test de payload Resend) ─
export async function sendResendEmail(
  to: string[],
  subject: string,
  html: string,
  apiKey: string,
): Promise<boolean> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: 'TrazApp <notificaciones@trazapp.cl>', to, subject, html }),
  });
  return res.ok;
}

// ── Entry point (solo cuando se ejecuta directamente) ─────
if (import.meta.main) {
  const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')!;
  const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const RESEND_API_KEY       = Deno.env.get('RESEND_API_KEY')!;

  Deno.serve(async () => {
    // ── DRY_RUN guard ─────────────────────────────────────
    if (Deno.env.get('DRY_RUN')) {
      return new Response('DRY_RUN: no emails sent.', { status: 200 });
    }

    try {
      const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
      // ... logica original sin cambios ...
    } catch (e) {
      return new Response(`Error: ${e.message}`, { status: 500 });
    }
  });
}
```

> **Alternativa a `import.meta.main`:** Si el planner prefiere no reestructurar la funcion por completo, la alternativa es dejar `Deno.serve` en el top level pero mover las constantes con `!` dentro del handler. Ambas opciones son validas; `import.meta.main` es mas idiomatico en Deno para libraries que tambien son executables.

---

## Estado del Arte

| Enfoque Antiguo | Enfoque Actual | Cuando Cambio | Impacto |
|----------------|----------------|---------------|---------|
| `import_map.json` | `deno.json` con `imports:` | Deno 1.28+ / Supabase CLI 1.215+ | `import_map.json` sigue funcionando pero es legacy |
| `https://deno.land/std@0.192.0/testing/asserts.ts` | `jsr:@std/assert@1` | Deno 1.38+ (JSR launch) | Especificador JSR es mas corto y tiene versionado semantico |
| `denoland/setup-deno@v1` | `denoland/setup-deno@v2` | Oct 2024 (Deno 2.0 release) | v2 del action soporta Deno 2.x; v1 sigue funcionando pero no es recomendado |
| `deno test --allow-all` sin restricciones | `deno test --allow-env --allow-read` con permisos minimos | Siempre fue posible | Mejor practica de seguridad en CI |

**Obsoleto/no recomendado:**
- `deno.land/x/mock` (third-party): reemplazado por `jsr:@std/testing/mock` (oficial)
- `import_map.json` standalone: usar `deno.json` con clave `"imports"` en su lugar

---

## Preguntas Abiertas

1. **Estrategia de extraccion: `sendResendEmail` vs. testear con handler completo**
   - Lo que sabemos: `buildEmailHtml` ya existe y puede exportarse. El test EFN-04 requiere verificar el payload a Resend, que ocurre dentro del loop del handler.
   - Lo que no esta claro: Si extraer `sendResendEmail` como funcion exportada es preferible a stubbear fetch y luego simular tambien la respuesta de Supabase (mucho mas complejo).
   - Recomendacion: Extraer `sendResendEmail(to, subject, html, apiKey)` — es el refactor minimo que habilita EFN-04 sin necesitar mock de Supabase.

2. **`deno.json` en `tests/` vs. especificadores directos `jsr:`**
   - Lo que sabemos: Ambas opciones funcionan. `jsr:` directo es mas verboso pero sin config extra. `deno.json` con imports es mas limpio.
   - Lo que no esta claro: Si el planner quiere un `deno.json` a nivel de `supabase/functions/` que cubra todas las funciones, o uno especifico en `tests/`.
   - Recomendacion: `deno.json` solo dentro de `tests/` — es el scope mas pequeno y no afecta el deploy de la funcion en Supabase.

3. **Permisos Deno en CI: `--allow-all` vs. permisos granulares**
   - Lo que sabemos: `--allow-env --allow-read` es suficiente si los tests no hacen network real (fetch stubbeado).
   - Recomendacion: Usar `--allow-env --allow-read` (minimos necesarios). Si aparecen errores de permisos durante implementacion, agregar el permiso especifico, no escalcar a `--allow-all`.

---

## Disponibilidad del Entorno

| Dependencia | Requerida por | Disponible | Version | Fallback |
|------------|--------------|-----------|---------|----------|
| Deno runtime | `deno test` local | ✗ (no instalado en esta maquina) | — | CI usa `denoland/setup-deno@v2`; para desarrollo local: `brew install deno` o `curl -fsSL https://deno.land/install.sh \| sh` |
| `denoland/setup-deno@v2` | Job Deno en CI | ✓ (Action existe en GitHub Marketplace) | v2.0.4 (tag latest) | — |
| `jsr:@std/assert@1` | Tests Deno | ✓ (resuelto por Deno al ejecutar tests) | v1.x | — |
| `jsr:@std/testing/mock@1` | Tests Deno | ✓ (resuelto por Deno al ejecutar tests) | v1.x | — |

**Dependencias faltantes sin fallback:** Ninguna (CI instala Deno automaticamente con el Action).

**Dependencias faltantes con fallback (desarrollo local):**
- Deno no esta instalado localmente. El desarrollador puede correr los tests en CI o instalar Deno localmente: `brew install deno` (macOS).

---

## Arquitectura de Validacion

### Framework de Tests

| Propiedad | Valor |
|-----------|-------|
| Framework | Deno built-in test runner (`deno test`) |
| Config file | `supabase/functions/tests/deno.json` (a crear en Wave 0) |
| Comando rapido | `deno test supabase/functions/tests/ --allow-env --allow-read` |
| Suite completa | Igual (solo hay un archivo de tests por ahora) |

### Mapa de Requisitos a Tests

| Req ID | Comportamiento | Tipo de Test | Comando Automatizado | Archivo existe |
|--------|---------------|-------------|---------------------|----------------|
| EFN-01 | `DRY_RUN` presente retorna 200 sin llamar fetch | unit (Deno) | `deno test supabase/functions/tests/ --allow-env` | ❌ Wave 0 |
| EFN-02 | `buildEmailHtml()` exportada y pura | refactor + unit | `deno test supabase/functions/tests/ --allow-env` | ❌ Wave 0 |
| EFN-03 | `buildEmailHtml()` genera HTML correcto para fixture de trabajador | unit (Deno) | `deno test supabase/functions/tests/notif-vencimiento-test.ts --allow-env` | ❌ Wave 0 |
| EFN-04 | Stub de `globalThis.fetch` captura payload Resend | unit (Deno) | `deno test supabase/functions/tests/notif-vencimiento-test.ts --allow-env` | ❌ Wave 0 |
| EFN-05 | Job Deno en CI pasa en verde | CI integration | GitHub Actions `deno-test` job | ❌ Wave 0 |

### Tasa de Muestreo

- **Por commit:** `deno test supabase/functions/tests/ --allow-env --allow-read`
- **Por merge:** Mismo comando (la suite completa es rapida — estimado < 10 segundos)
- **Gate de fase:** Suite verde antes de `/gsd-verify-work`

### Gaps de Wave 0 (archivos a crear antes de implementar)

- [ ] `supabase/functions/tests/notif-vencimiento-test.ts` — cubre EFN-01, EFN-03, EFN-04
- [ ] `supabase/functions/tests/deno.json` — config de imports para `@std/assert` y `@std/testing`
- [ ] Refactor de `supabase/functions/notif-vencimiento/index.ts` — exports + DRY_RUN guard + `import.meta.main`

---

## Dominio de Seguridad

> `security_enforcement: true` en config.json. ASVS level 1.

### Categorias ASVS Aplicables

| Categoria ASVS | Aplica | Control Estandar |
|---------------|--------|-----------------|
| V2 Authentication | No | Tests no autentican usuarios |
| V3 Session Management | No | No hay sesiones en los tests |
| V4 Access Control | No | Tests son offline, sin Supabase |
| V5 Input Validation | Si (parcial) | Los fixtures de test deben cubrir edge cases: arrays vacios, HTML injection en nombres |
| V6 Cryptography | No | No se usa crypto en los tests |

### Patrones de Amenaza Conocidos para este Stack

| Patron | STRIDE | Mitigacion Estandar |
|--------|--------|---------------------|
| API key de Resend expuesta en logs de CI | Disclosure | `DRY_RUN=1` en el job Deno — nunca se usa RESEND_API_KEY real; el stub no necesita key real |
| Email enviado a usuarios reales en CI | Tampering | `DRY_RUN` guard + stub de fetch — doble capa de proteccion |
| HTML injection via datos de trabajador (epp_nombre, obra_nombre) | Tampering | `buildEmailHtml` usa template literals, no sanitizacion. El test debe incluir un fixture con caracteres especiales `<script>` para verificar que el HTML no es ejecutable. Scope: solo documentar, no bloquear — es un email internal. |

---

## Fuentes

### Primarias (HIGH confidence)

- [docs.deno.com/runtime/fundamentals/testing](https://docs.deno.com/runtime/fundamentals/testing/) — convenciones de naming, flags de `deno test`, permisos, deno.json config
- [docs.deno.com/examples/web_testing_tutorial](https://docs.deno.com/examples/web_testing_tutorial/) — patron completo de spy sobre `globalThis.fetch` con `assertSpyCalls` y restauracion en `finally`
- [docs.deno.com/runtime/reference/continuous_integration](https://docs.deno.com/runtime/reference/continuous_integration/) — YAML oficial para `denoland/setup-deno@v2` con `deno-version: v2.x`
- [supabase.com/docs/guides/functions/unit-test](https://supabase.com/docs/guides/functions/unit-test) — estructura de directorios `supabase/functions/tests/`, naming `[function]-test.ts`
- [github.com/denoland/setup-deno](https://github.com/denoland/setup-deno) — version latest `v2.0.4`, opciones de configuracion, caching

### Secundarias (MEDIUM confidence)

- [github.com/denoland/deno/discussions/18809](https://github.com/denoland/deno/discussions/18809) — stub de `globalThis.fetch` con `@std/testing/mock` verificado por multiples contributors
- [docs.deno.com/examples/stubbing_tutorial](https://docs.deno.com/examples/stubbing_tutorial/) — patron `using stub = stub(...)` para auto-restore
- [supabase.com/docs/guides/functions/dependencies](https://supabase.com/docs/guides/functions/dependencies) — `deno.json` vs `import_map.json` (legacy)

### Terciarias (LOW confidence)

- Ninguna en esta investigacion — todos los claims criticos estan verificados contra fuentes primarias.

---

## Log de Supuestos

| # | Claim | Seccion | Riesgo si es incorrecto |
|---|-------|---------|------------------------|
| A1 | `import.meta.main` es la forma recomendada de evitar la ejecucion del handler al importar | Patron 1 / Refactor de index.ts | Si Supabase no soporta `import.meta.main` en el deploy, habria que mover constantes dentro del handler. Bajo riesgo — `import.meta.main` es estandar Deno. [ASSUMED] |
| A2 | `deno test supabase/functions/tests/` corre bien desde la raiz del repo en CI | Job YAML / Patron 4 | Podria requerir `cd supabase/functions/tests && deno test .` si hay conflictos de CWD. Bajo riesgo. [ASSUMED] |
| A3 | Extraer `sendResendEmail` como export es el minimo cambio necesario para EFN-04 | Preguntas Abiertas #1 | Si el planner prefiere testear el handler completo (con Supabase stubbeado), el enfoque cambia significativamente. [ASSUMED] |

**Todos los claims criticos sobre APIs de Deno, versiones de packages, y patrones de CI son [VERIFIED] o [CITED] contra fuentes oficiales.**

---

## Metadata

**Descomposicion de Confianza:**

| Area | Nivel | Razon |
|------|-------|-------|
| Stack (Deno stdlib + setup-deno) | HIGH | Verificado contra docs oficiales y GitHub del action |
| Patron de fetch stub | HIGH | Ejemplo completo en docs.deno.com/examples/web_testing_tutorial |
| Estructura de directorios Supabase | HIGH | Citado de supabase.com/docs/guides/functions/unit-test |
| Refactor de index.ts con `import.meta.main` | MEDIUM | Patron estandar Deno pero no verificado contra un ejemplo identico con Deno.serve en Supabase |
| Permisos minimos de deno test | MEDIUM | Logica derivada de docs de permisos; puede requerir ajuste en implementacion |

**Fecha de investigacion:** 2026-06-14
**Valido hasta:** 2026-08-14 (estimado — Deno es stable, cambios son backwards-compatible)
