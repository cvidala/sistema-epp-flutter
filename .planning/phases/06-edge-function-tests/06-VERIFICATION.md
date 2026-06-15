---
phase: 06-edge-function-tests
verified: 2026-06-14T20:00:00Z
status: human_needed
score: 8/9 must-haves verified
overrides_applied: 0
re_verification: false
human_verification:
  - test: "Ejecutar deno test supabase/functions/tests/ --allow-env --allow-read con DRY_RUN=1 y confirmar que los 6 tests pasan en verde"
    expected: "6 tests pasan, 0 fallan, sin conexion a Supabase ni a api.resend.com"
    why_human: "Deno no esta instalado localmente. La ejecucion real requiere que el job deno-test de GitHub Actions corra en un PR/push a main. No se puede verificar la ejecucion de los tests con herramientas estaticas."
---

# Phase 6: Edge Function Tests — Reporte de Verificacion

**Phase Goal:** `notif-vencimiento/index.ts` tiene guardia DRY_RUN que bloquea emails en entornos de test, la logica de negocio esta extraida en funciones puras, y los tests Deno verifican HTML, payload Resend y manejo de errores sin enviar emails reales ni necesitar Supabase.
**Verified:** 2026-06-14T20:00:00Z
**Status:** human_needed
**Re-verificacion:** No — verificacion inicial.

---

## Goal Achievement

### Observable Truths

| #  | Truth (ROADMAP Success Criteria / PLAN must-haves)                                                              | Status     | Evidencia                                                                                                                                  |
|----|-----------------------------------------------------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| SC1 | `index.ts` lee `Deno.env.get('DRY_RUN')` y retorna inmediatamente sin llamar a Resend cuando esta presente     | VERIFIED  | Linea 151: `if (Deno.env.get('DRY_RUN')) { return new Response('DRY_RUN: no emails sent.', { status: 200 }); }` — primera instruccion dentro de `Deno.serve` |
| SC2 | `buildEmailHtml()` es una funcion pura exportada que acepta datos de trabajadores y devuelve HTML verificable sin Supabase ni Resend | VERIFIED  | Lineas 47-135: `export function buildEmailHtml(todos, criticos, avisos): string` — sin I/O, sin imports de Supabase/Resend |
| SC3 | `deno test supabase/functions/tests/` pasa completamente sin variables de produccion ni conexion a Supabase    | ? UNCERTAIN | El archivo de tests existe, no referencia env vars de produccion al nivel de modulo, y `index.ts` no lee secrets fuera de `import.meta.main`. La ejecucion efectiva no puede verificarse sin Deno instalado. Delegado a CI (ver Human Verification). |
| SC4 | El test que stubea `globalThis.fetch` captura el payload Resend (URL, destinatario, asunto, HTML) y verifica su estructura | VERIFIED  | Test 5 (lineas 75-103): captura `capturedUrl` y `capturedBody`, assertea URL `https://api.resend.com/emails`, `to`, `subject`, `html` |
| SC5 | El CI ejecuta `deno test supabase/functions/tests/` en un job separado con `denoland/setup-deno@v2` que pasa en verde | VERIFIED (CI wiring) | `.github/workflows/test.yml` lineas 62-79: job `deno-test` con `denoland/setup-deno@v2`, `deno-version: v2.x`, sin `needs:`, `DRY_RUN: "1"`. Ejecucion verde en CI requiere push/PR. |
| T1  | Importar `index.ts` desde un test no inicia el servidor ni falla por env vars ausentes                          | VERIFIED  | Secrets (`SUPABASE_URL!`, `SUPABASE_SERVICE_KEY!`, `RESEND_API_KEY!`) movidos a lineas 145-147 DENTRO de `if (import.meta.main)` (linea 144). `FROM_EMAIL` y `DASHBOARD_URL` permanecen a nivel de modulo como strings literales sin `!`. |
| T2  | `buildEmailHtml()` es exportada y genera HTML correcto sin Supabase ni Resend                                   | VERIFIED  | Identico a SC2 |
| T3  | El handler con DRY_RUN presente retorna 200 sin llamar a fetch                                                   | VERIFIED  | Identico a SC1 — guardia en linea 151-153 retorna antes de cualquier llamada a `sendResendEmail` o `fetch` |
| T4  | Un stub de `globalThis.fetch` captura el payload enviado a Resend (URL, to, subject, html)                      | VERIFIED  | Identico a SC4 |

**Score:** 8/9 truths verified (1 UNCERTAIN — ejecucion de tests en verde, delegada a CI)

---

### Analisis EFN-02: Discrepancia entre REQUIREMENTS y ROADMAP

**EFN-02 (REQUIREMENTS.md):** "La logica de agrupacion y filtrado de trabajadores por vencimiento EPP esta extraida en una funcion pura testeable sin Supabase ni Resend"

**ROADMAP SC#2:** "`buildEmailHtml()` es una funcion pura exportada que acepta datos de trabajadores y devuelve HTML verificable sin importar Supabase ni Resend"

**Observacion:** La logica de agrupacion por org (`porOrg Map`, lineas 167-170) y el filtrado criticos/avisos (lineas 193-194) permanecen DENTRO del handler `Deno.serve`, no exportados. El ROADMAP SC#2 no los requiere — solo pide que `buildEmailHtml()` sea pura y exportada, lo cual esta satisfecho. Conforme a las instrucciones de verificacion, el ROADMAP es el contrato primario. La diferencia entre la formulacion de EFN-02 en REQUIREMENTS y el SC del ROADMAP es una decision de alcance tomada al planificar (el PLAN 06-01 usa la formulacion del ROADMAP, no la de EFN-02 literal). Se registra como observacion, no como blocker.

---

### Required Artifacts

| Artifact                                                   | Expected                                                                | Status   | Detalles                                                                                                      |
|------------------------------------------------------------|-------------------------------------------------------------------------|----------|---------------------------------------------------------------------------------------------------------------|
| `supabase/functions/notif-vencimiento/index.ts`            | Exports puros, DRY_RUN guard, import.meta.main, sendResendEmail         | VERIFIED | 5 exports: `Vencimiento`, `Destinatario`, `sendResendEmail`, `buildEmailHtml`, `formatFecha`. Guard en L151. |
| `supabase/functions/tests/notif-vencimiento-test.ts`       | 6 tests Deno: HTML, DRY_RUN, payload Resend                             | VERIFIED | 6 `Deno.test(...)` confirmados. Importa con `jsr:` directo. `globalThis.fetch` stubbeado y restaurado en finally. |
| `supabase/functions/tests/deno.json`                       | Config imports JSR con entrada `@std/testing/mock`                      | VERIFIED | Contiene las 3 entradas: `@std/assert`, `@std/testing`, `@std/testing/mock`. |
| `.github/workflows/test.yml`                               | Job `deno-test` separado con denoland/setup-deno@v2                     | VERIFIED | Job en L62-79. Sin `needs:`, sin secrets de Supabase/Resend. `DRY_RUN: "1"`. `timeout-minutes: 5`. |
| `CLAUDE.md`                                                | Comando `deno test` documentado en seccion CI/CD                        | VERIFIED | L403: `DRY_RUN=1 deno test supabase/functions/tests/ --allow-env --allow-read`. L408: nota de `brew install deno` y `setup-deno@v2`. |

---

### Key Link Verification

| From                                     | To                                           | Via                                             | Status   | Detalles                                                            |
|------------------------------------------|----------------------------------------------|-------------------------------------------------|----------|---------------------------------------------------------------------|
| `notif-vencimiento-test.ts`              | `notif-vencimiento/index.ts`                 | `import { ... } from '../notif-vencimiento/index.ts'` | WIRED | Linea 8-12 del test file                                           |
| `notif-vencimiento-test.ts`              | `globalThis.fetch` stub                      | `spy(async (input, init) => ...)` asignado a `globalThis.fetch` | WIRED | Lineas 87/122. Restauracion en `finally` en L101 y L135.          |
| `.github/workflows/test.yml` (deno-test) | `supabase/functions/tests/`                  | `deno test supabase/functions/tests/ --allow-env --allow-read` | WIRED | Linea 76 del workflow.                                             |
| `.github/workflows/test.yml` (deno-test) | `denoland/setup-deno@v2`                     | `uses: denoland/setup-deno@v2`                  | WIRED  | Linea 71. `deno-version: v2.x` en L73.                            |

---

### Data-Flow Trace (Level 4)

No aplica — los artifacts son tests y CI config, no componentes que rendericen datos dinamicos de una fuente externa. `buildEmailHtml` recibe datos via parametros de funcion (fixtures en tests), no via fetch/store. `sendResendEmail` es interceptada por el spy antes de alcanzar la red real.

---

### Behavioral Spot-Checks

| Comportamiento                                                       | Comando                                                                              | Resultado                              | Status   |
|----------------------------------------------------------------------|--------------------------------------------------------------------------------------|----------------------------------------|----------|
| `deno test` pasa los 6 tests                                         | `deno test supabase/functions/tests/ --allow-env --allow-read`                       | Deno no instalado localmente           | SKIP     |
| `index.ts` no lee secrets a nivel de modulo (fuera de `import.meta.main`) | `sed -n '1,143p' index.ts \| grep "Deno.env.get"` | Sin matches (exit 1 de grep = 0 coincidencias) | PASS |
| Secrets dentro de `import.meta.main` (lineas > 144)                 | `grep -n "SUPABASE_URL\|RESEND_API_KEY" index.ts`                                   | L145, L146, L147 — todas > L144        | PASS     |
| YAML del workflow es estructuralmente valido                          | Verificacion manual de estructura (python3-yaml no disponible)                       | Claves clave presentes, estructura coherente | PASS |

---

### Probe Execution

No hay `probe-*.sh` definidos ni declarados para esta fase. Los tests son Deno; su ejecucion se delega al job CI `deno-test`.

---

### Requirements Coverage

| Requirement | Plan          | Descripcion                                                                                | Status                   | Evidencia                                                                 |
|-------------|---------------|--------------------------------------------------------------------------------------------|--------------------------|---------------------------------------------------------------------------|
| EFN-01      | 06-01-PLAN.md | DRY_RUN guard bloquea envio de emails en entornos de test                                  | VERIFIED (estatico)      | `if (Deno.env.get('DRY_RUN'))` en L151 de index.ts. Test 6 verifica semantica. |
| EFN-02      | 06-01-PLAN.md | Logica de agrupacion/filtrado extraida en funcion pura testeable sin Supabase/Resend        | PARTIAL (ROADMAP SC satisfecho) | `buildEmailHtml` es pura y exportada (ROADMAP SC#2 cumplido). Logica de agrupacion `porOrg` sigue en handler. Ver seccion "Analisis EFN-02". |
| EFN-03      | 06-01-PLAN.md | Tests Deno verifican que `buildEmailHtml()` genera HTML correcto                            | VERIFIED (estatico)      | Tests 1-4 en notif-vencimiento-test.ts verifican contenido HTML con fixtures. |
| EFN-04      | 06-01-PLAN.md | Tests Deno verifican payload Resend via `globalThis.fetch` stub sin emails reales           | VERIFIED (estatico)      | Test 5: `assertSpyCalls(mockFetch, 1)`, URL, `to`, `subject`, `html` asercionados. |
| EFN-05      | 06-02-PLAN.md | CI ejecuta `deno test supabase/functions/tests/` en job separado con `denoland/setup-deno@v2` | VERIFIED (wiring)       | Job `deno-test` en test.yml L62-79. Necesita PR/push para confirmar verde. |

---

### Anti-Patterns Found

| Archivo                                                     | Linea | Pattern                                        | Severidad | Impacto                                                        |
|-------------------------------------------------------------|-------|------------------------------------------------|-----------|----------------------------------------------------------------|
| `supabase/functions/notif-vencimiento/index.ts`             | 215   | `return new Response(\`Error: ${e.message}\`, ...)` donde `e` no esta tipado | Info | `e` es `unknown` en TypeScript estricto; `.message` puede fallar en runtime si `e` no es `Error`. Es codigo existente no modificado en esta fase. |

No se encontraron marcadores TBD, FIXME, XXX ni XXX sin referencia formal en los archivos modificados por esta fase.

---

### Human Verification Required

#### 1. Ejecucion real de los 6 tests Deno en CI

**Test:** Abrir un PR a `main` (o hacer push) y revisar el check `deno-test` en GitHub Actions → pestaña Checks del PR.

**Expected:** El check `deno-test` aparece en verde en paralelo al check `test` (Flutter). Los 6 tests de `supabase/functions/tests/notif-vencimiento-test.ts` pasan. El log muestra `6 passed, 0 failed`. Sin llamadas a `api.resend.com` ni a Supabase.

**Why human:** Deno no esta instalado en el entorno local de verificacion. No se puede ejecutar `deno test` sin instalar Deno. La ejecucion real de los tests — que es la verdad ultima de SC#3 — requiere el runner de GitHub Actions.

---

### Gaps Summary

No hay gaps bloqueadores. La unica incertidumbre es la ejecucion efectiva de los tests (`SC3`), que es estructuralmente delegada a CI por diseno (Deno no disponible localmente). Los artefactos, el wiring y el job CI estan completos y correctamente conectados. La verificacion humana del check `deno-test` verde en CI es el unico paso pendiente.

**Nota sobre EFN-02:** La logica de agrupacion por org (`porOrg`) no fue extraida como funcion pura exportada, pero el ROADMAP SC#2 (contrato primario) solo requiere que `buildEmailHtml()` sea la funcion pura exportada — lo cual esta satisfecho. Si se desea alinear estrictamente con el texto de EFN-02 en REQUIREMENTS.md, se puede extraer `groupByOrg(vencimientos: Vencimiento[]): Map<string, Vencimiento[]>` en una futura iteracion.

---

_Verified: 2026-06-14T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
